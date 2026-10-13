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

# Keep trying, rather than giving up. The first version made one attempt and
# waited 45 s, which is enough when the radio is already associated but not from
# a cold boot -- and when slot is the boot process there is no Allium menu to
# run this from by hand, so a single failure means fetching the SD card. An
# attempt costs nothing while it is idle, so it retries for as long as it takes.
# How early this runs matters: at boot the radio may not be ready when
# wifi-on.sh insmods the driver, which would explain cold boots failing while
# the same script works by hand from a menu later on.
log "uptime at start: $(cut -d" " -f1 /proc/uptime 2>/dev/null)s"
log "wlan0 before wifi-on: $(ifconfig wlan0 > /dev/null 2>&1 && echo present || echo absent)"
log "module before wifi-on: $(grep -c 8188fu /proc/modules 2>/dev/null)"
log ""

attempt=1
while :; do
	[ -x "$scripts/wifi-on.sh" ] && sh "$scripts/wifi-on.sh" > /dev/null 2>&1
	log "attempt $attempt at $(cut -d" " -f1 /proc/uptime 2>/dev/null)s: wlan0 $(ifconfig wlan0 > /dev/null 2>&1 && echo present || echo ABSENT), module $(grep -c 8188fu /proc/modules 2>/dev/null)"

	# Association first: it and DHCP fail for different reasons.
	assoc=""
	n=0
	while [ $n -lt 45 ]; do
		state=$(wpa_cli -i wlan0 status 2>/dev/null | sed -n 's/^wpa_state=//p')
		[ "$state" = "COMPLETED" ] && assoc=1 && break
		essid=$(iwconfig wlan0 2>/dev/null | sed -n 's/.*ESSID:"\([^"]*\)".*/\1/p')
		[ -n "$essid" ] && assoc=1 && break
		n=$((n + 1))
		sleep 1
	done

	# wifi-on.sh starts udhcpc before the link is up, so that attempt has
	# already given up by now; ask again.
	addr=""
	if [ -n "$assoc" ]; then
		udhcpc -i wlan0 -n -q -t 5 -T 2 -s /etc/init.d/udhcpc.script > /dev/null 2>&1
		m=0
		while [ $m -lt 20 ]; do
			addr=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
			[ -n "$addr" ] && break
			m=$((m + 1))
			sleep 1
		done
	fi

	if [ -n "$addr" ]; then
		log "attempt $attempt: associated, address $addr"
		break
	fi

	log "  ${assoc:+associated but no lease}${assoc:-no association} after ${n}s"
	log "  supplicant: $(pgrep wpa_supplicant > /dev/null 2>&1 && echo running || echo NOT running)"
	log "  wpa_state: $(wpa_cli -i wlan0 status 2>/dev/null | sed -n 's/^wpa_state=//p')"
	# Only on the first two attempts, so the file stays readable: is the network
	# even visible? This radio is 2.4 GHz only.
	if [ "$attempt" -le 2 ]; then
		log "  config: $(wc -c < "$conf" 2>/dev/null || echo 0) bytes"
		log "  networks in range:"
		iwlist wlan0 scan 2>/dev/null | sed -n 's/.*ESSID:"\(.*\)"/    \1/p' | sort -u | head -12 >> "$out"
		log "  driver messages:"
		dmesg 2>/dev/null | grep -iE "8188|wlan|wifi" | tail -6 >> "$out"
	fi
	sync
	attempt=$((attempt + 1))
	sleep 15
done

# setsid so they outlive whatever started this.
pgrep telnetd > /dev/null 2>&1 || setsid telnetd -l sh > /dev/null 2>&1 || telnetd -l sh > /dev/null 2>&1
# tcpsvd is the listener; ftpd is only spawned per connection, so looking for
# ftpd reports "down" while FTP is serving perfectly well.
pgrep tcpsvd > /dev/null 2>&1 || setsid tcpsvd -E 0.0.0.0 21 ftpd -w "$root" > /dev/null 2>&1 &
sleep 1
log "telnet: $(pgrep telnetd > /dev/null 2>&1 && echo up || echo down)"
log "ftp:    $(pgrep tcpsvd > /dev/null 2>&1 && echo up || echo down)"
log ""
log "on the computer:  export SLOT_DEVICE=$addr"
sync
