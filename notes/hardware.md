# Miyoo Mini Flip — measured facts

From `card/System/probe.sh` run on the device on **2026-10-12**, firmware as
shipped on Dean's Allium card. Raw report and `slot.log` are in `device-dump/`
(gitignored). Everything here is measured, not inferred; spec-sheet claims that
turned out wrong are called out.

## Verdict

**The armv7 build runs on the device.** `slot --init-root` completed with exit 0
and created the content root; a normal start gets through boot, reads the panel,
and stops at exactly one thing:

```
slot: boot: start at 0.0 ms
slot: fb0 hint 752x560
slot: gl context: libEGL.so: cannot open shared object file: No such file or directory
```

So the toolchain, libc, loader and binary are all correct. The only blocker is
the renderer, as expected.

## Core facts

| | measured | note |
|---|---|---|
| kernel | Linux 4.9.84 SMP PREEMPT, `armv7l` | built 2025-09-02 |
| CPU | 2x ARMv7 rev 5, CPU part **0xc07** | Cortex-A7, as expected |
| CPU features | `neon vfpv4 idiva idivt vfpd32 lpae thumbee` | matches our `-march=armv7ve -mfpu=neon-vfpv4` |
| **RAM total** | **103352 kB (~101 MB)** | **not 128 MB** — the rest is reserved for the SoC |
| RAM available | 81632 kB at idle, no swap | the real ceiling to design against |
| **glibc** | **2.28** (A-profile 8.2-2018-08, gcc 8.2.1) | our build needs <= 2.28 — exact match |
| loader | `/lib/ld-linux-armhf.so.3` | what both launch scripts use |
| card root | `/mnt/SDCARD`, `/dev/mmcblk0p1` | confirmed |
| card mount | `vfat rw,dirsync,relatime,fmask=0000` | **not** `noexec`; files are +x |
| rootfs | squashfs, read-only; `/tmp`, `/var` tmpfs | only the card is writable |

## Panel — `/sys/class/graphics/fb0`, "MStar FB0"

| attr | value |
|---|---|
| `virtual_size` | `752,1680` |
| `modes` | `U:752x560p-76`, `U:752x560p-210` |
| `bits_per_pixel` | `32` |
| `stride` | `3008` (= 752 x 4) |
| `rotate` | `0` |

Three things follow, and they are better than assumed:

1. **The panel is 752x560, not the 750x560 the spec sheets claim.** 752 is also
   conveniently a multiple of 16.
2. `virtual_size` height 1680 is **3 x 560**: the framebuffer is already
   **triple-buffered**, so the software `Surface` can page-flip with
   `FBIOPAN_DISPLAY` instead of tearing or blitting through a shadow buffer.
3. **32 bpp and no rotation needed** — no `SLOT_ROTATE` equivalent required, and
   no 16-bit packing in the rasteriser.

Against slot's `OUT_W`/`OUT_H` of 720x480 and `SCALE = 3` over a 240x160 source:
752x560 fits a **3x** GBA image (720x480) with a 16px side and 40px top/bottom
border, which is close to upstream's own geometry. That is the layout to aim at.

## No 3D, but a 2D blitter and an audio API

```
no EGL/GLES/Mali libraries anywhere on the usual paths
```

Confirmed absent. What *is* there, in **`/config/lib`** (a read-only squashfs):

```
libmi_gfx.so    libmi_disp.so   libmi_panel.so  libmi_sys.so
libmi_ao.so     libmi_ai.so     libmi_common.so libcam_os_wrapper.so
libmi_divp.so   libmi_ipu.so    libmi_sed.so    libmi_vdec.so
libmi_venc.so   libmi_wlan.so
```

- `libmi_gfx.so` — the SigmaStar 2D blitter. Candidate for hardware-accelerating
  the blit and scale once a CPU rasteriser works.
- `libmi_ao.so` — audio out, used by Allium via FFI.
- **MI_AO cannot resample from the Game Boy's rate.** Its sample-rate enum is
  literal Hz — 8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000,
  96000 — with no 32768. `MI_AO_EnableReSmp` takes the same enum, so handing the
  hardware resampler the core's rate is not possible; 32000 would be 2.4% out,
  which is an audible pitch and speed error. The software resample in `emu.rs`
  stays.
