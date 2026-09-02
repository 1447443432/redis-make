# redis-make

通过 Docker 和 GitHub Actions 编译 Redis 可移植安装包，支持 amd64、arm64，使用 CentOS 7 Builder 生成 glibc 2.17 基线包。默认版本为 Redis 8.8.2。

Redis 使用包内 OpenSSL 3.5.6，并为 Redis 可执行文件写入相对 RPATH；目标服务器不需要额外安装对应的 OpenSSL 运行库。

## 项目结构

```text
redis-make/
├── .github/workflows/build-redis.yml
├── config/redis-version.conf
├── sources/
├── output/
├── Dockerfile
├── build-redis.sh
├── build.sh
└── README.md
```

## 本地构建

仓库已内置 Redis 8.8.2 和 OpenSSL 3.5.6 源码包。构建时如果对应文件已存在就直接复用；如果不存在，才自动下载并缓存到 `sources/`。

```bash
chmod +x build-redis.sh
./build-redis.sh amd64
./build-redis.sh arm64 8.8.2
```

默认版本在 `config/redis-version.conf` 中配置，也可以通过参数或环境变量覆盖。构建脚本支持任意已发布的三段式 Redis 版本；后续升级只需修改默认版本或传入新版本号：

```bash
REDIS_VERSION=8.8.2 ./build-redis.sh amd64
./build-redis.sh amd64 9.0.0
BUILDER_IMAGE=my-builder:latest ./build-redis.sh amd64
DOCKER_NO_CACHE=true ./build-redis.sh amd64
```

新增版本不需要修改构建逻辑。例如构建 Redis 9.0.0 时，脚本会自动下载 `redis-9.0.0.tar.gz`；如果希望长期内置该版本，可以将下载后的源码包提交到 `sources/`。

输出示例：

```text
output/
├── redis-8.8.2-glibc2.17-amd64.tar.gz
├── redis-8.8.2-glibc2.17-amd64.tar.gz.sha256
├── build-info.txt
└── docker-amd64.log
```

安装：

```bash
tar zxf redis-8.8.2-glibc2.17-amd64.tar.gz -C /usr/local
/usr/local/redis-8.8.2-glibc2.17-amd64/bin/redis-server --version
/usr/local/redis-8.8.2-glibc2.17-amd64/bin/redis-cli --version
```

构建默认启用 TLS（`BUILD_TLS=yes`），产物包含：

```text
redis-server
redis-cli
redis-benchmark
redis-sentinel
redis-check-aof
redis-check-rdb
redis-trib.rb
```

## GitHub Actions

推送构建相关文件到 `master` 或手动执行 `Build Redis` 会分别构建 amd64、arm64，并创建或覆盖：

```text
redis-8.8.2
```

Release 附件包含两个架构的安装包、SHA256 文件、构建信息和 Docker 日志。手动执行时可在 `redis_version` 中填写三段式版本号；新增 Redis 版本无需修改 Workflow 或构建逻辑。

Workflow 只监听 Dockerfile、构建脚本、配置和 Workflow 自身的变更。README 等文档文件的提交不会触发构建。

## Builder

默认镜像：

```text
registry.cn-shanghai.aliyuncs.com/jing-images/linux_amd64_centos_builder:7.9.2009
registry.cn-shanghai.aliyuncs.com/jing-images/linux_arm64_centos_builder:7.9.2009
```

镜像至少需要 gcc、g++、make、perl、tar、curl、sha256sum、readelf，以及编译 OpenSSL 和 Redis TLS 所需的基础开发工具。RPATH 在链接阶段写入，不依赖 `patchelf`。
