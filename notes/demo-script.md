# Demo video script — slot on the Miyoo Mini Flip

For the clip linked from the upstream issue (`notes/upstream-perf-issue.md`)
and the repo README. Target **60–75 seconds**, no edit beyond cuts. The
audience is one maintainer deciding whether this port is real, so the job is
evidence, not atmosphere: real hardware, real games, no cuts that could hide a
stall.

## Before you film

- Charge past 50% so the battery indicator reads healthy on camera.
- Delete `Config/trace-latency.txt` from the card — the trace writes to the
  card from inside the frame loop and this should be a stock build.
- Set GB and GBC bezels to **Default** (quick menu → Bezel) and leave GBA on
  **AGS-102**, so each console shows its own body.
- Put a clear GBC cart next to two others on the GBC shelf — that run of three
  is the thing that used to ring, and it is worth showing settling in one
  motion.
- Film landscape at **60 fps**, handheld or on a small tripod, one light off to
  the side rather than straight on. Don't get closer than ~30 cm or the panel
  moirés; frame the whole device, hands in shot.
- Stills for thumbnails, over the network, no camera involved:
  `SLOT_DEVICE=<ip> task device:shot OUT=shot.png`.

## Shot list

**1. The hardware (0:00–0:08)**
Closed clamshell on the desk, pick it up, open it. slot already on screen.
> "This is a Miyoo Mini Flip. Two Cortex-A7s, 128 megs of RAM, and no GPU at
> all. This is slot, running on it."

**2. The shelf (0:08–0:20)**
Scroll the GBC shelf, deliberately across the three clear shells, and let it
settle. Then scroll fast and let it settle again.
> "Everything you're seeing is drawn on the CPU — there's no GLES on this chip.
> The shelf art, the carts, the shadows: all of it is a software rasteriser
> writing straight to the framebuffer."

**3. Insert a Game Boy cart (0:20–0:34)**
Select a GB game, press A, let the insert animation play through to the game.
Hold still a beat on the Game Boy body around the picture.
> "Picking a game plays the whole insert animation, and the game comes up
> inside its own console — a Game Boy here, with the battery lamp."

**4. The bezel is per console (0:34–0:46)**
Tap MENU, move to **Bezel**, cycle it: Default → AGS-102 → None → back.
Close the menu. Then eject (hold MENU) and start a **GBC** game to show the
Color body, then a **GBA** one to show the SP shell.
> "Each console gets its own body, and you can change it per console from the
> in-game menu. Game Boy, Game Boy Color, and the Advance SP shell for GBA."

**5. It actually plays (0:46–1:00)**
Thirty seconds of real play on the GBA game, on gpSP — something with
movement and sound. Let the audio be heard.
> "GBA runs on gpSP, which has an ARM dynarec; the frontend's own work is about
> eight milliseconds of a sixteen millisecond frame, so there's room for the
> core. Saves, save states and the sleep-on-close all work."

**6. Close the lid (1:00–1:08)**
Close it mid-game — screen goes dark — reopen, play continues.
> "Closing the lid saves and darkens the panel; opening it picks up where you
> were."

**7. End card (1:08–1:15)**
Static frame, text only:
```
slot on the Miyoo Mini Flip
software renderer, no GPU
GB / GBC / GBA — single player
link play: written, untested
github.com/deanmarano/slot-miyoo
```

## What not to claim on camera

- Don't say link/multiplayer works — it is written and untested.
- Don't quote frame numbers you aren't showing. "About eight milliseconds of
  sixteen" is measured and in `notes/hardware.md`; anything sharper than that
  belongs in text where it can be checked.
- Don't show the shelf with the trace file armed — the per-frame logging makes
  it slower than the build you are demoing.