- **Audio works through MI_AO.** Game sound and slot's own cartridge effects,
  no clicking. The cost is real: with audio dead the pacer reported work well
  under the period, and with it running it is **15.5 ms against 16.76 ms** —
  zero frames missed, but about 1 ms of headroom, which is why it feels shaky.
- **MI_AO is the path that works, and the audio server owns it.** The vendor
  stack goes through MI_AO, and with the server running slot's
  `MI_AO_SetPubAttr` returns `0xa0052009` — decoded with the SDK's own macro
  (`MI_ERR_ID | module<<16 | level<<12 | errid`) that is errid 9,
  `E_MI_ERR_NOT_PERM`, "try to change static attribute". Only one of them can
  configure the device, so the boot hook skips the server when `.slot-boot` is
  set.
- **The click every three seconds was not the server's absence.** It was slot's
  ALSA sink: `RELEASE_AFTER` drops the device after three seconds of silence and
  the amplifier pops each time it reopens. The MI_AO sink never releases.
- **The driver leaks `ERESTARTSYS`.** `snd_pcm_writei` and `snd_pcm_recover`
  both return `-512` when a signal interrupts them, which `snd_strerror` renders
  as "Unknown error 512". It is kernel-internal and should never reach
  userspace. Treating it as fatal killed the sink on its first write and the
  ring then overflowed — 417,000 samples dropped in a session, heard as a pop
  every second or two. Both calls retry it now.
- **ALSA runs at 48 kHz and has `plug`, but it cannot resample to 32768.** `plug:default` and
  `plughw:0,0` do not open at all, so there is no resampling plugin to fall back
  on, and `hw:0,0` rejects the core's 32768 Hz outright: "Rate doesn't match
  (requested 32768Hz, get 48000Hz)". `patches/0005` opens at a rate the hardware
  takes and tells the ring, which is all that was needed, since `emu.rs` already
  resamples the core's output to whatever rate the ring reports.
- **The audio server has to be off.** The boot hook starts one to suppress a pop
  on open, and it holds the PCM, which is why slot's sink reported "Device or
  resource busy". Skipped when `.slot-boot` is set.
- **ALSA does exist**, contrary to what I first concluded. The qemu container had
  no `libasound.so`, and I wrongly generalised that to the device. On hardware
  slot's ALSA sink loads and gets as far as `hw:0,0: Device or resource busy`,
  so the library and the PCM are both there and something else was holding the
  device. An `MI_AO` sink may still be wanted, but it is not forced.

## The lid: poll `hallvalue`, there are no events

**Resolved.** The clamshell sensor is a platform device and exposes its state at

```
/sys/devices/soc0/soc/soc:hall-mh248/hallvalue     1 open, 0 closed
```

which is the same convention slot's `read_lid` already expects — it was only
looking under `/sys/class/power_supply`, which this device does not have at all.
`patches/0003` points it at the right file and keeps upstream's search as the
fallback.

Sampling it once a second across a lid cycle, written to the card so the record
survives the device suspending, gave: `1` throughout, then a single `0`, then
nothing — **the system suspends about a second after the lid shuts**. So there
is one poll's worth of warning and no more, and nothing at all to count edges
from, which settles the question below.

### Why not events

The sensor emits no evdev events for a lid cycle. Five or six cycles produced
nothing on `event1`; the single `KEY_POWER` pulse in the trace came at 8 s
uptime, i.e. boot. The pops heard on each transition are the amplifier powering,
not something slot can see.

### The old note, kept because it was wrong in an instructive way



The one pulse that *was* captured looked like the whole story, and it is not —
it is the boot-time one. It emits a momentary `KEY_POWER` press and release in
the same millisecond:

```
35994ms event1 type=0x01 code=0x74(116) value=1 -> Power
35994ms event1 type=0x01 code=0x74(116) value=0 -> Power
```

Concluding from it that the lid had to be driven by edges would have been
wrong, and would have rebuilt the same guesswork that made closing the lid shut
the handheld down in the first place. More cycles showed there were no further
events at all, and the state file turned up by searching sysfs for the chip name
from the probe.

## Panel orientation

**The LCD is fitted upside down.** A frame written top-down to `/dev/fb0`
appears inverted on the panel — confirmed on the device, and the reason
`card/System/launch_frontend.sh` exports `SLOT_FB_ROTATE=180`. `fb0/rotate`
reads `0`, so nothing in sysfs advertises this.

