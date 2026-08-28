#!/usr/bin/env bash
# Verify OP-TEE + kernel deployment on Raspberry Pi 5.
#
# Usage:
#   export PI_SUDO_PASSWORD='...'
#   ./testing_rpi5_optee_kernel.sh [user@host] [options]
#
# Options:
#   --quick          Smoke tests only (skip xtest regression)
#   --xtest-level N  xtest level (default: 0)
#   -h, --help
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_TARGET="${PI_TARGET:-skmitra@192.168.0.107}"
QUICK=0
XTEST_LEVEL=0
FAILURES=0

usage() {
	sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help) usage 0 ;;
		--quick) QUICK=1; shift ;;
		--xtest-level) XTEST_LEVEL="${2:?--xtest-level requires a value}"; shift 2 ;;
		--xtest-level=*) XTEST_LEVEL="${1#*=}"; shift ;;
		*@*|*.*) PI_TARGET="$1"; shift ;;
		*)
			echo "Unknown option: $1" >&2
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
	if [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null 2>&1; then
		sshpass -e ssh -o StrictHostKeyChecking=accept-new "$@"
	else
		ssh "$@"
	fi
}

check() {
	local name="$1"
	local cmd="$2"
	echo ""
	echo "==> ${name}"
	if remote_ssh "${PI_TARGET}" "${cmd}"; then
		echo "    PASS"
	else
		echo "    FAIL" >&2
		FAILURES=$((FAILURES + 1))
	fi
}

PASS_ESC="${PI_SUDO_PASSWORD:-${SSHPASS:-}}"

echo "==> Testing OP-TEE deployment on ${PI_TARGET}"

check "SSH reachability" 'uname -snrm'

check "config.txt armstub + kernel_address" \
	"grep -E '^armstub=armstub8-2712-optee.bin$|^kernel_address=0x200000$' /boot/firmware/config.txt"

check "/dev/tee0 and /dev/teepriv0" \
	'test -c /dev/tee0 && test -c /dev/teepriv0 && ls -l /dev/tee0 /dev/teepriv0'

check "tee-supplicant active" \
	'systemctl is-active tee-supplicant'

check "optee kernel driver (dmesg)" \
	"printf '%s\n' '${PASS_ESC}' | sudo -S -p '' dmesg | grep -qi 'optee: initialized driver'"

check "optee-sw-log installed" \
	'test -x /usr/local/bin/optee-sw-log || test -x /usr/bin/optee-sw-log'

check "xtest installed" \
	'command -v xtest >/dev/null'

check "test TAs present" \
	'test "$(ls -1 /lib/optee_armtz/*.ta 2>/dev/null | wc -l)" -ge 5'

check "wlan0 or eth0 up (network)" \
	'nmcli -t -f DEVICE,STATE device | grep -E "^(eth0|wlan0):connected"'

if [[ "${QUICK}" == "1" ]]; then
	echo ""
	echo "==> Quick mode: skipping xtest regression"
else
	echo ""
	echo "==> Running xtest -l ${XTEST_LEVEL} (may take several minutes)"
	XTEST_LOG="/tmp/xtest-rpi5-$(date +%Y%m%d%H%M%S).log"
	if remote_ssh "${PI_TARGET}" \
		"printf '%s\n' '${PASS_ESC}' | sudo -S -p '' xtest -l ${XTEST_LEVEL}" \
		| tee "${XTEST_LOG}"; then
		if grep -qE '[0-9]+ test cases of which [1-9][0-9]* failed' "${XTEST_LOG}"; then
			echo "    FAIL: some xtest cases failed (see ${XTEST_LOG})" >&2
			FAILURES=$((FAILURES + 1))
		else
			echo "    PASS: xtest completed"
		fi
	else
		echo "    FAIL: xtest execution error" >&2
		FAILURES=$((FAILURES + 1))
	fi
fi

echo ""
if [[ "${FAILURES}" -eq 0 ]]; then
	echo "==> All tests passed"
	exit 0
fi

echo "==> ${FAILURES} test(s) failed" >&2
exit 1
