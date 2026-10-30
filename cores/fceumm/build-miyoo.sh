#!/bin/sh
# Build fceumm_libretro.so for the Miyoo Mini Flip (SSD202D, armv7 Cortex-A7).
#
# The NES core. Upstream slot has no NES, so there are no upstream patches to
# reuse; this is libretro-fceumm as it comes, built the way gpSP is:
# platform=classic_armv7_a7 takes CC from the environment and sets the
# cortex-a7 / neon-vfpv4 flags. A NES is light work for a 1.2 GHz A7 -- nothing
# here is tuned for speed, and nothing needs to be until the device says so.
#
# Expect the same two "(standard_in) 1: syntax error" lines as gpSP: the
# Makefile asks bc to compare "8.3.0" with "4.9", bc cannot, and the else
# branches are taken -- -march=armv7ve, and no -static-libgcc. `task
# core:fceumm` asserts the .so needs nothing past libc and libm, which is what
# makes the second one harmless.
#
# Run inside the toolchain container; see taskfile.yml task core:fceumm.
set -eu

usage() {
	echo "usage: $0 stamp COMMIT | build COMMIT TARBALL WORKDIR OUT" >&2
	exit 2
}

device_cflags="-mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"

stamp() {
	echo "commit=$1"
	echo "source=https://github.com/libretro/libretro-fceumm/archive/$1.tar.gz"
	echo "recipe=make platform=classic_armv7_a7"
	echo "target=arm-linux-gnueabihf (glibc 2.28, gcc 8.3)"
	echo "device_cflags=$device_cflags"
}

build() {
	commit="$1" tarball="$2" work="$3" out="$4"
	src="$work/libretro-fceumm-$commit"

	rm -rf "$work"
	mkdir -p "$work"
	tar -xzf "$tarball" -C "$work"
	[ -f "$src/Makefile.libretro" ] || {
		echo "$tarball does not hold libretro-fceumm-$commit/Makefile.libretro" >&2
		exit 1
	}

	# CFLAGS in the environment, never as a make argument; see CLAUDE.md.
	CFLAGS="$device_cflags" \
		make -C "$src" platform=classic_armv7_a7 \
		CC="${CROSS_COMPILE}gcc" CXX="${CROSS_COMPILE}g++" AR="${CROSS_COMPILE}ar" \
		GIT_VERSION="\"$(printf %s "$commit" | cut -c1-7)\"" \
		-j"$(getconf _NPROCESSORS_ONLN)"

	mkdir -p "$(dirname "$out")"
	cp "$src/fceumm_libretro.so" "$out"
	stamp "$commit" >"$out.meta"
}

case "${1:-}" in
stamp) [ $# -eq 2 ] && [ -n "$2" ] || usage; stamp "$2" ;;
build) [ $# -eq 5 ] || usage; build "$2" "$3" "$4" "$5" ;;
*) usage ;;
esac
