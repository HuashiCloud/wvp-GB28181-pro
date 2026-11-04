# 该已验证底座保留原运维布局，并已包含 Java 21 和 FFmpeg 4.2.7。
# 统一通过同目录 build-image.sh 校验应用 Jar 后构建，不在镜像内编译或更新依赖。
ARG WVP_BASE_IMAGE=registry.cn-gdgz1.ctyun.cn/paas/wangwuli-wvp@sha256:b0b6f4d788389e6c6f911194a59c6d12888706332446f17d5ade0181d5be7c46
FROM ${WVP_BASE_IMAGE}

ARG WVP_BASE_IMAGE
ARG SOURCE_REPOSITORY
ARG SOURCE_REVISION
ARG APPLICATION_VERSION
ARG APPLICATION_JAR_SHA256
LABEL org.opencontainers.image.source="${SOURCE_REPOSITORY}" \
      org.opencontainers.image.revision="${SOURCE_REVISION}" \
      org.opencontainers.image.version="${APPLICATION_VERSION}" \
      com.qiyun.base.image="${WVP_BASE_IMAGE}" \
      com.qiyun.application.jar-sha256="${APPLICATION_JAR_SHA256}" \
      com.qiyun.source.patch-sha256=""

WORKDIR /opt/wvp

# 不允许旧版 Jar 或字节码覆盖补丁在新应用旁继续生效。
RUN test -n "${SOURCE_REPOSITORY}" && test -n "${SOURCE_REVISION}" && test -n "${APPLICATION_JAR_SHA256}" \
    && rm -f /opt/wvp/wvp-pro-*.jar /opt/wvp/recording-fix.jar \
    && java -version
COPY target/qiyun-wvp.jar /opt/wvp/wvp.jar

# 部署负责以参数传入环境配置；镜像默认入口不启动内置数据库或媒体服务。
ENTRYPOINT ["java", "-jar", "/opt/wvp/wvp.jar", "--spring.config.location=/opt/wvp/config/application.yml"]
