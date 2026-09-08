#!/usr/bin/env bash
# Deploy qai_host + QAI TA to a Raspberry Pi 5 over SSH.
# Usage: ./deploy-qai-ta.sh USER@PI_LAN_IP
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 USER@PI_LAN_IP" >&2
  exit 1
fi

TARGET="$1"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
QAI_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$QAI_DIR/out"

if [[ ! -x "$OUT/ca/qai_host" ]] || ! ls "$OUT/ta/"*.ta >/dev/null 2>&1; then
  echo "Artifacts missing; building..."
  "$QAI_DIR/scripts/build-qai-ta.sh"
fi

TA_NAME="$(basename "$(ls "$OUT/ta/"*.ta | head -1)")"
echo "Deploying to $TARGET ..."

scp "$OUT/ca/qai_host" "$TARGET:/tmp/qai_host"
scp "$OUT/ta/$TA_NAME" "$TARGET:/tmp/$TA_NAME"

ssh -t "$TARGET" "sudo install -m 0755 /tmp/qai_host /usr/local/bin/qai_host && \
  sudo install -m 0644 /tmp/$TA_NAME /lib/optee_armtz/$TA_NAME && \
  sudo systemctl restart tee-supplicant 2>/dev/null || true && \
  echo 'Installed:' && ls -l /usr/local/bin/qai_host /lib/optee_armtz/$TA_NAME"

echo
echo "Run on Pi:"
echo "  qai_host"
echo "  qai_host --tinyml"
echo "  qai_host --qai"
echo "  qai_host --protected --qai"
echo "  qai_host --bench 200"
echo "  qai_host --ree-compare"
