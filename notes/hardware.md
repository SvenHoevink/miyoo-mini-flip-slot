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
- `libmi_ao.so` — audio out. **There is no ALSA**: qemu already showed slot
  `dlopen`s `libasound.so`, and nothing here provides it, so audio needs an
  `MI_AO` sink behind slot's existing `Sink` trait. Allium's `ffi` crate binds
  `mi_ao.h` and is the reference.

## Input

Two evdev nodes, which slot discovers by walking `/sys/class/input` already:

| node | name | notes |
|---|---|---|
| `event0` | `soc:gpio_keys` | all buttons, `EV=100003` |
| `event1` | `hall wake key` | **the clamshell hall sensor** |

The lid sensor is a gift: slot already handles `SW_LID` in
`crates/slot/src/input/evdev.rs`, so closing the Flip can suspend as upstream
intends. Per-button codes still need an `evtest`-style capture — the probe lists
the devices but not the individual keycodes.

## Open problem: no battery sysfs

```
$ ls /sys/class/power_supply
ls: /sys/class/power_supply: No such file or directory
```

`slot-power` reads `/sys/class/power_supply` for the battery gauge, and it does
not exist on this device. The HUD battery indicator has no source yet. Find out
how Allium reads the charge (likely an ADC under `/sys/devices` or via the MI
libraries) before writing anything.
