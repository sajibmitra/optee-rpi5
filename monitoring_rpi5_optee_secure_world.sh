#!/usr/bin/env bash
# Run a normal-world program that invokes secure world, while streaming secure logs.
#
# Usage:
#   export PI_SUDO_PASSWORD='...'
#   ./monitoring_rpi5_optee_secure_world.sh [user@host] [-- command [args...]]
#
# Default command (if none given):
#   xtest -l 0
#
# Examples:
#   ./monitoring_rpi5_optee_secure_world.sh skmitra@192.168.0.107
#   ./monitoring_rpi5_optee_secure_world.sh skmitra@192.168.0.107 -- xtest 1001
#   ./monitoring_rpi5_optee_secure_world.sh skmitra@192.168.0.107 -- xtest -l 0
#
# Secure-world lines are prefixed with [SEC]; normal-world with [NW].
# Requires optee-sw-log on the Pi (deployed via build-rpi5-optee.sh).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_DIR="${ARTIFACT_DIR:-${ROOT_DIR}/artifacts/rpi5-optee}"
PI_TARGET="${PI_TARGET:-skmitra@192.168.0.107}"
REMOTE_CMD=(xtest -l 0)

usage() {
	sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help) usage 0 ;;
		--)
			shift
			REMOTE_CMD=("$@")
			break
			;;
		*@*|*.*)
			PI_TARGET="$1"
			shift
			;;
		*)
			echo "ERROR: unexpected argument: $1 (use -- before remote command)" >&2
			usage 1
			;;
	esac
done

if [[ -n "${PI_SUDO_PASSWORD:-}" ]]; then
	export SSHPASS="${PI_SUDO_PASSWORD}"
elif [[ -n "${SSHPASS:-}" ]]; then
	export PI_SUDO_PASSWORD="${SSHPASS}"
fi

remote_ssh() {
	local ssh_args=(-o StrictHostKeyChecking=accept-new)
	if [[ -t 0 ]]; then
		ssh_args+=(-t)
	fi
	if [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null 2>&1; then
		sshpass -e ssh "${ssh_args[@]}" "$@"
	else
		ssh "${ssh_args[@]}" "$@"
	fi
}

remote_scp() {
	if [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null 2>&1; then
		sshpass -e scp -o StrictHostKeyChecking=accept-new "$@"
	else
		scp "$@"
	fi
}

PASS_ESC="${PI_SUDO_PASSWORD:-${SSHPASS:-}}"

ensure_optee_sw_log() {
	local host_bin="${ARTIFACT_DIR}/optee-sw-log"
	local src="${ROOT_DIR}/tools/optee-sw-log.c"

	if remote_ssh "${PI_TARGET}" 'test -x /usr/local/bin/optee-sw-log || test -x /usr/bin/optee-sw-log'; then
		return 0
	fi

	echo "==> optee-sw-log missing on Pi; installing from host"
	if [[ ! -x "${host_bin}" ]]; then
		mkdir -p "${ARTIFACT_DIR}"
		cc -O2 -Wall -Wextra -o "${host_bin}" "${src}"
	fi

	remote_scp "${host_bin}" "${PI_TARGET}:/tmp/optee-sw-log"
	remote_ssh "${PI_TARGET}" "printf '%s\n' '${PASS_ESC}' | sudo -S -p '' install -m755 /tmp/optee-sw-log /usr/local/bin/optee-sw-log"
	echo "==> Installed /usr/local/bin/optee-sw-log"
}

ensure_optee_sw_log

echo "==> Monitoring secure world on ${PI_TARGET}"
echo "==> Normal-world command: ${REMOTE_CMD[*]}"
echo ""

remote_ssh "${PI_TARGET}" bash -s -- "${REMOTE_CMD[@]}" <<REMOTE
set -euo pipefail
PASS='${PASS_ESC}'
REMOTE_CMD=("\$@")

SW_LOG=""
for p in /usr/local/bin/optee-sw-log /usr/bin/optee-sw-log; do
	if [[ -x "\$p" ]]; then
		SW_LOG="\$p"
		break
	fi
done
if [[ -z "\$SW_LOG" ]]; then
	echo "ERROR: optee-sw-log not found on Pi; redeploy with build-rpi5-optee.sh" >&2
	exit 1
fi

sudo_run() {
	if [[ -n "\${PASS}" ]]; then
		printf '%s\n' "\${PASS}" | sudo -S -p '' "\$@"
	else
		sudo "\$@"
	fi
}

FIFO="\$(mktemp -u /tmp/optee-sw-log.XXXXXX)"
mkfifo "\$FIFO"
trap 'rm -f "\$FIFO"; kill "\$LOG_PID" 2>/dev/null || true' EXIT

sudo_run "\$SW_LOG" -f >"\$FIFO" 2>/tmp/optee-sw-log.err &
LOG_PID=\$!

# If secure log buffer is missing, warn once but keep running the NW command.
(
	sleep 2
	if [[ -s /tmp/optee-sw-log.err ]]; then
		sed 's/^/[SEC-ERR] /' /tmp/optee-sw-log.err
	fi
) &
ERR_PID=\$!

sed -u 's/^/[SEC] /' "\$FIFO" &
SED_PID=\$!

sleep 0.3
echo "[NW] Running: \${REMOTE_CMD[*]}"
set +e
sudo_run "\${REMOTE_CMD[@]}" 2>&1 | sed -u 's/^/[NW] /'
NW_RC=\${PIPESTATUS[0]}
set -e

sleep 0.5
kill "\$ERR_PID" 2>/dev/null || true
wait "\$ERR_PID" 2>/dev/null || true
kill "\$LOG_PID" 2>/dev/null || true
wait "\$LOG_PID" 2>/dev/null || true
kill "\$SED_PID" 2>/dev/null || true
wait "\$SED_PID" 2>/dev/null || true

echo ""
echo "==> Normal-world command exited with status \${NW_RC}"
exit "\${NW_RC}"
REMOTE
