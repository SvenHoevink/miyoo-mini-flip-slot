# Handoff: audio latency on the Miyoo Mini Flip port of slot

Written 2026-10-14. Pass this to whoever picks up the audio work.

Repo: `/home/dean/github/deanmarano/slot-miyoo`. Read `CLAUDE.md` and
`notes/hardware.md` first — especially the sections "MI_AO ignores `u32FrmNum`",
"`CONFIG_HZ` is 100", and "The handheld's address moves".

## The symptom

Audio plays cleanly but roughly **350 ms behind the picture**. Game speed,
video pacing and pitch are all correct; this is purely latency.

## The cause, measured

MI_AO silently ignores `MI_AUDIO_Attr_t.u32FrmNum`. Asked for 2 periods it
accepted **33 periods of 512 frames = 352 ms** (measured by filling it until
writes blocked). `Ring::fill` pads with silence rather than waiting, so the sink
races ahead and keeps that buffer permanently full. **Any latency figure
computed from the attributes is fiction** — do not trust `u32FrmNum`.

## The blocker, and where to start

`MI_AO_QueryChnStat` reports `u32ChnTotalNum / u32ChnFreeNum / u32ChnBusyNum`,
and the shim exposes `slotao_queued()` returning `u32ChnBusyNum`. A throttle
built on it (`SLOTAO_QUEUE=N`: write only while busy < N periods, topping up to
N each pass) **does remove the lag** — but throughput then pins at exactly
**43,008 frames/s** against the 48,000 the codec is configured for.

That figure was identical with 512-frame periods (84/s) and 128-frame periods
(336/s) — a 4x granularity change, same frame rate. Since each pass tops up to
a *target*, our drain rate is the codec's consumption, so the codec appears to
consume ~10% slower than its configured rate. Consequence: production backs up,
the ring fills to capacity, `Ring::push_blocking` stalls the emulator
(`Ring::stalls` passed 3,000 in one session), the core is held near 51 Hz, and
the codec still reaches 0 every window — audible as chop.

**Start by explaining the 43,008**, before building anything on top of it.
Suggested first step: log `u32ChnTotalNum` and `u32ChnFreeNum` alongside
`u32ChnBusyNum` — only busy is currently read, and it may not mean what it
appears to. Also worth testing `SLOTAO_QUEUE=5` with
`E_MI_AUDIO_SAMPLE_RATE_44100` to see whether the drain figure tracks the
configured rate at all.

## Already ruled out — do not re-attempt

- **Write cadence** — the 4x period change (512→128) left the frame rate
  identical.
- **The audio thread starving the core** — sleeping every pass instead of only
  the empty ones changed nothing.
- **A too-shallow ring** — it reports `0 starved` throughout. The deficit moves
  *downstream* of the ring, which makes ring numbers actively misleading here.
- **`drc_target` headroom** — tried capacity/4 instead of /2; the ring was the
  symptom, not the cause. Now back to upstream's /2.
- **The rate enum** — `MI_AUDIO_SampleRate_e` is literal Hz
  (`E_MI_AUDIO_SAMPLE_RATE_48000 = 48000`), so 48000 is valid and is what's set.
- **Vendor resampling** — `slotao_resample_from()` exists but is never called,
  so `MI_AO_EnableReSmp` is not in the path.
- **Direct ALSA** — refuses 32768 Hz; at 48 kHz every write fails with
  `snd_pcm_recover` returning -512 persistently. MI_AO is the only path.
- **Shrinking the ring alone** — the ring's DRC target went 100 ms → 33 ms
  (67 ms of real reduction) with *no audible change*, because the 352 ms
  dominated. That non-result is the clue that found the real cause; don't redo
  it.

## Current state (verified on the device)

Throttle is **off by default** (`SLOTAO_QUEUE` unset or 0 → unthrottled, laggy,
clean). `SLOTAO_QUEUE=5` gives the low-latency-but-choppy version for A/B —
one line in the launch script, no rebuild.

