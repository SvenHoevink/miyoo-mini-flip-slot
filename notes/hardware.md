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
- **ALSA does exist**, contrary to what I first concluded. The qemu container had
  no `libasound.so`, and I wrongly generalised that to the device. On hardware
  slot's ALSA sink loads and gets as far as `hw:0,0: Device or resource busy`,
  so the library and the PCM are both there and something else was holding the
  device. An `MI_AO` sink may still be wanted, but it is not forced.

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

## Open problem: no battery sysfs

```
$ ls /sys/class/power_supply
ls: /sys/class/power_supply: No such file or directory
```

`slot-power` reads `/sys/class/power_supply` for the battery gauge, and it does
not exist on this device. The HUD battery indicator has no source yet. Find out
how Allium reads the charge (likely an ADC under `/sys/devices` or via the MI
libraries) before writing anything.
