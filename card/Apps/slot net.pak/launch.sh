#!/bin/sh
# Bring up everything needed to deploy to this handheld over the network, using
# Allium's own scripts rather than reimplementing them, and leave the address
# where it can be read back.
#
# Allium's scripts live at /mnt/SDCARD/.allium/scripts. wait-for-wifi.sh, which
# telnet-on and ftp-on both call, is what blocks until the link is up, so WiFi
# has to be configured in Allium's settings once beforehand.
cd "$(dirname "$0")" || exit 1
root="$(cd ../.. && pwd)"
out="$root/slot-net.txt"
scripts="$root/.allium/scripts"

log() { echo "$@" >> "$out"; }

: > "$out"
log "slot net — $(date 2>/dev/null)"

if [ ! -d "$scripts" ]; then
	log "no $scripts: this is not an Allium card, bring the services up by hand"
	sync
	exit 1
fi

[ -x "$scripts/wifi-on.sh" ] && sh "$scripts/wifi-on.sh" >/dev/null 2>&1
log "wifi: $(sh "$scripts/wait-for-wifi.sh" >/dev/null 2>&1 && echo up || echo "DOWN — set it up in Allium's settings first")"

for s in telnet ftp; do
	if [ -x "$scripts/$s-on.sh" ]; then
		sh "$scripts/$s-on.sh" >/dev/null 2>&1
		log "$s: $?"
	else
		log "$s: no $s-on.sh"
	fi
done

# The address, which is the whole point of writing this file.
log ""
log "addresses:"
ip addr 2>/dev/null | grep -oE 'inet [0-9.]+' | grep -v '127\.0\.0\.1' >> "$out" ||
	ifconfig 2>/dev/null | grep -oE 'inet addr:[0-9.]+' >> "$out"
log ""
log "then, on the computer:  export SLOT_DEVICE=<the address above>"
log "                        task deploy   /   task log"
sync
