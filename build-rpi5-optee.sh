#!/usr/bin/env bash
# Build OP-TEE OS, client, tests, ATF armstub, and (optionally) the Pi kernel.
#
# Max logging (secure + normal world):
#   OPTEE_MAX_LOG=1 ./build-rpi5-optee.sh
#
# Or set levels individually (0=none .. 4=flow):
#   CFG_TEE_CORE_LOG_LEVEL=4 CFG_TEE_TA_LOG_LEVEL=4 \
#   CFG_TEE_CLIENT_LOG_LEVEL=4 CFG_TEE_SUPP_LOG_LEVEL=4 \
#   ./build-rpi5-optee.sh
#
# View logs on Pi:
#   Secure world (OP-TEE/TA): serial UART GPIO 14/15 @ 115200 (enable_uart=1)
#   tee-supplicant:           journalctl -fu tee-supplicant
#   libteec/xtest:            stdout (run in foreground)
#   Kernel driver:            dmesg -w | grep -i optee
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS="${JOBS:-$(nproc)}"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/rpi5-optee"
OPTEE_OS_DIR="${ROOT_DIR}/optee_os"
OPTEE_CLIENT_DIR="${ROOT_DIR}/optee_client"
OPTEE_CLIENT_EXPORT="${OPTEE_CLIENT_EXPORT:-${OPTEE_CLIENT_DIR}/out/export/usr}"
OPTEE_TEST_DIR="${ROOT_DIR}/optee_test"
ATF_DIR="${ROOT_DIR}/arm-trusted-firmware"
TA_DEV_KIT_DIR="${OPTEE_OS_DIR}/out/arm-plat-rpi5/export-ta_arm64"
SKIP_KERNEL_BUILD="${SKIP_KERNEL_BUILD:-0}"

# Logging (secure world + normal world). Levels 0–4: none, error, info, debug, flow.
# Shortcut: OPTEE_MAX_LOG=1 sets all log levels to 4 (max verbosity).
if [[ "${OPTEE_MAX_LOG:-0}" == "1" ]]; then
	CFG_TEE_CORE_LOG_LEVEL="${CFG_TEE_CORE_LOG_LEVEL:-4}"
	CFG_TEE_TA_LOG_LEVEL="${CFG_TEE_TA_LOG_LEVEL:-4}"
	CFG_TEE_CLIENT_LOG_LEVEL="${CFG_TEE_CLIENT_LOG_LEVEL:-4}"
	CFG_TEE_SUPP_LOG_LEVEL="${CFG_TEE_SUPP_LOG_LEVEL:-4}"
else
	CFG_TEE_CORE_LOG_LEVEL="${CFG_TEE_CORE_LOG_LEVEL:-2}"
	CFG_TEE_TA_LOG_LEVEL="${CFG_TEE_TA_LOG_LEVEL:-1}"
	CFG_TEE_CLIENT_LOG_LEVEL="${CFG_TEE_CLIENT_LOG_LEVEL:-1}"
	CFG_TEE_SUPP_LOG_LEVEL="${CFG_TEE_SUPP_LOG_LEVEL:-1}"
fi

# Must match plat/rpi/rpi5/include/platform_def.h and plat-rpi5 conf.mk
BL31_PAD_SIZE=$((0x80000))          # BL31_LIMIT / RPI5_OPTEE_EMBED_BASE
OPTEE_EMBED_SIZE=$((0x80000))       # RPI5_OPTEE_EMBED_SIZE
OPTEE_LOAD_BASE="0x1D000000"        # RPI5_OPTEE_LOAD_BASE / CFG_TZDRAM_START
OPTEE_LOAD_SIZE="0x02000000"        # CFG_TZDRAM_SIZE
KERNEL_LOAD_ADDR="0x200000"         # must be above embedded OP-TEE in armstub

mkdir -p "${ARTIFACT_DIR}"

echo "==> Log levels: core=${CFG_TEE_CORE_LOG_LEVEL} ta=${CFG_TEE_TA_LOG_LEVEL} client=${CFG_TEE_CLIENT_LOG_LEVEL} supplicant=${CFG_TEE_SUPP_LOG_LEVEL}"
echo "    Secure-world output -> PL011 UART (GPIO 14/15); NW -> journalctl/stdout"

