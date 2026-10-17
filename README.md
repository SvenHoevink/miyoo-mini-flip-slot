# slot-miyoo

An attempt to port [**slot**](https://slot-cfw.fyi/) — Brandon Kowalski's
Game Boy-centric frontend for the Anbernic RG SP — to the **Miyoo Mini Flip**.

Upstream lives in `upstream/slot` as a submodule, pinned to the commit this
port was last rebased onto.

```
git clone --recurse-submodules https://github.com/deanmarano/slot-miyoo
# or, in an existing clone:
git submodule update --init
```

**Just want it on a card?** → **[docs/INSTALL.md](docs/INSTALL.md)**. This
README describes how the port works and why it is built the way it is; the
install page is the short version. See also
[docs/link.md](docs/link.md) for two-player and
[notes/variants.md](notes/variants.md) for the other Miyoo models.

## Status

**It runs games on the handheld.** GB, GBC and GBA, at roughly the frame budget,
with working input and a software renderer standing in for the GPU this device
does not have.

**The submodule was bumped on 2026-10-15, by 94 upstream commits**, and the
port rebased onto it: an in-game menu, favourites, a recents shelf, handmade
cart and shelf art, per-console screen settings and per-platform bezels, on a
new canvas and layout model. Eighteen patches now, all replayed and all seen
on the handheld.

**The bump also broke the memory budget**, and fixing that took most of a day
and is the bulk of what is new here. slot was holding 44 MB before a core was
even loaded, against about 80 MB the device can give, and a GBA cart was being
OOM-killed mid-game. The causes were five, and the measurements are in
[notes/hardware.md](notes/hardware.md):

| | freed |
|---|---|
| a ROM read into slot that gpSP never looks at (`need_fullpath`) | 8-32 MB |
| textures that could only be recycled, never freed | ~8 MB |
| carousel grounds kept decoded for the life of the process | 3.4 MB |
| rewind sized for a 1 GB device: 20 MB ring, 12 MB/s of CPU | 13.5 MB |
| cart faces kept while a game plays | 3.4 MB |

Mother 3's 32 MB cart went from *cannot load* to playing on both cores.

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

**Single-player is done.** Sixteen carts have been played on the handheld
across all three platforms, and five of them on both GBA cores. Taken from the
`States/` and `Saves/` trees the device itself wrote, not from memory:

| | |
|---|---|
| GB, mGBA | Tetris, Tetris GB SRS Colorized, BurgerTime Deluxe, Trip World |
| GBC, mGBA | Alleyway DX, Super Mario Land DX, Super Mario Land 2 DX, Donkey Kong Land III DX, Kirby's Pinball Land DX, Galaga & Galaxian DX, Rayman |
| GBA, gpSP *and* mGBA | Kirby & the Amazing Mirror, Golden Sun: The Lost Age, Mother 3 |
| GBA, gpSP | Kurukuru Kururin, Mario Kart: Super Circuit |

The last three are the ones that made the memory work necessary: Golden Sun
and Kirby are 16 MB carts that fill a JIT cache, and Mother 3 is 32 MB, which
is more than this device can hold twice.

Where it stands:

| | |
|---|---|
| boots, renders, runs games | yes |
| GB / GBC / GBA | yes, GBA on gpSP |
| frame budget | backend 8.2 ms of a 16.86 ms period, core 6.3 ms |
| shelf | scrolls at 15-18 ms a frame, from 30-36 |
| buttons, including the d-pad | yes |
| lid open/close | dozes, saves, darkens the panel |
| audio | yes, ~100 ms behind the picture |
| battery indicator | yes, from `axp_test` |
| saves and save states | yes, including MBC2's 512x4 bits |
| bezels | a Game Boy body under GB, a Color one under GBC, the Advance SP shell under GBA — filling the panel, picked per console in the quick menu |
| big carts | 32 MB ROMs play on both cores |

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
    Part   { x, y, w, h, tex: TexId, alpha: f32, uv: [f32; 4] },
    Turned { x, y, w, h, tex: TexId, alpha: f32, turn: f32 },
    Game,
    Shot   { tex: TexId },
}
```

All GL is quarantined in `slot-gfx` (~1,950 lines, of which the actual drawing
is `draw.rs`, `pipeline.rs`, `fbo.rs`, `quad.rs`, `shaders.rs`). The seam is
the `Surface` trait plus that six-variant display list. A CPU rasteriser that
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

## What the port changes

Everything the port adds to upstream is a patch under `patches/`, applied to
the submodule's working tree by `task patch`. Nothing above `slot-gfx` is
touched: the UI emits the same display list it always did.

| | |
|---|---|
| `0001` | the crash handler's register read, on armv7 |
| `0002` | the software rendering backend |
| `0003` | input: Miyoo button codes, the event struct, thread priority, the lid |
| `0004` | evdev bitmaps as 32-bit words; the battery's vendor tool |
| `0005` | audio: an MI_AO sink, and a rate fallback for ALSA |
| `0006` | timing around the eject |
| `0007` | the about-box sticker |
| `0008` | the backlight as a PWM channel |
| `0009` | picture geometry for this panel |
| `0010` | naming the battery's source in the probe line |

### Toolchain and cores

`toolchain/Dockerfile` cross-builds all three artifacts; `task all` drives it.
gpSP is the GBA core, for its ARM dynarec — 6.3 ms a frame against mGBA's
14-18.

Four of upstream's assumptions are 64-bit ones, invisible on the aarch64
hardware slot was written for: the crash handler's register read (`0001`),
evdev capability bitmaps read as 64-bit words (`0004`), `struct input_event`
taken as 24 bytes rather than 16 (`0003`), and input threads that run at a
priority this scheduler starves (`0003`).

### Graphics

`0002` swaps slot's GLES2 backend for a CPU rasteriser writing into mmapped
`/dev/fb0`, behind a cargo feature beside upstream's `host` and `device`. The
panel is mounted upside down, so the card's launch script sets
`SLOT_FB_ROTATE=180`; `0009` sizes the picture for it, at 3x actual with a
height-filling stretch.

The sprite path draws the shelf and the menus — gameplay never reaches it
(`sprites 0.0 over 0 draws`). Each source row is expanded once to destination
width with the column mask folded in, then reused for the three-odd output rows
that map to it, and the remaining linear loop is hand-written NEON via inline
`asm!`, since the intrinsics are unstable on stable armv7. It costs 9.7 ms at
186 draws. LLVM will not autovectorise it at any loop shape: the horizontal
scale makes the source read a gather, and NEON has no gather instruction.

### Input

`gpio_keys` reports keyboard codes rather than `BTN_*`, so `0003` carries the
map; all 18 per-button codes are cross-checked against Allium's own.

MENU is contested. `alliumd` keeps running underneath whatever it launches and
owns MENU globally, drawing a hotkeys overlay over the running game, so both it
and slot answer every press. **Do not kill `alliumd`** — the card's boot hook
falls through to a reboot loop without it. Boot slot *instead of* Allium from
that same hook: see
[Booting straight into slot](#booting-straight-into-slot-without-allium).

### Power

The backlight is a PWM channel at
`soc/1f003400.pwm/pwm/pwmchip0/pwm0/duty_cycle`, the same file Allium writes;
there is no `/sys/class/backlight` and no dispdbg here, so `0008` consults it
only when neither exists. Its step ladder is measured rather than scaled,
because the panel's response is steeply non-linear: against an 800 ns period,
duty 1 is not visible at all, the firmware boots at 6, and 112 is as bright as
anyone wanted.

The lid is polled, not listened to — the hall sensor emits no evdev events at
all. `0003` reads
`/sys/devices/soc0/soc/soc:hall-mh248/hallvalue` (1 open, 0 closed), already
the convention upstream expects. Closing dozes rather than suspends: `doze`
flushes the state writer and the resume snapshot, so **shutting the lid is a
save point**, the core parks at `Speed::Paused`, the backlight goes to step 0,
and `DOZE_TIMEOUT` powers the handheld off after 180 s. The SoC stays awake for
those three minutes, which is why FTP still answers with the lid shut.

The battery is a vendor tool, not sysfs: there is no `/sys/class/power_supply`
on this device at all. `/customer/app/axp_test` prints
`{"battery":93, "voltage":4026, "charging":0}`, which is what Allium reads too.
`0004` falls back to it; `0010` makes the probe line name whichever source will
be read.

### Audio

`0005` adds an MI_AO sink beside the ALSA one, and gives ALSA a rate fallback
because this alsa-lib has no plug plugin and will not resample.

MI_AO ignores `MI_AUDIO_Attr_t.u32FrmNum` and holds 341 ms of queue whatever it
is asked for, so **any latency figure computed from the attributes is
fiction** — querying the queue and holding it down is the only control that
works. `MI_AO_QueryChnStat` answers in bytes, so the throttle converts to
frames before acting on them. On the handheld that measures 48,036 frames/s, 0
core stalls, 0 dropped, 0 starved, and about 100 ms of total latency. The
throttle is on by default at five periods; `SLOTAO_QUEUE=0` restores the
unthrottled path. Full numbers in
[notes/audio-handoff.md](notes/audio-handoff.md).

### The sticker

The undo sticker is slot's about box, and upstream's names model AGS-102 and
BaseOS. `0007` names the Mini Flip, Miyoo's firmware and Allium instead,
credits slot to Brandon Kowalski for the Anbernic RG SP, says that this is an
unofficial port, and carries a wordmark regenerated by `tools/wordmark.py` from
the Open Sans the sticker already ships. The only patch here that changes what
the frontend says rather than what it does.

## Still open

- **Two-player is written but unplayed.** `card/System/slotlink.sh` is the
  Miyoo's radio script — upstream's wants a second interface, `nl80211` and
  5 GHz, and this chip has none of the three. It passes its contract tests
  under busybox but no game has been linked yet, and whether this radio will
  do AP mode at all is open: **Apps → slot link probe** answers it on the
  device. slot's link is mGBA-only, so GB/GBC is the realistic target and GBA
  would interpret at ~22 ms a frame. See [docs/link.md](docs/link.md).

- **GB palettes are off by default.** `gb_palettes=0` in `Config/slot.state`.
  Turn them on in the quick menu under Screen, then L2 and R2 cycle 48 of them,
  `GBC Red` included. mGBA does the recolouring -- slot passes the palette as a
  core option, so the software renderer is not involved -- and it applies to
  monochrome Game Boy carts, not to GBC titles that carry their own colour.

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

### slot itself

For anyone installing rather than developing, **[docs/INSTALL.md](docs/INSTALL.md)**
is the page to follow, and `task release` builds the single zip it describes.
From a working tree:

```sh
task dist                       # cores + frontend + content root -> ./dist
cp -R dist/. /media/<you>/<card>/
sync
```

Adds **Apps → "slot"**, and it runs. ROMs go unzipped in `Games/GB`,
`Games/GBC` and `Games/GBA` — slot's own library, not the `Roms/` the launcher
uses — and GBA needs `BIOS/gba_bios.bin`.

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

## Booting straight into slot, without Allium

slot wants the handheld to itself — on the Anbernic machines it *is* the
launcher — and under Allium the daemon keeps running underneath and claims the
MENU button, drawing a hotkeys overlay over the game.

The card's boot hook is `.tmp_update/updater`, which the stock firmware runs: it
sets up the backlight PWM and the LCD, detects the model, starts the audio
server, and ends by running `alliumd`. `card/.tmp_update/updater` is that file
with one block added before the `alliumd` line:

```sh
if [ -f "$ROOT"/.slot-boot ]; then
    SLOT_ROOT="$ROOT" "$ROOT"/System/launch_frontend.sh
