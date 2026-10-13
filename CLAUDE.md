# CLAUDE.md

Porting [slot](https://slot-cfw.fyi/) to the **Miyoo Mini Flip**. Read
`README.md` first for the target hardware, the blockers and the plan; this file
is about how to work in the repo.

## Ground rules

**Never report a port step as working until it ran on the handheld.** This
project's whole difficulty is that the target has no GPU and 128 MB of RAM.
A host build that compiles, or a unit test that passes, proves nothing about
the device. Say "builds for armv7" or "compiles" — not "works".

`task run:qemu` runs the real device binary here and is the right loop for
writing the rasteriser, but it is **not** evidence about the device. It cannot
speak to frame times on a 1.2 GHz Cortex-A7 or to a 128 MB ceiling, and its
`fb0` is the host's. "Draws correctly under qemu" is a true and useful claim;
"works on the Mini Flip" is not the same claim.

**Don't invent hardware facts.** `notes/hardware.md` now holds measured values
for the panel, CPU, RAM, libc, mounts and input — use those, not spec sheets,
which were wrong about the panel (752x560, not 750) and the usable RAM (~101 MB,
not 128). Anything still missing from that file is a hypothesis; mark it as one.
The per-button evdev codes and the battery source are the notable gaps.

`.gitmodules` sets `ignore = dirty` for the submodule, because `task patch`
leaves its working tree modified by design; the *pinned commit* is still
tracked, so a deliberate upstream bump shows up in `git status` as it should.

**`upstream/slot` is read-only.** It is a submodule pinned to a specific
upstream commit. Never commit changes inside it. Port work lives in this
repo's own tree. If a change must land in upstream files, write it as a patch
under `patches/` so a rebase onto a newer upstream stays possible, and record
which upstream commit it applies to.

## Where the port goes

The architectural seam, and the reason this is feasible at all:

- `slot-ui` has **no** graphics calls. It emits `Vec<Draw>` — five variants,
  defined in `upstream/slot/crates/slot-gfx/src/draw.rs`.
- All GL lives in `slot-gfx`, behind the `Surface` trait
  (`crates/slot-gfx/src/surface.rs`) and selected by cargo feature:
  `host` (winit + glutin, for a desktop window) or `device`
  (`fbdev.rs`: dlopen `libEGL.so`, GLES2 on `/dev/fb0`).

The port adds a third backend — a CPU rasteriser over mmapped `/dev/fb0` —
and changes nothing above the seam. **If a port change requires editing
`slot-ui`, stop and reconsider; it almost certainly belongs in the backend.**

Files that matter, in order: `surface.rs` (the trait, plus `OUT_W`/`OUT_H`),
`draw.rs` (the display list), `pipeline.rs` (the game pass, `SCALE`/`SRC_W`/
`SRC_H`), `fbo.rs` (offscreen compositing — the big RAM consumer),
`shaders.rs`, `lcd3x.rs` and `grade.rs` (per-pixel effects; the first things
to make no-ops).

## The toolchain is settled; don't relitigate it

`toolchain/Dockerfile` + `taskfile.yml` cross-build all three artifacts for
armv7 from a clean tree. The decisions are made and the reasoning is in the
scripts: glibc/dynamic (not musl-static, because slot `dlopen`s its cores),
`armv7-unknown-linux-gnueabihf`, `platform=classic_armv7_a7` for gpSP,
`cores/miyoo-toolchain.cmake` for mGBA. Build with `task`, not by hand.

Two traps already paid for, both found by rebuilding from clean rather than
incrementally — so **run `task clean && task all` before trusting a build
change**:

- The base image exports `CROSS_COMPILE` and its PATH only from root's
  bashrc/profile, so non-login shells and non-root uids lose both. Everything
  the build needs is set as `ENV` in the Dockerfile; keep it that way.
- Never pass `CFLAGS` as a make *argument* to a libretro core. A command-line
  variable overrides the Makefile's own `CFLAGS +=`, dropping include paths and
  `-DHAVE_DYNAREC`. It goes in the environment.

## Upstream assumes aarch64 in places that will bite

`upstream/slot/taskfile.yml` asserts `file ... | grep -q aarch64` after every
device build and core build, and `device:sh` runs builds in a
`rust:1-bullseye` container that is only fetched when the host isn't
`Linux-aarch64`. An armv7 path needs its own tasks rather than edits to those
— keep them in a top-level `taskfile.yml` in this repo that delegates to
upstream's where it can.

Rust toolchain is pinned to 1.96 by `upstream/slot/rust-toolchain.toml`.

## Commands

```sh
git submodule update --init          # after cloning

# This port (needs Docker + go-task), from the repo root:
task              # list tasks
task all          # cores + frontend for armv7
task clean        # drop build output, revert the submodule
task shell        # shell inside the cross toolchain
task glibc        # glibc floor of the built binary
task dist         # SD card tree
task probe        # the on-device probe app alone
task run:qemu     # run the device build here, under qemu
task verify:root  # prove dist's content root matches slot --init-root

# Upstream, run from upstream/slot (needs go-task):
task --list                          # all upstream tasks
task run                             # slot in a desktop window, SLOT_ROOT=./sdcard
task sdcard                          # create an empty content root
task check                           # fmt + clippy (host and device) + tests
```

Useful env vars upstream honours: `SLOT_ROOT` (content root), `SLOT_WINDOW`
(window size, e.g. `1280x960`), `SLOT_BARE` (no chrome), `SLOT_ROTATE=ccw`
(portrait panels — relevant to us).

Run the desktop build at the target's geometry to eyeball layout before
touching the device:

```sh
SLOT_WINDOW=750x560 task run
```

## Dependencies on the device, for `slot-power` and input

slot discovers hardware by walking sysfs rather than matching on a device
name — `/sys/class/graphics/fb0`, `/sys/class/input`, `/sys/class/power_supply`,
`/sys/class/block`, `/proc/mounts`, `/proc/uptime`, `/proc/interrupts`. That
is the port's friend: much of it may just work. Check each path exists on the
Miyoo before assuming which.

## The target card runs Allium

Dean's card is an **Allium** install (`Apps/<Name>.pak/`, `allium.log` at the
root), not stock or Onion (`App/<Name>/config.json`). `card/` ships both layouts
because they coexist harmlessly, but Allium is the one that has to work.

