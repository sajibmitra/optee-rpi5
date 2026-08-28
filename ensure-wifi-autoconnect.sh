#!/usr/bin/env bash
# Ensure NetworkManager WiFi profiles autoconnect on next boot.
#
# Run ON the Pi (or via deploy-rpi5-optee.sh after firmware install, before reboot).
# Does not create SSIDs or rewrite secrets — only flips autoconnect flags on
# existing 802-11-wireless connections (e.g. netplan-wlan0-ForkCoder).
#
# Usage:
#   sudo ./ensure-wifi-autoconnect.sh
#   PI_SUDO_PASSWORD=... ./ensure-wifi-autoconnect.sh   # uses sudo -S
# Optional: WIFI_CONN_NAME=netplan-wlan0-ForkCoder to prefer one profile for `up`.
set -euo pipefail

SUDO_MODE=none
if [[ "$(id -u)" -eq 0 ]]; then
	SUDO_MODE=root
elif sudo -n true 2>/dev/null; then
	SUDO_MODE=nopasswd
elif [[ -n "${PI_SUDO_PASSWORD:-${SSHPASS:-}}" ]]; then
	SUDO_MODE=password
	export PI_SUDO_PASSWORD="${PI_SUDO_PASSWORD:-${SSHPASS}}"
else
	echo "Need root, passwordless sudo, or PI_SUDO_PASSWORD/SSHPASS." >&2
	exit 1
fi

sudo_run() {
	case "${SUDO_MODE}" in
		root) "$@" ;;
		nopasswd) sudo -n "$@" ;;
		password) printf '%s\n' "${PI_SUDO_PASSWORD}" | sudo -S -p '' "$@" ;;
	esac
}

if ! command -v nmcli >/dev/null 2>&1; then
	echo "nmcli not found; skipping WiFi autoconnect ensure." >&2
	exit 0
fi

echo "  -> Enabling NetworkManager networking + WiFi radio"
sudo_run nmcli networking on || true
sudo_run nmcli radio wifi on || true

mapfile -t WIFI_NAMES < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null \
	| awk -F: '$2=="802-11-wireless"{print $1}')

if [[ "${#WIFI_NAMES[@]}" -eq 0 ]]; then
	echo "  -> No WiFi (802-11-wireless) NM connections found."
	if [[ -d /etc/netplan ]]; then
		echo "  -> netplan files present:"
		ls -la /etc/netplan || true
	fi
	exit 0
fi

PREFERRED="${WIFI_CONN_NAME:-}"
UP_CANDIDATE=""

for name in "${WIFI_NAMES[@]}"; do
	echo "  -> Autoconnect on: ${name}"
	sudo_run nmcli connection modify "${name}" \
		connection.autoconnect yes \
		connection.autoconnect-priority 100 || true
	if [[ -n "${PREFERRED}" && "${name}" == "${PREFERRED}" ]]; then
		UP_CANDIDATE="${name}"
	elif [[ -z "${UP_CANDIDATE}" ]]; then
		# Prefer ForkCoder / netplan-wlan0 names when no explicit preference.
		case "${name}" in
			*ForkCoder*|netplan-wlan0*) UP_CANDIDATE="${name}" ;;
		esac
	fi
done

if [[ -z "${UP_CANDIDATE}" ]]; then
	UP_CANDIDATE="${WIFI_NAMES[0]}"
fi

# Bring up now if wlan interface exists (optional; helps verify before reboot).
WLAN_DEV="$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null \
	| awk -F: '$2=="wifi"{print $1; exit}')"
if [[ -n "${WLAN_DEV}" && -n "${UP_CANDIDATE}" ]]; then
	echo "  -> Attempting connection up: ${UP_CANDIDATE} on ${WLAN_DEV}"
	sudo_run nmcli connection up "${UP_CANDIDATE}" ifname "${WLAN_DEV}" || true
fi

echo "  -> WiFi connection summary:"
nmcli -t -f NAME,TYPE,AUTOCONNECT connection show 2>/dev/null \
	| awk -F: '$2=="802-11-wireless"{print}' || true

echo "  -> Installing NetworkManager boot hook (99-wifi-autoconnect)"
sudo_run install -d /etc/NetworkManager/dispatcher.d
sudo_run bash -c 'cat > /etc/NetworkManager/dispatcher.d/99-wifi-autoconnect <<'\''DISPATCHER'\''
#!/bin/sh
# Re-enable WiFi radio after boot / link changes (OP-TEE deploy safety net).
if [ "$2" = "up" ] || [ "$2" = "connectivity-change" ]; then
	nmcli radio wifi on 2>/dev/null || true
fi
DISPATCHER
chmod 755 /etc/NetworkManager/dispatcher.d/99-wifi-autoconnect'

echo "  -> ensure-wifi-autoconnect done"
