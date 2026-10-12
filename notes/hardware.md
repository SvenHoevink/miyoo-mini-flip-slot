# Miyoo Mini Flip — measured facts

Nothing here yet. Everything below is **unconfirmed** until filled in from the
device itself; see "Probing the device" in `README.md` for the commands.

| | spec sheets say | device says | date |
|---|---|---|---|
| kernel / arch | armv7l | — | — |
| CPU | 2x Cortex-A7 @1.2GHz (one vendor page claims A72) | — | — |
| RAM total / free | 128 MB | — | — |
| fb0 virtual_size | — | — | — |
| fb0 bits_per_pixel | — | — | — |
| fb0 stride | — | — | — |
| panel, physical | 2.8" 750x560 | — | — |
| rotation needed | unknown | — | — |
| EGL / GLES present | expected absent | — | — |
| MI_GFX (2D blit) present | expected present | — | — |
| battery sysfs path | — | — | — |
| firmware version | — | — | — |

## Button map

Fill from `cat /proc/bus/input/devices` and `evtest`.

| button | device | evdev code |
|---|---|---|
