# qiyun WVP 源码维护与镜像构建

此 fork 保存官方最新基线、qiyun 定制源码、生产快照和模块化贡献。环境配置与密钥由私有部署配置维护。

## 分支与已验证发布

| 分支 | 用途 |
| --- | --- |
| `master` | 官方 `648540858/wvp-GB28181-pro:master` 镜像，2026-11-05 核对为 `4e8a45a6307ab7b7b7bd2f8f4dff97fe0f4cfa99` |
| `codex/qiyun` | 默认维护分支，保留已合入官方的源码、qiyun 定制与本目录构建配方 |
| `codex/qiyun-wvp-recovery-20261105` | 当前已验收生产应用快照 `ce981c1d1ae33d6fb017266a93ee59bf2af96bbd` |
| `codex/qiyun-production-release-20261104` | 前一生产快照 `e020a039fa0564be13f9ad97ba97ef42e18cc077` |
| `codex/upstream-custom-integration-20261105` | 下列七个官方贡献模块的组合验证分支 |

已验收应用 Jar 的 SHA-256 为 `0dbbb9daf0e55f57e63aa861e3531354f3108961deffc42a0b60d52d2be3b5c6`，运行于 Java 21.0.12.1 / FFmpeg 4.2.7。
生产镜像固定为 `registry.cn-gdgz1.ctyun.cn/paas/wangwuli-wvp@sha256:95ba40cd6e1016b3341fd9c2d2edb9c196f0dcee1eed2a724ce03d994534c5bb`。

该应用完成了 46分04秒、74分56秒长录像与新 60 秒请求的真实设备/成品验证；长录像成品经过全解码、接缝、PTS/DTS、音频和自动转存后的完整 HTTP GET/SHA-256 核验。前一条 23分29秒故障录像也已恢复并核验归档文件。
生产应用相关 Java 回归 451 项通过；贡献模块组合相关 Java 455 项、Jest 8 项、Node 11 项通过，均无跳过。

## 官方模块与依赖

| 模块 | PR | 前置模块 |
| --- | --- | --- |
| A 回放回调与 RTP 生命周期 | [#2258](https://github.com/648540858/wvp-GB28181-pro/pull/2258) | 无 |
| B 原 Dialog 可靠关闭与归属 | [#2259](https://github.com/648540858/wvp-GB28181-pro/pull/2259) | A |
| C 原生下载完整性与旧结果恢复 | [#2260](https://github.com/648540858/wvp-GB28181-pro/pull/2260) | B |
| D 分段下载、内容校验和显式重做合并 | [#2261](https://github.com/648540858/wvp-GB28181-pro/pull/2261) | C、B |
| E 国标历史回放独立播放器身份 | [#2262](https://github.com/648540858/wvp-GB28181-pro/pull/2262) | A |
| F Assist 内网 HTTP 与返回链接协议 | [#2263](https://github.com/648540858/wvp-GB28181-pro/pull/2263) | 无 |
| G 录像占用只读查询 | [#2264](https://github.com/648540858/wvp-GB28181-pro/pull/2264) | D |

各 PR 说明包含完整审核 SHA 和本模块增量对比。聚合 PR #2254 已链接替代模块后关闭，原讨论与分支保留。已合并的云录像会话 PR #2255 沿用官方代码。
Assist 的精确裁切与元数据保留修复保存在独立的 [HuashiCloud/wvp-pro-assist](https://github.com/HuashiCloud/wvp-pro-assist) fork。

## 合入后续官方更新

使用独立同步分支合并官方更新，保留定制提交和发布快照。普通 clone 的 `origin` 指向此 fork，并设置官方 `upstream`：

```sh
git remote add upstream https://github.com/648540858/wvp-GB28181-pro.git
git fetch upstream master
git switch -c codex/sync-upstream-YYYYMMDD origin/codex/qiyun
git merge upstream/master
```

按受影响模块执行 JDK 21 回归；分段模块使用独立 Redis 与 FFmpeg/ffprobe 4.2.7，并验证前端构建。现有 POM 固定跳过测试，测试在隔离副本临时启用 Surefire，完成后恢复 POM。验证后的同步分支通过 PR 合入 `codex/qiyun`。
官方镜像分支使用普通快进推送更新：`git push origin refs/remotes/upstream/master:refs/heads/master`。新增发布保留新的源码快照引用。

## 构建应用镜像

构建环境使用 JDK 21、Node/npm、Docker，以及固定底座镜像的拉取权限。使用普通 clone 构建，使 Jar 的 `git.properties` 记录当前提交。
先按项目流程安装前端依赖；已验证的 Node 26 前端命令为 `NODE_OPTIONS=--openssl-legacy-provider npm run build:prod`。前端构建后再执行 Maven 打包，确认 Jar 包含静态页面。

将下例应用 Jar 路径和镜像标签替换为本次产物：

```sh
wvp_revision="$(git rev-parse HEAD)"
bash docker/qiyun/build-image.sh \
  /path/to/built/application.jar \
  registry.example.com/team/wvp:version \
  https://github.com/HuashiCloud/wvp-GB28181-pro \
  "$wvp_revision"
```

脚本校验 Jar 的源码提交、干净标记、前端入口和 SHA-256，构建上下文仅包含已校验 Jar 与 Dockerfile；镜像写入来源标签并使用固定 Java/FFmpeg 底座。输出本地镜像后，按环境交付流程推送、以 digest 更新部署并验证实际录像。
