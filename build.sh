#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${BASE_DIR}"

REDIS_VERSION="${REDIS_VERSION:?REDIS_VERSION is required}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
SOURCE_DIR="${SOURCE_DIR:-${BASE_DIR}/sources}"
WORK_DIR="${WORK_DIR:-${BASE_DIR}/work}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
REDIS_TAR="${SOURCE_DIR}/redis-${REDIS_VERSION}.tar.gz"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/redis}"
BUILD_LOG="${OUTPUT_DIR}/build.log"
BUILD_INFO="${OUTPUT_DIR}/build-info.txt"

mkdir -p "${OUTPUT_DIR}"
: >"${BUILD_LOG}"

run_stage()
{
    local name="$1"
    shift
    echo "[INFO] ${name}"
    "$@" >>"${BUILD_LOG}" 2>&1
    echo "[OK] ${name}"
}

validate()
{
    printf '%s' "${REDIS_VERSION}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'
    test -s "${REDIS_TAR}"
    tar tzf "${REDIS_TAR}" >/dev/null
}

extract()
{
    rm -rf "${WORK_DIR}"
    mkdir -p "${WORK_DIR}"
    tar xzf "${REDIS_TAR}" -C "${WORK_DIR}"
    REDIS_SRC="${WORK_DIR}/redis-${REDIS_VERSION}"
    test -d "${REDIS_SRC}"
}

compile()
{
    cd "${REDIS_SRC}"
    make -j"${BUILD_JOBS}" BUILD_TLS=yes
}

install()
{
    cd "${REDIS_SRC}"
    rm -rf "${INSTALL_PREFIX}"
    make PREFIX="${INSTALL_PREFIX}" BUILD_TLS=yes install
}

verify()
{
    "${INSTALL_PREFIX}/bin/redis-server" --version
    "${INSTALL_PREFIX}/bin/redis-cli" --version
    test -x "${INSTALL_PREFIX}/bin/redis-server"
    test -x "${INSTALL_PREFIX}/bin/redis-cli"
}

package()
{
    local glibc build_arch package package_root stage_dir
    glibc="$(ldd --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    case "$(uname -m)" in
        x86_64) build_arch=amd64 ;;
        aarch64) build_arch=arm64 ;;
        *) echo "unsupported architecture" >&2; return 1 ;;
    esac
    package="redis-${REDIS_VERSION}-glibc${glibc}-${build_arch}.tar.gz"
    package_root="redis-${REDIS_VERSION}-glibc${glibc}-${build_arch}"
    stage_dir="${WORK_DIR}/${package_root}"
    rm -rf "${stage_dir}"
    cp -a "${INSTALL_PREFIX}" "${stage_dir}"
    tar czf "${OUTPUT_DIR}/${package}" -C "${WORK_DIR}" "${package_root}"
    (cd "${OUTPUT_DIR}" && sha256sum "${package}") >"${OUTPUT_DIR}/${package}.sha256"
    cat >"${BUILD_INFO}" <<INFO
redis_version=${REDIS_VERSION}
arch=${build_arch}
glibc=${glibc}
build_jobs=${BUILD_JOBS}
build_tls=true
install_prefix=${INSTALL_PREFIX}
INFO
}

main()
{
    run_stage 'validate sources' validate
    run_stage 'extract sources' extract
    run_stage 'compile redis' compile
    run_stage 'install redis' install
    run_stage 'verify binaries' verify
    run_stage 'package redis' package
    ls -lh "${OUTPUT_DIR}"
    echo "BUILD SUCCESS: redis-${REDIS_VERSION}"
}

main "$@"
