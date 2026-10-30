# NES and SNES

Written 2026-10-30. **Nothing here has run on a handheld yet.** It builds for
armv7 and the host test suite passes; that is the whole claim. Every number
below that matters -- frame time, RAM -- is still to be measured, and goes in
`notes/hardware.md` with a date and firmware version once it is.

## what is known

From the armv7 build, run under `qemu-arm` against the toolchain's own
glibc 2.28 sysroot, with two hand-assembled test carts that each fill the
screen with one colour -- so this is "the cores load and draw", not a game
playing:

| | FCEUmm | Snes9x 2005 |
|---|---|---|
| .so | 2.3 MB, needs libc and libm, GLIBC_2.7 at most | 0.7 MB, the same |
| frame | 256x224, every pixel the cart's colour | 256x224, likewise |
| timing | 60.10 fps, 48,000 Hz | 59.92 fps, 32,040 Hz |
| save state | 13.7 KB | 529 KB |

The SNES state is the one to watch: `0017` sizes the rewind ring by state
size, so a SNES game gets far fewer rewind steps per MB than a GBA one, and
each step costs a 529 KB serialize. Time it with rewind on.

## what was added

| | |
|---|---|
| cores | `cores/fceumm` (NES, GPL-2.0) and `cores/snes9x2005` (SNES, Snes9x's non-commercial licence), built like gpSP: `platform=classic_armv7_a7`, CFLAGS in the environment, tarball pinned in `taskfile.yml` |
| `patches/0027` | the two systems, end to end: platforms, cores, the frame each core draws into, the picture's size, buttons, settings, and the NES and SNES carts on the shelf |
| `patches/0028` | both open full screen at the panel's 4:3, rather than at 2x with a border |

The cart shells and their label boxes are fragilesilver/slot-fragile's
(`assets/nes_neutral.png`, `assets/snes_neutral.png`, `slot-ui/src/media.rs`),
from commit `f2da56a`, GPL-3.0 like the rest of slot. Fragile drew them with
its `tools/fragile/media/draw_carts.py`; regenerate them from there.

`0027` changes `slot-ui`, which CLAUDE.md says to stop and reconsider. It is a
feature rather than a port fix -- upstream has no NES or SNES to make work --
so there is no backend to put the carts in instead. It says so in its header.

## how it fits upstream's model

**The canvas.** Upstream copies every core's picture into a fixed 240x160
frame, centring a Game Boy's 160x144 inside it. A NES or SNES picture is
256x224 and would have been cut down to 240x160. `Platform::canvas()` now
names the frame per system -- 240x160 for the Game Boy family, unchanged;
256x224 for the two consoles -- and `LibretroCore::set_canvas` sizes the
host's buffer before the game loads. The renderer already took any source
size: the column table is keyed on the image's width, so the only change
there is reallocating the frame when the size moves.

- FCEUmm is told to drop 8 lines top and bottom, which is its own default and
  what a television hid, so it draws 256x224 too.
- SNES hi-res (512 wide) is averaged pair by pair; interlace (448 tall) takes
  every other line. Averaging keeps the blending those modes are mostly used
  for. A 239-line picture keeps its middle 224.

**The picture's size.** Stretch, the default for both consoles since `0028`,
fills the whole panel: 752x560 on the Flip, 640x480 on the Mini. Both are 4:3
or within 1% of it, which is the shape a television showed these consoles at
-- 8:7 pixels and overscan -- so this is their own aspect, not a distortion.
On the Flip that is 2.94x across by 2.5x down, nearest-neighbour, so columns
and rows come out two and three pixels in turn. Actual is the largest whole
multiple with square pixels: 2x, 512x448, on both panels. L1/R1 switch them on
a NES game as on a Game Boy; on the SNES the shoulders are the game's, so
there is no gesture, and `actual` in the per-game `Config/video_mode.txt` is
the only way back to 2x.

**Buttons.** The SNES gets X and Y from the two turbo bindings, which default
to the device's X and Y; turbo is off there, and the turbo rows are hidden in
the in-game menu because their labels would be wrong. L and R go to the game.
The NES keeps the Game Boy layout, turbo included.

**Settings that do not apply** are hidden in game and ignored if reached: the
LCD shaders, colour correction and bezels. A television had none of them.

## to measure on the handheld, in this order

1. **SNES frame time.** `SLOT_TRACE_LATENCY=1`, a busy scene in Super Mario
   World, Donkey Kong Country and Chrono Trigger. `emu>pub` has to leave room
   for the ~8 ms the backend takes. Snes9x 2005 runs on `frameskip=auto`, which
   hides a slow core as dropped frames rather than slow motion -- read the
   frameskip, not just the feel.
2. **The game pass at 256x224.** The default is now the full panel, 752x560
   -- 421,120 output pixels against the GBA's 345,600 at 720x480 -- so it is
   the slowest picture slot draws; time it. 2x, 512x448, is the fallback if it
   does not keep up.
3. **RAM** with a 4 MB SNES cart and rewind on, against the 15 MB floor in
   `hardware.md`. Snes9x 2005 loads the ROM from memory, so slot holds a copy.
4. **Shelf scroll** with NES and SNES carts in view. Their shadows are two more
   textures held for the life of the process, about 0.75 MB together.
5. **Audio.** Snes9x 2005 reports 32,040 Hz; the ring resamples to the codec's
   48 kHz. Listen for the DRC walking.

Expected to struggle whatever the numbers say: the Super FX games (Star Fox,
Yoshi's Island) and SA-1 games. Report them; do not promise them.

## measured on the handheld (2026-10-30)

Mini Flip, stock firmware 202510011046, booted straight into slot. Super Mario
World on Snes9x 2005, `SLOT_TRACE_LATENCY` armed, `pace:` lines per 600
presents:

| | missed a latch, per 600 |
|---|---|
| rewind on (529 KB state every 11 frames) | 20-30 |
| rewind off | 7-27 |
| rewind off, `SLOT_DRIVE_EMU=1` | 330-510, core and draw in series |
| rewind off, `SLOT_DRIVE_EMU=overlap` (`0029`) | 0-5 |

The core itself takes 8-10 ms a frame (`emu>pub`), so it was never the problem:
the hitches were rewind's serialize and the core's own 60 Hz timer against a
59.6 Hz panel. Overlap is the card's default since the volume-HUD round, played
on SNES and GBA; `Config/drive-timer.txt` goes back to the core's own clock.
Input to screen, from the `latency:` lines' totals: ~40 ms overlapped against
~53 unchained, so the overlap's one-frame pipeline costs no latency over the
timer it replaced -- the timer's frames waited for the next draw anyway.

Tapping MENU in a NES or SNES game overflowed the stack until `0030`, which
looked like a frozen handheld: no log line, no power button. Found by
seating the real cart on the real core in a test under Docker; the device
log was no help, because a frozen handheld that loses power loses the last
seconds of `slot.log` with it.

## the volume HUD (2026-10-30)

Same handheld and firmware. With the core ticked by the panel, the volume
HUD made the game slow down for as long as the bar showed: Super Mario World
traced 247 of 600 presents missing a latch in a window with the bar up, 0-6
without it. Two causes, two patches:

- `0031`: a present that spanned two blanks ticked the core once, so the
  game lost a frame each time. It now owes the core one tick per blank, up
  to three (`0033` lets longer stalls go).
- `0032`: any sprite over the game sent the whole frame through the canvas,
  21.6 ms of render against ~10. The game now stays on the direct path and
  only the HUD's rect is composed and copied out.

Played on the Flip with `0031`-`0033` together: volume changes, a GBA cart
on gpSP and SNES play all held speed. A long present now logs its
draw_list, end_frame and overlay times under `SLOT_TRACE_LATENCY`.

Blue light was still the slow case (traced the same day, Pokemon Emerald on
gpSP, blue light 5): 0032 sent a HUD through the canvas whenever the gain
was on, 20-24 ms a frame with the bar up against 7.8 without it, 675
presents over 25 ms with no overlay time in any of them. `0034` grades the
overlay as it composes it and keeps the direct path; it also stops a GBA
HUD from carrying the whole Advance shell with it, and from staying on the
panel, faint, after it fades.

Played on the Flip with `0034` (2026-10-31): volume changes on a GBA cart
with blue light on hold speed, and the bar leaves nothing behind when it
fades.
