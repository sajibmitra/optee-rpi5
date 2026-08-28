#!/usr/bin/env bash
# Recover Raspberry Pi 5 SSH/WiFi after a bad OP-TEE armstub reboot.
#
# Important: OP-TEE firmware update does NOT erase NetworkManager / netplan
# WiFi profiles. Those live on the root filesystem. Losing SSH after reboot
# almost always means boot hung or failed because of armstub/BL31/BL32 — the
# board never reaches Linux networking.
#
# Use this when you can mount the Pi's boot FAT (SD card in another PC, or
# USB gadget / live OS), OR when you have HDMI/UART/Ethernet console.
set -euo pipefail

BOOT_DIR="${1:-/boot/firmware}"
CONFIG="${BOOT_DIR}/config.txt"

usage() {
	cat <<'EOF'
Usage: recover-boot-wifi.sh [/path/to/boot/firmware]

Disables the OP-TEE armstub so stock Raspberry Pi firmware can boot Linux
again. Does not modify NetworkManager / netplan / wpa_supplicant.

On another PC after inserting the Pi SD card (boot partition often mounts as
/media/$USER/bootfs or similar):

  ./recover-boot-wifi.sh /media/$USER/bootfs

On the Pi (HDMI/UART/Ethernet console):

  sudo ./recover-boot-wifi.sh /boot/firmware
  sudo reboot

After Linux is back up over WiFi/SSH, re-deploy with the fixed embedded armstub:

  PI_SUDO_PASSWORD=... ./deploy-rpi5-optee.sh user@pi-ip
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

if [[ ! -d "${BOOT_DIR}" ]]; then
	echo "Boot directory not found: ${BOOT_DIR}" >&2
	usage >&2
	exit 1
fi

if [[ ! -f "${CONFIG}" ]]; then
	echo "Missing ${CONFIG}" >&2
	exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
cp -a "${CONFIG}" "${CONFIG}.recover-${STAMP}"

# Comment out OP-TEE armstub / overlay lines; leave everything else alone.
sed -i -E \
	-e 's/^[[:space:]]*armstub=armstub8-2712-optee\.bin/# &/' \
	-e 's/^[[:space:]]*dtoverlay=optee-rpi5/# &/' \
	"${CONFIG}"

# Optional: rename armstub so even a leftover armstub= line cannot load it.
if [[ -f "${BOOT_DIR}/armstub8-2712-optee.bin" ]]; then
	mv -f "${BOOT_DIR}/armstub8-2712-optee.bin" \
		"${BOOT_DIR}/armstub8-2712-optee.bin.disabled-${STAMP}"
	echo "Renamed armstub8-2712-optee.bin -> .disabled-${STAMP}"
fi

echo "Updated ${CONFIG} (backup: ${CONFIG}.recover-${STAMP})"
echo "WiFi profiles were not touched (they are on the rootfs, not this FAT)."
echo "Reinsert SD / reboot the Pi, then SSH should work if networking was OK before."
grep -E '^(# )?armstub=|^(# )?kernel_address=|^(# )?dtoverlay=optee' "${CONFIG}" || true
echo
echo "Once SSH is back, force WiFi autoconnect (ForkCoder / netplan-wlan0):"
echo "  sudo bash ~/optee-rpi5/ensure-wifi-autoconnect.sh"
echo "  # or:"
echo "  sudo nmcli networking on; sudo nmcli radio wifi on"
echo "  sudo nmcli connection modify netplan-wlan0-ForkCoder connection.autoconnect yes connection.autoconnect-priority 10"
echo "  sudo nmcli connection up netplan-wlan0-ForkCoder"
