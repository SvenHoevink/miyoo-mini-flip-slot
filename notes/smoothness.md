# hitches in play, every core (2026-10-31)

Written 2026-10-31, without the handheld. **Nothing here has run on a Mini
Flip yet.** It builds for armv7, the tests below pass as armv7 under qemu,
and the launch-script change passes under busybox; that is the whole claim.
The report was "slowdowns still", on no particular core, so the search was
for things every core shares rather than for one emulator's cost.

## what changed

| | |
|---|---|
| `card/System/launch_frontend.sh` | the `performance` governor while slot runs, the launcher's put back after |
| `patches/0041` | background work below the draw; the autosave and the battery off it |
| `patches/0042` | the backend's two test modules out of the device build, so clippy is green again |

### the governor

Nothing in this port set one, so slot ran under whatever the launcher left
-- and both launchers leave `ondemand`: Onion's `runtime.sh` writes it back
after every game, and Allium's launcher never touches it except in its own
pico-8 and ffplay scripts, which set `performance` for the run and
`ondemand` after. This port now does what those do. `ondemand` stepping the
shared clock of both cores down between busy frames fits "hitches, not slow
motion", but **that is a hypothesis**: the governor slot actually ran under
has never been read off the device. The launch now logs it, before and
after, to `Logs/crash/exits.log` as
`launch: governor ondemand -> performance, 1200000 kHz`, which answers it
on the first boot. `touch Config/cpu-ondemand.txt` turns the change off.

Not an overclock: `performance` holds the kernel's own `scaling_max_freq`.

### 0041, what the draw waited on

Read out of the code; the patch header has the detail.

1. **The rewind worker ran at nice -8**, above the draw at 0, because Linux
   gives a thread its creator's nice value and it is spawned from the
   emulator thread. A SNES snapshot is 529 KB of copy, XOR and LZ4 every
   eleven frames -- and nes-snes.md measured rewind costing 20-30 missed
   latches per 600 against 7-27 without. Background work is nice 10 now,
   the draw -4.
2. **The rewind worker copied each state twice.** It takes ownership now.
   Its hand-off stays a blocking send: dropping snapshots instead was tried
   and broke four of upstream's `tests/rewind.rs` cases, which pin that
   every push is kept in order -- caught by running the suite against a
   0001-0037 baseline, not by the device.
3. **The minute autosave asked the core for its state from the draw**: up to
   a frame waiting for the emulator, then a serialize. It asks from its own
   writer thread now.
4. **The battery was `axp_test`, spawned and waited for on the draw every
   ten seconds.** Only the first reading waits now.

## the cores: measured, and left alone

`core_bench` (upstream's, `crates/slot-retro/examples`) built for armv7 and
run under qemu-user on an x86 host, with Peter Lemon's public-domain test
carts. **qemu milliseconds are not A7 milliseconds**; read them only against
each other, and gpSP not at all -- qemu pays for every block its JIT writes.

| core | cart | ms/frame | state | serialize |
|---|---|---|---|---|
| FCEUmm | ItaloTest.nes | 1.6 | 13.7 KB | 0.03 ms |
| mGBA (GB) | HelloWorld.gb | 1.9 | 198 KB | 0.26 ms |
| Snes9x 2005 | MonsterFarmJump.sfc | 2.0-2.5 | 529 KB | 0.23 ms |
| mGBA (GBA) | BGMode7.gba | 6.6-7.6 | 516 KB | 0.77 ms |

- gpSP, FCEUmm and Snes9x 2005 already build `-Ofast -flto
  -fomit-frame-pointer` through `platform=classic_armv7_a7`.
- mGBA builds `-O3` without LTO, and already exports only the 25 `retro_*`
  symbols. Rebuilt with `-fvisibility=hidden` and with `-flto`, neither
  separated from the stock build across two interleaved rounds of three
  carts -- qemu's run-to-run spread here is 10-20%, larger than any
  difference. Not changed: a build flag nobody can show a gain for is not
  worth un-settling the toolchain over.
- Snes9x 2005's only speed knob, `snes9x_2005_overclock_cycles`, is the
  core's own "unsafe" hack against a *game's* slowdown and changes how games
  behave; left off. FCEUmm has no frameskip at this commit, and does not need
  one at 1.6 ms.
- The mGBA Game Boy state is ~198 KB, not the ~24 KB `rewind::plan`'s doc
  comment assumes, so a GB cart snapshots every 4 frames rather than 2. Still
  inside the 3 MB/s budget the plan is for; noted rather than changed.

## to measure on the handheld

1. `Logs/crash/exits.log`: what governor the launcher left, and that the
   switch took.
2. `touch Config/trace-latency.txt`, then the `pace:` line's "missed a latch
   per 600" on a SNES game with rewind **on** -- the 20-30 from
   nes-snes.md is the before-number.
3. Whether a hitch every 60 s (autosave) or every 10 s (battery) is gone.
