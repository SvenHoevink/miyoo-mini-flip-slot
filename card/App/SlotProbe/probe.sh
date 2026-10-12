#!/bin/sh
# Collect the hardware facts the slot port is blocked on, into one file on the
# card. Runs on the device from the Miyoo launcher (stock or Onion) with no
# shell, no ADB and no network.
#
# Written for busybox sh: no bashisms, every tool optional, never exit early on
# a missing path. A blank answer is a real answer, so missing output is printed
# as "(absent)" rather than skipped.
#
# Results belong in notes/hardware.md.

root="${1:-/mnt/SDCARD}"

say() { echo "$@"; }
rule() { say ""; say "== $* =="; }

# cat a file, or say so when it is not there.
show() {
	if [ -r "$1" ]; then
		printf '%s: ' "$1"
		cat "$1" 2>/dev/null || say "(unreadable)"
	else
		say "$1: (absent)"
	fi
}

run() {
	printf '$ %s\n' "$*"
	"$@" 2>&1 || say "(failed: $?)"
}

say "slot probe"
say "date: $(date 2>/dev/null)"
say "card root: $root"

rule "kernel and cpu"
run uname -a
show /proc/cpuinfo
show /proc/device-tree/model

rule "memory"
show /proc/meminfo
run free

rule "libc"
# The port links against glibc 2.28. Anything older will refuse our binary.
for d in /lib /usr/lib; do
	ls "$d"/libc.so* "$d"/ld-*.so* 2>/dev/null
done
if [ -x /lib/libc.so.6 ]; then
	run /lib/libc.so.6
elif command -v ldd >/dev/null 2>&1; then
	run ldd --version
else
	say "no way to ask libc its version"
fi

rule "framebuffer"
for a in virtual_size bits_per_pixel stride modes name rotate state; do
	show "/sys/class/graphics/fb0/$a"
done
run ls -l /dev/fb0

rule "3d / egl — expected absent, this is the port's blocker"
found=""
for d in /lib /usr/lib /usr/local/lib /customer/lib /config/lib; do
	[ -d "$d" ] || continue
	hits="$(ls "$d" 2>/dev/null | grep -iE 'egl|gles|mali|^libgl' || true)"
	[ -n "$hits" ] && { say "$d:"; echo "$hits" | sed 's/^/  /'; found=yes; }
done
[ -n "$found" ] || say "no EGL/GLES/Mali libraries anywhere on the usual paths"

rule "sigmastar 2d (mi_gfx) — the likely replacement path"
for d in /lib /usr/lib /customer/lib /config/lib; do
	[ -d "$d" ] || continue
	hits="$(ls "$d" 2>/dev/null | grep -iE 'mi_|cam_os' || true)"
	[ -n "$hits" ] && { say "$d:"; echo "$hits" | sed 's/^/  /'; }
done

rule "input"
run ls -l /dev/input
show /proc/bus/input/devices

rule "power"
run ls /sys/class/power_supply
for s in /sys/class/power_supply/*; do
	[ -d "$s" ] || continue
	for a in capacity status voltage_now present; do
		show "$s/$a"
	done
done

rule "mounts — is the card noexec?"
show /proc/mounts

rule "what else is running"
run ps

rule "slot binary"
# The real question: does our armv7 glibc-2.28 build load at all? Run it with no
# arguments and keep whatever it says. Expect it to die for want of libEGL, which
# would still prove the binary itself is good.
bin="$root/System/slot"
if [ ! -f "$bin" ]; then
	say "$bin: (absent, nothing to test)"
else
	run ls -l "$bin"
	# Invoke the loader directly: FAT32/exFAT cards are often mounted noexec,
	# which is also why upstream's launch_frontend.sh does this.
	ld=/lib/ld-linux-armhf.so.3
	if [ -x "$ld" ]; then
		say "--- $ld $bin --init-root /tmp/slot-probe-root ---"
		"$ld" "$bin" --init-root /tmp/slot-probe-root 2>&1 | head -40
		say "(exit $?)"
		run ls /tmp/slot-probe-root
	else
		say "$ld: (absent) — wrong loader for this device?"
		ls /lib/ld-* 2>/dev/null
	fi
	for core in gpsp_libretro.so mgba_libretro.so; do
		[ -f "$root/System/$core" ] && run ls -l "$root/System/$core"
	done
fi

rule "done"
say "copy this file off the card and into notes/hardware.md"
