#!/usr/bin/env bash
# Full OP-TEE + kernel deployment to Raspberry Pi 5 (fresh OS or upgrade).
#
# Merges: fetch kernel config (optional) -> build -> deploy armstub/userspace ->
#         install OP-TEE kernel + modules -> reboot -> wait for SSH.
#
# Usage:
#   export PI_SUDO_PASSWORD='...'
#   ./deploy_rpi5_optee_kernel.sh [user@host] [options]
#
# Options:
#   --skip-build                 Use existing artifacts (skip build-rpi5-optee.sh)
#   --skip-kernel-config-fetch   Do not refresh artifacts/rpi5-optee/pi-kernel.config
#   --no-reboot                  Install kernel but do not reboot
#   --no-wait                    Do not wait for Pi after reboot
#   -h, --help
#
# Environment:
#   PI_SUDO_PASSWORD / SSHPASS   Non-interactive sudo on the Pi
#   OPTEE_MAX_LOG=1              Max secure + normal world log levels (default: 1)
#   JOBS                         Parallel build jobs
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_TARGET="${PI_TARGET:-skmitra@192.168.0.107}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${ROOT_DIR}/artifacts/rpi5-optee}"
KERNEL_CONFIG="${KERNEL_CONFIG:-${ARTIFACT_DIR}/pi-kernel.config}"
SKIP_BUILD=0
SKIP_KERNEL_CONFIG_FETCH=0
DO_REBOOT=1
DO_WAIT=1
OPTEE_MAX_LOG="${OPTEE_MAX_LOG:-1}"

usage() {
	sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

for arg in "$@"; do
	case "$arg" in
		-h|--help) usage 0 ;;
		--skip-build) SKIP_BUILD=1 ;;
		--skip-kernel-config-fetch) SKIP_KERNEL_CONFIG_FETCH=1 ;;
		--no-reboot) DO_REBOOT=0; DO_WAIT=0 ;;
		--no-wait) DO_WAIT=0 ;;
		*@*|*.*) PI_TARGET="$arg" ;;
		*)
			echo "Unknown option: $arg" >&2
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

remote_scp() {
	if [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null 2>&1; then
		sshpass -e scp -o StrictHostKeyChecking=accept-new "$@"
	else
		scp "$@"
	fi
}

wait_for_pi() {
	local tries="${1:-180}"
	local i=0
	local targets=("${PI_TARGET}")
	# If waiting on Ethernet, also try known WiFi IP (and vice versa).
	case "${PI_TARGET}" in
		*@192.168.0.107) targets+=("${PI_TARGET%@*}@172.20.10.2") ;;
		*@172.20.10.2) targets+=("${PI_TARGET%@*}@192.168.0.107") ;;
	esac

	echo "==> Waiting for SSH (up to ${tries}s): ${targets[*]}"
	while (( i < tries )); do
		for t in "${targets[@]}"; do
			if remote_ssh -o ConnectTimeout=5 -o BatchMode=yes "${t}" 'true' 2>/dev/null; then
				echo "==> Pi is back online at ${t}"
				PI_TARGET="${t}"
				return 0
			fi
		done
		sleep 5
		(( i += 5 )) || true
	done
	echo "ERROR: none of [${targets[*]}] accepted SSH within ${tries}s" >&2
	echo "       Router/link flaps can look like a boot hang. Check HDMI/UART or both IPs." >&2
	return 1
}

echo "==> Target: ${PI_TARGET}"
remote_ssh -o ConnectTimeout=10 "${PI_TARGET}" 'echo "  Pi reachable: $(uname -snrm)"'

if [[ "${SKIP_KERNEL_CONFIG_FETCH}" != "1" ]]; then
	echo "==> Refreshing ${KERNEL_CONFIG} from Pi"
	mkdir -p "${ARTIFACT_DIR}"
	KVER="$(remote_ssh "${PI_TARGET}" 'uname -r')"
	FETCHED=0
	# Custom OP-TEE kernels often lack /boot/firmware/config-$KVER; try common paths.
	for remote_cfg in \
		"/boot/firmware/config-${KVER}" \
		"/boot/config-${KVER}" \
		"/boot/config-6.18.34+rpt-rpi-2712" \
		"/boot/config-6.12.25+rpt-rpi-2712"
	do
		if remote_ssh "${PI_TARGET}" "test -f '${remote_cfg}'" 2>/dev/null; then
			if remote_scp "${PI_TARGET}:${remote_cfg}" "${KERNEL_CONFIG}.new" 2>/dev/null; then
				mv -f "${KERNEL_CONFIG}.new" "${KERNEL_CONFIG}"
				echo "  -> Updated $(basename "${KERNEL_CONFIG}") from ${remote_cfg}"
				FETCHED=1
				break
			fi
		fi
	done
	if [[ "${FETCHED}" != "1" ]]; then
		if [[ -f "${KERNEL_CONFIG}" ]]; then
			echo "  -> No remote config for ${KVER}; keeping existing $(basename "${KERNEL_CONFIG}")"
		else
			echo "ERROR: No kernel config on Pi and ${KERNEL_CONFIG} missing locally." >&2
			echo "       Copy one manually, e.g. scp pi:/boot/config-*-rpi-2712 ${KERNEL_CONFIG}" >&2
			exit 1
		fi
	fi
else
	echo "==> Skipping kernel config fetch (--skip-kernel-config-fetch)"
fi

if [[ "${SKIP_BUILD}" != "1" ]]; then
	echo "==> Building OP-TEE stack + kernel (OPTEE_MAX_LOG=${OPTEE_MAX_LOG})"
	OPTEE_MAX_LOG="${OPTEE_MAX_LOG}" JOBS="${JOBS:-$(nproc)}" "${ROOT_DIR}/build-rpi5-optee.sh"
else
	echo "==> Skipping build (--skip-build)"
	require_artifacts() {
		local f
		for f in \
			"${ARTIFACT_DIR}/armstub8-2712-optee.bin" \
			"${ARTIFACT_DIR}/kernel_2712-optee.img"
		do
			[[ -f "$f" ]] || { echo "Missing $f; run without --skip-build" >&2; exit 1; }
		done
	}
	require_artifacts
fi

echo "==> Deploying armstub + OP-TEE userspace (no reboot yet)"
PI_TARGET="${PI_TARGET}" "${ROOT_DIR}/deploy-rpi5-optee.sh" "${PI_TARGET}"

echo "==> Installing OP-TEE kernel + modules"
INSTALL_ARGS=("${PI_TARGET}")
if [[ "${DO_REBOOT}" == "1" ]]; then
	INSTALL_ARGS+=(--reboot)
fi
PI_TARGET="${PI_TARGET}" "${ROOT_DIR}/install-rpi5-optee-kernel.sh" "${INSTALL_ARGS[@]}"

if [[ "${DO_REBOOT}" == "1" && "${DO_WAIT}" == "1" ]]; then
	sleep 10
	wait_for_pi 180
	echo "==> Post-reboot quick check"
	remote_ssh "${PI_TARGET}" 'uname -r; ls -l /dev/tee0 /dev/teepriv0 2>/dev/null || true'
fi

echo "==> Deployment complete"
echo "Next: ./testing_rpi5_optee_kernel.sh ${PI_TARGET}"
echo "      ./monitoring_rpi5_optee_secure_world.sh ${PI_TARGET} -- xtest -l 0"
