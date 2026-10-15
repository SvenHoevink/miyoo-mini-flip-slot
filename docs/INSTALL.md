# installing slot on a Miyoo Mini Flip

This is the short version. The [README](../README.md) is the development log and
explains *why*; this page is just what to do.

You need: the handheld, its SD card, a computer with a card reader, and a
`slot-miyoo-*.zip` from [Releases](https://github.com/deanmarano/slot-miyoo/releases)
(or `task release`, if you are building it yourself).

Nothing here reflashes the device, deletes anything, or replaces your launcher.
slot installs beside it as one more app.

## 1. back up the card

The stock firmware is particular and a known-good copy costs nothing. Copy the
whole card somewhere before you start. If you skip one step on this page, don't
let it be this one.

## 2. unzip into the card root

Put the card in your computer. The **card root** is the directory holding
`Roms/` and `Apps/` — the one the handheld sees as `/mnt/SDCARD`.

Unpack the zip so its contents land *in* that directory, not in a subfolder of
it. You should end up with `System/slot` on the card, not
`slot-miyoo-v0.1/System/slot`.

```sh
unzip -d /media/you/MIYOO slot-miyoo-v0.1-flip.zip
sync
```

It merges: `Apps/` and `App/` gain slot's entries, `System/` gains the binary
and the launch scripts, and the content root slot expects is created empty.
Nothing already on the card is removed.

Then eject the card properly — `sync` above, and unmount before pulling it.

## 3. put the card back and find slot

Boot the handheld. slot appears under **Apps → slot**.

**If it isn't there, reboot once more.** The launcher caches its app list, and
the first boot after adding files often doesn't show them.

## 4. games and the GBA BIOS

ROMs go **unzipped** in the folders the zip created:

| system | folder |
|---|---|
| Game Boy | `Games/GB` |
| Game Boy Color | `Games/GBC` |
| Game Boy Advance | `Games/GBA` |

These are slot's own folders and are **not** the `Roms/` your launcher uses —
slot keeps its library separate. Saves and save states land beside them in
`Saves/` and `States/`.

GBA also needs a BIOS at **`BIOS/gba_bios.bin`**. Without it GBA games will not
start. It is not included here and you have to supply it yourself.

## 5. the controls worth knowing

| gesture | what it does |
|---|---|
| **hold MENU ~1 s** | **eject the cart, back to the shelf** |
| tap MENU | quick menu — brightness and volume, on the shelf only |
| double-tap MENU | polaroids |
| hold POWER ~1 s | power menu |
| **START on the shelf, GBA cart selected** | core picker: left = mGBA, right = **gpSP** |

**For GBA, pick gpSP.** mGBA interprets on this CPU and runs at roughly half
speed; gpSP has an ARM JIT and holds the frame budget. The choice is per game.

slot boots straight back into whatever cart was last in the slot — that is
deliberate, not a fault. Eject to get the shelf back.

## if something is wrong

slot writes **`slot.log`** to the card root. Read it first; it says what it was
doing when it stopped. Then:

| symptom | likely cause |
|---|---|
| no slot in the app list | launcher cache — reboot again |
| GBA games won't start | no `BIOS/gba_bios.bin` |
| a GBA game runs at half speed | mGBA is selected; switch to gpSP |
| MENU draws a hotkey bar over the game | that is Allium's overlay, not slot. Known, see the README |
| nothing on screen at all | check `slot.log`, and that `System/slot` really is on the card |

There is no battery indicator on this device, and the lid does nothing yet.
Both are known and listed in the README.

## going further

- [working over the network](../README.md#working-over-the-network-instead-of-moving-the-card)
  — WiFi, telnet and FTP, so new builds don't need the card moved.
- [booting straight into slot](../README.md#booting-straight-into-slot-without-allium)
  — skip Allium entirely.
- [two-player link](link.md) — against another slot handheld.

slot is by [Brandon Kowalski](https://github.com/BrandonKowalski/slot). This is
an unofficial port; please don't send slot's issue tracker Miyoo bugs.
