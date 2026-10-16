# other Miyoo models — what would it take

Written 2026-10-15, from reading the tree and the stock boot hook. **Nothing
here is measured on a Mini or a Mini Plus**; no such device has been probed
yet. Everything about those two panels is marked as a hypothesis, per the
ground rule in CLAUDE.md. `notes/hardware.md` remains the file for measured
facts, and the Flip is the only thing in it.

Scope right now is the **Mini Plus**, because it has WiFi — which means
`task deploy`, telnet and FTP, and the two-player link. The original Mini has
none of that and every build would travel by SD card, so it is parked.

## model detection, which is the one solved part

The stock boot hook already does this, and `card/System/launch_frontend.sh`
now does it the same way:

| model | test the firmware uses | which handheld |
|---|---|---|
| 285 | `/dev/input/event1` exists | **Mini Flip** — the measured one |
| 354 | `/customer/app/axp_test` exists | **Mini Plus** |
| 283 | neither | original Mini |

This is the firmware's own test, taken from `card/.tmp_update/updater`, so it
is as reliable as the boot process that depends on it. `SLOT_MIYOO_MODEL`
overrides it.

## what almost certainly carries over

The Mini, Mini Plus and Mini Flip are all **SigmaStar SSD202D** — the same
armv7 Cortex-A7, the same 128 MB, the same no-GPU problem. So the expensive,
hard-won parts of this port are SoC-level and should need nothing:

- the toolchain, the triple, glibc 2.28, both libretro cores
- the software rasteriser itself, and the whole reason it exists
- the four 32-bit fixes in upstream (`0001`, `0003`, `0004`)
- the MI_AO audio sink (`0005`), which is a SigmaStar interface
- `/dev/fb0` and the mmap path
- the card layout, launch scripts and the Allium integration

That is most of the port. The variants are a panel-and-peripherals problem,
not a re-port.

## what is model-specific, and the state of each

### the panel — the real blocker

`OUT_W`/`OUT_H` in `crates/slot-gfx/src/surface.rs` are **compile-time
constants**, set to the Flip's 752x560 by `patches/0002`. Upstream's own value
is 720x480 and is letterboxed into whatever panel the device has; this port
deliberately changed it to *be* the panel, so the shelf uses the whole screen.

The Mini Plus panel is believed to be **640x480** (hypothesis — probe it).
If so:

- a 752x560 canvas simply does not fit a 640x480 panel, so today's binary
  will not lay out correctly there. The launch script now says so in the log
  instead of drawing something wrong in silence.
- 640x480 is **4:3** exactly, which the Flip's 752x560 is only to within
  0.71%. `patches/0012` widened `bezel::framed()` to that tolerance, so the
  Plus takes the same path without needing the tolerance at all, and is
  *closer* to upstream than the Flip is.
- the GB/GBC picture at 3x is 480x432, which fits 640x480 comfortably — so
  `patches/0009`'s fitting work is a Flip-shaped problem and may not arise.

**Feasibility:** 59 references to `OUT_W`/`OUT_H` across the patches, but
checked, and **none of them is a fixed-size array or other const context** —
the only derived constants are `SRC_W`/`SRC_H` and two test-local ones. So
either route is open:

1. *build-time variant* — select the pair behind a cargo feature and build one
   binary per model. Cheap, a few lines, no runtime cost, two artifacts.
2. *runtime geometry* — read it from `fb0`, which the backend already does for
   its own purposes ("fb0 hint 752x560" in the log). One binary for every
   model, and the honest shape of the thing, but it touches all 59 sites and
   turns consts into fields.

Start with (1) to get a Plus running, and only do (2) if a third model shows
up. Doing (2) first is the kind of refactor that is easier to justify than to
finish.

### everything else

| thing | Flip, measured | Mini Plus | how to settle it |
|---|---|---|---|
| panel rotation | fitted upside down, `SLOT_FB_ROTATE=180` | unknown, probably not | look at the screen |
| buttons | `gpio_keys` keyboard codes (`patches/0003`) | likely the same, Plus has no hinge | `slot probe`, input section |
| lid / hall sensor | present, drops `KEY_POWER` | **no lid at all** — the Plus is a slab | nothing to do |
| backlight | PWM (`patches/0008`) | likely same SoC PWM, maybe another channel | probe `/sys/class/pwm` |
| WiFi | rtl8188fu, 2.4 GHz only | has WiFi, chip unknown | probe `/proc/modules` |
| battery | no `/sys/class/power_supply` | unknown; the Plus has an AXP chip (`axp_test`) | probe — this one could go *better* than the Flip |
| audio | MI_AO (`patches/0005`) | same SoC, expect the same | listen to it |

Two of those are worth noticing. The Plus has **no lid**, so the one open
hardware question on the Flip simply does not exist there. And the Plus has an
**AXP power chip** — it is the thing its model detection keys on — which is
the most likely route to the battery indicator the Flip cannot have.

## the next step, which needs no build

`task probe` already produces a tree that runs on any of these handhelds, and
it needs no cross-build, no shell and no network:

```sh
task probe
cp -R dist-probe/. /media/<you>/<plus card>/
sync
```

Then **Apps → slot probe** on the Mini Plus, and read `slot-probe.txt` from
the card. That one file answers the panel size, the rotation question, the
input codes, the WiFi chip and whether `/sys/class/power_supply` exists —
which is every row above. Land it here as a measured section, and the
build-time variant becomes a short afternoon rather than a guess.

If it has WiFi working, `card/System/linkprobe.sh` (Apps → slot link probe) is
worth running at the same time: a Plus that can host a link is a second device
to test two-player against without involving the Anbernic.
