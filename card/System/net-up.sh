#!/bin/sh
# Bring the handheld onto the network: WiFi, then telnet and FTP of the card.
#
# Used from two places: the "slot net" app, and the boot hook when slot is
# booted instead of Allium. In that second case there is no alliumd to do it,
# and losing the network would mean going back to carrying the SD card between
# machines, so this runs in the background at boot.
#
# It deliberately does not call Allium's telnet-on.sh/ftp-on.sh: both begin with
# wait-for-wifi.sh, which pings 1.1.1.1 once a second for up to sixty seconds,
# and calling the pair after waiting once meant minutes of an apparently frozen
# handheld. A LAN address is all that is needed, so it waits for one and starts
# the daemons directly.
#
# usage: net-up.sh [card root] [log file]
root="${1:-/mnt/SDCARD}"
out="${2:-$root/slot-net.txt}"
scripts="$root/.allium/scripts"
conf=/appconfigs/wpa_supplicant.conf

log() { echo "$@" >> "$out"; }

: > "$out"
log "slot net — $(date 2>/dev/null)"
log ""

# Credentials from the card, if given. Allium's on-screen keyboard has no shift
# key, so a network name with capitals cannot be typed on the handheld at all,
# and SSIDs are case-sensitive.
creds="$root/slot-wifi.txt"
if [ -r "$creds" ]; then
	real=$(grep -v '^[[:space:]]*#' "$creds" | grep -v '^[[:space:]]*$')
	ssid=$(echo "$real" | sed -n '1p' | tr -d '\r')
	psk=$(echo "$real" | sed -n '2p' | tr -d '\r')
	if [ -n "$ssid" ]; then
		mkdir -p /appconfigs 2>/dev/null
		{
			echo "ctrl_interface=/var/run/wpa_supplicant"
			echo "update_config=1"
			echo "network={"
			echo "	ssid=\"$ssid\""
			if [ -n "$psk" ]; then
				echo "	psk=\"$psk\""
			else
				echo "	key_mgmt=NONE"
			fi
			echo "}"
		} > "$conf"
		log "wrote $conf for \"$ssid\""
	fi
fi

[ -x "$scripts/wifi-on.sh" ] && sh "$scripts/wifi-on.sh" > /dev/null 2>&1

# An address, not the internet, and bounded so this can never look like a hang.
addr=""
n=0
while [ $n -lt 45 ]; do
	addr=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
	[ -n "$addr" ] && break
	n=$((n + 1))
	sleep 1
done

if [ -z "$addr" ]; then
	log "wlan0 has no address after ${n}s"
	log ""
	log "  driver module: $(grep -c 8188fu /proc/modules 2>/dev/null) (want 1)"
	log "  supplicant: $(pgrep wpa_supplicant > /dev/null 2>&1 && echo running || echo no)"
	log "  config: $(wc -c < "$conf" 2>/dev/null || echo 0) bytes"
	sync
	exit 1
fi

log "address: $addr"
# setsid so they outlive whatever started this.
pgrep telnetd > /dev/null 2>&1 || setsid telnetd -l sh > /dev/null 2>&1 || telnetd -l sh > /dev/null 2>&1
pgrep tcpsvd > /dev/null 2>&1 || setsid tcpsvd -E 0.0.0.0 21 ftpd -w "$root" > /dev/null 2>&1 &
log "telnet: $(pgrep telnetd > /dev/null 2>&1 && echo up || echo down)"
# tcpsvd is the listener; ftpd is only spawned per connection, so looking for
# ftpd reports "down" while FTP is serving perfectly well.
log "ftp:    $(pgrep tcpsvd > /dev/null 2>&1 && echo up || echo down)"
log ""
log "on the computer:  export SLOT_DEVICE=$addr"
sync
