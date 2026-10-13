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

# Diagnostics, off by default because each writes a line per frame or per event
# to the card:
#   SLOT_TRACE_LATENCY=1  per-frame breakdown and the backend's own per-stage
#                         timings, into slot.log
#   SLOT_TRACE_INPUT=1    every input event and how it mapped, into
#                         input-trace.log, plus a survey of the input nodes
#   SLOT_FB_VSYNC=1       block in the page flip until the panel latches; off
#                         because slot paces itself and waiting here too cost
#                         most of the frame budget

# TEMPORARY, to capture how the clamshell hall sensor signals open and close so
# the lid can be wired to Btn::Lid. Writes input-trace.log; remove once mapped.
export SLOT_TRACE_INPUT=1

# TEMPORARY, to confirm whether the audio retry churn is what slowed gameplay.
export SLOT_TRACE_LATENCY=1

[ -f "$SD/slot.log" ] && mv -f "$SD/slot.log" "$SD/slot.log.1"

# NOTE: this used to stop Allium's daemon for the session, because alliumd owns
# the MENU button globally and draws a hotkeys overlay over the running game,
# which fights slot for the same button. That caused the handheld to shut down
# hard when launching a game, three times out of four, so it is reverted: a
# clumsy menu button is a far better problem than a device that cuts power.
#
# alliumd is PID 817-ish, started by /customer/main, and evidently something
# depends on it staying alive. If the overlay is worth another attempt, find out
# what notices its absence first -- do not just kill it again.
exec /lib/ld-linux-armhf.so.3 "$SYS/slot" > "$SD/slot.log" 2>&1