Launch script sets `SLOT_RING_FRAMES=8`, `SLOT_DRIVE_EMU=0`. No traces enabled.
Sink constants: `DEVICE_HZ=48_000`, `CHANNELS=2`, **`PERIOD_FRAMES=512`**,
`WRITE_TIMEOUT_MS=200`. (128 existed only to give the throttle granularity and
was reverted with it.)

Confirmed healthy: ring sitting on its 3200 target, `0 dropped`, `0 core
stalls`, starvation frozen at its startup figure.

Instrumentation already in place (keep it — it's what produced every real
finding): the ring trace prints `N/target queued, N dropped, N starved, N core
stalls` under `SLOT_TRACE=1`, and with the throttle on the sink also prints
`codec queue low N of N, N empty passes, N send errors, N periods written`
every 5 s.

## Workflow

- `upstream/slot` is a **read-only pinned submodule**. All changes live as
  `patches/*.patch`. Edit the submodule, then **regenerate the patch before
  `task build`** (build runs `task patch`), and use `git add -N` for new files
  or they vanish from the patch and `unpatch` deletes them. Patch 0005 is the
  audio one; regenerate with:
  `cd upstream/slot && git add -N crates/slot/src/audio/miao.rs && git diff -- crates/slot/src/audio/ crates/slot/src/emu.rs crates/slot/src/drc.rs > ../../patches/0005-audio-miao-sink.patch`
  Then verify the round-trip: `task unpatch && task patch` (expect 7 applied).
  **Save a copy of edited files before `task unpatch` — it wipes the submodule.**
- `shim/slotao.c` is the C shim over MI_AO; rebuild with `task shim`.
- Deploy: `SLOT_DEVICE=<ip> SLOT_WAIT_S=150 task deploy`. Logs: `task log`.
  Crashes: `task crashes` — **run this; it was missed for a whole session.**
- **A deploy writes files but does not restart slot.** After deploying, confirm
  the running build is the one you pushed before trusting any log or asking
  anyone to listen. The fingerprints are the sink's `queue target` line and the
  ring's target value; `md5sum` the card's `System/slot` against the local
  build if in doubt. An entire round of "it still sounds wrong" was the old
  process still running.
- **The device's address is DHCP and moves** (seen on .135 and .145).
  `task device:find` sweeps for it; it takes the subnet from `SLOT_DEVICE`,
  because the build host is on 10.200.0.0/24 and reaches the handheld through a
  router — a sweep of the *local* link finds nothing and looks conclusive.
  `net-up.sh` also writes the address into `slot-net.txt` on the card.
- WiFi is flaky at cold boot but recovers (dropped 4-way handshakes, then
  COMPLETED ~50 s). If the device is unreachable, put the SD card in the Mac
  (`dean@192.168.1.10`, `/Volumes/YELLOWSP`) and read/write it over ssh.

## Hard-won rules that apply directly here

- **`CONFIG_HZ` is 100.** A `thread::sleep` of a few ms can return a tick late.
  This caused *four* bugs in this area, three of them by changing control flow
  around a sleep without checking the path where no work happens. If you touch
  the sink loop, check every branch where nothing gets written.
- **Measure, don't configure.** `u32FrmNum` is the cautionary tale.
- **A non-result is data.** "67 ms of reduction nobody can hear" was the clue
  that cracked this; chase those instead of cutting further.
- **Distrust your own instruments.** The ring's `0 starved`, a port sweep of a
  routed subnet, and `low 2147483647 of 0` were all confidently wrong. Validate
  a measurement against something known before building on it.
- Do not kill `alliumd`. Never report anything as working until it ran on the
  handheld.

## Also open, unrelated to latency

mGBA segfaults in `_GBMBC2Read` on Kirby's Pinball Land DX (GBC), ~0.9 s after
the first frame, reproducibly. The load logs no `emu: save ram` line where a
cart with SRAM does. Inside the core, past the seam; GBC cannot fall back to
gpSP. Retry at the next core bump.
