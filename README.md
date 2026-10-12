# slot-miyoo

An attempt to port [**slot**](https://slot-cfw.fyi/) — Brandon Kowalski's
Game Boy-centric frontend for the Anbernic RG SP — to the **Miyoo Mini Flip**.

Upstream lives in `upstream/slot` as a submodule, pinned to the commit this
port was last rebased onto.

```
git clone --recurse-submodules <this repo>
# or, in an existing clone:
git submodule update --init
```

## Status

**It cross-compiles for the device. Nothing has run on the device yet.**

`task all` produces, from a clean tree, three armv7 artifacts that the handheld
could load — verified as 32-bit ARMv7-A, VFPv4 hard-float, needing nothing
beyond glibc 2.28:

| artifact | size | notes |
|---|---|---|
| `target-miyoo/rust/armv7-unknown-linux-gnueabihf/device/slot` | 4.0 MB | the frontend |
| `vendor-miyoo/gpsp_libretro.so` | 756 KB | ARM dynarec, all upstream patches |
| `vendor-miyoo/mgba_libretro.so` | 2.1 MB | all 7 upstream patches |

The whole of slot needed **exactly one** source change to compile for armv7
(`patches/0001-crash-registers-on-armv7.patch`, 6 lines: the crash handler's
register read). Everything else, the GLES pipeline included, compiles as-is —
because the `gl` crate resolves entry points at runtime, so **the GPU problem
is a runtime problem, not a compile-time one.** The binary will build, ship,
start, fail to find `libEGL.so`, and die. The software rasteriser is still the
work; see the plan.

Nothing here is confirmed against hardware. `notes/hardware.md` is empty.

## The problem in one table

slot ships for the Allwinner H700 Anbernic handhelds (RG SP, RG34XX/SP,
RG35XXSP, 35XX Plus, RG28XX). The Miyoo Mini Flip is a different machine in
every way that matters to a renderer:

| | Anbernic H700 (slot's target) | Miyoo Mini Flip |
|---|---|---|
| SoC | Allwinner H700 | SigmaStar SSD202D |
| CPU | 4x Cortex-A53, **aarch64** | 2x Cortex-A7 @1.2GHz, **armv7 (32-bit)** |
| RAM | 1 GB | **128 MB** |
| 3D GPU | Mali-G31, **libEGL + GLES2** | **none** — 2D blitter only (SigmaStar MI_GFX) |
| Panel | 640x480 / 720x480 | 2.8" **750x560** |
| OS | Anbernic BaseOS (Linux) | Miyoo stock / OnionOS (Linux) |

Three of those are load-bearing:

1. **No GLES2.** slot's device renderer (`crates/slot-gfx/src/fbdev.rs`) dlopens
   `libEGL.so` and builds an OpenGL ES 2.0 context on `/dev/fb0`. The SSD202D
   has no 3D core and no such library. Every pass in `pipeline.rs`, `fbo.rs`
   and `draw.rs` is GLSL. This is the port.
2. **32-bit ARM.** Upstream builds `aarch64` only (`task build:device`, and
   `file ... | grep -q aarch64` assertions throughout `taskfile.yml`). Both
   the Rust binary and the mGBA/gpSP libretro cores need an
   `armv7-unknown-linux-gnueabihf` toolchain.
3. **128 MB RAM.** slot composites through offscreen framebuffers at 720x480
   and keeps wallpaper, label art and font atlases resident, on top of a
   libretro core. The budget needs measuring, not guessing.

## Why this is tractable anyway

The useful discovery: **`slot-ui` contains no graphics calls at all.**

```
$ grep -rl "gl::" upstream/slot/crates/slot-ui/src   # no output
```

The UI builds a flat display list and hands it over:

```rust
pub enum Draw {
    Rect   { x, y, w, h, colour: [f32; 4] },
    Tex    { x, y, w, h, tex: TexId, alpha: f32 },
    Turned { x, y, w, h, tex: TexId, alpha: f32, turn: f32 },
    Game,
    Shot   { tex: TexId },
}
```

All GL is quarantined in `slot-gfx` (~1,950 lines, of which the actual drawing
is `draw.rs`, `pipeline.rs`, `fbo.rs`, `quad.rs`, `shaders.rs`). The seam is
the `Surface` trait plus that five-variant display list. A CPU rasteriser that
honours both, writing straight into `/dev/fb0`, replaces the GLES backend
without touching a line of UI code.

So: a `software` feature alongside upstream's `host` and `device`.

## Building

Needs Docker and [go-task](https://taskfile.dev). Everything cross-builds in
`toolchain/Dockerfile`, which carries the Miyoo Mini gcc (8.3,
`arm-linux-gnueabihf`, **glibc 2.28 — the device's own libc**) alongside a
pinned Rust 1.96 with the armv7 target, so one image builds the C cores and the
Rust frontend.

```sh
task            # list tasks
task all        # cores + frontend for armv7, from scratch
task cores      # just the two libretro cores
task build      # just the frontend
task dist       # assemble the SD card tree -> ./dist
task probe      # assemble just the probe app -> ./dist-probe
task glibc      # highest glibc version the binary needs (device must be >= this)
task shell      # poke around inside the toolchain container
task clean      # drop build output and un-patch the submodule
```

Choices worth knowing, with the reasoning in the scripts themselves:

- **`arm-linux-gnueabihf`, glibc, dynamic** — not musl-static. slot `dlopen`s
  its libretro cores, and a fully static binary has no dynamic loader. The
  toolchain and triple are the ones the Miyoo Mini community settled on
  (Allium, a Rust launcher for this same SoC, uses the same image).
- **`armv7-unknown-linux-gnueabihf`** for Rust and `platform=classic_armv7_a7`
  for gpSP, both with `-mtune=cortex-a7 -mfpu=neon-vfpv4`, so frontend and
  cores target one ISA. Allium uses the lower `arm-unknown-linux-gnueabihf`
  baseline; this device is a Cortex-A7, so there is no reason to give up armv7.
- **Patches, not edits.** `upstream/slot` is a pinned submodule and stays
  pristine; `task patch` applies `patches/*.patch` to its working tree and
  `task unpatch` reverts. A patch that no longer applies is a hard error, not a
  warning, so an upstream bump cannot silently drop a change.

## Plan

- [x] **armv7 toolchain.** `toolchain/Dockerfile`; `task build`.
- [x] **Cores for armv7.** Both built with upstream's patches; `task cores`.
      gpSP has `HAVE_DYNAREC=1` (ARM JIT) and is expected to be the GBA core —
      mGBA has no GBA dynarec and interprets, which at 1.2 GHz probably will not
      hold 60fps. Unmeasured.
- [ ] **Probe the hardware.** Confirm panel geometry, pixel format, rotation,
      evdev button map, battery sysfs paths, free RAM, and that the device's
      glibc is >= 2.28. See below.
- [ ] **Software `Surface`.** `/dev/fb0` mmap + double buffer via `FBIOPAN_DISPLAY`.
- [ ] **Software rasteriser.** The five `Draw` variants: filled rect with alpha,
      textured blit with alpha, rotated blit (`Turned`, used by the cart
      animation), and the game blit with nearest-neighbour scaling.
- [ ] **Drop or cheapen the shader passes.** `lcd3x` masks, blue-light `grade`
      and the bezel compositing are per-pixel shader work. On this CPU they
      start as no-ops behind a config flag.
- [ ] **Fit 750x560.** Upstream hardcodes `OUT_W = 720`, `OUT_H = 480` with
      `SCALE = 3` (a 240x160 source). 750x560 is neither 4:3 nor an integer
      multiple of 240x160 — decide between 2x integer (480x320, letterboxed)
      and a non-integer fit, and author a bezel for it.
- [x] **Boot integration.** `card/App/Slot` plus an armv7
      `card/System/launch_frontend.sh`; `task dist` assembles the card tree.
      Untested on hardware.
- [ ] **Measure.** RAM headroom and sustained frame time, on-device, before
      calling anything done.

## Layout

```
card/                    what ships on the SD card
  App/Slot/              launcher entry for slot
  App/SlotProbe/         launcher entry that collects hardware facts
  System/                armv7 launch script
cores/                   armv7 build scripts for the two libretro cores,
                         counterparts to upstream's aarch64 ones
  miyoo-toolchain.cmake  cross settings for mGBA's cmake build
patches/                 changes to upstream files, applied to the submodule
toolchain/Dockerfile     the cross build box
notes/hardware.md        measured device facts (empty until probed)
upstream/slot            pinned submodule, read-only
taskfile.yml             the armv7 build tasks
```

## Getting it onto the card

Both trees are built to be copied **into the card root** — the directory the
device sees as `/mnt/SDCARD`, where `App/`, `Roms/` and friends already live.
Nothing is reflashed and nothing existing is deleted; the copy merges into
`App/` and adds `System/` beside it.

### The probe — do this one first

This is the useful one today, and it needs no build, no ADB and no shell:

```sh
task probe                      # writes ./dist-probe
cp -R dist-probe/. /media/<you>/<card>/
sync
```

Then on the handheld: **Apps → "slot probe"**. The screen may not change — it
writes a file and exits, taking a second or two. Put the card back in your
machine and read `slot-probe.txt` at its root. That file answers everything
`notes/hardware.md` is waiting on, including the two questions that decide the
next move: whether the device's glibc is >= 2.28, and whether any `libEGL`
exists.

### slot itself — expect it to fail, informatively

```sh
task dist                       # cores + frontend + content root -> ./dist
cp -R dist/. /media/<you>/<card>/
sync
```

Adds **Apps → "slot"**. It will start and die, because the device has no
`libEGL.so`; `slot.log` at the card root will say so. That is the expected
outcome at this stage, and worth doing only because the failure message is
evidence. ROMs, if you want them in place for later, go unzipped in
`Games/GBA`, `Games/GB` and `Games/GBC`, and GBA needs `BIOS/gba_bios.bin`.

### Caveats worth reading before you copy

- **Keep a backup of the card.** Nothing here deletes, but the stock firmware
  is particular and a known-good copy costs nothing.
- **Card format:** whatever the device already boots from — don't reformat.
  FAT32 and exFAT are both routinely mounted `noexec`, which is why both launch
  scripts hand the binary to `ld.so` rather than executing it.
- **`/mnt/SDCARD` is an assumption.** It is the Miyoo Mini path and the Mini
  Flip is the same SoC family, but the scripts don't rely on it: each derives
  the root from its own location. The probe prints the real path.
- **App icons** point at `../../Icons/Default/app/`, which is an Onion path. On
  stock firmware the entry should still appear, just without an icon.
- **If the app doesn't show up**, the launcher has cached its list — reboot the
  device. On Onion, a Package-Manager visit also refreshes it.

## Probing the device

The app above is the no-shell route and collects all of this. If you do have a
shell (ADB over USB, or telnet/SSH depending on firmware), the same ground by
hand:

```sh
uname -a                              # kernel, confirm armv7l
ldd --version                         # must be >= 2.28, what we link against
cat /proc/cpuinfo /proc/meminfo
cat /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/bits_per_pixel
cat /sys/class/graphics/fb0/modes /sys/class/graphics/fb0/stride
ls /dev/input/ ; cat /proc/bus/input/devices    # button map
ls /sys/class/power_supply/                     # battery, for slot-power
ls /usr/lib/ | grep -iE 'egl|gles|mali|mi_'     # expect no EGL, maybe MI_GFX
free -m
```

Land the results in `notes/hardware.md` — the plan's resolution and input work
depends on them.

## Credit and licence

slot is by [Brandon Kowalski](https://github.com/BrandonKowalski/slot) and is
GPL-3.0-or-later; this port inherits that. It is an unofficial, unaffiliated
effort — please don't send slot's issue tracker bug reports about a Miyoo.
