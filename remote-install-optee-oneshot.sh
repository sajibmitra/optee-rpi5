#!/usr/bin/env bash
# One-shot OP-TEE install for Raspberry Pi 5 — run ON the Pi with an interactive
# TTY so sudo can prompt for a password.
#
# From the build host (artifacts already staged under ~/optee-rpi5):
#   scp remote-install-optee-oneshot.sh skmitra@192.168.0.107:~/
#   ssh -t skmitra@192.168.0.107 'bash ~/remote-install-optee-oneshot.sh'
#
# Or:
#   ssh -t skmitra@192.168.0.107 'bash -s' < remote-install-optee-oneshot.sh
#
# Does NOT reboot automatically. Reboot when ready:
#   ssh -t skmitra@192.168.0.107 'sudo reboot'
set -euo pipefail

DROP_DIR="${HOME}/${REMOTE_DIR:-optee-rpi5}"
BOOT_DIR="/boot/firmware"
CONFIG="${BOOT_DIR}/config.txt"
STAMP="$(date +%Y%m%d-%H%M%S)"
NET_BACKUP="${HOME}/optee-network-backup-${STAMP}"
EXPECTED_ARMSTUB_SIZE=$((0x100000))

if [[ ! -d "${BOOT_DIR}" ]]; then
	echo "Missing ${BOOT_DIR}; expected Raspberry Pi OS Bookworm boot firmware layout." >&2
	exit 1
fi

if [[ ! -f "${DROP_DIR}/armstub8-2712-optee.bin" ]]; then
	echo "Missing embedded armstub in ${DROP_DIR}" >&2
	exit 1
fi

ARMSTUB_SIZE=$(stat -c%s "${DROP_DIR}/armstub8-2712-optee.bin")
if [[ "${ARMSTUB_SIZE}" -ne "${EXPECTED_ARMSTUB_SIZE}" ]]; then
	echo "Refusing install: armstub size ${ARMSTUB_SIZE} != ${EXPECTED_ARMSTUB_SIZE}" >&2
	exit 1
fi

echo "  -> Backing up network configuration to ${NET_BACKUP}"
mkdir -p "${NET_BACKUP}"
for path in \
	/etc/NetworkManager/system-connections \
	/etc/NetworkManager/NetworkManager.conf \
	/etc/wpa_supplicant \
	/etc/netplan \
	"${BOOT_DIR}/wpa_supplicant.conf" \
	"${BOOT_DIR}/cmdline.txt" \
	/etc/hostname \
	/etc/hosts
do
	if [[ -e "${path}" ]]; then
		# Always use sudo (netplan NM yaml is often root:root mode 600).
		sudo cp -a --parents "${path}" "${NET_BACKUP}/"
	fi
done

echo "  -> Backing up boot config/armstub files (not a full FAT duplicate)"
sudo mkdir -p "${BOOT_DIR}.file-backups"
sudo cp -a "${CONFIG}" "${BOOT_DIR}.file-backups/config.txt.${STAMP}"
if [[ -f "${BOOT_DIR}/cmdline.txt" ]]; then
	sudo cp -a "${BOOT_DIR}/cmdline.txt" "${BOOT_DIR}.file-backups/cmdline.txt.${STAMP}"
fi
if [[ -f "${BOOT_DIR}/armstub8-2712.bin" ]]; then
	sudo cp -a "${BOOT_DIR}/armstub8-2712.bin" \
		"${BOOT_DIR}.file-backups/armstub8-2712.bin.${STAMP}"
fi
if [[ -f "${BOOT_DIR}/armstub8-2712-optee.bin" ]]; then
	sudo cp -a "${BOOT_DIR}/armstub8-2712-optee.bin" \
		"${BOOT_DIR}.file-backups/armstub8-2712-optee.bin.${STAMP}"
fi

echo "  -> Installing embedded BL31+OP-TEE armstub"
# Install the combined image — NOT plain bl31.bin (breaks BL32 handoff /
# can leave the board unreachable over WiFi after reboot).
sudo cp "${DROP_DIR}/armstub8-2712-optee.bin" "${BOOT_DIR}/armstub8-2712-optee.bin"
sudo mkdir -p "${BOOT_DIR}/optee"
sudo cp "${DROP_DIR}"/tee*.bin "${BOOT_DIR}/optee/" 2>/dev/null || true
sudo touch "${CONFIG}"

set_config() {
	key="$1"
	value="$2"
	sudo bash -c 'key="$1"; val="$2"; cfg="$3"; if grep -qE "^[[:space:]]*#?[[:space:]]*${key}=" "$cfg"; then sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}=.*|${key}=${val}|" "$cfg"; else printf "%s=%s\n" "$key" "$val" >> "$cfg"; fi' _ "${key}" "${value}" "${CONFIG}"
}

echo "  -> Updating ${CONFIG} (armstub + kernel_address; leave WiFi alone)"
set_config arm_64bit 1
set_config enable_uart 1
set_config armstub armstub8-2712-optee.bin
# Critical: default kernel_address 0x80000 would overwrite embedded OP-TEE.
set_config kernel_address 0x200000

