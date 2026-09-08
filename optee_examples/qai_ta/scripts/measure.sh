#!/usr/bin/env bash
# Phase 9 measurement helper (run on the Pi after deploy).
set -euo pipefail

N="${1:-200}"
HOST_BIN="${QAI_HOST:-qai_host}"

echo "===== QAI-OPTEE measurement (N=$N) ====="
echo
echo "--- Baseline ---"
"$HOST_BIN" --baseline --bench "$N"
echo
echo "--- TinyML ---"
"$HOST_BIN" --tinyml --bench "$N"
echo
echo "--- QAI hybrid ---"
"$HOST_BIN" --qai --bench "$N"
echo
echo "--- Protected QAI ---"
"$HOST_BIN" --protected --qai --bench "$N"
echo
echo "--- Model info ---"
"$HOST_BIN" --info
echo
echo "Done. Compare REE vs TEE avg times above for research tables."
