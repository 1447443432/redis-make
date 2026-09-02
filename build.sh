#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${BASE_DIR}"

REDIS_VERSION="${REDIS_VERSION:?REDIS_VERSION is required}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.6}"
BUILD_TLS="${BUILD_TLS:-false}"
MALLOC="${MALLOC:-libc}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
SOURCE_DIR="${SOURCE_DIR:-${BASE_DIR}/sources}"
WORK_DIR="${WORK_DIR:-${BASE_DIR}/work}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
REDIS_TAR="${SOURCE_DIR}/redis-${REDIS_VERSION}.tar.gz"
OPENSSL_TAR="${SOURCE_DIR}/openssl-${OPENSSL_VERSION}.tar.gz"
INSTALL_PREFIX="${INSTALL_PREFIX:-${WORK_DIR}/runtime}"
BUILD_LOG="${OUTPUT_DIR}/build.log"
BUILD_INFO="${OUTPUT_DIR}/build-info.txt"

mkdir -p "${OUTPUT_DIR}"
: >"${BUILD_LOG}"

run_stage()
{
    local name="$1"
    local status
    shift
    echo "[INFO] ${name}"
    if "$@" >>"${BUILD_LOG}" 2>&1; then
        echo "[OK] ${name}"
        return 0
    fi
    status=$?
    echo "[ERROR] ${name} (exit ${status})" >&2
    echo "========== ${name} error summary ==========" >&2
    grep -iE 'error|failed|fatal|not found|cannot|unsupported|no such' "${BUILD_LOG}" | tail -80 >&2 || true
    echo "========== ${name} last log ==========" >&2
    tail -120 "${BUILD_LOG}" >&2 || true
    echo "==========================================" >&2
    return "${status}"
}

validate()
{
    printf '%s' "${REDIS_VERSION}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'
    test -s "${REDIS_TAR}"
    tar tzf "${REDIS_TAR}" >/dev/null
    case "${MALLOC}" in libc|jemalloc) ;; *) return 1 ;; esac
    if [ "${BUILD_TLS}" = true ]; then
        test -s "${OPENSSL_TAR}"
        tar tzf "${OPENSSL_TAR}" >/dev/null
    fi
}

extract()
{
    rm -rf "${WORK_DIR}"
    mkdir -p "${WORK_DIR}/runtime"
    tar xzf "${REDIS_TAR}" -C "${WORK_DIR}"
    if [ "${BUILD_TLS}" = true ]; then
        tar xzf "${OPENSSL_TAR}" -C "${WORK_DIR}"
    fi
    REDIS_SRC="${WORK_DIR}/redis-${REDIS_VERSION}"
    test -d "${REDIS_SRC}"
    if [ "${BUILD_TLS}" = true ]; then
        OPENSSL_SRC="${WORK_DIR}/openssl-${OPENSSL_VERSION}"
        test -d "${OPENSSL_SRC}"
    fi
}

build_openssl()
{
    [ "${BUILD_TLS}" = true ] || return 0
    cd "${OPENSSL_SRC}"
    ./config \
        shared \
        no-tests \
        -g \
        "--prefix=${WORK_DIR}/runtime/openssl" \
        --libdir=lib \
        "--openssldir=${WORK_DIR}/runtime/openssl/ssl" \
        '-Wl,-rpath,$ORIGIN'
    make -j"${BUILD_JOBS}"
    make install_sw
}

compile_redis()
{
    local make_args=(BUILD_TLS="${BUILD_TLS}" MALLOC="${MALLOC}" USE_SYSTEMD=no)
    if [ "${BUILD_TLS}" = true ]; then
        make_args+=(OPENSSL_PREFIX="${WORK_DIR}/runtime/openssl" LIBSSL_LIBS=-lssl LIBCRYPTO_LIBS=-lcrypto 'REDIS_LDFLAGS=-Wl,-rpath,$$ORIGIN/../openssl/lib')
    fi
    cd "${REDIS_SRC}"
    make -j"${BUILD_JOBS}" "${make_args[@]}"
}

