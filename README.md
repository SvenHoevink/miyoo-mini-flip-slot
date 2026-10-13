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

**It runs games on the handheld.** GB, GBC and GBA, at roughly the frame budget,
with working input and a software renderer standing in for the GPU this device
does not have.

`task all` produces, from a clean tree, three armv7 artifacts that the handheld
could load — verified as 32-bit ARMv7-A, VFPv4 hard-float, needing nothing
beyond glibc 2.28:

| artifact | size | notes |
|---|---|---|
| `target-miyoo/rust/armv7-unknown-linux-gnueabihf/device/slot` | 4.0 MB | the frontend |
| `vendor-miyoo/gpsp_libretro.so` | 756 KB | ARM dynarec, all upstream patches |
| `vendor-miyoo/mgba_libretro.so` | 2.1 MB | all 7 upstream patches |

Compiling for armv7 took **one** six-line change (`patches/0001`): the GLES
pipeline builds untouched, because the `gl` crate resolves entry points at
runtime. The GPU problem was never a compile-time one — the binary built, ran,
and died looking for `libEGL.so`. Replacing that is `patches/0002`.

Where it stands:

| | |
|---|---|
| boots, renders, runs games | yes |
| GB / GBC / GBA | yes, GBA on gpSP |
| frame budget | backend 8.2 ms of a 16.86 ms period, core 6.3 ms |
| buttons, including the d-pad | yes |
| lid open/close | detected, does nothing |
| audio | ALSA is present; untested |
| battery indicator | no source on this device |

The renderer, the cores and the input map are all working. What is left is in
"Still open" at the bottom.

## The problem in one table

slot ships for the Allwinner H700 Anbernic handhelds (RG SP, RG34XX/SP,
RG35XXSP, 35XX Plus, RG28XX). The Miyoo Mini Flip is a different machine in
every way that matters to a renderer:

