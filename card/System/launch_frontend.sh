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

# Temporary, while input is being brought up: slot surveys every /dev/input
# node (opened or skipped, with its capability bitmap) and logs each event and
# whether it mapped, to $SD/input-trace.log. Drop this once buttons work.
export SLOT_TRACE_INPUT=1

[ -f "$SD/slot.log" ] && mv -f "$SD/slot.log" "$SD/slot.log.1"

exec /lib/ld-linux-armhf.so.3 "$SYS/slot" > "$SD/slot.log" 2>&1
