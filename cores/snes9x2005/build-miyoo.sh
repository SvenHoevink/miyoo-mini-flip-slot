#!/bin/sh
# Build snes9x2005_libretro.so for the Miyoo Mini Flip (SSD202D, armv7 Cortex-A7).
#
# The SNES core. Snes9x 2005 rather than current Snes9x: it is the 1.43-era
# code, far lighter than the modern core, and the usual pick on armv7
# handhelds. Whether it holds 60 fps on this A7 is not measured yet -- see
# notes/nes-snes.md. Upstream slot has no SNES, so there are no upstream
# patches to reuse.
#
# USE_BLARGG_APU stays 0, the Makefile's default: Blargg's APU is the accurate
# one and costs CPU this device does not have to spare. That is what the
# snes9x2005_plus build turns on, and why this is not that build.
#
# Same bc lines and same assertion as gpSP and FCEUmm; see cores/fceumm.
#
# The licence is Snes9x's own, which forbids commercial use. It ships beside
# the core in System/licenses so nobody receives one without the other.
#
# Run inside the toolchain container; see taskfile.yml task core:snes9x2005.
set -eu

usage() {
	echo "usage: $0 stamp COMMIT | build COMMIT TARBALL WORKDIR OUT" >&2
	exit 2
}

device_cflags="-mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"

stamp() {
	echo "commit=$1"
	echo "source=https://github.com/libretro/snes9x2005/archive/$1.tar.gz"
	echo "recipe=make platform=classic_armv7_a7 USE_BLARGG_APU=0"
	echo "target=arm-linux-gnueabihf (glibc 2.28, gcc 8.3)"
	echo "device_cflags=$device_cflags"
}

build() {
	commit="$1" tarball="$2" work="$3" out="$4"
	src="$work/snes9x2005-$commit"

	rm -rf "$work"
	mkdir -p "$work"
	tar -xzf "$tarball" -C "$work"
	[ -f "$src/Makefile" ] || {
		echo "$tarball does not hold snes9x2005-$commit/Makefile" >&2
		exit 1
	}

	# CFLAGS in the environment, never as a make argument; see CLAUDE.md.
	CFLAGS="$device_cflags" \
		make -C "$src" platform=classic_armv7_a7 USE_BLARGG_APU=0 \
		CC="${CROSS_COMPILE}gcc" CXX="${CROSS_COMPILE}g++" AR="${CROSS_COMPILE}ar" \
		GIT_VERSION="\"$(printf %s "$commit" | cut -c1-7)\"" \
		-j"$(getconf _NPROCESSORS_ONLN)"

	mkdir -p "$(dirname "$out")"
	cp "$src/snes9x2005_libretro.so" "$out"
	cp "$src/copyright" "$out.copyright"
	stamp "$commit" >"$out.meta"
}

case "${1:-}" in
stamp) [ $# -eq 2 ] && [ -n "$2" ] || usage; stamp "$2" ;;
build) [ $# -eq 5 ] || usage; build "$2" "$3" "$4" "$5" ;;
*) usage ;;
esac
