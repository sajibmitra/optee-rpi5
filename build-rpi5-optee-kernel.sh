#!/usr/bin/env bash
# Build Raspberry Pi 5 kernel (kernel_2712.img) with OP-TEE driver enabled.
#
# Uses the running Pi's /boot/config-* as base when available, otherwise the
# fetched pi-kernel.config in artifacts. Output:
#   artifacts/rpi5-optee/kernel_2712-optee.img
#
# Prerequisites (Debian/Ubuntu):
#   sudo apt-get install -y git bc bison flex libssl-dev libncurses-dev \
#       dwarves python3 rsync
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_DIR="${ARTIFACT_DIR:-${ROOT_DIR}/artifacts/rpi5-optee}"
CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/.cache}"
KERNEL_REPO="${KERNEL_REPO:-https://github.com/raspberrypi/linux.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-rpi-6.18.y}"
KERNEL_SRC="${KERNEL_SRC:-${CACHE_DIR}/linux-rpi}"
KERNEL_CONFIG_BASE="${KERNEL_CONFIG_BASE:-${ARTIFACT_DIR}/pi-kernel.config}"
KERNEL_FRAGMENT="${KERNEL_FRAGMENT:-${ROOT_DIR}/config/rpi5-kernel-optee.fragment}"
OUT_IMAGE="${OUT_IMAGE:-${ARTIFACT_DIR}/kernel_2712-optee.img}"
MODULES_STAGING="${MODULES_STAGING:-${ARTIFACT_DIR}/kernel-modules-staging}"
JOBS="${JOBS:-$(nproc)}"
ARCH=arm64

mkdir -p "${ARTIFACT_DIR}" "${CACHE_DIR}"

if [[ ! -f "${KERNEL_CONFIG_BASE}" ]]; then
	echo "Missing ${KERNEL_CONFIG_BASE}" >&2
	echo "Fetch from Pi: scp pi:/boot/config-\$(uname -r) ${KERNEL_CONFIG_BASE}" >&2
	exit 1
fi

if [[ ! -d "${KERNEL_SRC}/.git" ]]; then
	echo "==> Cloning ${KERNEL_REPO} (branch ${KERNEL_BRANCH})"
	git clone --depth 1 --branch "${KERNEL_BRANCH}" "${KERNEL_REPO}" "${KERNEL_SRC}"
else
	echo "==> Updating ${KERNEL_SRC}"
	git -C "${KERNEL_SRC}" fetch --depth 1 origin "${KERNEL_BRANCH}"
	git -C "${KERNEL_SRC}" checkout -f "${KERNEL_BRANCH}"
	git -C "${KERNEL_SRC}" reset --hard "origin/${KERNEL_BRANCH}"
fi

echo "==> Preparing kernel .config (base + OP-TEE fragment)"
cp -f "${KERNEL_CONFIG_BASE}" "${KERNEL_SRC}/.config"
if [[ -f "${KERNEL_FRAGMENT}" ]]; then
	while IFS= read -r line || [[ -n "${line}" ]]; do
		[[ -z "${line}" || "${line}" =~ ^# ]] && continue
		key="${line%%=*}"
		val="${line#*=}"
		case "${val}" in
			y) "${KERNEL_SRC}/scripts/config" --file "${KERNEL_SRC}/.config" --enable "${key}" ;;
			m) "${KERNEL_SRC}/scripts/config" --file "${KERNEL_SRC}/.config" --module "${key}" ;;
			n) "${KERNEL_SRC}/scripts/config" --file "${KERNEL_SRC}/.config" --disable "${key}" ;;
			*) "${KERNEL_SRC}/scripts/config" --file "${KERNEL_SRC}/.config" --set-val "${key}" "${val}" ;;
		esac
	done < "${KERNEL_FRAGMENT}"
fi
make -C "${KERNEL_SRC}" ARCH="${ARCH}" olddefconfig

if ! grep -q '^CONFIG_TEE=y' "${KERNEL_SRC}/.config" || ! grep -q '^CONFIG_OPTEE=y' "${KERNEL_SRC}/.config"; then
	echo "ERROR: CONFIG_TEE/CONFIG_OPTEE not enabled in kernel .config" >&2
	exit 1
fi

echo "==> Building kernel Image.gz + modules (this takes a while)"
make -C "${KERNEL_SRC}" ARCH="${ARCH}" -j"${JOBS}" Image.gz modules

cp -f "${KERNEL_SRC}/arch/arm64/boot/Image.gz" "${OUT_IMAGE}"
KERNEL_RELEASE="$(make -C "${KERNEL_SRC}" ARCH="${ARCH}" kernelrelease)"
rm -rf "${MODULES_STAGING}"
mkdir -p "${MODULES_STAGING}"
make -C "${KERNEL_SRC}" ARCH="${ARCH}" modules_install INSTALL_MOD_PATH="${MODULES_STAGING}"

echo "==> Wrote ${OUT_IMAGE} ($(stat -c%s "${OUT_IMAGE}") bytes)"
echo "==> Modules for ${KERNEL_RELEASE} staged in ${MODULES_STAGING}/lib/modules/${KERNEL_RELEASE}"
echo "Install with: ./install-rpi5-optee-kernel.sh [user@pi]"
