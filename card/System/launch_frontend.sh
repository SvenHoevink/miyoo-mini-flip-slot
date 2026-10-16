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
LOGS="$SD/Logs"
export SLOT_ROOT="$SD"

# Logs live in Logs/ since upstream moved them there, and upstream's
# coresave.sh -- which this card still uses, through coresave-miyoo.sh --
# writes the core and copies the log by that path. Anything left at the root
# by an older build is moved rather than orphaned.
mkdir -p "$LOGS" 2>/dev/null
for f in slot.log slot.log.1 input-trace.log slot-launch.txt; do
	[ -f "$SD/$f" ] && mv -f "$SD/$f" "$LOGS/$f"
done
[ -d "$SD/crash" ] && [ ! -e "$LOGS/crash" ] && mv "$SD/crash" "$LOGS/crash"

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
# Switched from the card rather than by editing this script, so a question
# about frame times costs an empty file and a relaunch instead of a redeploy:
#   touch Config/trace-latency.txt   -- per-frame latency, and the backend's
#                                       per-stage profile every 60 frames
#   touch Config/trace-input.txt     -- every input event and how it mapped
[ -f "$SD/Config/trace-latency.txt" ] && export SLOT_TRACE_LATENCY=1
[ -f "$SD/Config/trace-input.txt" ] && export SLOT_TRACE_INPUT=1
#
# Two more that change behaviour rather than reporting it:
#   SLOT_FB_VSYNC=1       block in the page flip until the panel latches; off
#                         because slot paces itself and waiting here too cost
#                         most of the frame budget
#   SLOT_FB_PAGES=1       give up the page flip and draw at the scanout; this
#                         skips the driver's 6.6 ms page copy but tears, on the
#                         shelf and in game both, so it is not used
#   SLOT_DRIVE_EMU=0      stop chaining the core to the display's rate
#   SLOT_RING_FRAMES=N    audio ring depth in 60 Hz video frames, upstream's 8
#                         here; half of it is the DRC target, so 67 ms at
#                         48 kHz. Deeper is more audio latency
#   SLOTAO_FRAMES=N       MI_AO's hardware buffer, in 512-frame periods, 4 here
#                         = 43 ms. The other half of the latency

# The driver's FBIOPAN_DISPLAY costs 6.6 ms a frame here, which with 13.4 ms of
# real work puts the loop near 20 ms. Drawing straight at the scanout
# (SLOT_FB_PAGES=1) gives those 6.6 ms back but tears visibly, so the page flip
# stays. Instead the core is unchained from the display: it keeps its own
# 59.73 Hz and the display drops the frames it cannot fit, so the speed and the
# audio pitch are right and the cost is judder rather than slow motion.
export SLOT_DRIVE_EMU=0

# Audio: upstream's ring depth, and the codec queue throttle on by default in
# the binary (SLOTAO_QUEUE, five 512-frame periods, 53 ms).
#
# MI_AO ignores the buffer depth in its attributes -- asked for two periods it
# accepted 32, which is 341 ms -- and that was the audio lag. The throttle
# queries the queue instead and tops it up to a target, which held the whole
# pipeline at ~100 ms, measured. It used to make the sound choppy as well, and
# that turned out to be MI_AO_QueryChnStat answering in *bytes* where the
# throttle read periods: any audio at all counted as "5 or more", so it only
# wrote once the codec had run completely dry. notes/hardware.md has the
# numbers. SLOTAO_QUEUE=0 goes back to unthrottled and laggy if ever needed.
export SLOT_RING_FRAMES=8

# A cart that crashes its core soft-bricks the handheld: the seated cart is
# re-inserted on every boot, the core segfaults, slot dies before it can clear
# the cart, and since slot is the boot process there is no shelf to escape to.
# Kirby's Pinball Land DX does exactly this -- SIGSEGV in mGBA's _GBMBC2Read --
# and getting out of it needed FTP and a hand-edited Config/slot.state.
#
# So: drop a guard before launching and clear it once slot has survived a while.
# Finding it still there at boot means the last launch did not survive its first
# seconds, and the seated cart is the likeliest reason, so it is unseated and
# the handheld comes up on the shelf.
guard="$SD/Config/.slot-launching"
if [ -f "$guard" ]; then
	sed -i -e 's/^cart=.*/cart=/' -e 's/^cart_platform=.*/cart_platform=/' \
		"$SD/Config/slot.state" 2>/dev/null
	rm -f "$guard"
	echo "slot: last launch did not survive; unseated the cart" >> "$LOGS/slot-launch.txt"
fi
: > "$guard"
sync
# Long enough to be past loading a core and showing a frame, short enough that
# a deliberate power-off mid-game does not usually trip it -- and tripping it
# only costs starting at the shelf.
#
# The sleeper's pid is kept so it can be killed when slot returns. Backgrounded
# and forgotten, it outlives the very crash the guard exists to catch: slot was
# OOM-killed eight seconds into a GBA cart, this script exited, and the orphan
# then cleared the guard anyway twenty-five seconds later. The next boot saw a
# clean guard, re-seated the cart and died again -- a loop that needed FTP to
# get out of, which is exactly what the guard was written to prevent.
( sleep 25; rm -f "$guard" ) &
sleeper=$!

[ -f "$LOGS/slot.log" ] && mv -f "$LOGS/slot.log" "$LOGS/slot.log.1"

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
# log into $SD/Logs/crash. Kept per-boot so a crash is still there after a
# restart.
mkdir -p "$LOGS/crash" 2>/dev/null
echo "|/bin/sh $SYS/coresave-miyoo.sh %p %s %e %t" > /proc/sys/kernel/core_pattern 2>/dev/null
ulimit -c unlimited 2>/dev/null

# Not exec: the exit status is worth recording. An unexplained shutdown looks
# the same as a clean exit from the outside, and this is what tells them apart.
started="$(date '+%F %T' 2>/dev/null)"
/lib/ld-linux-armhf.so.3 "$SYS/slot" > "$LOGS/slot.log" 2>&1
status=$?
# Before anything else: if the sleeper is still pending, slot did not survive
# its first seconds, and the guard has to stay for the next boot to find.
kill "$sleeper" 2>/dev/null
echo "$started -> $(date '+%F %T' 2>/dev/null) exit=$status" >> "$LOGS/crash/exits.log"
if [ "$status" -gt 128 ]; then
	# 128 + signal: killed rather than returned. 139 is SIGSEGV, 134 SIGABRT.
	echo "  killed by signal $((status - 128)); see Logs/crash and Logs/slot.log.1" >> "$LOGS/crash/exits.log"
	cp -f "$LOGS/slot.log" "$LOGS/crash/slot-exit-$status.log" 2>/dev/null
fi
sync
