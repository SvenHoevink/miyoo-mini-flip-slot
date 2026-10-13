#!/bin/sh
# Bring this handheld onto the network so builds can be pushed to it over FTP
# instead of moving the SD card, and write what happened to slot-net.txt at the
# card root.
#
# Why this does not just call Allium's telnet-on.sh and ftp-on.sh: both begin
# with wait-for-wifi.sh, which pings 1.1.1.1 once a second for up to sixty
# seconds. Calling the pair of them after waiting ourselves meant up to three
# minutes of a handheld that looks frozen. We also do not need the internet --
# only a LAN address -- so this waits for wlan0 to have an address instead, and
# starts the two daemons directly.
cd "$(dirname "$0")" || exit 1
root="$(cd ../.. && pwd)"
out="$root/slot-net.txt"
scripts="$root/.allium/scripts"
conf=/appconfigs/wpa_supplicant.conf

log() { echo "$@" >> "$out"; }

: > "$out"
log "slot net — $(date 2>/dev/null)"
log ""

# Credentials, if the card carries them. Put SSID and PSK on two lines in
# slot-wifi.txt at the card root and this writes the supplicant config, which
# otherwise has to be set up through Allium's own settings first.
creds="$root/slot-wifi.txt"
if [ -r "$creds" ]; then
	# Skip comments and blanks so the file can explain itself: the first real
	# line is the network name, the second is the password.
	real=$(grep -v '^[[:space:]]*#' "$creds" | grep -v '^[[:space:]]*$')
	ssid=$(echo "$real" | sed -n '1p' | tr -d '\r')
	psk=$(echo "$real" | sed -n '2p' | tr -d '\r')
	if [ -n "$ssid" ]; then
		if [ -n "$psk" ]; then
			log "writing $conf for \"$ssid\" (with a password)"
		else
			log "writing $conf for \"$ssid\" as an OPEN network — no password"
			log "was given on the second line, which is wrong for most networks"
		fi
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
	fi
fi

if [ ! -s "$conf" ]; then
	log "no usable $conf — set WiFi up in Allium's settings, or put the"
	log "network name on line 1 and the password on line 2 of slot-wifi.txt"
	log "at the card root and run this again."
fi

[ -x "$scripts/wifi-on.sh" ] && sh "$scripts/wifi-on.sh" > /dev/null 2>&1

# Wait for an address rather than for the internet, and bound it so this can
# never look like a hang.
addr=""
n=0
while [ $n -lt 20 ]; do
	addr=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
	[ -n "$addr" ] && break
	n=$((n + 1))
	sleep 1
done

if [ -n "$addr" ]; then
	log "address: $addr"
	# Directly, not via the -on.sh wrappers, which would each wait again.
	pgrep telnetd > /dev/null 2>&1 || (cd "$root" && telnetd -l sh)
	pgrep ftpd > /dev/null 2>&1 || (cd "$root" && tcpsvd -E 0.0.0.0 21 ftpd -w "$root" > /dev/null 2>&1 &)
	log "telnet: $(pgrep telnetd > /dev/null 2>&1 && echo up || echo down)"
	log "ftp:    $(pgrep ftpd > /dev/null 2>&1 && echo up || echo down)"
	log ""
	log "on the computer:  export SLOT_DEVICE=$addr"
	log "                  task deploy   /   task log"
else
	log "wlan0 has no address after ${n}s"
	log ""
	log "diagnostics:"
	log "  driver module: $(grep -c 8188fu /proc/modules 2>/dev/null) (want 1)"
	log "  wlan0: $(ifconfig wlan0 2>/dev/null | head -1 || echo 'no such interface')"
	log "  config: $(wc -c < "$conf" 2>/dev/null || echo 0) bytes"
	log "  supplicant: $(pgrep wpa_supplicant > /dev/null 2>&1 && echo running || echo 'not running')"
fi
sync