| | Anbernic H700 (slot's target) | Miyoo Mini Flip |
|---|---|---|
| SoC | Allwinner H700 | SigmaStar SSD202D |
| CPU | 4x Cortex-A53, **aarch64** | 2x Cortex-A7 @1.2GHz, **armv7 (32-bit)** |
| RAM | 1 GB | **128 MB, ~101 MB usable** |
| 3D GPU | Mali-G31, **libEGL + GLES2** | **none** — 2D blitter only (SigmaStar MI_GFX) |
| Panel | 640x480 / 720x480 | 2.8" **752x560**, 32bpp, triple-buffered |
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
3. **101 MB of usable RAM.** `MemTotal` is 103352 kB — the 128 MB on the spec
   sheet minus what the SoC reserves — with no swap and about 81 MB free at
   idle. slot composites through offscreen framebuffers and keeps wallpaper,
   label art and font atlases resident, on top of a libretro core.

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
task run:qemu   # run the device build here, under qemu
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

## What the port needed

- **armv7 toolchain and cores.** `toolchain/Dockerfile`; `task all`. gpSP has the
  ARM JIT and is the GBA core to use — 6.3 ms a frame against mGBA's 14-18.
- **A software renderer.** `patches/0002`: slot's GLES2 backend replaced by a
  framebuffer and a CPU rasteriser, behind a cargo feature, with nothing above
  `slot-gfx` aware of the swap.
- **Four 32-bit assumptions in upstream**, none visible on the aarch64 hardware
  slot was written for: the crash handler's register read (`0001`), evdev
  capability bitmaps read as 64-bit words (`0004`), `struct input_event` being
  16 bytes rather than 24 (`0003`), and the input threads being starved into
  stalls of over a second (`0003`).
- **Miyoo button codes.** `gpio_keys` reports keyboard codes, not `BTN_*`
  (`0003`).
- **An upside-down panel.** `SLOT_FB_ROTATE=180`, set in the card's launch
  script.

## Still open

- **The lid does nothing.** The hall sensor is detected and its events are
  dropped rather than acted on, because it advertises `KEY_POWER` and closing
  the clamshell otherwise shut the handheld down. Wiring it to `Btn::Lid` needs
  its open/close signalling captured first; see `notes/hardware.md`.
- **Allium owns the MENU button.** Its daemon draws a hotkeys overlay over the
  running game and claims MENU for itself, so slot's gestures work but are
  shadowed. Stopping the daemon fixed the overlay and made the handheld power
  off when launching a game, so it is reverted — **do not kill `alliumd`**. The
  route worth trying is a setting or per-app config in Allium.
- **No in-game settings menu.** Upstream's quick menu is shelf-only; in-game the
  menu button belongs to the link menu, which this device has no support for. A
  patch to open the quick menu in-game was written and dropped in favour of
  matching upstream.
- **No battery indicator.** `/sys/class/power_supply` does not exist here, so
  `slot-power` has nothing to read.
- **Audio is untested.** ALSA is present and the sink loads; it reached
  "device busy" once, with something else holding the PCM.
- **The sprite path is unoptimised.** It costs 12 ms a frame on menu screens
  with ~186 draws, because gameplay never exercises it (0.0 ms there).

## Layout

```
card/                    what ships on the SD card
  App/                   launcher entries, stock and Onion layout
  Apps/                  launcher entries, Allium layout (*.pak)
  System/probe.sh        the hardware probe, one copy for every layout
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

## Working over the network instead of moving the card

Allium already ships the pieces: `.allium/scripts/wifi-on.sh`, `telnet-on.sh`
(a root shell on port 23) and `ftp-on.sh` (writable FTP of the card root on
port 21). With those up, nothing needs the SD card moved:

```sh
export SLOT_DEVICE=192.168.1.x
task deploy          # build and push the frontend over FTP
task deploy:cores    # push the libretro cores too, which rarely change
task log             # pull slot.log back and print the last stage/frame lines
```

On the handheld, once per boot, run **Apps → slot net**. It writes what happened
to `slot-net.txt` at the card root, including the address `SLOT_DEVICE` wants,
and diagnostics when the link does not come up.

If WiFi has never been set up, put the network name and the password on the
first two non-comment lines of **`slot-wifi.txt`** at the card root; the app
writes `/appconfigs/wpa_supplicant.conf` from it.

This exists because **Allium's on-screen keyboard has no shift key**, so a
network name containing capitals cannot be typed on the handheld at all — and
SSIDs are case-sensitive, so the supplicant sits there looking for a network
that does not exist. Setting it from the card sidesteps the keyboard entirely.
Delete the file once WiFi works, so the password is not left on the card.

It deliberately does **not** call Allium's `telnet-on.sh` and `ftp-on.sh`: both
start with `wait-for-wifi.sh`, which pings `1.1.1.1` once a second for up to
sixty seconds, so calling the pair of them after waiting once meant up to three
minutes of a handheld that looks frozen. It also only needs a LAN address, not
the internet, so it waits for `wlan0` to have an address — bounded at twenty
seconds — and starts `telnetd` and `ftpd` directly.

The `device:check` step fails with a clear message rather than a curl error
when the handheld is not listening.

`task sh:device CMD='...'` runs a command on the handheld over telnet, which is
the quickest way to try something without a rebuild — reading `/proc`, or
relaunching with a different setting:

```sh
SLOT_DEVICE=192.168.1.x task sh:device CMD='free -m'
```

## Seeing what it draws

```sh
task shot        # renders a frame under qemu into target-miyoo/frame.png
```

![slot's shelf, rendered by the software rasteriser](docs/shelf.png)

That is slot's shelf drawn entirely on the CPU at 752x560 — no GPU, no EGL —
with the 720x480 canvas centred and the panel's border around it. Carts, labels,
text and alpha all land where the GL path puts them.

To get a populated shelf without ROMs, `task shot` writes a content root and
slot needs `Config/slot.state` to hold **every** key its parser requires
(`cart`, `brightness`, `blue_light`, `volume`, `muted`, `clock_set`,
`utc_offset_min` at least) — a partial file is discarded whole and you land back
on the clock screen.

## Running it without the handheld

The device build runs on an ordinary x86 machine under qemu, which is the
rasteriser's dev loop:

```sh
task binfmt      # once per boot; needs Docker, not root
task run:qemu
```

```
glibc here: ldd (Debian GLIBC 2.31-13+deb11u14) 2.31
slot: boot: start at 0.2 ms
slot: fb0 hint 3840x2160
slot: gl context: libEGL.so: cannot open shared object file: No such file or directory
```

That is the whole port in four lines. The armv7 binary **runs** — it boots,
reads the framebuffer geometry, and stops at exactly one thing: EGL. Which is
the predicted failure, now reproducible on demand without touching hardware.
`task verify:root` leans on the same trick to prove the content root `task dist`
builds is byte-for-byte what `slot --init-root` makes.

Two caveats. qemu says nothing about **speed** — it cannot tell you whether a
Cortex-A7 holds 60fps, and that question is settled only on the device. And the
`fb0` it reports is the host's, not a 750x560 panel.

`task binfmt` registers a host-wide qemu handler from a privileged container
(Docker is enough, no root). It lasts until reboot; undo it with
`docker run --privileged --rm tonistiigi/binfmt --uninstall arm`.

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

### Controls on the Mini Flip

The button map is in `patches/0003`; the gestures are upstream's, from
`crates/slot-input/src/gesture.rs`. The ones worth knowing:

| gesture | action |
|---|---|
| **hold MENU ~1 s** | **eject the cart, back to the shelf** |
| tap MENU | quick menu (brightness, volume) — on the shelf only |
| double-tap MENU | polaroids |
| SELECT held, then MENU | game menu |
| hold POWER ~1 s | power menu |
| **START on the shelf, GBA cart selected** | **core picker: left = mGBA, right = gpSP** |

**The quick menu is shelf-only, as upstream intends.** In-game the menu button
belongs to the link menu behind the select chord, and this device has no link
support, so that chord answers "no link support" — there is no in-game settings
menu here. That is upstream's design, kept deliberately; a patch to open the
quick menu from a running game was written and then dropped in favour of
matching upstream.

**For GBA, pick gpSP.** mGBA has no GBA dynarec and interprets, while gpSP has
an ARM JIT — the whole reason this port builds it. The choice is per game and
is kept in `Config/selected_core.txt`.

**slot has no quit.** Its power menu offers only Restart and Power Off, because
on the Anbernic handhelds it replaces the launcher and there is nothing to
return to. On an Allium card there is, so `task stop` kills it over telnet and
hands the screen back — much better than rebooting, which also drops the WiFi.

slot boots straight into whatever cart was last seated — that is intended, not
a fault: the cart is remembered in `Config/slot.state` and re-seated at startup,
so the handheld behaves as though you left it in the slot. Ejecting clears it
and the next boot lands on the shelf.

On this device MENU is `KEY_ESC`, A is `KEY_SPACE`, B is `KEY_LEFTCTRL` — see
`notes/hardware.md` for the full table.

## Caveats worth reading before you copy

- **Keep a backup of the card.** Nothing here deletes, but the stock firmware
  is particular and a known-good copy costs nothing.
- **Card format:** whatever the device already boots from — don't reformat.
  FAT32 and exFAT are both routinely mounted `noexec`, which is why both launch
  scripts hand the binary to `ld.so` rather than executing it.
- **`/mnt/SDCARD` is the card root**, confirmed against a live Allium install.
  The scripts still derive it from their own location rather than hardcoding it,
  so a differently-mounted card works too.
- **Three launcher layouts ship, and the unused ones are ignored.** Stock and
  Onion read `App/<Name>/config.json`; Allium reads `Apps/<Name>.pak/`. Both are
  in the tree with the same `config.json` schema, and the probe itself lives once
  at `System/probe.sh` with a thin entry per layout. No `icon` key is set — it is
  optional, and the path conventions differ per launcher, so an icon that works
  on one shows up broken on another.
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
