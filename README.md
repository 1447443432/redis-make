# redis-make

通过 Docker 和 GitHub Actions 编译 Redis 可移植安装包，支持 amd64、arm64，使用 CentOS 7 Builder 生成 glibc 2.17 基线包。默认版本为 Redis 8.8.2。

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

脚本会自动下载并缓存 Redis 源码到 `sources/`：

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

推送到 `master` 或手动执行 `Build Redis` 会分别构建 amd64、arm64，并创建或覆盖：

```text
redis-8.8.2
```

Release 附件包含两个架构的安装包、SHA256 文件、构建信息和 Docker 日志。手动执行时可在 `redis_version` 中填写三段式版本号；新增 Redis 版本无需修改 Workflow 或构建逻辑。

## Builder

默认镜像：

```text
registry.cn-shanghai.aliyuncs.com/jing-images/linux_amd64_centos_builder:7.9.2009
registry.cn-shanghai.aliyuncs.com/jing-images/linux_arm64_centos_builder:7.9.2009
```

镜像至少需要 gcc、g++、make、perl、tar、curl、sha256sum 和 Redis TLS 构建所需的 OpenSSL 开发文件。