## Buttons — keyboard codes, not gamepad codes

This is why the first on-device run ignored every press: slot's `code_to_btn`
maps `BTN_*` gamepad codes (`0x130`+) as the Anbernic handhelds report, but
`soc:gpio_keys` here reports **keyboard** codes, so every lookup missed and
`pick_devices` rejected the node outright.

Decoded from the `B: KEY=` bitmap the probe captured, and cross-checked against
Allium's own Miyoo map — the two agree exactly on all 18:

| code | key | slot button |
|---|---|---|
| 103 / 108 / 105 / 106 | UP / DOWN / LEFT / RIGHT | d-pad |
| 57 | KEY_SPACE | A |
| 29 | KEY_LEFTCTRL | B |
| 42 | KEY_LEFTSHIFT | X |
| 56 | KEY_LEFTALT | Y |
| 18 / 20 | KEY_E / KEY_T | L1 / R1 |
| 15 / 14 | KEY_TAB / KEY_BACKSPACE | L2 / R2 |
| 28 | KEY_ENTER | Start |
| 97 | KEY_RIGHTCTRL | Select |
| 1 | KEY_ESC | Menu |
| 115 / 114 / 116 | VOLUMEUP / VOLUMEDOWN / POWER | as named |

The d-pad arrives as keys, not as `ABS_HAT0X/Y`, so upstream's `Hat` decoding
never fires here either.

### And `struct input_event` is 16 bytes here, not 24

This was the actual reason buttons did nothing, and slot's own input trace
found it. The struct opens with a `timeval`, two C longs wide, so it is 24
bytes on a 64-bit kernel and **16 on this 32-bit one**. Reading 24-byte records
out of a 16-byte stream slides every field by eight bytes, so the timestamp is
read as type/code/value. The trace is unmistakable once you know:

```
2113ms event0 type=0xba29 code=0x3a36(14902) value=565800 -> ignored
2553ms event0 type=0xba2a code=0x3a36(14902) value=5791   -> ignored
3603ms event0 type=0xba2b code=0x3a36(14902) value=55766  -> ignored
```

`type` should be 0..0x1f. That slowly incrementing `0xba29, 0xba2a, 0xba2b` is
the seconds field of the timestamp, and `value` is microseconds. Every event
decoded as noise and was dropped, which is why *nothing* responded rather than
the wrong things responding.

Fixed in `patches/0003`: the width is derived from `size_of::<c_long>()`.

### And the capability bitmaps are 32-bit here

`slot_power::has_bit` read these masks as 64-bit words. The kernel prints them
as `unsigned long`, which is **32 bits** on this device, so every bit above 31
was looked up in the wrong word — losing most of the keyboard range, including
`KEY_SPACE` (the A button). `pick_devices` only kept working by accident:
`KEY_ESC` is bit 1, low enough to land in the right word either way.

Fixed in `patches/0004`, with tests that pin the device's real bitmap and the
32-bit word maths explicitly, since `usize::BITS` on a 64-bit build host would
otherwise hide the whole case.

## Input

Two evdev nodes, which slot discovers by walking `/sys/class/input` already:

| node | name | notes |
|---|---|---|
| `event0` | `soc:gpio_keys` | all buttons, `EV=100003` |
| `event1` | `hall wake key` | **the clamshell hall sensor** |

Both are opened successfully — the trace confirms `event0 opened` and
`event1 opened` — so nothing is holding the devices grabbed and the node
selection works.

The lid sensor is a gift: slot already handles `SW_LID` in
`crates/slot/src/input/evdev.rs`, so closing the Flip can suspend as upstream
intends. Per-button codes still need an `evtest`-style capture — the probe lists
the devices but not the individual keycodes.

## What the device says about itself at boot

```
slot: panel 752x560, canvas 752x560, turned false, ccw false
slot: backlight no backlight (0 to 255), battery no battery, rtc0, no motor
slot: boot: first frame at 511.6 ms
```

So: no backlight control found, no battery (below), no rumble motor, but `rtc0`
is present. First frame in ~0.5 s on real hardware.

## Frame budget, measured on the device