Allium is itself a Rust launcher for this same SoC, and it draws without a GPU —
so it is the closest working reference for the software rasteriser, as well as
for the audio path (it uses SigmaStar `MI_AO` via FFI rather than ALSA). Worth
reading before inventing anything.

## Anything that ships on the card is busybox sh

`card/` holds the launcher entries and launch scripts. The device's shell is
busybox, so no bashisms, no `local`, no arrays, and assume any given tool may
be missing. Test with `docker run --rm -v "$PWD":/src busybox:1.36 sh <script>`
rather than the host shell, which is fish with GNU coreutils behind it.

Start slot through `/lib/ld-linux-armhf.so.3` rather than executing it, as both
launch scripts do: FAT32 and exFAT cards are routinely mounted `noexec`.
Upstream does the same with the aarch64 loader.

## NEON is not available to us the easy way

Rust's armv7 NEON intrinsics (`std::arch::arm`) are **unstable** —
`stdarch_arm_neon_intrinsics`, rust-lang/rust#111800 — and upstream pins stable
1.96. `-C target-feature=+neon` is likewise rejected as unstable on this target
and changes nothing; `-C target-cpu=cortex-a7` already implies it. aarch64 NEON
is stable, which is why slot never had to care.

Verified by disassembly: **LLVM autovectorises none of the backend's hot
loops** — zero NEON instructions in `Game::draw`, `raster::blit`,
`draw_sprites` or `Image::from_rgba`. Bounds checks and the byte-strided,
branchy access patterns are the likely reason, so shaping loops around
`chunks_exact` and iterators is the first thing to try and costs nothing.

If hand-written NEON is really needed, the options on stable are inline
`core::arch::asm!` or a C shim built with the cross gcc (8.3 supports
`arm_neon.h` with `-mfpu=neon-vfpv4`). Do not reach for either until the
per-stage profile says which loop deserves it.

## Conventions

- Match upstream's style in any code that mirrors it — it is terse, comments
  are sparse and explain *why*, and prose in docs/commits is lowercase-plain
  rather than marketing. `cargo fmt` and clippy-clean (`-D warnings`).
- Record device measurements (frame times, RAM) as numbers in `notes/`, with
  the date and the firmware version they came from.
- GPL-3.0-or-later, inherited from slot. Keep upstream's `licenses/` tree in
  anything shipped to a card.
- No Claude/Anthropic attribution in commits or PR bodies.
