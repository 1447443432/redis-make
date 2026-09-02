ARG BUILDER_IMAGE=registry.cn-shanghai.aliyuncs.com/jing-images/linux_amd64_centos_builder:7.9.2009
FROM ${BUILDER_IMAGE}

WORKDIR /data/redis-make

COPY sources ./sources
COPY config ./config
COPY build.sh ./build.sh

RUN chmod +x ./build.sh

USER root

ENTRYPOINT ["./build.sh"]