`SLOT_TRACE_LATENCY=1` in the card's launch script writes a per-frame breakdown
to `slot.log`. From the first run with a game going:

```
read>pad 18.3  pad>emu 0.3  emu>pub 10.1  pub>take 1.5  take>swapped 55.0  (swap 16.2)  total 85.4 ms
read>pad 23.6  pad>emu 0.3  emu>pub 14.1  pub>take 1.6  take>swapped 50.9  (swap  7.0)  total 90.5 ms
read>pad 39.0  pad>emu 6.8  emu>pub  9.6  pub>take 1.5  take>swapped 49.1  (swap  6.8)  total 106.0 ms
```

`take>swapped` is this backend — the rasteriser plus the output blit — and at
**~50 ms against a 16.7 ms budget** it was the whole problem. The emulator core
(`emu>pub`) runs in 10-20 ms and the panel swap in 3-16 ms, so neither is
anywhere near the limit. Optimise the renderer, not the cores.

Progress, p50 of `take>swapped`:

| | ms |
|---|---|
| first measured run | 52.9 |
| + rotated output memcpy | 36.2 |
| + 3x lookup for the game pass | 43.3 — **worse, and the path never ran** |
| + per-stage profiling | the game pass is 32 of the 47 ms |
| + flat column table, no per-pixel checks | 34.5 (game 32.6 -> 21.0) |
| + source row expanded once per source row | 26.5 (game 17.1, upload 0.4) |
| + NEON kernel for the row scale | 25.6 (**game 17.1 -> 7.8**) |
| + cached column table and scratch | — |
| + memset clear, all games on gpSP | 25.7 (stages sum to **12.8**) |
| + deferred clear | clear 0.9 -> **0.0**, stages 11.6 |
| + game straight to the framebuffer | **8.2** (clear 0.0, upload 0.2, out 8.0 incl. game) |

Worst single frame in each 60-frame window: p50 **15.4 ms**, p90 18.7, against a
16.86 ms period — where it had been 19-21 ms. `take>swapped` p50 11.1,
`emu>pub` 6.3.

### What is still unexplained

The pacer reports `work 36-45 ms` while `take>swapped` is 11 and the core is 6.
`work` is measured from the top of the loop to the swap, so it also spans
`advance` and `step_emulator`, and the latter can block waiting on the emulator
thread. That would make most of it *waiting* rather than work, which is what the
healthy frames suggest — `total 17.8 ms` on a good one — but it has not been
proven, and it is the obvious thing to measure next if the stutter persists.

With everything on gpSP: `emu>pub` 6.4, and the backend's own stages are
clear 0.9, upload 0.3, game 8.6, sprites 0.0, out 3.0 — **12.8 ms**, inside the
16.77 ms period. The memset took the clear from 1.4 to 0.9.

### The gap is not the renderer

`take>swapped` is 25.7 against stages summing to 12.8, and the pacer reports
`work 28 ms`. That ~13 ms is now larger than anything left in the rasteriser,
and it is *not* in the rasteriser: `latency::taken()` fires immediately after
`upload_game`, and the whole of `Frontend::compose` runs after it —
`cart_faces.sync`, `sync_clock`, `sync_about`, `sync_quick_clock`,
`sync_core_picker`, texture uploads, then building the display list. All of it
lands inside `take>swapped` and none of it inside the backend's profile.

`patches/0005` times that block temporarily, printing `slot: compose: sync N
build N ms/frame`. It is diagnostic only and should be dropped once the budget
is settled.

**It was not the sync work.** Measured, that block is **0.1 ms a frame** — the
guess was wrong. The gap is the swap:

```
swap  p50=11.4  p90=15.3  max=15.9 ms
```

`take>swapped` 25.2 = about 12.5 ms of render plus 11.4 ms of *waiting*.
`FBIOPAN_DISPLAY` was being issued with `FB_ACTIVATE_VBL`, which blocks until
the panel latches — capped at one 16.7 ms period, which is exactly the shape of
that distribution. slot paces itself, so blocking here too put two pacers in
series and spent most of the budget on nothing.

It now pans with `FB_ACTIVATE_NOW` and returns; the hardware still latches whole
pages at its own blank and there are three of them, so tearing is not expected.
`SLOT_FB_VSYNC=1` restores the blocking behaviour if that turns out to be
wrong.

