# Draft issue for BrandonKowalski/slot

Working copy. Paste the part below the line into a new issue; nothing here is
posted automatically. The commits it refers to are on the `upstream-fixes`
branch in `upstream/slot`, cut against upstream `main`, and in this repo as
`patches/0014` and `patches/0015`.

Title: **Porting to the Miyoo Flip Mini - performance fixes from a GPU-less port**

---

Claude & I have been porting slot (which is amazing, btw, thank you so much for
it!) to the **Miyoo Mini Flip** and have it running well on the handheld. The
hardware is more meager, and I needed some perf improvements to get it running
smoothly. You can find them in my fork, but I've had Claude describe them
below.

I'm not sure all of the changes make sense (especially with your focus on Ambernic)
and not wanting to expand your support surface, but I think these are some perf
wins worth upstreaming.

The port is at <https://github.com/deanmarano/slot-miyoo>:
15 patches against upstream plus the software backend, all of it rebased onto
`main` as of this week. Short video of it running: **[link]**

## Miyoo Flip Mini Specs

| | |
|---|---|
| SoC | SigmaStar SSD202D, 2x Cortex-A7 @ 1.2 GHz, **armv7 32-bit** |
| GPU | none — no libEGL, no GLES2, a 2D blitter only |
| RAM | 128 MB, ~101 MB usable, no swap |
| Panel | 2.8" 752x560, 32bpp, triple buffered, mounted upside down |

Thankfully, `slot-ui` emits no graphics calls, which is what made this
feasible: the port adds a third `Surface` backend — a CPU rasteriser writing to
mmapped `/dev/fb0` — beside `host` and `device`, and changes nothing above that
seam.  GB, GBC and GBA all play on the handheld, GBA on gpSP.
Link/multiplayer is untested (and likely out of reach on this device, but tbd).

Below is Claude explaining the improvements.

---

Everything below was measured on the device with `SLOT_TRACE_LATENCY=1`.

## 1. `emu.rs` throws away the frame debt on a late frame

```rust
// crates/slot/src/emu.rs
match deadline.checked_duration_since(now) {
    Some(wait) => std::thread::sleep(wait),
    None => deadline = now,
}
```

Where the kernel tick is coarse — `CONFIG_HZ` is 100 here, so a sleep can't
land finer than 10 ms — "sleep the rest of the frame" routinely overshoots.
After mGBA's 8.26 ms of work the remaining wait is 8.4 ms, which comes back
late almost every frame, and resetting the deadline to `now` makes every
overshoot permanent. The core settled at **~52 Hz**: a Game Boy that feels
slow, audio stretched to match (a 1.37 resample factor) and the ring starving
in proportion (747,876 starved samples, `queued` down to 357 of 4800).

Carrying the debt forward instead makes the next wait that much shorter and
the average come out at `PRESENT`. Past four frames of debt it still resyncs,
since that's a real stall rather than timer grain and repaying it flat out
would be audible.

This one isn't exotic: any host where a sleep overshoots — a loaded CPU, a
coarse tick, a slow card read — loses that time permanently today.

## 2. No thread has a scheduling priority

slot sets none, on any thread. On a two-core device the emulator thread is the
one with a hard deadline and the one that loses the CPU. The port sets
`setpriority(-8)` on the emu thread and `-10` on the input readers and the
audio writer; on this hardware that's the difference between an audio ring
that holds and one that doesn't.

Cheap, and `libc` is already a dependency.

## 3. The animation step is the real frame time, unclamped

`Shelf::update` is a critically damped spring stepped by `dt`:

```rust
let accel = -2.0 * OMEGA * self.vel - OMEGA * OMEGA * (self.scroll - target);
self.vel += accel * dt;
self.scroll += self.vel * dt;
```

The velocity term is `vel * (1 - 2w*dt)`, which turns **negative past
dt = 1/2w = 31.25 ms** with `OMEGA = 16`. The velocity then flips sign every
frame and the carousel rings back and forth instead of settling.

It was reported to me from the handheld as "it goes back and forth rapidly
before it stops", and — the useful part — as happening on the Game Boy Color
shelf but not the Game Boy one. A clear shell is the most expensive cart to
draw (see 4), and three in view is what pushed the frame over the line:

```
clear 0.7  sprites 25.6-37.3 over 18 draws  out 3.0  ms/frame, worst 75.3
```

Clamping the step to 25 ms restores what the spring is for rather than
changing it: an animation on a slower frame runs slow instead of coming apart.
A GPU host won't meet 31 ms often, but a crowded shelf, a slow card or a
background rebuild can all get there, and the failure is ugly when it does.

## 4. A clear cart is three full-size blends every frame

A clear cart is drawn as three sprites over the same rect — the game-coloured
interior, the board, then the plastic and its label. They never move relative
to each other. Per cart, measured:

```
tex id 9  278x300  6.0 ms  72 ns/px -- skip 5082  copy 0     blend 78318
tex id 36 278x300  2.1 ms  25 ns/px -- skip 18214 copy 62516 blend 2670
tex id 6  278x300  4.2 ms  50 ns/px -- skip 5272  copy 35046 blend 43082
```

**13 ms for one clear cart**, against 2 ms for a solid one. Compositing the
three into the face once, on the worker thread that already builds it, so the
shelf sends one sprite:

| | before | after |
|---|---|---|
| sprite stage | 25.6–37.3 ms over 18–20 draws | 15.4–16.0 over 14 |
| whole frame | ~30–41 ms, worst 44–78 | ~19–20 ms, worst 21–27 |
| one clear cart | 13 ms | 1.9 ms, mostly a straight copy |

It also drops a full-size texture per clear cart from memory, which matters at
101 MB. With a GPU it's three quads saved rather than a rescue, so this is the
one I'd understand you not wanting.

**It is not pixel-identical**, which I'd rather say up front than bury: a
faded cart — the ones either side of the selection — now composites as one
stack at that alpha, instead of layer over layer each at that alpha. The
current way darkens twice where the layers overlap and this doesn't. I think
flattened is the more correct of the two and it looks right on the device, but
it is a change in appearance and your call.

## What I've run

Each commit on its own, against current `main`: `cargo fmt --check`,
`cargo test -p slot-ui`, and `cargo test -p slot --features device --lib`.

Tests added: two that pin the clamp against `OMEGA` rather than against the
number, and one that composites a clear cart's three layers independently and
checks the flattened face against them.