fi
```

Booting slot means no Allium, and Allium was what brought up WiFi, telnet and
FTP — without which the only way to put a new build on the handheld is to carry
the card to a computer. So the hook starts the network itself, in the background
so it never delays the frontend, when a `.slot-net` file is present.
`System/net-up.sh` does that work and is shared with the **slot net** app.

```sh
task boot:install        # put the hook on the card (once; it is boot-critical,
                         # so `dist` and `deploy` never touch it)
task boot:slot           # .slot-boot + .slot-net: slot boots, network comes up
task boot:allium         # back to Allium
```

**To turn it on by hand:** create an empty `.slot-boot` at the card root, and
`.slot-net` alongside it for the network.
**To turn it off:** delete `.slot-boot`. It needs no shell and no telnet — any
computer with the card in it will do, which is the point of gating it on a file.

If slot exits or fails to start, execution falls through to Allium below, so a
bad build cannot leave a handheld that will not boot. The original is kept on
the card as `.tmp_update/updater.allium-orig`.

**Never kill `alliumd` instead.** The boot hook ends with a `while true; do
reboot; done` for when the launcher exits, so killing it makes the handheld
reboot — which is exactly what happened when it was tried, and it looked like a
power fault rather than a script doing as it was told.

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
/customer/app/axp_test                          # battery; there is no sysfs one
ls /usr/lib/ | grep -iE 'egl|gles|mali|mi_'     # expect no EGL, maybe MI_GFX
free -m
```

Land the results in `notes/hardware.md` — the plan's resolution and input work
depends on them.

## Credit and licence

slot is by [Brandon Kowalski](https://github.com/BrandonKowalski/slot) and is
GPL-3.0-or-later; this port inherits that. It is an unofficial, unaffiliated
effort — please don't send slot's issue tracker bug reports about a Miyoo. The
sticker in-app says the same thing, for anyone who reads the device before the
README.
