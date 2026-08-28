#!/usr/bin/env bash
# Install OP-TEE-enabled kernel_2712 image + tee-supplicant service on the Pi.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_TARGET="${PI_TARGET:-${1:-skmitra@192.168.0.107}}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${ROOT_DIR}/artifacts/rpi5-optee}"
KERNEL_IMAGE="${KERNEL_IMAGE:-${ARTIFACT_DIR}/kernel_2712-optee.img}"
MODULES_STAGING="${MODULES_STAGING:-${ARTIFACT_DIR}/kernel-modules-staging}"
DO_REBOOT=0

for arg in "$@"; do
	case "$arg" in
		--reboot) DO_REBOOT=1 ;;
		*@*|*.*) PI_TARGET="$arg" ;;
	esac
done

if [[ ! -f "${KERNEL_IMAGE}" ]]; then
	echo "Missing ${KERNEL_IMAGE}; run ./build-rpi5-optee-kernel.sh first" >&2
	exit 1
fi

if [[ -n "${PI_SUDO_PASSWORD:-}" ]]; then
	export SSHPASS="${PI_SUDO_PASSWORD}"
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

KERNEL_RELEASE=""
if [[ -d "${MODULES_STAGING}/lib/modules" ]]; then
	KERNEL_RELEASE="$(basename "$(find "${MODULES_STAGING}/lib/modules" -mindepth 1 -maxdepth 1 -type d | head -1)")"
fi

echo "==> Copying kernel to ${PI_TARGET}"
remote_scp "${KERNEL_IMAGE}" "${PI_TARGET}:~/optee-rpi5/kernel_2712-optee.img"
if [[ -n "${KERNEL_RELEASE}" ]]; then
	echo "==> Copying kernel modules (${KERNEL_RELEASE})"
	# Use rsync (not scp -r): OpenSSH scp often nests the directory name,
	# ending up as /lib/modules/$KREL/$KREL/ and breaking depmod.
	remote_ssh "${PI_TARGET}" "rm -rf ~/optee-rpi5/kernel-modules && mkdir -p ~/optee-rpi5/kernel-modules"
	# Exclude dangling host-only build/source symlinks (paths from the build PC).
	RSYNC_EXCLUDES=(--exclude=build --exclude=source)
	if [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null 2>&1; then
		sshpass -e rsync -a --delete "${RSYNC_EXCLUDES[@]}" \
			-e "ssh -o StrictHostKeyChecking=accept-new" \
			"${MODULES_STAGING}/lib/modules/${KERNEL_RELEASE}/" \
			"${PI_TARGET}:~/optee-rpi5/kernel-modules/"
	else
		rsync -a --delete "${RSYNC_EXCLUDES[@]}" \
			"${MODULES_STAGING}/lib/modules/${KERNEL_RELEASE}/" \
			"${PI_TARGET}:~/optee-rpi5/kernel-modules/"
	fi
fi

echo "==> Installing kernel + tee-supplicant service"
remote_ssh "${PI_TARGET}" "bash -s" <<REMOTE
set -euo pipefail
BOOT=/boot/firmware
STAMP=\$(date +%Y%m%d-%H%M%S)
SRC="\${HOME}/optee-rpi5/kernel_2712-optee.img"
PASS='${SSHPASS:-}'

sudo_run() {
	if [[ -n "\${PASS}" ]]; then
		printf '%s\n' "\${PASS}" | sudo -S -p '' "\$@"
	else
		sudo "\$@"
	fi
}

if [[ ! -f "\${SRC}" ]]; then
	echo "Missing \${SRC}" >&2
	exit 1
fi

sudo_run cp -a "\${BOOT}/kernel_2712.img" "\${BOOT}/kernel_2712.img.bak-\${STAMP}"
sudo_run cp "\${SRC}" "\${BOOT}/kernel_2712.img"

KREL='${KERNEL_RELEASE}'
MOD_SRC="\${HOME}/optee-rpi5/kernel-modules"
# Tolerate a previously nested copy (.../KREL/KREL/) from old scp -r.
if [[ -n "\${KREL}" && -d "\${MOD_SRC}/\${KREL}" && ! -f "\${MOD_SRC}/modules.builtin" ]]; then
	MOD_SRC="\${MOD_SRC}/\${KREL}"
fi
if [[ -n "\${KREL}" && -d "\${MOD_SRC}" ]]; then
	echo "Installing modules for \${KREL}"
	if [[ ! -f "\${MOD_SRC}/modules.builtin" ]]; then
		echo "ERROR: modules tree incomplete (missing modules.builtin in \${MOD_SRC})" >&2
		ls -la "\${MOD_SRC}" >&2 || true
		exit 1
	fi
	sudo_run mkdir -p "/lib/modules/\${KREL}"
	# Wipe nested/broken previous installs before syncing.
	sudo_run rm -rf "/lib/modules/\${KREL}"
	sudo_run mkdir -p "/lib/modules/\${KREL}"
	sudo_run rsync -a "\${MOD_SRC}/" "/lib/modules/\${KREL}/"
	sudo_run depmod -a "\${KREL}"
fi
sync

sudo_run bash -c 'cat > /etc/systemd/system/tee-supplicant.service <<'\''UNIT'\''
[Unit]
Description=OP-TEE supplicant
After=local-fs.target

[Service]
Type=simple
ExecStart=/usr/sbin/tee-supplicant
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT'

sudo_run systemctl daemon-reload
sudo_run systemctl enable tee-supplicant.service

echo "Kernel installed (backup: kernel_2712.img.bak-\${STAMP})"
REMOTE

if [[ "${DO_REBOOT}" == "1" ]]; then
	# Use the same sudo password path as the install block (plain `sudo reboot` fails
	# when the Pi requires a password and only PI_SUDO_PASSWORD/SSHPASS is set).
	remote_ssh "${PI_TARGET}" "bash -s" <<REMOTE
set -euo pipefail
PASS='${SSHPASS:-}'
if [[ -n "\${PASS}" ]]; then
	printf '%s\n' "\${PASS}" | sudo -S -p '' reboot
else
	sudo -n reboot
fi
REMOTE
else
	echo "Reboot when ready: ssh ${PI_TARGET} 'sudo reboot'"
fi
