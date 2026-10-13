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
#   SLOT_TRACE=1          the audio ring every so often, as
#                         "queued/target, N dropped, M starved"
#
# All three are off now that the pacing is settled, and they are not free: each
# writes to the card from inside the frame loop, SLOT_TRACE_LATENCY once per
# frame and SLOT_TRACE_INPUT once per event. Turn on only the one being read.
#
# Two more that change behaviour rather than reporting it:
#   SLOT_FB_VSYNC=1       block in the page flip until the panel latches; off
#                         because slot paces itself and waiting here too cost
#                         most of the frame budget
#   SLOT_FB_PAGES=1       give up the page flip and draw at the scanout; this
#                         skips the driver's 6.6 ms page copy but tears, on the
#                         shelf and in game both, so it is not used
#   SLOT_DRIVE_EMU=0      stop chaining the core to the display's rate
#   SLOT_RING_FRAMES=N    audio ring depth in 60 Hz video frames; 12 here (200
#                         ms, half of it the target) against upstream's 8,
#                         because the frontend's 30-50 ms spikes drained a
#                         133 ms ring. Deeper is more audio latency

# The driver's FBIOPAN_DISPLAY costs 6.6 ms a frame here, which with 13.4 ms of
# real work puts the loop near 20 ms. Drawing straight at the scanout
# (SLOT_FB_PAGES=1) gives those 6.6 ms back but tears visibly, so the page flip
# stays. Instead the core is unchained from the display: it keeps its own
# 59.73 Hz and the display drops the frames it cannot fit, so the speed and the
# audio pitch are right and the cost is judder rather than slow motion.
export SLOT_DRIVE_EMU=0

# TEMPORARY, for one run: with the core unchained the resample factor should sit
# at 1.0 rather than following the display. Remove once confirmed.
export SLOT_TRACE=1
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
# Crash handling. slot's own handler prints the faulting pc and lr to the log
# (see patches/0001 for the armv7 register read); this adds the kernel side:
# upstream's coresave.sh writes the core, the process maps and a copy of the
# log into $SD/crash. Kept per-boot so a crash is still there after a restart.
mkdir -p "$SD/crash" 2>/dev/null
echo "|/bin/sh $SYS/coresave-miyoo.sh %p %s %e %t" > /proc/sys/kernel/core_pattern 2>/dev/null
ulimit -c unlimited 2>/dev/null

# Not exec: the exit status is worth recording. An unexplained shutdown looks
# the same as a clean exit from the outside, and this is what tells them apart.
started="$(date '+%F %T' 2>/dev/null)"
/lib/ld-linux-armhf.so.3 "$SYS/slot" > "$SD/slot.log" 2>&1
status=$?
echo "$started -> $(date '+%F %T' 2>/dev/null) exit=$status" >> "$SD/crash/exits.log"
if [ "$status" -gt 128 ]; then
	# 128 + signal: killed rather than returned. 139 is SIGSEGV, 134 SIGABRT.
	echo "  killed by signal $((status - 128)); see crash/ and slot.log.1" >> "$SD/crash/exits.log"
	cp -f "$SD/slot.log" "$SD/crash/slot-exit-$status.log" 2>/dev/null
fi
sync
