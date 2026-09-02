#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${BASE_DIR}"

ARCH="${1:-amd64}"
VERSION_ARG="${2:-}"
OUTPUT_DIR="${OUTPUT_DIR:-${BASE_DIR}/output}"
SOURCE_DIR="${SOURCE_DIR:-${BASE_DIR}/sources}"
CONTAINER_OUTPUT_DIR="${CONTAINER_OUTPUT_DIR:-/output}"
DOCKER_NO_CACHE="${DOCKER_NO_CACHE:-false}"

# shellcheck disable=SC1091
source config/redis-version.conf
REDIS_VERSION="${VERSION_ARG:-${REDIS_VERSION}}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.6}"

case "${ARCH}" in
    amd64)
        BUILDER_IMAGE="${BUILDER_IMAGE:-registry.cn-shanghai.aliyuncs.com/jing-images/linux_amd64_centos_builder:7.9.2009}"
        EXPECTED_ARCH=x86_64
        ;;
    arm64)
        BUILDER_IMAGE="${BUILDER_IMAGE:-registry.cn-shanghai.aliyuncs.com/jing-images/linux_arm64_centos_builder:7.9.2009}"
        EXPECTED_ARCH=aarch64
        ;;
    *) echo "[ERROR] unsupported arch: ${ARCH}" >&2; exit 1 ;;
esac

printf '%s' "${REDIS_VERSION}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || {
    echo "[ERROR] invalid Redis version: ${REDIS_VERSION}" >&2
    exit 1
}

mkdir -p "${OUTPUT_DIR}" "${SOURCE_DIR}"
SOURCE_ARCHIVE="${SOURCE_DIR}/redis-${REDIS_VERSION}.tar.gz"
if [ -s "${SOURCE_ARCHIVE}" ]; then
    echo "[OK] use cached source: $(basename "${SOURCE_ARCHIVE}")"
else
    echo "[INFO] source not found, download: redis-${REDIS_VERSION}.tar.gz"
    curl --fail --location --retry 5 --connect-timeout 20 --max-time 1200 \
        -o "${SOURCE_ARCHIVE}.tmp" \
        "https://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz"
    tar tzf "${SOURCE_ARCHIVE}.tmp" >/dev/null
    mv "${SOURCE_ARCHIVE}.tmp" "${SOURCE_ARCHIVE}"
fi

OPENSSL_ARCHIVE="${SOURCE_DIR}/openssl-${OPENSSL_VERSION}.tar.gz"
if [ -s "${OPENSSL_ARCHIVE}" ]; then
    echo "[OK] use cached dependency: $(basename "${OPENSSL_ARCHIVE}")"
else
    echo "[INFO] dependency not found, download: openssl-${OPENSSL_VERSION}.tar.gz"
    curl --fail --location --retry 5 --connect-timeout 20 --max-time 1200 \
        -o "${OPENSSL_ARCHIVE}.tmp" \
        "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
    tar tzf "${OPENSSL_ARCHIVE}.tmp" >/dev/null
    mv "${OPENSSL_ARCHIVE}.tmp" "${OPENSSL_ARCHIVE}"
fi

IMAGE_NAME="redis-builder:${REDIS_VERSION}-${ARCH}"
DOCKER_LOG="${OUTPUT_DIR}/docker-${ARCH}.log"
DOCKER_ARGS=(docker build --pull --platform "linux/${ARCH}" --build-arg "BUILDER_IMAGE=${BUILDER_IMAGE}" -t "${IMAGE_NAME}")
[ "${DOCKER_NO_CACHE}" = true ] && DOCKER_ARGS+=(--no-cache)
"${DOCKER_ARGS[@]}" . >"${DOCKER_LOG}" 2>&1

docker run --rm --platform "linux/${ARCH}" --entrypoint /bin/bash --user 0:0 \
    "${IMAGE_NAME}" -c "test \"\$(uname -m)\" = \"${EXPECTED_ARCH}\""

rm -f "${OUTPUT_DIR}"/redis-"${REDIS_VERSION}"-*-"${ARCH}".tar.gz*
docker run --rm --platform "linux/${ARCH}" --user 0:0 \
    -e "OUTPUT_DIR=${CONTAINER_OUTPUT_DIR}" \
    -e "REDIS_VERSION=${REDIS_VERSION}" \
    -e "OPENSSL_VERSION=${OPENSSL_VERSION}" \
    -v "${OUTPUT_DIR}:${CONTAINER_OUTPUT_DIR}" \
    "${IMAGE_NAME}"

package="${OUTPUT_DIR}/redis-${REDIS_VERSION}-glibc*-${ARCH}.tar.gz"
found=( ${package} )
[ -f "${found[0]}" ] || { echo '[ERROR] package not found' >&2; exit 1; }
(cd "${OUTPUT_DIR}" && sha256sum -c "$(basename "${found[0]}.sha256")")
echo "BUILD SUCCESS: ${found[0]}"
