#!/usr/bin/env bash
# Deploy embedded BL31+OP-TEE armstub + OP-TEE userspace to a Raspberry Pi 5.
#
# WiFi note
# ---------
# OP-TEE firmware (armstub / tee*.bin / config.txt keys) does NOT live in the
# same place as WiFi profiles. On Raspberry Pi OS Bookworm, WiFi is in:
#   /etc/NetworkManager/system-connections/  and/or  /etc/netplan/
# This script NEVER copies into those paths. It only backs them up.
# If SSH dies after reboot, the usual cause is a bad armstub/boot hang — not
# deleted WiFi settings. Recover via HDMI/UART/Ethernet or by editing the
# boot FAT from another machine (see recover-boot-wifi.sh).
#
# Sudo: set PI_SUDO_PASSWORD (or SSHPASS) to allow non-interactive sudo -S.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_TARGET="${PI_TARGET:-${1:-skmitra@192.168.0.107}}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${ROOT_DIR}/artifacts/rpi5-optee}"
CLIENT_OUT_DIR="${CLIENT_OUT_DIR:-${ROOT_DIR}/optee_client/out}"
TA_DIR="${TA_DIR:-${ROOT_DIR}/optee_os/out/arm-plat-rpi5/export-ta_arm64/ta}"
REMOTE_DIR="${REMOTE_DIR:-optee-rpi5}"
DO_REBOOT=0
EXPECTED_ARMSTUB_SIZE=$((0x100000))  # BL31_PAD + OPTEE_EMBED

for arg in "$@"; do
	case "$arg" in
		--help|-h)
			echo "Usage: $(basename "$0") [user@host] [--reboot]"
			echo "Default target: ${PI_TARGET}"
			echo
			echo "Deploys embedded BL31+OP-TEE armstub and Linux OP-TEE userspace."
			echo "Never overwrites NetworkManager / wpa_supplicant / netplan WiFi config."
			echo "Optional: PI_SUDO_PASSWORD or SSHPASS for non-interactive sudo."
			exit 0
			;;
		--reboot)
			DO_REBOOT=1
			;;
		*@*|*.*)
			PI_TARGET="$arg"
			;;
	esac
done

require_file() {
	[[ -f "$1" ]] || { echo "Missing required file: $1" >&2; exit 1; }
}

# Prefer PI_SUDO_PASSWORD; fall back to SSHPASS if already set for sshpass.
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

echo "==> Checking local artifacts in ${ARTIFACT_DIR}"
require_file "${ARTIFACT_DIR}/armstub8-2712-optee.bin"
require_file "${ARTIFACT_DIR}/bl31.bin"
require_file "${ARTIFACT_DIR}/tee-raw.bin"
require_file "${ARTIFACT_DIR}/tee.bin"

ARMSTUB_SIZE=$(stat -c%s "${ARTIFACT_DIR}/armstub8-2712-optee.bin")
if (( ARMSTUB_SIZE != EXPECTED_ARMSTUB_SIZE )); then
	echo "ERROR: ${ARTIFACT_DIR}/armstub8-2712-optee.bin is ${ARMSTUB_SIZE} bytes;" >&2
	echo "       expected ${EXPECTED_ARMSTUB_SIZE} (BL31 padded to 512KiB + OP-TEE padded to 512KiB)." >&2
	echo "       Re-run ./build-rpi5-optee.sh before deploying." >&2
	exit 1
fi

# Refuse overlays that could clobber WiFi / network config on the rootfs.
if [[ -d "${ARTIFACT_DIR}/rootfs-overlay" ]]; then
	for bad in \
		"${ARTIFACT_DIR}/rootfs-overlay/etc/NetworkManager" \
		"${ARTIFACT_DIR}/rootfs-overlay/etc/netplan" \
		"${ARTIFACT_DIR}/rootfs-overlay/etc/wpa_supplicant" \
		"${ARTIFACT_DIR}/rootfs-overlay/boot"
	do
		if [[ -e "${bad}" ]]; then
			echo "ERROR: refusing deploy; overlay must not contain network/boot paths:" >&2
			echo "       ${bad}" >&2
			exit 1
		fi
	done
fi

python3 - "${ARTIFACT_DIR}/armstub8-2712-optee.bin" "${ARTIFACT_DIR}/tee-raw.bin" <<'PY'
import sys
armstub = open(sys.argv[1], "rb").read()
tee = open(sys.argv[2], "rb").read()
off = 0x80000
if armstub[off:off + len(tee)] != tee:
    raise SystemExit("ERROR: armstub OP-TEE region does not match tee-raw.bin; rebuild artifacts")