install()
{
    local make_args=(BUILD_TLS="${BUILD_TLS}" MALLOC="${MALLOC}" USE_SYSTEMD=no)
    if [ "${BUILD_TLS}" = true ]; then
        make_args+=(OPENSSL_PREFIX="${WORK_DIR}/runtime/openssl" LIBSSL_LIBS=-lssl LIBCRYPTO_LIBS=-lcrypto)
    fi
    cd "${REDIS_SRC}"
    rm -rf "${INSTALL_PREFIX}/bin" "${INSTALL_PREFIX}/share"
    make PREFIX="${INSTALL_PREFIX}" "${make_args[@]}" install
}

verify_rpath()
{
    [ "${BUILD_TLS}" = true ] || return 0
    local file rpath
    command -v readelf >/dev/null 2>&1
    for file in "${INSTALL_PREFIX}"/bin/*; do
        if file -b "${file}" | grep -q ELF; then
            rpath="$(readelf -d "${file}" | grep -E '(RPATH|RUNPATH)' | sed -n '1p')"
            printf '%s\n' "${file}: ${rpath}"
            grep -q '\$ORIGIN/../openssl/lib' <<<"${rpath}"
        fi
    done
}

verify_openssl_runtime()
{
    [ "${BUILD_TLS}" = true ] || return 0
    local file ldd_output
    test -f "${INSTALL_PREFIX}/openssl/lib/libssl.so.3"
    test -f "${INSTALL_PREFIX}/openssl/lib/libcrypto.so.3"
    for file in "${INSTALL_PREFIX}"/bin/*; do
        if file -b "${file}" | grep -q ELF; then
            ldd_output="$(ldd "${file}" 2>&1)"
            printf '%s\n' "${ldd_output}"
            grep -q 'libssl.so.3' <<<"${ldd_output}"
            grep -q 'libcrypto.so.3' <<<"${ldd_output}"
            ! grep -qE 'lib(ssl|crypto)\.so\.10' <<<"${ldd_output}"
        fi
    done
}

verify()
{
    local file ldd_output
    for file in "${INSTALL_PREFIX}"/bin/*; do
        if file -b "${file}" | grep -q ELF; then
            ldd_output="$(ldd "${file}" 2>&1)"
            printf '%s\n' "${ldd_output}"
            ! grep -q 'not found' <<<"${ldd_output}"
        fi
    done
    "${INSTALL_PREFIX}/bin/redis-server" --version
    "${INSTALL_PREFIX}/bin/redis-cli" --version
    test -x "${INSTALL_PREFIX}/bin/redis-server"
    test -x "${INSTALL_PREFIX}/bin/redis-cli"
}

package()
{
    local glibc build_arch package package_root stage_dir
    glibc="$(ldd --version 2>&1 | sed -n '1p' | grep -oE '[0-9]+\.[0-9]+' | sed -n '1p')"
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
    if [ "${BUILD_TLS}" = true ]; then
        test -f "${stage_dir}/openssl/lib/libssl.so.3"
        test -f "${stage_dir}/openssl/lib/libcrypto.so.3"
    fi
    tar czf "${OUTPUT_DIR}/${package}" -C "${WORK_DIR}" "${package_root}"
    (cd "${OUTPUT_DIR}" && sha256sum "${package}") >"${OUTPUT_DIR}/${package}.sha256"
    cat >"${BUILD_INFO}" <<INFO
redis_version=${REDIS_VERSION}
openssl_version=${OPENSSL_VERSION}
arch=${build_arch}
glibc=${glibc}
build_jobs=${BUILD_JOBS}
build_tls=${BUILD_TLS}
malloc=${MALLOC}
install_prefix=${INSTALL_PREFIX}
INFO
}

main()
{
    run_stage 'validate sources' validate
    run_stage 'extract sources' extract
    run_stage 'build openssl' build_openssl
    run_stage 'compile redis' compile_redis
    run_stage 'install redis' install
    run_stage 'verify relative rpath' verify_rpath
    run_stage 'verify OpenSSL runtime' verify_openssl_runtime
    run_stage 'verify binaries' verify
    run_stage 'package redis' package
    ls -lh "${OUTPUT_DIR}"
    echo "BUILD SUCCESS: redis-${REDIS_VERSION}"
}

main "$@"