echo "==> Building OP-TEE OS for Raspberry Pi 5, AArch64 core and AArch64 TAs"
make -C "${OPTEE_OS_DIR}" \
	PLATFORM=rpi5 \
	CROSS_COMPILE=aarch64-linux-gnu- \
	CFG_ARM64_core=y \
	CFG_USER_TA_TARGETS=ta_arm64 \
	CFG_TZDRAM_START="${OPTEE_LOAD_BASE}" \
	CFG_TZDRAM_SIZE="${OPTEE_LOAD_SIZE}" \
	CFG_RPI5_SW_LOG="${CFG_RPI5_SW_LOG:-y}" \
	CFG_TEE_CORE_LOG_LEVEL="${CFG_TEE_CORE_LOG_LEVEL}" \
	CFG_TEE_TA_LOG_LEVEL="${CFG_TEE_TA_LOG_LEVEL}" \
	-j"${JOBS}"

echo "==> Building OP-TEE client natively for Raspberry Pi OS/Ubuntu arm64"
make -C "${OPTEE_CLIENT_DIR}" \
	CROSS_COMPILE= \
	CFG_TEE_CLIENT_LOG_LEVEL="${CFG_TEE_CLIENT_LOG_LEVEL}" \
	CFG_TEE_SUPP_LOG_LEVEL="${CFG_TEE_SUPP_LOG_LEVEL}" \
	-j"${JOBS}"

echo "==> Building OP-TEE test with the AArch64 TA dev kit"
# Remove stale nested build dir that blocks linking out/xtest/xtest (the binary).
rm -rf "${OPTEE_TEST_DIR}/out/xtest/xtest"
make -C "${OPTEE_TEST_DIR}" \
	CROSS_COMPILE= \
	TA_DEV_KIT_DIR="${TA_DEV_KIT_DIR}" \
	OPTEE_CLIENT_EXPORT="${OPTEE_CLIENT_EXPORT}" \
	CFG_TEE_TA_LOG_LEVEL="${CFG_TEE_TA_LOG_LEVEL}" \
	-j"${JOBS}"

echo "==> Building Arm Trusted Firmware BL31 for Raspberry Pi 5 (SPD=opteed)"
make -C "${ATF_DIR}" \
	PLAT=rpi5 \
	DEBUG=1 \
	CROSS_COMPILE=aarch64-linux-gnu- \
	SPD=opteed \
	-j"${JOBS}"

echo "==> Staging boot and OP-TEE binaries in ${ARTIFACT_DIR}"
cp -f "${ATF_DIR}/build/rpi5/debug/bl31.bin" "${ARTIFACT_DIR}/"
cp -f \
	"${OPTEE_OS_DIR}/out/arm-plat-rpi5/core/tee.elf" \
	"${OPTEE_OS_DIR}/out/arm-plat-rpi5/core/tee.bin" \
	"${OPTEE_OS_DIR}/out/arm-plat-rpi5/core/tee-raw.bin" \
	"${OPTEE_OS_DIR}/out/arm-plat-rpi5/core/tee-header_v2.bin" \
	"${OPTEE_OS_DIR}/out/arm-plat-rpi5/core/tee-pager_v2.bin" \
	"${OPTEE_OS_DIR}/out/arm-plat-rpi5/core/tee-pageable_v2.bin" \
	"${ARTIFACT_DIR}/"

BL31_BIN="${ARTIFACT_DIR}/bl31.bin"
TEE_RAW="${ARTIFACT_DIR}/tee-raw.bin"
ARMSTUB="${ARTIFACT_DIR}/armstub8-2712-optee.bin"

BL31_SIZE=$(stat -c%s "${BL31_BIN}")
TEE_SIZE=$(stat -c%s "${TEE_RAW}")

if (( BL31_SIZE > BL31_PAD_SIZE )); then
	echo "ERROR: bl31.bin (${BL31_SIZE}) exceeds BL31 pad region (${BL31_PAD_SIZE})" >&2
	exit 1
fi
if (( TEE_SIZE > OPTEE_EMBED_SIZE )); then
	echo "ERROR: tee-raw.bin (${TEE_SIZE}) exceeds OP-TEE embed region (${OPTEE_EMBED_SIZE})" >&2
	exit 1
fi

echo "==> Building embedded armstub (BL31 @ 0x0 + OP-TEE @ 0x$(printf '%x' "${BL31_PAD_SIZE}"))"
# Layout: [0, 0x80000) BL31 zero-padded | [0x80000, 0x100000) tee-raw zero-padded
{
	cat "${BL31_BIN}"
	dd if=/dev/zero bs=1 count=$((BL31_PAD_SIZE - BL31_SIZE)) status=none
	cat "${TEE_RAW}"
	dd if=/dev/zero bs=1 count=$((OPTEE_EMBED_SIZE - TEE_SIZE)) status=none
} > "${ARMSTUB}"
chmod +x "${ARMSTUB}"

