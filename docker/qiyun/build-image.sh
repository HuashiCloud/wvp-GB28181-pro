#!/usr/bin/env bash
set -euo pipefail
umask 077

# 先在普通完整 checkout 中以 Java 21 构建前端与 Jar；Maven 不会自动构建前端。
# 当前已验证的 Node 26 在 web/ 执行 NODE_OPTIONS=--openssl-legacy-provider npm run build:prod，
# 再在仓库根目录以 Java 21 执行 mvn package。
# 共享 worktree 的 JGit 可能误认 common HEAD，
# 因此必须显式提供实际应用版本，不能拿当前脚本分支或 Docker 标签代替 Jar 内的版本。
if [[ $# -ne 4 ]]; then
    printf '用法: %s <含前端的Jar> <本地镜像标签> <源码仓库HTTPS地址> <应用Git版本>\n' "$0" >&2
    exit 2
fi

jar=$1
image=$2
source_repository=$3
expected_revision=$4
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository=$(git -C "$script_directory" rev-parse --show-toplevel)
expected_commit=$(git -C "$repository" rev-parse --verify --end-of-options "${expected_revision}^{commit}")

# 镜像配方可以独立更新，应用代码必须仍与 Jar 所声明的编译版本一致。
runtime_paths=(pom.xml src/main/java src/main/resources web)
if ! git -C "$repository" diff --quiet "$expected_commit" -- "${runtime_paths[@]}" \
        || [[ -n $(git -C "$repository" ls-files --others --exclude-standard -- "${runtime_paths[@]}") ]]; then
    printf '当前应用源码与指定版本不一致，请使用对应的完整 checkout。\n' >&2
    exit 1
fi

# 校验实际送入镜像的副本，避免原 Jar 在校验后被另一次构建替换。
build_context=$(mktemp -d "${TMPDIR:-/tmp}/qiyun-wvp-image.XXXXXX")
trap 'rm -rf -- "$build_context"' EXIT
mkdir "$build_context/target"
cp -- "$jar" "$build_context/target/qiyun-wvp.jar"
cp -- "$script_directory/Dockerfile" "$build_context/Dockerfile"

metadata=$(python3 - "$build_context/target/qiyun-wvp.jar" "$expected_commit" "$source_repository" <<'PY'
import hashlib
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit
from zipfile import BadZipFile, ZipFile

jar, expected, source = sys.argv[1:]
try:
    url = urlsplit(source)
    if (url.scheme != "https" or not url.hostname or url.username is not None
            or url.password is not None or url.query or url.fragment
            or len(url.path.strip("/").split("/")) != 2
            or any(character.isspace() for character in source)):
        raise ValueError("源码地址必须是无凭据、查询参数和片段的 HTTPS 仓库地址")
    with ZipFile(jar) as archive:
        names = archive.namelist()
        properties_name = "BOOT-INF/classes/git.properties"
        index_name = "BOOT-INF/classes/static/index.html"
        if names.count(properties_name) != 1 or names.count(index_name) != 1:
            raise ValueError("Jar 必须包含唯一的 git.properties 和前端 static/index.html")
        if archive.getinfo(properties_name).file_size > 65536:
            raise ValueError("Jar 版本元数据无效")
        lines = archive.read(properties_name).decode("iso-8859-1").splitlines()
        def property_value(key):
            values = [line.split("=", 1)[1] for line in lines if line.startswith(key + "=")]
            if len(values) != 1:
                raise ValueError("Jar 缺少唯一的版本或干净状态标记")
            return values[0]
        revision = property_value("git.commit.id.full")
        if not re.fullmatch("[0-9a-f]{40}", revision) or revision != expected:
            raise ValueError("Jar 内 Git 版本与指定应用版本不一致，不能据此标注镜像")
        if property_value("git.dirty") != "false":
            raise ValueError("Jar 来自有未提交变更的构建，不能据此标注镜像")
        version = property_value("git.build.version")
        if not re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z._+-]{0,127}", version):
            raise ValueError("Jar 应用版本无效")
        if archive.getinfo(index_name).file_size <= 0:
            raise ValueError("Jar 前端入口为空，请先构建前端")
    digest = hashlib.sha256()
    with Path(jar).open("rb") as application:
        for chunk in iter(lambda: application.read(1024 * 1024), b""):
            digest.update(chunk)
    print(revision, digest.hexdigest(), version)
except (OSError, ValueError, BadZipFile, KeyError):
    # 不输出元数据、文件路径或可能带凭据的调用参数。
    print("Jar 或源码地址校验失败：请核对版本、dirty 标记和已构建的前端入口。", file=sys.stderr)
    sys.exit(1)
PY
)
IFS=' ' read -r revision jar_sha256 application_version <<< "$metadata"

# 只把已验证 Jar 和配方传入 Docker，不发送工作区配置或其他未跟踪文件。
docker build --platform linux/amd64 --pull=false --network none \
    --build-arg "SOURCE_REPOSITORY=$source_repository" \
    --build-arg "SOURCE_REVISION=$revision" \
    --build-arg "APPLICATION_VERSION=$application_version" \
    --build-arg "APPLICATION_JAR_SHA256=$jar_sha256" \
    -t "$image" "$build_context"
printf '本地镜像已构建：%s\n应用版本：%s\nJar SHA256：%s\n' "$image" "$revision" "$jar_sha256"