With gpSP the stages add up to about 12.4 ms (clear 1.4, upload 0.3, game 7.8,
sprites 0.0, out 2.9) and slot's own pacer agrees: `work 12.7 ms, period
16.76 ms`, the first time work has fit inside the period. It reads as mostly
smooth with occasional stutters, which is a variance problem rather than a
throughput one — hence caching the column table (2160 `sin()` calls a frame)
and the two scratch buffers that were being heap-allocated every frame.

`take>swapped` still reads ~25 ms against stages that sum to 12.4, and that is
not reconciled. The pacer's `work` number suggests the difference is waiting
rather than work, but it has not been proven either way.

The frame upload was the ~10 ms that the stage timings could not account for:
it converted 38,400 pixels one three-byte copy at a time, before any of the
timed work. It is one memcpy now, 0.4 ms.

### gpSP is worth more than any of this

| GBA core | `emu>pub` |
|---|---|
| mGBA (interpreter) | 14.2 ms |
| **gpSP (ARM JIT)** | **5.5 ms** |

Pick it with START on the shelf over a GBA cart. This is the single largest win
in the whole exercise and it is a menu option.

Per-stage, from the device:

```
slot: soft: clear 1.2 game 32.6 sprites 0.0 out 2.7 ms/frame, game path separable
```

So the clear, the sprites and the output are all cheap, and the game pass is
the whole remaining cost. `game path separable` also says the 3x lookup does
not run: GB and GBC are 160x144 inside the 240x160 buffer, so the source and
picture rects are partial and the scale is 4.5x across, not 3x. The lookup only
ever fits GBA.

### The sprite path

Measured at a fixed draw count, which is the only way these numbers mean
anything:

| | sprites at 186 draws |
|---|---|
| before | 12.0 ms |
| after the divide and bounds checks came out | **9.7 ms** |

About 19%, or 0.052 ms a draw. It does not touch gameplay — `sprites 0.0 over
0 draws` there — and was never going to: the shelf and menus are what it is
for. A 20.6 ms reading taken in between was a busier screen, not a regression,
which is why the draw count is logged alongside now.

### NEON will not come for free here

The horizontal scale makes the source read a **gather** — each output column
takes an arbitrary source texel — and NEON has no gather instruction. Cleaning
the loop up (no bounds checks, no per-pixel branch) did not make LLVM
autovectorise it, and would not have: the obstacle is the access pattern, not
the loop shape. Vectorising this needs the row expanded to destination width
first, or a `vtbl` shuffle exploiting the fixed scale ratio, and either way it
needs inline asm or a C shim, since the intrinsics are unstable here.

**Done, as inline asm.** Two things to know if you touch it: the assembler
needs `.fpu neon` inside the block, because the target feature cannot be named
on stable for armv7; and a 16-bit scalar operand to `vmull` must live in
`d0`-`d7`, so the row factor goes in `d4` rather than anywhere convenient.
`task test` runs the workspace as armv7 under qemu, which is how the kernel is
checked against its scalar reference — the only way to exercise it short of the
handheld.

The expansion is now done anyway, for its own sake: each *source* row is
expanded once to destination width with the column mask folded in, and reused
for the three-odd output rows that map to it, which cuts the gather work by
that factor. The remaining per-output-row loop is linear, so it is the right
shape for NEON — LLVM still will not take it (4-byte stride, three channels of
four, u16 to u32 to u8), but hand-written it is now a simple widening multiply
by a row scalar rather than anything clever.

The lesson from the middle row: the memcpy fast path was first written with
`!half` in its condition, and this panel is *always* rotated, so it never ran
once and the number did not move. Measure the change, do not assume it.

## The lid shuts the handheld down

`event1 "hall wake key"` advertises `KEY_POWER`, so closing the clamshell
decodes as a power-button press and slot acts on it. slot's own lid support
reads a `hallkey` file under `/sys/class/power_supply`, and **that directory
does not exist on this device at all**, so `find_hall` returns `None` and there
is nothing else feeding `Btn::Lid`.

For now the hall node's key events are dropped rather than acted on
(`patches/0003`), so the lid does nothing instead of shutting down. Wiring it up
properly needs the open/close signalling, which the input trace is back on to
capture: whether it holds a value across the closed state, or just pulses on
each transition, decides whether it can drive `Btn::Lid` directly.

## Allium's daemon fights slot for the MENU button

`alliumd` keeps running underneath whatever it launches, and it owns MENU
globally: it draws a "Global Hotkeys / Ingame Hotkeys" overlay over the running
game and claims MENU plus power, volume and brightness. slot wants the same
button — a tap is its quick menu, a hold ejects — so both react to every press.

This was the real cause of the menu button feeling broken, and it is invisible
from slot's own logs: the gesture log showed slot deciding correctly all along.
Capturing `/dev/fb0` over the network and looking at it is what settled it,
which is worth remembering as a diagnostic — `dd if=/dev/fb0` on the device,
then `tools/fb2png.py`.

**Do not kill `alliumd`** — and the reason turned out to be mundane. The card's
boot hook, `.tmp_update/updater`, ends like this:

```sh
RUST_LOG=info "$ROOT"/.allium/bin/alliumd >"$ROOT"/allium.log 2>&1
...
else
    while true; do
        reboot
        sleep 10
    done
