# Audio latency on the Miyoo Mini Flip port of slot — resolved

Written 2026-10-14 as a handoff for an open problem; **closed the same day.**
Kept because the way it was got wrong twice is more useful than the fix.

Repo: `/home/dean/github/deanmarano/slot-miyoo`. Read `CLAUDE.md` and
`notes/hardware.md` first — especially "MI_AO ignores `u32FrmNum`",
"`CONFIG_HZ` is 100", and "The handheld's address moves".

## The symptom, and the answer

Audio played cleanly about **350 ms behind the picture**. Speed, video pacing
and pitch were all correct; it was purely latency.

Two causes, stacked:

1. **MI_AO ignores `MI_AUDIO_Attr_t.u32FrmNum`.** Asked for 2 periods it took
   32 of 512 frames — `u32ChnTotalNum` reads 65536 bytes — and `Ring::fill`
   pads with silence rather than waiting, so the sink raced ahead and kept all
   341 ms of it full. **Any latency figure computed from the attributes is
   fiction.** Holding the queue down by *querying* it is the only control that
   works.
2. **`MI_AO_QueryChnStat` answers in bytes, and the throttle read periods.**
   That is the whole of the unexplained "43,008 frames/s" that made the
   throttle unusable for a session. Any audio at all in the codec counts as "5
   or more", so the throttle only wrote once the queue had run completely dry,
   then dumped the target in one burst — a sawtooth from 53 ms to zero every
   59.5 ms, whose ~6 ms floor is a pass noticing on the next 10 ms tick.
   48000 × 53.3/59.5 = 43,008, stable to four figures because a duty cycle is.

Fixed by converting the byte count to frames and throttling on those. Measured
on the handheld: 48,036 frames/s, the queue never below 35 ms of its 53, the
ring on its 3200 target, 0 core stalls, 0 dropped, 0 starved, 0 send errors,
and about 100 ms of total latency against ~420. Confirmed by ear: no lag, no
chop. The throttle is now **on by default** at five periods; `SLOTAO_QUEUE=0`
restores the unthrottled path. Full numbers in `notes/hardware.md`.

## How this stayed hidden for a session, which is the useful part

- **An identical number across a 4x change was read as an exoneration.**
  Changing the period size 512 → 128 left the frames/s identical, and that
  retired "write cadence" as a suspect. It should have done the opposite: a
  mechanism indifferent to granularity is a *clue*, and a duty cycle set by the
  10 ms tick is exactly that. The experiment was right and the inference was
  backwards.
- **A measurement with no denominator was built on anyway.** `u32ChnBusyNum`
  was the only field ever read. One line printing `total` and `free` beside it
  — `total 65536` — ended the whole investigation in a minute, because 65536 is
  not a period count and could not be mistaken for one.
- **A fact that contradicted the theory was in hand the whole time.** The
  unthrottled sink's pitch was correct, which proves the codec consumes 48,000
  frames a second. "The codec drains 10% slow" could not have been true.
- **The loop's own rate was never counted** while being theorised about. It
  measured a clean 100/s; the prior session's leading theory, and the next
  one's, both had it wrong.

Every one of those is the `CLAUDE.md` rule "distrust your own instruments",
which the file already said, in a case where it was not obvious which
instrument was lying.

## Already ruled out — do not re-attempt

- ~~**Write cadence**~~ — the entry that was wrong. The 4x period change
  (512→128) left the frames/s identical and that retired the suspect; see
  "How this stayed hidden" above for why it should not have.
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

## Current state (verified on the device, 2026-10-14)

Throttle **on by default** in the binary: `SLOTAO_QUEUE` unset means 5 periods,
53 ms. `SLOTAO_QUEUE=0` is the old unthrottled path if MI_AO ever stops
answering `QueryChnStat`.

Launch script sets `SLOT_RING_FRAMES=8`, `SLOT_DRIVE_EMU=0`. No traces enabled.
Sink constants: `DEVICE_HZ=48_000`, `CHANNELS=2`, `PERIOD_FRAMES=512`,
`WRITE_TIMEOUT_MS=200`.

Confirmed on the handheld: 48,036 frames/s, codec queue floor 35 ms of 53, ring
1748-2905 on a 3200 target, `0 core stalls`, `0 dropped`, `0 starved`, `0 send
errors`, ~100 ms total latency. No lag, no chop, by ear.

One transient left, not a defect: fast-forward (`FfStart`) drives the ring to
~150 frames and the throttle declines to write what the ring cannot fill rather
than padding silence. Output holds 48,137 frames/s through it and it recovers
within two 5 s windows.

Instrumentation (keep it — it's what produced every real finding): the ring
trace prints `N/target queued, N dropped, N starved, N core stalls` under
`SLOT_TRACE=1`, and with the throttle on the sink prints, every 5 s, the queue
floor in frames and ms, the pass count against its own elapsed time, periods
written with the frames/s derived from that same elapsed time, the max periods
a pass managed, the times a top-up stopped because the ring was short, empty
passes, send errors — and `MI_AO_QueryChnStat`'s total/free/busy, which is the
line that cracked this.

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
  `task device:find` sweeps for it, taking the subnet from `SLOT_DEVICE`.
  The build host is on **192.168.1.12/24, the same link as the handheld**
  (checked 2026-10-14 with `ip -4 route`); an earlier note here claimed it was
  on 10.200.0.0/24 behind a router, which was reading `docker0`. So a sweep of
  the local link is the right sweep after all — but FTP answering nowhere does
  *not* mean the device is off. `net-up.sh` is what starts FTP, and it only
  runs when `Apps > slot net` is launched; a powered-on handheld that has not
  run it looks exactly like an absent one. Check the WiFi is associated and
  run the app before concluding anything. It also writes the address into
  `slot-net.txt` on the card.
- **FTP comes up by itself on every boot.** The boot path is
  `.tmp_update/updater` on the card, not Allium -- Allium's own copy is kept
  beside it as `updater.allium-orig` -- and with `.slot-boot` present it
  backgrounds `System/net-up.sh` whenever `.slot-net` is present, then runs
  `launch_frontend.sh`. Both flags are on the card. So there is nothing to
  launch by hand: `Apps > slot net` is the Allium-era route and is not
  reachable from a slot boot. **Give it about a minute** -- the radio is flaky
  from cold and drops the 4-way handshake once or twice before COMPLETED at
  ~50 s, which is normal and not a wrong key. A sweep run before that answers
  nothing and looks exactly like an absent device; one was.
- If it is genuinely unreachable, put the SD card in the Mac
  (`dean@192.168.1.10`, `/Volumes/YELLOWSP`) and read/write it over ssh. Note
  that pulling the card truncates `slot-net.txt` mid-attempt, which reads as a
  failed association when it is only an interrupted log.

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