print(f"  armstub layout OK (tee-raw at 0x{off:x}, {len(tee)} bytes)")
PY

echo "==> Creating remote drop directory on ${PI_TARGET}"
remote_ssh "${PI_TARGET}" "mkdir -p ~/${REMOTE_DIR}/overlays ~/${REMOTE_DIR}/rootfs-overlay"

echo "==> Copying boot artifacts (explicit list; never copies WiFi/network configs)"
remote_scp \
	"${ARTIFACT_DIR}/armstub8-2712-optee.bin" \
	"${ARTIFACT_DIR}/bl31.bin" \
	"${ARTIFACT_DIR}/tee.bin" \
	"${ARTIFACT_DIR}/tee-raw.bin" \
	"${ARTIFACT_DIR}/tee-header_v2.bin" \
	"${ARTIFACT_DIR}/tee-pager_v2.bin" \
	"${ARTIFACT_DIR}/tee-pageable_v2.bin" \
	"${PI_TARGET}:~/${REMOTE_DIR}/"

if [[ -f "${ROOT_DIR}/ensure-wifi-autoconnect.sh" ]]; then
	remote_scp "${ROOT_DIR}/ensure-wifi-autoconnect.sh" \
		"${PI_TARGET}:~/${REMOTE_DIR}/ensure-wifi-autoconnect.sh"
fi

if [[ -f "${ARTIFACT_DIR}/MEMORY-LAYOUT.txt" ]]; then
	remote_scp "${ARTIFACT_DIR}/MEMORY-LAYOUT.txt" "${PI_TARGET}:~/${REMOTE_DIR}/"
fi

if [[ -f "${ARTIFACT_DIR}/overlays/optee-rpi5-overlay.dts" ]]; then
	remote_scp "${ARTIFACT_DIR}/overlays/optee-rpi5-overlay.dts" \
		"${PI_TARGET}:~/${REMOTE_DIR}/overlays/"
fi

if [[ -d "${ARTIFACT_DIR}/rootfs-overlay" ]]; then
	echo "==> Copying rootfs-overlay (usr/lib OP-TEE only)"
	remote_scp -r "${ARTIFACT_DIR}/rootfs-overlay/." "${PI_TARGET}:~/${REMOTE_DIR}/rootfs-overlay/"
fi

