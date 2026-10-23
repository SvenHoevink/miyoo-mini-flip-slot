# two-player, against an Anbernic

**Link play does not work on these handhelds, and the reason is the radio.**
Measured 2026-10-23 on a Mini Flip and a Mini Plus: the chip will not host an
AP, will not carry data peer-to-peer in ad-hoc, and through an access point
jitters by ten times a frame. The detail is below, under "hosting: answered".
The rest of this page is kept because it is still true about slot's link and
about what would be needed on a handheld that could.

slot has a real two-player link, and most of it is hardware-independent, so
the port gets it nearly for free. This page is what it is, what this device can
and cannot do with it, and how to try it.

**Status: not yet played end to end.** The card-side radio script is written
and tested against its contract, and the frame-budget arithmetic below is from
measurements on the device — but no game has been linked between two handhelds
yet. Everything here marked "expected" is a prediction, not a result.

## what the link actually is

Two handhelds, a private WiFi between them, and a TCP session carrying the
emulated link cable:

```
 Miyoo Mini Flip                         Anbernic RG SP
 ───────────────                         ──────────────
 slot                                    slot
   │  System/slotlink.sh link join         │  System/slotlink.sh link host
   ▼                                       ▼
 wlan0 ──── SSID "slotlink", WPA2 ──────── AP
 10.42.0.2                                 10.42.0.1
   │                                       │
   └────────── TCP :7211 ──────────────────┘
                mGBA serial data
```

The addresses and the port are compiled into slot (`HOST_ADDR` in
`crates/slot/src/link_start.rs`), so a card script's whole job is to make
`10.42.0.1` and `10.42.0.2` exist on the right two handhelds. That script is
the only device-specific part, and it is `System/slotlink.sh`.

## what this device can do

### GB and GBC: expected to work

slot's link session is **mGBA only** — `apply_link_options` in
`crates/slot/src/core.rs` returns early for any other core. On this CPU mGBA
runs a Game Boy in **8.26 ms** a frame, which against the backend's 8.2 ms and
a 16.86 ms period is tight but is the budget the port already holds today.

### GBA: expected to be too slow

mGBA has no GBA dynarec and interprets, at **14.2 ms** a frame here. With the
backend that is ~22 ms against a 16.86 ms period — about 45 fps, before any
link stalls. gpSP is the fast GBA core on this device (5.5 ms) but slot's link
does not use it, so there is no fast path for a GBA link.

`gpsp_serial` in the same file is a different thing and does **not** change
this: it tells gpSP which in-cart link hardware to emulate for a single-player
cart, not how to talk to another handheld.

So: **try this with Tetris or Pokémon Gold before trying it with a GBA game.**

### hosting: answered, and the answer is no (2026-10-23)

Tested on a Mini Flip and a Mini Plus, both rtl8188fu, with the radio driven
by hand rather than through the UI. The driver *claims* it can:

```
wpa_cli get_capability modes   ->  IBSS AP
wpa_cli get_capability channels ->  Mode[G] 1-14, Mode[B] 1-14   (no 5 GHz)
```

It cannot. AP mode was tried on wlan0 with both backends:

| | result |
|---|---|
| `-Dnl80211` | `DISCONNECTED` then `SCANNING` for twelve seconds; never beacons |
| `-Dwext` | `ioctl[SIOCSIWAP]: Operation not permitted`, then `SCANNING` |

Asked to host, the interface goes looking for networks instead. So upstream's
arrangement -- one handheld brings up an AP, the other joins it -- cannot work
here, and not for want of a second interface: the one radio will not do it.

### ad-hoc: forms, merges, and carries nothing

IBSS looked like the answer. It is symmetric, which suits two identical
handhelds better than an AP/station split, and the driver does bring it up:

```
0s: DISCONNECTED
1s: COMPLETED      bssid 02:11:87:6c:e1:5e  freq 2437  mode=IBSS
```

Two handhelds, started a few seconds apart with `ap_scan=1`, **find each other
and merge into one cell**: both report the same BSSID afterwards, and each
sees the other's cell in a scan. Addresses and routes come up correctly.

And then nothing crosses. Five pings each way, 100% loss, in both directions,
with static ARP entries in place so the broadcast ARP cannot be blamed:

```
Flip: bssid 02:11:87:2c:5d:4f  arp 10.42.0.2 -> 98:03:cf:9d:48:1a (static)
Plus: bssid 02:11:87:2c:5d:4f  arp 10.42.0.1 -> a8:b5:8e:a7:49:c0 (static)
both: 5 packets transmitted, 0 received
```

The driver associates in IBSS and does not carry data in it. Frame counters
say where it stops -- this is with power saving turned off *before* the cell
was joined, since in ad-hoc there is no AP to hold frames for a sleeping
radio, and with HT disabled in case the two ends were agreeing rates neither
could receive:

```
Flip:  before rx_pkts=2539 tx_pkts=134   after rx_pkts=2539 tx_pkts=134
Plus:  before rx_pkts=2601 tx_pkts=174   after rx_pkts=2601 tx_pkts=174
both:  same bssid, 5 packets transmitted by ping, 0 received
```

`tx_pkts` does not move. The packets are handed to the driver and never go
out. Not power save, not the receive path, not rates, not keys: the transmit
path in ad-hoc is not there.

Everything a script can reach has been tried -- mode, both driver backends,
`ap_scan`, power management, HT, open and CCMP cells, static ARP. Fixing this
means patching rtl8188fu's IBSS transmit path and building the module, for a
chip whose vendor shipped it stubbed. That is a driver project, not a
frontend one.

### over an access point: it works, and it is too slow

Both handhelds on the same house WiFi can reach each other -- so if two people
are in the same building with the same network, there is a path. The latency
is the problem:

| | min | avg | max |
|---|---|---|---|
| as shipped (`rtw_power_mgnt=2`) | 6.7 ms | 147.5 ms | 469.2 ms |
| power save off, both ends, re-associated | 7.1 ms | 74.5 ms | 221.3 ms |

A linked frame is **16.8 ms**. The floor is fast enough; the average is four
times over it and the spikes are thirteen times over. Turning the driver's
power saving off (`rtw_power_mgnt`, `rtw_ips_mode`) helps and does not fix it.

### so: not on this radio

Not for want of CPU -- in a GBA game this port uses about 6 ms of a 16.8 ms
frame, and GB is lighter still. The radio is the limit: it will not host, it
will not pass data peer-to-peer, and through an access point it jitters by ten
times a frame.

What would change the answer: a handheld whose WiFi driver does AP or a
working IBSS, or a wired path. Neither is these three.

## the frequency, which is the thing that will bite

Upstream's link meets on **5745 MHz**, which is 5 GHz. This radio is an
**rtl8188fu: 2.4 GHz only.** It cannot see that network at all.

Whichever handheld hosts chooses the channel, so:

| who hosts | what to do |
|---|---|
| **the Miyoo** | nothing. It hosts on 2437 MHz (channel 6) and the Anbernic's join scans every channel after its first attempt, so it finds it |
| **the Anbernic** | it must be told a 2.4 GHz channel, or the Miyoo never sees it: set `AGS_LINK_FREQ=2437` in its launch environment |

If a link fails with both ends apparently fine, this is the first thing to
check. Everything else about the two scripts agrees on purpose — the SSID
(`slotlink`) and passphrase (`slotlink0`) are deliberately kept at upstream's
defaults so an unmodified Anbernic pairs with this card. Don't change them on
one side only.

## trying it

1. **Probe first.** Apps → slot link probe, then read `slot-linkprobe.txt`.
   It tells you whether the Miyoo can host, which decides step 3.
2. **Same game, both handhelds.** A GB or GBC game to start with, for the
   budget reason above. Both need the cart seated.
3. **Pick who hosts** from the probe's verdict. If the Anbernic hosts, set
   `AGS_LINK_FREQ=2437` on it first.
4. **Start the link on the host, then the joiner.** The host waits 30 s for a
   peer (`HOST_BOUND`); the joiner reports "no host" and keeps waiting rather
   than erroring, so starting them in the wrong order is recoverable.
5. **In-game, link as the game does it** — the cable menu, the trade centre,
   whatever the cart wants. slot is standing in for the cable, not for the
   game's own menus.

## when it doesn't work

`System/slotlink.sh` appends to **`slot-link.txt`** at the card root, every
run, with each `wpa_state` change. That file is the first place to look.

| in the trace | what it means |
|---|---|
| `join: no host found` | nobody is hosting, or the host is on 5 GHz. See the table above |
| `supplicant would not start` | wrong driver flag. The script tries `nl80211` then `wext`; pin it with `SLOT_LINK_DRIVER=wext` |
| `host: AP never came up` | this radio will not do AP mode — use the join role and host from the Anbernic |
| `no wlan0` | the module is not loaded. Normally `warm` handles it via Allium's `wifi-on.sh` |

A link takes the radio for itself, so the handheld leaves your normal network
while it is up — `task deploy` and telnet stop working until the link ends.
`link down` puts the network back; if a crash skips it, a reboot will do.

Knobs, all optional, all read from the environment:
`SLOT_LINK_DRIVER`, `SLOT_LINK_FREQ`, `SLOT_LINK_SSID`, `SLOT_LINK_PSK`,
`SLOT_LINK_JOIN_S`, `SLOT_LINK_TRACE`.

## testing the script without a radio

```sh
task test:card
```

Runs `card/test-slotlink-miyoo.sh` under a real busybox, with every tool faked.
It checks the five subcommands, both addresses, the driver detection and —
hardest — that "nobody is hosting" exits **3** and a genuine fault does not,
because slot shows a patient waiting screen for 3 and a red error for anything
else.
