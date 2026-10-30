# installing slot on a clean SD card -- Miyoo Mini Flip

From an empty microSD card to playing Game Boy, GBA, NES and SNES games in
slot, step by step. [INSTALL.md](INSTALL.md) is the general page, for a card
that already has a launcher on it; this one assumes you are starting over.

> **NES and SNES are new and have not been played on a handheld yet.** They
> build and the cores load, but nobody has timed a SNES game on the Flip. If
> one runs slow, that is worth reporting -- see
> [notes/nes-snes.md](../notes/nes-snes.md).

## what you need

- the Miyoo Mini Flip and its USB-C charger
- a microSD card -- anything from 8 GB up works; slot itself takes about 15 MB
- a computer with a card reader
- the **`slot-miyoo-*.zip`** from this repository's
  [Releases](https://github.com/SvenHoevink/miyoo-mini-flip-slot/releases), or
  one you built with `task release` (see the [README](../README.md#build-it))
- your own game files -- none are included

## 1. format the card as FAT32

The Flip reads **FAT32 only**. exFAT, which most cards over 32 GB come
formatted as, does not work.

| on | how |
|---|---|
| Windows, card up to 32 GB | right-click the card in Explorer → Format → File system **FAT32** |
| Windows, card over 32 GB | Windows' own tool will not offer FAT32 at that size; use a FAT32 formatter such as *guiformat* |
| macOS | Disk Utility → View → Show All Devices → select the **card itself** → Erase → Format **MS-DOS (FAT)**, Scheme **Master Boot Record** |
| Linux | `sudo mkfs.vfat -F 32 -n MIYOO /dev/sdX1` -- check `sdX` with `lsblk` first; this erases it |

Formatting erases everything on the card. If it had anything you want, copy
it off first.

## 2. (only if needed) bring the handheld's firmware up to date

The Flip keeps its operating system in its own memory, not on the card, so a
card holding nothing but slot boots it fine. **You only need this step if the
handheld's firmware is old** -- slot is tested on stock build **202510011046**;
check yours under Settings on the handheld.

1. Get the Mini Flip firmware from
   [lomiyoo's firmware page](https://lomiyoo.com/pages/firmware).
2. Put **`miyoo285_fw.img`** in the root of the card.
3. Unzip the inner `miyoo285.zip` into a folder called **`miyoo285/`** on the
   card -- not loose in the root, or slot's entry gets buried among the
   firmware's own files.
4. Put the card in the Flip, **plug in the charger first**, then switch it on.
   It updates itself and reboots.
5. If no rocket appears: power off, hold **MENU**, and plug the charger in
   while still holding it.

The update writes the handheld's memory and leaves the card alone, so you can
do this before or after step 3.

## 3. unzip slot into the root of the card

Unzip the release so its contents land **directly in the root of the card**,
not in a folder of their own. You should see `System/slot` on the card -- not
`slot-miyoo-v0.3.0/System/slot`.

```sh
# Linux / macOS, with the card mounted at /media/you/MIYOO (or /Volumes/MIYOO)
unzip -d /media/you/MIYOO slot-miyoo-*.zip
sync
```

On Windows, open the zip, select everything inside it, and drag it onto the
card.

The card should now look like this:

```
App/Slot/            launcher entry for stock firmware and Onion
Apps/slot.pak/       launcher entry for Allium
System/              slot itself, the four emulator cores, launch scripts, licences
BIOS/                the GBA BIOS goes here
Games/GB/  Games/GBC/  Games/GBA/  Games/NES/  Games/SNES/
Labels/    Saves/    States/       one folder per system, same names
Bezels/  Config/  Logs/  Wallpapers/
```

## 4. add your games

**Yes, there are NES and SNES folders.** The zip creates them empty, and slot
makes them again on start-up if they go missing:

| system | folder | files |
|---|---|---|
| Game Boy | `Games/GB` | `.gb` |
| Game Boy Color | `Games/GBC` | `.gbc`, `.gb` |
| Game Boy Advance | `Games/GBA` | `.gba` |
| NES | **`Games/NES`** | `.nes` (also `.unf`, `.unif`) |
| Super Nintendo | **`Games/SNES`** | `.sfc`, `.smc` |

- ROMs go in **unzipped**. A `.zip` is not read.
- These are **slot's own folders**. The stock launcher's `Roms/` folder is
  not used; slot keeps its library separate.
- **GBA needs a BIOS** at `BIOS/gba_bios.bin` -- without it GBA games will not
  start. Supply your own. GB, GBC, NES and SNES need none.
- **Cart labels are optional:** a PNG in `Labels/<system>/` named exactly like
  the ROM (`Labels/SNES/Chrono Trigger (USA).png` for
  `Games/SNES/Chrono Trigger (USA).sfc`). Without one, slot prints the game's
  name on a coloured label.
- Saves land in `Saves/<system>/` and save states in `States/<system>/`.

## 5. eject, boot, and start slot

1. Eject the card properly (`sync` and unmount, or "Eject" on Windows/macOS).
2. Put it in the Flip and switch it on.
3. Open **App → slot**.

**If slot is not in the list, reboot once more** -- the launcher caches its app
list, and the first boot after adding files often misses new ones.

## 6. the controls

| | |
|---|---|
| **A** on the shelf | insert the cart and play |
| **hold MENU ~1 s** | **eject the cart, back to the shelf** |
| tap MENU in a game | the in-game menu: screen, states, controls |
| double-tap MENU in a game | straight to save states |
| hold POWER ~1 s | power menu |
| L1 / R1 in a GB, GBC or NES game | stretch to the screen's height / actual size |
| START on the shelf, GBA cart | core picker -- gpSP is the default for GBA; mGBA is slower here |

On the **SNES**, L1/R1 are the game's L and R, and X/Y are its X and Y.
NES and SNES games are drawn at 2x (512x448) by default.

slot starts back up in whatever cart was last in the slot. That is on
purpose: eject (hold MENU) to get back to the shelf.

## 7. optional: boot straight into slot

To have the Flip start in slot instead of the stock menu, copy
`System/autoboot/runtime.sh` from the card to **`.tmp_update/runtime.sh`** (make
the `.tmp_update` folder in the card root). To undo it, delete that file with
the card in a computer.

**Only on a card running stock firmware.** Allium and Onion boot through the
same file, and this would replace theirs.

## if something is wrong

slot writes **`Logs/slot.log`** on the card; read it first.

| symptom | likely cause |
|---|---|
| the Flip does not boot from the card | the card is exFAT -- reformat it as FAT32 (step 1) |
| no slot in the app list | reboot once more; check `App/Slot/` is in the root, not inside a folder |
| a NES or SNES game does not show up | it is zipped, or in the wrong folder, or has another extension |
| GBA games will not start | no `BIOS/gba_bios.bin` |
| a GBA game runs at half speed | mGBA was picked for it; START on the shelf, pick gpSP |
| a SNES game runs slow | not measured yet on this CPU -- please report which game |
| nothing on screen at all | check `Logs/slot.log`, and that `System/slot` is on the card |
