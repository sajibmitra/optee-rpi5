#!/usr/bin/env bash
# Build qai_ta host + TA for Raspberry Pi 5 OP-TEE.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
QAI_DIR="$(cd "$(dirname "$0")/.." && pwd)"

TA_DEV_KIT_DIR="${TA_DEV_KIT_DIR:-$ROOT/optee_os/out/arm-plat-rpi5/export-ta_arm64}"
TEEC_EXPORT="${TEEC_EXPORT:-$ROOT/optee_client/out/export/usr}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

if [[ ! -f "$TA_DEV_KIT_DIR/mk/ta_dev_kit.mk" ]]; then
  echo "ERROR: TA_DEV_KIT_DIR missing: $TA_DEV_KIT_DIR" >&2
  echo "Build OP-TEE OS first (./build-rpi5-optee.sh)." >&2
  exit 1
fi
if [[ ! -d "$TEEC_EXPORT/include" ]]; then
  echo "ERROR: TEEC_EXPORT missing: $TEEC_EXPORT" >&2
  exit 1
fi

echo "TA_DEV_KIT_DIR=$TA_DEV_KIT_DIR"
echo "TEEC_EXPORT=$TEEC_EXPORT"
echo "CROSS_COMPILE=$CROSS_COMPILE"

make -C "$QAI_DIR" clean || true
make -C "$QAI_DIR" \
  CROSS_COMPILE="$CROSS_COMPILE" \
  TA_DEV_KIT_DIR="$TA_DEV_KIT_DIR" \
  TEEC_EXPORT="$TEEC_EXPORT" \
  -j"$(nproc)"

OUT="$QAI_DIR/out"
mkdir -p "$OUT/ta" "$OUT/ca"
cp -f "$QAI_DIR/host/qai_host" "$OUT/ca/"
cp -f "$QAI_DIR/ta/"*.ta "$OUT/ta/"
echo "Built artifacts:"
ls -la "$OUT/ca" "$OUT/ta"