# Keep a clearly named copy for humans debugging older drops
cp -f "${ARMSTUB}" "${ARTIFACT_DIR}/armstub8-2712-optee-embedded.bin"

ARMSTUB_SIZE=$(stat -c%s "${ARMSTUB}")
EXPECTED_SIZE=$((BL31_PAD_SIZE + OPTEE_EMBED_SIZE))
if (( ARMSTUB_SIZE != EXPECTED_SIZE )); then
	echo "ERROR: armstub size ${ARMSTUB_SIZE} != expected ${EXPECTED_SIZE}" >&2
	exit 1
fi

echo "==> Staging OP-TEE client into rootfs-overlay"
OVERLAY="${ARTIFACT_DIR}/rootfs-overlay"
rm -rf "${OVERLAY}"
mkdir -p "${OVERLAY}/usr/sbin" "${OVERLAY}/usr/lib" "${OVERLAY}/lib/optee_armtz"
if [[ -x "${OPTEE_CLIENT_DIR}/out/tee-supplicant/tee-supplicant" ]]; then
	cp -f "${OPTEE_CLIENT_DIR}/out/tee-supplicant/tee-supplicant" "${OVERLAY}/usr/sbin/"
fi
if [[ -d "${OPTEE_CLIENT_DIR}/out/libteec" ]]; then
	cp -a "${OPTEE_CLIENT_DIR}/out/libteec"/libteec.so* "${OVERLAY}/usr/lib/" 2>/dev/null || true
	cp -a "${OPTEE_CLIENT_DIR}/out/libteec"/libteec.a "${OVERLAY}/usr/lib/" 2>/dev/null || true
fi
# Optional extra client libs when present
for libdir in libckteec libseteec libteeacl libasteec; do
	if [[ -d "${OPTEE_CLIENT_DIR}/out/${libdir}" ]]; then
		cp -a "${OPTEE_CLIENT_DIR}/out/${libdir}"/lib*.so* "${OVERLAY}/usr/lib/" 2>/dev/null || true
		cp -a "${OPTEE_CLIENT_DIR}/out/${libdir}"/lib*.a "${OVERLAY}/usr/lib/" 2>/dev/null || true
	fi
