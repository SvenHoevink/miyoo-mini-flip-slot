#!/bin/sh
# Build mgba_libretro.so for the Miyoo Mini Flip (SSD202D, armv7 Cortex-A7).
#
# The armv7 counterpart of upstream slot's cores/mgba/build.sh, which builds
# aarch64 for the Anbernic H700. Reuses upstream's patches from
# upstream/slot/cores/mgba/ so the core behaves the same, and cross-compiles via
# cores/miyoo-toolchain.cmake.
#
# Note: mGBA has no GBA dynarec, so this interprets. On a 1.2 GHz Cortex-A7 it is
# the GB/GBC core; expect gpSP (ARM JIT) to carry GBA. Measure before deciding.
#
# Run inside the toolchain container; see taskfile.yml task core:mgba:miyoo.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
patches="$here/../../upstream/slot/cores/mgba"
# This port's own core patches, applied after upstream slot's. They live here
# rather than beside upstream's because upstream/slot is a read-only pinned
# submodule. Each one carries a header saying what it fixes and which mgba
# commit it applies to; drop a patch when a core bump makes it redundant.
local_patches="$here/patches"
toolchain="$here/../miyoo-toolchain.cmake"

# No -flto=auto here: upstream uses it for the H700 build, but gcc 8.3 predates
# -flto=auto and mGBA's libretro target has had LTO trouble on this toolchain.
device_cflags="-O3"

usage() {
	echo "usage: $0 stamp COMMIT | build COMMIT WORKDIR OUT" >&2
	exit 2
}

sha256() { sha256sum "$1" | cut -d' ' -f1; }

stamp() {
	echo "commit=$1"
	echo "source=https://github.com/libretro/mgba/tree/$1"
	echo "recipe=cmake -DLIBMGBA_ONLY=ON -DBUILD_LIBRETRO=ON"
	echo "target=arm-linux-gnueabihf (glibc 2.28, gcc 8.3)"
	echo "device_cflags=$device_cflags"
	for p in "$patches"/*.patch; do
		echo "patch=$(basename "$p") sha256:$(sha256 "$p")"
	done
	# In the stamp as well, so editing one rebuilds the core rather than
	# silently reusing a .so built without it.
	for p in "$local_patches"/*.patch; do
		[ -e "$p" ] || continue
		echo "port-patch=$(basename "$p") sha256:$(sha256 "$p")"
	done
}

build() {
	commit="$1" work="$2" out="$3"
	src="$work/mgba"
	obj="$work/build"
	patches="$(cd "$patches" && pwd)"
	local_patches="$(cd "$local_patches" && pwd)"
	toolchain="$(cd "$(dirname "$toolchain")" && pwd)/$(basename "$toolchain")"

	mkdir -p "$src"
	[ -d "$src/.git" ] || git init -q "$src"
	git -C "$src" cat-file -e "$commit^{commit}" 2>/dev/null ||
		git -C "$src" fetch -q --depth 1 https://github.com/libretro/mgba "$commit"
	git -C "$src" checkout -q --force --detach "$commit"
	git -C "$src" clean -q -fdx
	for p in "$patches"/*.patch; do
		git -C "$src" apply "$p"
	done
	for p in "$local_patches"/*.patch; do
		[ -e "$p" ] || continue
		git -C "$src" apply "$p"
	done

	cmake -S "$src" -B "$obj" \
		-DCMAKE_TOOLCHAIN_FILE="$toolchain" \
		-DLIBMGBA_ONLY=ON -DBUILD_LIBRETRO=ON \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_FLAGS="$device_cflags"
	cmake --build "$obj" --target mgba_libretro --parallel "$(getconf _NPROCESSORS_ONLN)"

	[ -f "$obj/mgba_libretro.so" ] || {
		echo "cmake finished without producing mgba_libretro.so" >&2
		exit 1
	}
	mkdir -p "$(dirname "$out")"
	cp "$obj/mgba_libretro.so" "$out"
	stamp "$commit" >"$out.meta"
}

case "${1:-}" in
stamp) [ $# -eq 2 ] && [ -n "$2" ] || usage; stamp "$2" ;;
build) [ $# -eq 4 ] || usage; build "$2" "$3" "$4" ;;
*) usage ;;
esac
