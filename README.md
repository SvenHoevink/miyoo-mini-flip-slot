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

**Nothing works yet.** This repo currently holds the port notes and the plan.
Read "Why this is a port and not a config change" before expecting a build.

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

## Plan

- [ ] **Probe the hardware.** Confirm panel geometry, pixel format, rotation,
      evdev button map, battery sysfs paths, free RAM. See below.
- [ ] **armv7 toolchain.** `rustup target add armv7-unknown-linux-gnueabihf`,
      pick a working sysroot/linker, get a hello-world running on-device.
- [ ] **Cores for armv7.** Build `mgba_libretro.so` and `gpsp_libretro.so` for
      armv7 with upstream's patches from `upstream/slot/cores/`. gpSP's ARM JIT
      is a real asset on a Cortex-A7; mGBA interpreting GBA at 1.2 GHz may not
      hold 60fps, so expect gpSP to be the default for GBA.
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
- [ ] **Boot integration.** Hook slot into the Miyoo launcher, in place of
      upstream's Anbernic `card/System/launch_frontend.sh`.
- [ ] **Measure.** RAM headroom and sustained frame time, on-device, before
      calling anything done.

## Probing the device

Nothing above is settled until the handheld confirms it. Get a shell (ADB over
USB, or telnet/SSH depending on firmware) and capture:

```sh
uname -a                              # kernel, confirm armv7l
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