done
if [[ -d "${TA_DEV_KIT_DIR}/../ta" ]] || [[ -d "${OPTEE_OS_DIR}/out/arm-plat-rpi5/export-ta_arm64/ta" ]]; then
	TA_SRC="${OPTEE_OS_DIR}/out/arm-plat-rpi5/export-ta_arm64/ta"
	if compgen -G "${TA_SRC}/*.ta" >/dev/null; then
		cp -f "${TA_SRC}"/*.ta "${OVERLAY}/lib/optee_armtz/" || true
	fi
fi
# xtest + regression TAs for on-device validation
XTEST_BIN="${OPTEE_TEST_DIR}/out/xtest/xtest"
if [[ ! -x "${XTEST_BIN}" ]]; then
	echo "ERROR: xtest binary missing at ${XTEST_BIN}" >&2
	exit 1
fi
mkdir -p "${OVERLAY}/usr/local/bin"
cp -f "${XTEST_BIN}" "${OVERLAY}/usr/local/bin/xtest"

echo "==> Building optee-sw-log (secure-world log monitor for SSH)"
OPTEE_SW_LOG_BIN="${ARTIFACT_DIR}/optee-sw-log"
cc -O2 -Wall -Wextra -o "${OPTEE_SW_LOG_BIN}" "${ROOT_DIR}/tools/optee-sw-log.c"
cp -f "${OPTEE_SW_LOG_BIN}" "${OVERLAY}/usr/local/bin/optee-sw-log"

while IFS= read -r -d '' ta; do
	cp -f "${ta}" "${OVERLAY}/lib/optee_armtz/"
done < <(find "${OPTEE_TEST_DIR}/out/ta" -name '*.ta' -print0 2>/dev/null || true)

# tee-supplicant test plugin (needed for xtest regression_1033)
PLUGIN_SRC="${OPTEE_TEST_DIR}/out/supp_plugin"
if compgen -G "${PLUGIN_SRC}/*.plugin" >/dev/null; then
	mkdir -p "${OVERLAY}/usr/lib/tee-supplicant/plugins"
	cp -f "${PLUGIN_SRC}"/*.plugin "${OVERLAY}/usr/lib/tee-supplicant/plugins/"
	echo "  -> Staged tee-supplicant plugins from ${PLUGIN_SRC}"
else
	echo "WARNING: no *.plugin under ${PLUGIN_SRC}; regression_1033 will fail until rebuilt" >&2
fi

# Device-tree overlay source for reserved TZDRAM / SHMEM (compiled on the Pi if needed)
mkdir -p "${ARTIFACT_DIR}/overlays"
cat > "${ARTIFACT_DIR}/overlays/optee-rpi5-overlay.dts" <<'DTS'
/dts-v1/;
/plugin/;

/ {
	compatible = "brcm,bcm2712";

	fragment@0 {
		target-path = "/";
		__overlay__ {
			reserved-memory {
				#address-cells = <2>;
				#size-cells = <2>;
				ranges;

				optee@1d000000 {
					reg = <0x0 0x1d000000 0x0 0x02000000>;
					no-map;
				};

				optee-shm@8000000 {
					reg = <0x0 0x08000000 0x0 0x00400000>;
					no-map;
				};
			};
		};
	};
};
DTS

cat > "${ARTIFACT_DIR}/MEMORY-LAYOUT.txt" <<EOF
Raspberry Pi 5 OP-TEE memory layout
===================================

Armstub (armstub8-2712-optee.bin), loaded at PA 0 by VPU:
  0x00000000 - 0x00080000  BL31 (TF-A, SPD=opteed)
  0x00080000 - 0x00100000  Embedded OP-TEE (tee-raw.bin, padded)

Runtime:
  ${OPTEE_LOAD_BASE} + ${OPTEE_LOAD_SIZE}  TZDRAM / BL32 (OP-TEE)
  0x08000000 + 0x00400000                 OP-TEE shared memory (CFG_SHMEM_*)
  0x08400000 + 0x00010000                 Secure-world log ring (optee_sw_log)

Linux must use:
  kernel_address=${KERNEL_LOAD_ADDR}
so the kernel image does not overwrite the embedded OP-TEE before BL31 copies
it to TZDRAM.

BL32 handoff (opteed): arg0=MODE_RW_64, arg1/arg2=0, arg3=DTB PA.
Do not use dtoverlay=optee-rpi5; OP-TEE CFG_DT=y patches the DTB at boot.

Secure-world live log over SSH: sudo optee-sw-log -f
  (ring buffer at 0x08400000; also mirrored on PL011 UART if serial attached)

Note: Linux needs CONFIG_TEE/OPTEE driver for /dev/tee* (not in default Pi kernel).
Kernel image: artifacts/rpi5-optee/kernel_2712-optee.img (CONFIG_TEE/OPTEE=y).
EOF

if [[ "${SKIP_KERNEL_BUILD}" != "1" ]]; then
	echo "==> Building OP-TEE-enabled Pi kernel (Image.gz + modules)"
	ARTIFACT_DIR="${ARTIFACT_DIR}" JOBS="${JOBS}" "${ROOT_DIR}/build-rpi5-optee-kernel.sh"
else
	echo "==> Skipping kernel build (SKIP_KERNEL_BUILD=1)"
fi

echo "==> Done"
echo "Artifacts:"
ls -lh "${ARTIFACT_DIR}"
echo
echo "Embedded armstub: ${ARMSTUB} (${ARMSTUB_SIZE} bytes)"
echo "Require in config.txt: armstub=armstub8-2712-optee.bin and kernel_address=${KERNEL_LOAD_ADDR}"
if [[ -f "${ARTIFACT_DIR}/kernel_2712-optee.img" ]]; then
	echo "Kernel: ${ARTIFACT_DIR}/kernel_2712-optee.img"
	echo "Install kernel: ./install-rpi5-optee-kernel.sh [user@pi] [--reboot]"
fi
if [[ -x "${OVERLAY}/usr/local/bin/xtest" ]]; then
	echo "xtest staged in rootfs-overlay (run on Pi: sudo xtest -l 0)"
fi
if [[ -x "${OVERLAY}/usr/local/bin/optee-sw-log" ]]; then
	echo "Secure-world SSH log: sudo optee-sw-log -f"
fi
echo
echo "Note: do not deploy plain bl31.bin as the armstub when RPI5_EMBEDDED_OPTEE=1."
