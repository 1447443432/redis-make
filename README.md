# redis-make

通过 Docker 和 GitHub Actions 构建 Redis 可移植安装包，支持 amd64、arm64，使用 CentOS 7 Builder 生成 glibc 2.17 基线包。

默认版本为 Redis 8.8.2，后续构建其他三段式版本时不需要修改构建逻辑。默认关闭 TLS，并使用 `MALLOC=libc`，兼容 Linux 4K 和 64K 内存页环境。

## 项目结构

```text
redis-make/
├── .github/workflows/build-redis.yml
├── config/redis-version.conf
├── sources/                         # 可选的本地源码缓存
├── output/                          # 本地构建输出
├── Dockerfile
├── build-redis.sh
├── build.sh
└── README.md
```

## 本地构建

仓库内置 Redis 8.8.2 源码包；启用 TLS 时还会复用仓库内的 OpenSSL 3.5.6 源码包。构建脚本会优先使用 `sources/` 中匹配版本的源码，不存在时才下载。

```bash
chmod +x build-redis.sh
./build-redis.sh amd64
./build-redis.sh arm64 8.8.2
```

可通过参数或环境变量覆盖默认配置：

```bash
REDIS_VERSION=8.8.2 ./build-redis.sh amd64
MALLOC=libc ./build-redis.sh arm64
BUILD_TLS=true ./build-redis.sh amd64
BUILDER_IMAGE=my-builder:latest ./build-redis.sh amd64
DOCKER_NO_CACHE=true ./build-redis.sh amd64
```

支持的 `MALLOC` 值为：

- `libc`：默认值，推荐用于 4K/64K 页混合环境。
- `jemalloc`：Redis 默认分配器，性能特征不同，但在 64K 页系统上可能出现 `Unsupported system page size`，确认目标环境支持后再使用。

`DOCKER_NO_CACHE=true` 会禁用 Docker 构建层缓存，适合排查缓存污染或强制干净重建；普通构建无需勾选或设置它。

新版本只需传入版本号，例如：

```bash
./build-redis.sh amd64 9.0.0
```

如果希望长期内置该版本，可以将对应的 `redis-版本.tar.gz` 放入 `sources/`。否则脚本会从 Redis 官方 releases 地址下载。

输出示例：

```text
output/
├── redis-8.8.2-glibc2.17-amd64.tar.gz
├── redis-8.8.2-glibc2.17-amd64.tar.gz.sha256
├── build-info.txt
└── docker-amd64.log
```

安装与校验：

```bash
sha256sum -c redis-8.8.2-glibc2.17-amd64.tar.gz.sha256
tar zxf redis-8.8.2-glibc2.17-amd64.tar.gz -C /usr/local
/usr/local/redis-8.8.2-glibc2.17-amd64/bin/redis-server --version
/usr/local/redis-8.8.2-glibc2.17-amd64/bin/redis-cli --version
```

默认产物不依赖 OpenSSL，和 Redis 8.8.1 的非 TLS 包保持兼容。设置 `BUILD_TLS=true` 后，产物会携带 OpenSSL 3.5.6 运行库并写入相对 RPATH；目标主机不需要预装 `libssl.so.10` 或 `libcrypto.so.10`。

默认 `MALLOC=libc` 是兼容 64K 页系统的关键。Redis 8.8.2 如果使用 jemalloc，在 UOS 等 64K 页 ARM64 系统上可能启动时报：

```text
<jemalloc>: Unsupported system page size
```

## GitHub Actions

向 `master` 推送构建相关文件，或在 Actions → Build Redis → Run workflow 手动执行时，会分别构建 amd64 和 arm64，并创建或覆盖对应 Release：

```text
redis-8.8.2
```

Release 包含两个架构的安装包、SHA256 文件、构建信息和 Docker 日志。配置仓库 Secret `HAP_WEBHOOK_URL` 后，Release 创建成功会自动向 HAP Webhook 推送版本、下载地址和 SHA256；未配置时会跳过同步，不影响构建。

仅以下路径会触发自动构建：

- `.github/workflows/**`
- `Dockerfile`
- `build.sh`
- `build-redis.sh`
- `config/**`
- `sources/**`

README 等文档变更不会触发 workflow。

### 手动执行参数

在 Actions → Build Redis → Run workflow 页面填写：

- `redis_version`：Redis 三段式版本号，例如 `8.8.2`。留空使用 `config/redis-version.conf` 中的默认版本；填写新版本时无需修改脚本。
- `build_tls`：默认 `false`。不勾选时生成不依赖 OpenSSL 的兼容包；只有需要 Redis TLS 功能时才勾选。
- `malloc`：默认 `libc`。推荐保持默认，可兼容 4K/64K 内存页；只有确认目标环境支持时才选择 `jemalloc`。

推荐构建 Redis 8.8.2：

```text
redis_version: 8.8.2
build_tls:     unchecked
malloc:        libc
```

Workflow 会在构建摘要中展示版本、TLS、内存分配器、架构和 glibc 基线；构建失败时会打印构建阶段的错误摘要和最后日志，便于定位。

## Builder

默认镜像：

```text
registry.cn-shanghai.aliyuncs.com/jing-images/linux_amd64_centos_builder:7.9.2009
registry.cn-shanghai.aliyuncs.com/jing-images/linux_arm64_centos_builder:7.9.2009
```

镜像至少需要 gcc、g++、make、perl、tar、curl、sha256sum、readelf，以及 Redis 编译所需的基础开发工具。启用 TLS 时还需要 OpenSSL 编译工具链。
