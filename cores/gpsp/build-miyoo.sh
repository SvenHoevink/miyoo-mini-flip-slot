#!/bin/sh
# Build gpsp_libretro.so for the Miyoo Mini Flip (SSD202D, armv7 Cortex-A7).
#
# Upstream slot's cores/gpsp/build.sh builds platform=arm64 with -mcpu=cortex-a53
# for the Anbernic H700. This is the armv7 counterpart. It reuses upstream's
# patches from upstream/slot/cores/gpsp/ so the core behaves the same.
#
# platform=classic_armv7_a7 rather than gpsp's own platform=miyoomini: the latter
# hardcodes /opt/miyoomini-toolchain/usr/bin/arm-linux-gcc, a tool name our
# toolchain image does not use (it is arm-linux-gnueabihf-gcc). classic_armv7_a7
# takes CC from the environment and sets the same cortex-a7 / neon-vfpv4 flags,
# with HAVE_DYNAREC=1 and CPU_ARCH=arm, which is what matters: gpSP's ARM JIT is
# the reason GBA stands a chance at 1.2 GHz.
#
# Expect two "(standard_in) 1: syntax error" lines during the build. gpSP's
# Makefile gates some flags on `echo \`$(CC) -dumpversion\` "< 4.9" | bc -l`, and
# this toolchain's gcc reports "8.3.0" — two dots, which bc cannot parse. Both
# comparisons therefore fail and the else branches are taken: -march=armv7ve
# (which is what we want on a Cortex-A7) and no -static-libgcc/-static-libstdc++.
# The latter is a no-op here: the finished .so needs only libm and libc, which
# `task core:gpsp` asserts. Upstream's bug, harmless for us, so not patched.
#
# Run inside the toolchain container; see taskfile.yml task core:gpsp.
set -eu

usage() {
	echo "usage: $0 stamp COMMIT | build COMMIT TARBALL WORKDIR OUT" >&2
	exit 2
}

patches="upstream/slot/cores/gpsp"
# -DROM_BUFFER_SIZE caps a loop that otherwise mallocs 1 MB at a time until it
# fails -- "try to allocate up to 32 blocks of 1MB each" in init_gamepak_buffer,
# regardless of how big the ROM is. 16 covers every GBA cart here without
# swapping; a larger ROM swaps from the card, which gpSP is built to do and
# which beats being killed.
#
# -DSMALL_TRANSLATION_CACHE was here for a day and is deliberately not. gpSP
# mmaps ROM_TRANSLATION_CACHE_SIZE + RAM_TRANSLATION_CACHE_SIZE at core start
# -- 10.5 MB, becoming resident as code is translated -- and that was the shape
# of a GBA cart being OOM-killed 137 seconds into play. Small takes it to
# 2.4 MB and bought the memory back, but Kirby & the Amazing Mirror fills
# 2 MB of translations and then thrashes: flush, re-translate, flush, reported
# from the handheld as "a massive slowdown, it's chugging now".
#
# The memory came from elsewhere instead, which is the better place for it:
# nine cart faces rather than eighteen (patches/0016) and a crash that no
# longer leaves Allium resident alongside slot (card/.tmp_update/updater),
# together worth far more than the 8 MB this was saving.
device_cflags="-mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -DROM_BUFFER_SIZE=16"

sha256() { sha256sum "$1" | cut -d' ' -f1; }

stamp() {
	echo "commit=$1"
	echo "source=https://github.com/libretro/gpsp/archive/$1.tar.gz"
	echo "recipe=make platform=classic_armv7_a7"
	echo "target=arm-linux-gnueabihf (glibc 2.28, gcc 8.3)"
	echo "device_cflags=$device_cflags"
	for p in "$patches"/*.patch; do
		echo "patch=$(basename "$p") sha256:$(sha256 "$p")"
	done
}

build() {
	commit="$1" tarball="$2" work="$3" out="$4"
	src="$work/gpsp-$commit"
	patches="$(cd "$patches" && pwd)"

	rm -rf "$work"
	mkdir -p "$work"
	tar -xzf "$tarball" -C "$work"
	[ -f "$src/Makefile" ] || {
		echo "$tarball does not hold gpsp-$commit/Makefile" >&2
		exit 1
	}

	for p in "$patches"/*.patch; do
		patch -s -p1 -d "$src" <"$p"
	done

	# CFLAGS goes in the environment, never as a make argument: a command-line
	# variable beats the Makefile's own "CFLAGS +=", which would drop the include
	# paths and -DHAVE_DYNAREC and break the build outright.
	CFLAGS="$device_cflags" \
		make -C "$src" platform=classic_armv7_a7 \
		CC="${CROSS_COMPILE}gcc" CXX="${CROSS_COMPILE}g++" AR="${CROSS_COMPILE}ar" \
		GIT_VERSION="\"$(printf %s "$commit" | cut -c1-7)\"" \
		-j"$(getconf _NPROCESSORS_ONLN)"

	mkdir -p "$(dirname "$out")"
	cp "$src/gpsp_libretro.so" "$out"
	stamp "$commit" >"$out.meta"
}

case "${1:-}" in
stamp) [ $# -eq 2 ] && [ -n "$2" ] || usage; stamp "$2" ;;
build) [ $# -eq 5 ] || usage; build "$2" "$3" "$4" "$5" ;;
*) usage ;;
esac