fi
```

Killing `alliumd` makes that script continue past the launcher and hit the
reboot loop. The "hard shutdown when launching a game" was the handheld being
told to reboot, not a power fault or a watchdog.

The right way to have the machine to ourselves is to boot slot *instead of*
Allium, from that same hook. See "Booting straight into slot" in the README:
a `.slot-boot` file at the card root selects it, deleting the file undoes it
from any computer, and if slot exits the script falls through to Allium rather
than to the reboot loop.

## Why gesture timers misfire: `advance` drops input during a rebuild

Symptoms seen on the device: an 8.5 second hold of MENU producing no eject at
all, ejects and quick menus resolving about 250 ms *after* the release rather
than at the moment they are due, and the whole thing being intermittent.

`Frontend::advance` is the cause, or at least a sufficient one:

```rust
let events = input.poll(now);
if self.rebuild.is_some() {
    return;                         // events discarded here
}
self.session.feed(events, now);     // and feed is what calls gestures.tick
```

While a label or face rebuild is running, input is polled and **thrown away**,
and `Gestures::tick` never runs — so no hold timer advances and no press is
recorded. A hold that spans a rebuild cannot eject, and the press that follows
resolves against a stale clock.

**Status: mechanism found, not confirmed active.** slot does not log rebuilds,
so there is no evidence in the captured logs that one was running at the time.
Confirming it is one `eprintln` on that early return, behind
`SLOT_TRACE_LATENCY`.

Ruled out along the way: the chord path (no SELECT events appear in any trace)
and the double-tap path (the press in question came 671 ms after the previous
tap, outside the 350 ms window). Both of those also clear `menu_down_at`, so
they were worth eliminating.

If it is confirmed, the fix is a judgement call rather than an obvious one.
Upstream presumably intends input to be ignored while rebuilding; the harm here
is that events are *discarded* rather than left queued, and that the timers stop.
Rebuilds are also slower on this device than the hardware slot was written for.

## Button bounce

The polled GPIO emits spurious transitions. From the trace, three in a single
millisecond:

```
9289ms  release
9289ms  press
9289ms  release
```

That alone can manufacture a double tap, which lands on the polaroids screen.
Worth remembering before blaming gesture thresholds.

## Never overwrite the live binary

With slot as the boot process, `curl -T` straight onto `System/slot` hangs the
handheld: FTP truncates the file on open, and the running process loses the
pages it is executing from. Reachable one moment, gone the next, with no
network and no response to buttons.

`task deploy` uploads to `slot.new` and renames over the top, which is atomic
and leaves the running process on the old inode. The new build is picked up on
the next start.

Recovery, if it happens anyway: force the handheld off with the power button. A
truncated slot fails to start, and the boot hook falls through to Allium. If it
hangs instead of falling through, delete `.slot-boot` with the card in any
computer.

## Open problem: no battery sysfs

```
$ ls /sys/class/power_supply
ls: /sys/class/power_supply: No such file or directory
```

`slot-power` reads `/sys/class/power_supply` for the battery gauge, and it does
not exist on this device. The HUD battery indicator has no source yet. Find out
how Allium reads the charge (likely an ADC under `/sys/devices` or via the MI
libraries) before writing anything.
