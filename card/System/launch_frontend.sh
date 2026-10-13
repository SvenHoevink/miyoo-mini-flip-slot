#!/bin/sh
# armv7 counterpart of upstream/slot/card/System/launch_frontend.sh.
#
# Two differences from upstream, both because this is a Miyoo and not an
# Anbernic H700:
#   - the loader is /lib/ld-linux-armhf.so.3, not ld-linux-aarch64.so.1
#   - the card root defaults to /mnt/SDCARD, the Miyoo path, not /mnt/sdcard
#
# As upstream does, slot is started *through the loader* rather than executed
# directly: FAT32 and exFAT cards are routinely mounted noexec, and handing the
# binary to ld.so as an argument sidesteps that.
#
# Upstream's led.sh and coresave.sh hooks are left out until the device is known
# to have the sysfs paths they poke; see notes/hardware.md.
SD="${SLOT_ROOT:-/mnt/SDCARD}"
SYS="$SD/System"
export SLOT_ROOT="$SD"

# The Mini Flip's LCD is fitted upside down: a frame written top-down to
# /dev/fb0 appears inverted on the panel, confirmed on the device.
export SLOT_FB_ROTATE=180

# Temporary, while the software renderer is being tuned: one line per frame in
# slot.log breaking the frame down, of which take>swapped is this backend's
# rasteriser plus the output blit. Drop it once the frame rate is settled.
export SLOT_TRACE_LATENCY=1

# Also on, to capture how the clamshell hall sensor signals open and close so
# the lid can be wired up properly. Drop both once that is done.
export SLOT_TRACE_INPUT=1

[ -f "$SD/slot.log" ] && mv -f "$SD/slot.log" "$SD/slot.log.1"

# Allium's daemon keeps running under whatever it launches, and it owns the
# MENU button globally: it draws a "Global Hotkeys / Ingame Hotkeys" overlay
# over the game and claims MENU + power/volume/brightness for itself. slot wants
# that button too -- a tap is its quick menu, a hold ejects -- so both react to
# every press and the result is unusable.
#
# On the Anbernic handhelds slot *is* the launcher and owns input outright, so
# stopping alliumd for the session is what gives it the same footing. It is put
# back on the way out, including when slot crashes, since it is also what
# returns the handheld to its launcher.
ALLIUMD="$SD/.allium/bin/alliumd"
stopped=""
if [ -x "$ALLIUMD" ] && pgrep alliumd > /dev/null 2>&1; then
	killall alliumd > /dev/null 2>&1 && stopped=1
fi
restore_allium() {
	[ "$stopped" = 1 ] || return 0
	pgrep alliumd > /dev/null 2>&1 && return 0
	cd "$SD" && setsid "$ALLIUMD" > /dev/null 2>&1 &
}
trap restore_allium EXIT INT TERM

# Not exec: the trap has to run when slot exits.
/lib/ld-linux-armhf.so.3 "$SYS/slot" > "$SD/slot.log" 2>&1
restore_allium