if [[ -d "${CLIENT_OUT_DIR}" ]]; then
	echo "==> Copying OP-TEE client output"
	remote_ssh "${PI_TARGET}" "rm -rf ~/${REMOTE_DIR}/optee_client_out && mkdir -p ~/${REMOTE_DIR}/optee_client_out"
	remote_scp -r "${CLIENT_OUT_DIR}"/* "${PI_TARGET}:~/${REMOTE_DIR}/optee_client_out/"
fi

if [[ -d "${TA_DIR}" ]] && compgen -G "${TA_DIR}/*.ta" >/dev/null; then
	echo "==> Copying Trusted Applications"
	remote_ssh "${PI_TARGET}" "rm -rf ~/${REMOTE_DIR}/ta && mkdir -p ~/${REMOTE_DIR}/ta"
	remote_scp "${TA_DIR}"/*.ta "${PI_TARGET}:~/${REMOTE_DIR}/ta/"
fi

# Build a remote sudo wrapper: passwordless, or sudo -S via PI_SUDO_PASSWORD.
SUDO_MODE=none
if remote_ssh "${PI_TARGET}" "sudo -n true" 2>/dev/null; then
	SUDO_MODE=nopasswd
elif [[ -n "${SSHPASS:-}" ]]; then
	SUDO_MODE=password
else
	echo "ERROR: ${PI_TARGET} needs sudo, and no PI_SUDO_PASSWORD/SSHPASS is set." >&2
	echo "       Export PI_SUDO_PASSWORD and re-run, or enable NOPASSWD on the Pi." >&2
	exit 1
fi
echo "==> Remote sudo mode: ${SUDO_MODE}"

echo "==> Installing on Raspberry Pi (firmware/boot only; WiFi configs untouched)"
# Pass sudo password only through the SSH session stdin envelope, not a file on disk.
remote_ssh "${PI_TARGET}" \
	"REMOTE_DIR='${REMOTE_DIR}' DO_REBOOT='${DO_REBOOT}' SUDO_MODE='${SUDO_MODE}' bash -s" <<REMOTE
set -euo pipefail

DROP_DIR="\${HOME}/\${REMOTE_DIR:-optee-rpi5}"
BOOT_DIR="/boot/firmware"
CONFIG="\${BOOT_DIR}/config.txt"
STAMP="\$(date +%Y%m%d-%H%M%S)"
NET_BACKUP="\${HOME}/optee-network-backup-\${STAMP}"
EXPECTED_ARMSTUB_SIZE=\$((0x100000))
SUDO_MODE="\${SUDO_MODE:-nopasswd}"

# Optional sudo password on first line of this script's stdin is NOT used;
# password mode reads from env injected below via a here-doc marker.
sudo_run() {
	if [[ "\${SUDO_MODE}" == "password" ]]; then
		# shellcheck disable=SC2154
		printf '%s\n' "\${PI_SUDO_PASSWORD}" | sudo -S -p '' "\$@"
	else
		sudo -n "\$@"
	fi
}

export PI_SUDO_PASSWORD='${SSHPASS:-}'

if [[ ! -d "\${BOOT_DIR}" ]]; then
	echo "Missing \${BOOT_DIR}; expected Raspberry Pi OS Bookworm boot firmware layout." >&2
	exit 1
fi

if [[ ! -f "\${DROP_DIR}/armstub8-2712-optee.bin" ]]; then
	echo "Missing embedded armstub in \${DROP_DIR}" >&2
	exit 1
fi

ARMSTUB_SIZE=\$(stat -c%s "\${DROP_DIR}/armstub8-2712-optee.bin")
if [[ "\${ARMSTUB_SIZE}" -ne "\${EXPECTED_ARMSTUB_SIZE}" ]]; then
	echo "Refusing install: armstub size \${ARMSTUB_SIZE} != \${EXPECTED_ARMSTUB_SIZE}" >&2
	exit 1
fi

# Refuse staged overlays that contain network/boot trees.
for bad in \
	"\${DROP_DIR}/rootfs-overlay/etc/NetworkManager" \
	"\${DROP_DIR}/rootfs-overlay/etc/netplan" \
	"\${DROP_DIR}/rootfs-overlay/etc/wpa_supplicant" \
	"\${DROP_DIR}/rootfs-overlay/boot"
do
	if [[ -e "\${bad}" ]]; then
		echo "ERROR: staged overlay must not contain \${bad}" >&2
		exit 1
	fi
done

echo "  -> Snapshotting WiFi/network configs (read-only backup; install will NOT rewrite them)"
mkdir -p "\${NET_BACKUP}"
for path in \
	/etc/NetworkManager/system-connections \
	/etc/NetworkManager/NetworkManager.conf \
	/etc/wpa_supplicant \
	/etc/netplan \
	"\${BOOT_DIR}/wpa_supplicant.conf" \
	"\${BOOT_DIR}/cmdline.txt" \
	/etc/hostname \
	/etc/hosts
do
	if [[ -e "\${path}" ]]; then
		sudo_run cp -a --parents "\${path}" "\${NET_BACKUP}/"
	fi
done
echo "  -> Network backup: \${NET_BACKUP}"

echo "  -> Backing up boot config/armstub files only (not a full FAT wipe/replace)"
sudo_run mkdir -p "\${BOOT_DIR}.file-backups"
sudo_run cp -a "\${CONFIG}" "\${BOOT_DIR}.file-backups/config.txt.\${STAMP}"
if [[ -f "\${BOOT_DIR}/cmdline.txt" ]]; then
	sudo_run cp -a "\${BOOT_DIR}/cmdline.txt" "\${BOOT_DIR}.file-backups/cmdline.txt.\${STAMP}"
fi
if [[ -f "\${BOOT_DIR}/armstub8-2712.bin" ]]; then
	sudo_run cp -a "\${BOOT_DIR}/armstub8-2712.bin" \
		"\${BOOT_DIR}.file-backups/armstub8-2712.bin.\${STAMP}"
fi
if [[ -f "\${BOOT_DIR}/armstub8-2712-optee.bin" ]]; then
	sudo_run cp -a "\${BOOT_DIR}/armstub8-2712-optee.bin" \
		"\${BOOT_DIR}.file-backups/armstub8-2712-optee.bin.\${STAMP}"
fi

echo "  -> Installing embedded BL31+OP-TEE armstub (boot FAT allowlist only)"
# Allowlist writes under /boot/firmware:
#   armstub8-2712-optee.bin, optee/tee*.bin, overlays/optee-rpi5.dtbo, config.txt keys
# Never: wpa_supplicant.conf, cmdline.txt, full-directory replace, plain bl31.bin as armstub.
sudo_run cp "\${DROP_DIR}/armstub8-2712-optee.bin" "\${BOOT_DIR}/armstub8-2712-optee.bin"
sudo_run mkdir -p "\${BOOT_DIR}/optee"
sudo_run cp "\${DROP_DIR}"/tee*.bin "\${BOOT_DIR}/optee/" 2>/dev/null || true
sudo_run touch "\${CONFIG}"

# Never use `printf | sudo_run tee` in password mode: sudo -S consumes stdin,
# so tee would write empty values (armstub= / kernel_address=).
set_config() {
	key="\$1"
	value="\$2"
	# Pass key/value as bash -c args so sudo -S only sees the password on stdin.
	sudo_run bash -c 'key=\$1; val=\$2; cfg=\$3; if grep -qE "^[[:space:]]*#?[[:space:]]*\${key}=" "\$cfg"; then sed -i -E "s|^[[:space:]]*#?[[:space:]]*\${key}=.*|\${key}=\${val}|" "\$cfg"; else printf "%s=%s\n" "\$key" "\$val" >> "\$cfg"; fi' _ "\${key}" "\${value}" "\${CONFIG}"
}

ensure_dtoverlay() {
	name="\$1"
	sudo_run bash -c 'name=\$1; cfg=\$2; if grep -qE "^[[:space:]]*dtoverlay=\${name}([[:space:]]|,|\$)" "\$cfg"; then exit 0; fi; printf "dtoverlay=%s\n" "\$name" >> "\$cfg"' _ "\${name}" "\${CONFIG}"
}

echo "  -> Updating config.txt keys only (armstub + kernel_address); WiFi untouched"
set_config arm_64bit 1
set_config enable_uart 1
set_config armstub armstub8-2712-optee.bin
# Critical: default kernel_address 0x80000 would overwrite embedded OP-TEE.
set_config kernel_address 0x200000

# OP-TEE with CFG_DT=y patches the DTB at boot (firmware/optee + reserved-memory).
# Do NOT also enable dtoverlay=optee-rpi5 — duplicate reserved regions break probing.
if sudo_run grep -Eq "^[[:space:]]*#?[[:space:]]*dtoverlay=optee-rpi5" "\${CONFIG}"; then
	echo "  -> Removing dtoverlay=optee-rpi5 (OP-TEE patches DT at runtime)"
	sudo_run sed -i -E 's|^[[:space:]]*#?[[:space:]]*dtoverlay=optee-rpi5|#dtoverlay=optee-rpi5|' "\${CONFIG}"
fi

if [[ -f "\${DROP_DIR}/overlays/optee-rpi5-overlay.dts" ]]; then
	echo "  -> Skipping optee-rpi5 DT overlay install (redundant with CFG_DT=y)"
fi

# Intentionally NO restore/rewrite of NetworkManager/netplan/wpa.
# Firmware install never deletes those files; rewriting them is how WiFi
# can actually get corrupted if a partial backup is replayed.

if compgen -G "\${DROP_DIR}/ta/*.ta" >/dev/null; then
	echo "  -> Installing TAs"
	sudo_run mkdir -p /lib/optee_armtz
	sudo_run cp "\${DROP_DIR}"/ta/*.ta /lib/optee_armtz/
fi

if [[ -d "\${DROP_DIR}/rootfs-overlay" ]]; then
	echo "  -> Applying rootfs-overlay (usr + lib/optee_armtz only)"
	# Running tee-supplicant holds /usr/sbin/tee-supplicant (ETXTBSY on overwrite).
	sudo_run systemctl stop tee-supplicant.service 2>/dev/null || true
	sudo_run pkill -x tee-supplicant 2>/dev/null || true
	sleep 0.5
	if [[ -d "\${DROP_DIR}/rootfs-overlay/usr" ]]; then
		sudo_run mkdir -p /usr
		sudo_run cp -a "\${DROP_DIR}/rootfs-overlay/usr/." /usr/
	fi
	if [[ -d "\${DROP_DIR}/rootfs-overlay/lib/optee_armtz" ]]; then
		sudo_run mkdir -p /lib/optee_armtz
		sudo_run cp -a "\${DROP_DIR}/rootfs-overlay/lib/optee_armtz/." /lib/optee_armtz/
	fi
fi

if [[ -x "\${DROP_DIR}/optee_client_out/tee-supplicant/tee-supplicant" ]]; then
	echo "  -> Installing tee-supplicant"
	sudo_run systemctl stop tee-supplicant.service 2>/dev/null || true
	sudo_run pkill -x tee-supplicant 2>/dev/null || true
	sleep 0.5
	sudo_run cp "\${DROP_DIR}/optee_client_out/tee-supplicant/tee-supplicant" /usr/sbin/
	sudo_run chmod 755 /usr/sbin/tee-supplicant
fi

if [[ -f "\${DROP_DIR}/optee_client_out/libteec/libteec.so.2.0.0" ]]; then
	echo "  -> Installing libteec"
	sudo_run mkdir -p /usr/lib/aarch64-linux-gnu
	sudo_run rm -f /usr/lib/aarch64-linux-gnu/libteec.so* /lib/aarch64-linux-gnu/libteec.so*
	sudo_run cp "\${DROP_DIR}/optee_client_out/libteec/libteec.so.2.0.0" /usr/lib/aarch64-linux-gnu/
	(
		cd /usr/lib/aarch64-linux-gnu
		sudo_run ln -sf libteec.so.2.0.0 libteec.so.2.0
		sudo_run ln -sf libteec.so.2.0 libteec.so.2
		sudo_run ln -sf libteec.so.2 libteec.so
	)
	sudo_run ldconfig
fi

# Ensure tee-supplicant service unit exists and is running with the new binary.
if [[ -x /usr/sbin/tee-supplicant ]]; then
	if [[ ! -f /etc/systemd/system/tee-supplicant.service ]]; then
		echo "  -> Installing tee-supplicant.service"
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
	fi
	echo "  -> Starting tee-supplicant"
	sudo_run systemctl restart tee-supplicant.service || true
fi

echo "  -> Verifying WiFi profiles still present after firmware install"
if [[ -d /etc/NetworkManager/system-connections ]]; then
	ls -la /etc/NetworkManager/system-connections || true
fi
if [[ -d /etc/netplan ]]; then
	ls -la /etc/netplan || true
fi
if command -v nmcli >/dev/null 2>&1; then
	nmcli -t -f NAME,UUID,TYPE connection show || true
fi

# Force NM WiFi autoconnect BEFORE reboot so the next boot rejoins ForkCoder/etc.
echo "  -> Ensuring WiFi autoconnect (pre-reboot)"
if [[ -f "\${DROP_DIR}/ensure-wifi-autoconnect.sh" ]]; then
	# Re-export so the helper can sudo -S in password mode.
	export PI_SUDO_PASSWORD="\${PI_SUDO_PASSWORD:-}"
	export SSHPASS="\${PI_SUDO_PASSWORD:-}"
	bash "\${DROP_DIR}/ensure-wifi-autoconnect.sh" || true
elif command -v nmcli >/dev/null 2>&1; then
	sudo_run nmcli networking on || true
	sudo_run nmcli radio wifi on || true
	while IFS=: read -r _name _type; do
		[[ "\${_type}" == "802-11-wireless" ]] || continue
		echo "  -> Autoconnect on: \${_name}"
		sudo_run nmcli connection modify "\${_name}" \
			connection.autoconnect yes \
			connection.autoconnect-priority 10 || true
	done < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null || true)
fi

echo "  -> Flushing filesystems"
sync
sync

echo "Install complete."
# Capture grep output via command substitution (not printf|sudo tee) so password
# sudo -S cannot steal stdin and blank the verification lines.
_armstub_line=\$(sudo_run bash -c 'grep -E "^armstub=" "\$1" || true' _ "\${CONFIG}")
_kaddr_line=\$(sudo_run bash -c 'grep -E "^kernel_address=" "\$1" || true' _ "\${CONFIG}")
echo "config.txt \${_armstub_line}"
echo "config.txt \${_kaddr_line}"
if [[ "\${_armstub_line}" != "armstub=armstub8-2712-optee.bin" ]] || \
   [[ "\${_kaddr_line}" != "kernel_address=0x200000" ]]; then
	echo "ERROR: config.txt armstub/kernel_address not set correctly after install." >&2
	exit 1
fi
echo "Network backup (unchanged on disk): \${NET_BACKUP}"
echo "After reboot: dmesg | grep -iE 'optee|tee'; ls -l /dev/tee*"

if [[ "\${DO_REBOOT:-0}" == "1" ]]; then
	sudo_run reboot
fi
REMOTE

echo "==> Deployment finished"
if [[ "${DO_REBOOT}" != "1" ]]; then
	echo "Reboot when ready: PI_SUDO_PASSWORD=... $0 ${PI_TARGET} --reboot"
	echo "  or: ssh ${PI_TARGET} 'sudo reboot'"
fi
echo "If the Pi becomes unreachable after reboot, WiFi settings were likely NOT erased;"
echo "boot probably hung on a bad armstub. Use HDMI/UART/Ethernet or recover-boot-wifi.sh"
echo "on the SD card boot partition (comment out armstub= / rename armstub file)."