# OP-TEE with CFG_DT=y patches the DTB at boot (firmware/optee + reserved-memory).
# Do NOT also enable dtoverlay=optee-rpi5 — duplicate reserved regions break probing.
if sudo grep -Eq '^[[:space:]]*#?[[:space:]]*dtoverlay=optee-rpi5' "${CONFIG}"; then
	echo "  -> Removing dtoverlay=optee-rpi5 (OP-TEE patches DT at runtime)"
	sudo sed -i -E 's|^[[:space:]]*#?[[:space:]]*dtoverlay=optee-rpi5|#dtoverlay=optee-rpi5|' "${CONFIG}"
fi

if [[ -f "${DROP_DIR}/overlays/optee-rpi5-overlay.dts" ]]; then
	echo "  -> Skipping optee-rpi5 DT overlay install (redundant with CFG_DT=y)"
fi

# Do NOT rewrite NetworkManager / netplan / wpa after install.
# Firmware never deletes those files; replaying a backup can corrupt WiFi.
echo "  -> WiFi configs left untouched (backup only at ${NET_BACKUP})"

if compgen -G "${DROP_DIR}/ta/*.ta" >/dev/null; then
	echo "  -> Installing TAs"
	sudo mkdir -p /lib/optee_armtz
	sudo cp "${DROP_DIR}"/ta/*.ta /lib/optee_armtz/
fi

if [[ -d "${DROP_DIR}/rootfs-overlay" ]]; then
	echo "  -> Applying rootfs-overlay (usr + lib/optee_armtz only; no --delete)"
	if [[ -d "${DROP_DIR}/rootfs-overlay/usr" ]]; then
		sudo mkdir -p /usr
		sudo cp -a "${DROP_DIR}/rootfs-overlay/usr/." /usr/
	fi
	if [[ -d "${DROP_DIR}/rootfs-overlay/lib/optee_armtz" ]]; then
		sudo mkdir -p /lib/optee_armtz
		sudo cp -a "${DROP_DIR}/rootfs-overlay/lib/optee_armtz/." /lib/optee_armtz/
	fi
fi

if [[ -x "${DROP_DIR}/optee_client_out/tee-supplicant/tee-supplicant" ]]; then
	echo "  -> Installing tee-supplicant"
	sudo cp "${DROP_DIR}/optee_client_out/tee-supplicant/tee-supplicant" /usr/sbin/
fi

if [[ -f "${DROP_DIR}/optee_client_out/libteec/libteec.so.2.0.0" ]]; then
	echo "  -> Installing libteec"
	sudo mkdir -p /usr/lib/aarch64-linux-gnu
	sudo rm -f /usr/lib/aarch64-linux-gnu/libteec.so* /lib/aarch64-linux-gnu/libteec.so*
	sudo cp "${DROP_DIR}/optee_client_out/libteec/libteec.so.2.0.0" /usr/lib/aarch64-linux-gnu/
	(
		cd /usr/lib/aarch64-linux-gnu
		sudo ln -sf libteec.so.2.0.0 libteec.so.2.0
		sudo ln -sf libteec.so.2.0 libteec.so.2
		sudo ln -sf libteec.so.2 libteec.so
	)
	sudo ldconfig
fi

echo "  -> Flushing filesystems"
sync
sync
if command -v nmcli >/dev/null 2>&1; then
	echo "  -> NetworkManager profiles present:"
	nmcli -t -f NAME,UUID,TYPE connection show || true
fi

echo "  -> Ensuring WiFi autoconnect (pre-reboot)"
if [[ -f "${DROP_DIR}/ensure-wifi-autoconnect.sh" ]]; then
	bash "${DROP_DIR}/ensure-wifi-autoconnect.sh" || true
elif command -v nmcli >/dev/null 2>&1; then
	sudo nmcli networking on || true
	sudo nmcli radio wifi on || true
	while IFS=: read -r _name _type; do
		[[ "${_type}" == "802-11-wireless" ]] || continue
		echo "  -> Autoconnect on: ${_name}"
		sudo nmcli connection modify "${_name}" \
			connection.autoconnect yes \
			connection.autoconnect-priority 10 || true
	done < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null || true)
fi

echo "Install complete (no reboot)."
_armstub_line=$(sudo grep -E '^armstub=' "${CONFIG}" || true)
_kaddr_line=$(sudo grep -E '^kernel_address=' "${CONFIG}" || true)
echo "config.txt armstub=${_armstub_line}"
echo "config.txt kernel_address=${_kaddr_line}"
if [[ "${_armstub_line}" != "armstub=armstub8-2712-optee.bin" ]] || \
   [[ "${_kaddr_line}" != "kernel_address=0x200000" ]]; then
	echo "ERROR: config.txt armstub/kernel_address not set correctly after install." >&2
	exit 1
fi
echo "Network backup kept at: ${NET_BACKUP}"
echo "Reboot when ready: sudo reboot"
echo "After reboot: dmesg | grep -iE 'optee|tee'; ls -l /dev/tee*; sudo tee-supplicant -d"
