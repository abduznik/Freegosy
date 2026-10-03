# Save interoperability between emulators and RomM clients

Freegosy syncs game saves through RomM, and so do other RomM clients (for
example [Argosy](https://github.com/rommapp/argosy-launcher) on Android). The
same game can be played with different emulators on different machines. This
page records, per platform, how each emulator stores its saves, whether those
files are the same format, and what happens when a save made in one place is
played in another. It's the reference for making saves move between
emulators, one platform at a time.

Each platform section follows the same outline: **formats**, **how each
emulator names its files**, **the interop matrix**, **gaps and
recommendations**. Findings are marked **verified** (checked against real
files or by hand) or **from source** (read in the emulator's code).

Platforms covered so far: [PlayStation (PS1)](#playstation-ps1),
[PlayStation 2 (PS2)](#playstation-2-ps2), [Nintendo 64](#nintendo-64).

## How Freegosy moves a game save

For reference when reading the matrices:

- **Upload**: the emulator's save strategy (`lib/core/save/strategies/`) lists
  the files for the game (`getSaveFilesWithScreenshots`). One file is uploaded
  under its own name; several go up as one zip. Game saves are tagged on RomM
  with the emulator that made them: the RetroArch core without `_libretro`
  (e.g. `pcsx_rearmed`, as RomM's web player and Argosy name it), otherwise the
  emulator (e.g. `pcsx2`, `duckstation`), in the `freegosy` slot.
- **Download**: Freegosy takes RomM's **newest save for the game, whoever
  uploaded it** (`RommService.getLatestSave`; neither the tag nor the slot is
  checked). A save RetroArch compressed (RZIP, "SaveRAM compression") is
  unpacked, and so is one about to be uploaded. The save is then converted
  to the format the emulator on this machine reads, when it's in another
  emulator's format (`lib/core/save/formats/`, `convertSave`: source by the
  save's RomM tag, else by its files; target by this machine's tag), and
  handed to that emulator's strategy (`restoreSave`), which decides where it
  goes.
- So for a save to cross emulators, the **receiving** strategy must recognise
  the uploaded file (name and format) and write it where its emulator reads it.
- **Choosing a save** (the play screen and the game page's Saves tab): every
  save is listed, from this PC (each installed emulator's own, and backups)
  and RomM (live, nothing downloaded). For the emulator picked, each is
  marked by `fitFor` (`lib/core/save/catalog/`): its own, converted (its
  RomM tag, or by content, maps to another format of the same system), unknown
  maker (restored as it is), or unusable (another core's local save, another
  emulator's backup, no format to convert into). The chosen save is put in
  place before the game starts (`PlayPreparer`: the current save is backed up
  first; a failure stops the launch), and after play the save is uploaded
  unless it is still the content RomM has (`markSaveSynced` / `saveIsSynced`).
  Replacing a save on this PC that RomM doesn't have (never uploaded, e.g.
  played offline) always asks first (`PlayPrompt.notOnRomm`), whatever the
  times. A save on a memory card shared by every game (PCSX2, DuckStation,
  RetroArch's PS1/PS2 cores) is dated by the card, which any game changes:
  with a usable RomM save, it counts with its RomM copy's time, or not at all
  when RomM has no copy (`SaveEntry.sharedFile`). With RetroArch sorting saves
  by core, each core's own save for the game is a row of its own. The Saves
  tab restores into the game's emulator when the save fits it, else into the
  emulator that made it.
- **Same save or changed?** RomM keeps a `content_hash` for every save
  (`backend/handler/filesystem/assets_handler.py`): the md5 of a plain file;
  for a zip, the md5 of its files' sorted `<name>:<md5>` lines (folders
  skipped). Freegosy computes the same hash for the save on this PC
  (`lib/core/save/romm_content_hash.dart`, `SaveSyncService.rommHashOfLocal`:
  the files a push would upload, RZIP unpacked, a folder or several files as
  the zip a push builds). A push skips an upload whose hash is the last
  upload's; a pull downloads nothing when RomM's newest save has the hash of
  the save on this PC; the play screen marks such a RomM save "on this PC"
  and doesn't preselect it over the local one. Bundle zips carry no time in
  `freegosy_sync.txt` (only `contentHash`, and `savePath` for Windows games),
  so an unchanged save keeps its hash. Without a `content_hash` (older RomM,
  or zips RomM hashed before its fix), Freegosy falls back to its own
  fingerprint of the save it last synced.
- **Same name, two emulators**: RetroArch tags a save with its bare core
  name, which for `mgba`, `melonds`, `pcsx2`, `ppsspp`, `azahar`, `flycast`
  and `mame` is also a standalone emulator's id. RomM can't tell which made
  it, so such a RomM save fits both (`fitFor`).
- **Raw systems** (`lib/core/save/formats/raw_save_systems.dart`): emulators
  whose saves are the same bytes, named differently (`.sav`, `.srm`); each
  save strategy already names a save the way its emulator reads it, so the
  save is used as it is (`SaveAsIs`). One line per system:
  - NDS: melonDS ↔ RetroArch's melonDS and melonDS DS cores.

  Add a line only after loading a real save from each emulator in the other.
  Not verified yet: mGBA ↔ gambatte/SameBoy (GB/GBC, RTC data differs),
  mGBA ↔ VBA-Next/gpSP (GBA, save sizes differ), ares ↔ RetroArch for NES and
  SNES (ares names saves by memory type: `.ram`, `.eeprom`, …).
- **One save operation at a time** (`lib/core/save/strategy_lock.dart`): the
  save strategies are shared by every game and hold one game's setup (the
  RetroArch core, Eden's folder), so push, pull, restore, the backups and the
  save list run under one lock (`SaveSyncService.withStrategy`).
- **Backups** record the emulator and, for RetroArch, the core whose folder
  they copied, and go back only there; older RetroArch backups without a
  core go back into RetroArch with any core. A backup of a shared memory card
  puts back only this game's saves (`SaveStrategy.restoreBackup`). A session
  that left the save as it was adds no backup (same content hash of the files
  as the newest backup, file times ignored); 8 are kept per game.

## PlayStation (PS1)

### Format

A PS1 memory card is a **raw 128 KB image** (131,072 bytes): 16 blocks of 8 KB.
Block 0 starts with `MC` and holds a 15-entry directory, one 128-byte entry per
data block: allocation state, size, the next block of the save, the save's
file name and an XOR checksum. The file name starts with a region prefix and
the game's product code, e.g. `BESLES-02605-SETTING` (see
`lib/core/save/ps1_memory_card.dart`).

**DuckStation's `.mcd` and a RetroArch PS1 core's `.srm` are the same format.**
Verified: PCSX-ReARMed's `Crash Bandicoot (Europe).srm` and DuckStation's
`Colin McRae Rally 2.0 (Europe) (En,Fr,De,Es,It)_1.mcd` are both 131,072 bytes
with the same header and directory layout. The only difference is cosmetic:
PCSX-ReARMed fills free blocks with `00`, DuckStation with `FF`. SwanStation
(the libretro port of DuckStation) says so in its own option text: `.srm` and
per-game `.mcd` saves "have internally identical formats and can be converted
between one another via renaming the extension and removing/adding the slot
number (_1)".

### How each emulator names its cards

`<content>` is the file the emulator loaded without its extension: the ROM, or
the `.m3u` of a multi-disc game.

**DuckStation (standalone)**: set by *Memory Card Type* per port
(`[MemoryCards] CardNType` in `settings.ini`, overridable per game in
`gamesettings/<SERIAL>.ini`), in the `memcards` folder. Verified.

| Type (`CardNType`) | File |
|---|---|
| Separate Card Per Game (Serial) (`PerGame`) | `<serial>_N.mcd`, e.g. `SLES-02605_1.mcd` |
| Separate Card Per Game (Title) (`PerGameTitle`, the default for port 1) | `<title>_N.mcd`; the title is `saveName` (else `name`) from DuckStation's own `resources/gamedb.yaml`, or the disc set's from `discsets.yaml` for a multi-disc game when *Use Single Card For Multi-Disc Games* (`UsePlaylistTitle`) is on, unless a card under the disc's own title already exists. Unsafe characters become `_` per platform (Windows: `/ \ < > : " | ? *` and a trailing `.`; Linux: `/ *`; macOS: `/ * :`) |
| Separate Card Per Game (File Title) (`PerGameFileTitle`) | `<content>_N.mcd` |
| Shared Between All Games (`Shared`) | `shared_card_N.mcd` (or `CardNPath`) |
| No Memory Card / Non-Persistent | none |

**RetroArch PS1 cores**: in RetroArch's save folder (per core, e.g.
`saves/PCSX-ReARMed/`, when *Sort Saves into Folders by Core* is on). From
source, plus the verified files above.

| Core | Default (card 1) | Other settings |
|---|---|---|
| PCSX-ReARMed | `<content>.srm` (`pcsx_rearmed_memcard1 = libretro`) | `serial`: `<serial>_1.mcd` (the same name as DuckStation's Serial type); `shared`: `pcsx-card1.mcd`. Card 2 defaults to **shared**, `pcsx-card2.mcd` |
| Beetle / Mednafen PSX (+HW) | `<content>.srm` (*Memory Card 0 Method* = libretro) | Mednafen method: `<content>.0.mcr`; card 2 (when enabled): `<content>.1.mcr`; shared cards: `mednafen_psx_libretro_shared.N.mcr` |
| SwanStation | `<content>.srm` (`Libretro`) | By game code `<code>_N.mcd`; by title `<title>_N.mcd`; shared `duckstation_shared_card_N.mcd` |

With default settings **every RetroArch PS1 core uses `<content>.srm`**.

**Argosy (Android)**: from source (`SavePathResolver.kt`, `SaveDownloader.kt`,
`SavePathRegistry.kt`).

- PS1 runs mostly through RetroArch or Argosy's built-in libretro cores: the
  card is the game's `.srm`, and uploads go to RomM as `<content>.srm`.
- Standalone DuckStation on Android is registered but **disabled** (Android
  DuckStation writes its files unreadable to other apps). When enabled it only
  looks for `<content>_1.mcd` (File Title, port 1).
- On download Argosy writes the bytes to **its own** local path whatever the
  file is called on RomM: a PC-made `.mcd` lands as the game's `.srm`.

### Interop matrix

"verified" means checked by hand with real emulators and RomM: a DuckStation
save played on in RetroArch (PCSX-ReARMed) and back, both through Freegosy.
The other rows follow from the formats and the clients' code.

| Made in → played in | Result | Why |
|---|---|---|
| DuckStation → DuckStation | ✅ | The card is restored under the name this PC's Memory Card Type uses; a shared card gets only this game's saves merged in. |
| DuckStation → RetroArch (Freegosy) | ✅ verified | DuckStation uploads its port-1 card as `<content>.srm` (see below), which is the name the RetroArch core opens. |
| DuckStation → Argosy | ✅ | Argosy writes the bytes to its own `<content>.srm`. ⚠️ Two per-game ports upload a zip; not checked how Argosy handles that. |
| RetroArch (`.srm`) → DuckStation | ✅ verified | A 128 KB `.srm` with the `MC` header is taken as the port-1 card. |
| RetroArch ↔ RetroArch, RetroArch ↔ Argosy | ✅ | The same `<content>.srm` everywhere. |
| Argosy → DuckStation | ✅ | As RetroArch → DuckStation. |
| Chosen on the play screen: RetroArch card → DuckStation, or DuckStation card → RetroArch | ✅ | Shown as converted (`ps1.retroarch_srm` ↔ `ps1.mcd`): the same 128 KB card, under the name each one reads (`<stem>_1.mcd` for DuckStation, port 1). |
| Older `.mcd` uploads (DuckStation before the `.srm` name, or other clients' `<serial>_1.mcd`) → RetroArch (Freegosy) | ✅ | The RetroArch strategy restores a port-1 PS1 card (`.mcd`, 128 KB, `MC` header) as the game's `<content>.srm`. A card for another port keeps its name, which the core doesn't open by default. An old whole shared card (`shared_card_1.mcd`) lands with every game's saves on it; the game only sees its own. |
| A RetroArch core set to serial / shared / Mednafen cards → anywhere | ⚠️ | The RetroArch strategy only finds `<content>.srm`-style files, so those cards are never uploaded. |

### Gaps and recommendations

1. **Done: DuckStation uploads its port-1 card as `<content>.srm`.** The same
   bytes under the name every RetroArch core, Argosy and RomM's in-browser
   player expect. Other ports keep `<name>_N.mcd` (in a zip with the `.srm`).
   DuckStation's own restore accepts both names.
2. **Done: RetroArch restores a PS1 `.mcd` as `<content>.srm`**, when it is a
   128 KB `MC` card for port 1 (`_1.mcd`, `mcd1` / `card1`, `shared_card_1`,
   or no port in the name), alone or in a zip
   (`lib/core/save/formats/ps1_card_formats.dart`). This covers `.mcd` saves
   already on RomM and other clients' serial/title cards.
3. **Done (RetroArch, every platform): a stricter save match** (#116). A save
   belongs to the game when it is the ROM name followed by an extension, or
   else has the same title (every word, numbers included; case, punctuation,
   word order and `(…)`/`[…]` tags ignored). Before, one shared word of 3+
   letters was enough, so "Crash Bandicoot 2" could pick up
   `Crash Bandicoot (Europe).srm`.
4. **Later (RetroArch): the cores' own card modes** (serial, shared, `.mcr`).
   Rare, since every core defaults to `.srm`.
5. **Noted: RetroArch's core folder.** The strategy picks the save folder from
   the platform's default core or the per-game core mapping; a game actually
   played with another core keeps its card in that core's folder.
6. **Unverified**: whether RomM's in-browser player (EmulatorJS, RetroArch
   cores) loads a PS1 `.srm` uploaded this way; how Argosy handles a zip of
   two PS1 cards.

### Sources

- DuckStation: this repository's findings in `docs/save-state-sync.md` and the
  DuckStation strategy; files of a real install (`settings.ini`,
  `resources/gamedb.yaml`, `discsets.yaml`, `memcards/`).
- [libretro/pcsx_rearmed](https://github.com/libretro/pcsx_rearmed):
  `frontend/libretro.c` (`load_memcards`), `frontend/libretro_core_options.h`.
- [libretro/beetle-psx-libretro](https://github.com/libretro/beetle-psx-libretro):
  `libretro.c` (memcard options, `MDFN_MakeFName` / `MDFNMKF_SAV`).
- [libretro/swanstation](https://github.com/libretro/swanstation):
  `src/libretro/libretro_core_options.h`, `libretro_host_interface.cpp`.
- [rommapp/argosy-launcher](https://github.com/rommapp/argosy-launcher):
  `SavePathResolver.kt`, `SaveDownloader.kt`, `SavePathRegistry.kt`.

## PlayStation 2 (PS2)

### Format

PS2 memory cards come in two shapes that hold the same saves.

**File card**: an **8,650,752-byte image** (16,384 pages of 512 data bytes +
16 ECC bytes), starting with the superblock `Sony PS2 Memory Card Format
1.2.0.0`. Verified: PCSX2's `Mcd001.ps2` and LRPS2's
`system/pcsx2/memcards/Mcd001.ps2` on a real install are both this. Inside is
a FAT-style file system: each save is a top-level **directory** named
`<region prefix><serial><suffix>`, e.g. `BASLUS-20502` or
`BASLUS-21026-PROFILE` (`BA` = US, `BE` = Europe, `BI` = Japan/Asia). One card
holds every game's saves. Unlike a PS1 card there is no simple block list:
moving one game's saves in or out means reading and writing that file system
(clusters, FAT, directory entries, ECC).

**PCSX2 folder card**: a host **directory** with the card's name (e.g.
`memcards/Mcd001.ps2/`), holding an 8 KB `_pcsx2_superblock` and **one folder
per save**, named exactly like the save's directory on a file card. Each
folder holds that save's files plus a `_pcsx2_index` (PCSX2's record of
timestamps, attributes and order). Verified on a real install. With
`McdFolderAutoManage = true` (the default) PCSX2 shows the running game only
its own folders. PCSX2's Memory Cards settings can convert a card between
the two types.

**Play!**: each card is a plain host directory (`vfs/mc0`, `vfs/mc1`) with one
folder per save and no PCSX2 metadata. From source.

So a save folder of a folder card, a save directory of a file card, and a
save folder of a Play! card are the **same files**; only the container
differs.

### How each emulator names its cards

**PCSX2 (standalone)**: in `memcards/` (next to the exe in portable mode),
set by `[MemoryCards] SlotN_Filename` in `inis/PCSX2.ini`, overridable per
game in `gamesettings/`. Verified.

| Slot | Default | Notes |
|---|---|---|
| 1 | `Mcd001.ps2` | File or folder card under the same name; PCSX2 creates a **file** card by default. |
| 2 | `Mcd002.ps2` | An empty filename means no card in slot 2. |
| Multitap | `Mcd-MultitapN-SlotNN.ps2` | Off by default. |

Every game shares the same card unless a per-game setting points it at
another one.

**RetroArch PS2 cores**: from source, plus the verified files above.

| Core | Default | Other setting |
|---|---|---|
| LRPS2 (`pcsx2_libretro`, library name **`LRPS2`**) | *Shared Memory Cards* on: **file** cards `system/pcsx2/memcards/Mcd001.ps2` and `Mcd002.ps2`, shared by every game, **outside the save folder** | Off: `<content>.ps2` in RetroArch's save folder (`saves/LRPS2/` when *Sort Saves into Folders by Core* is on); slot 2 is disabled |
| Play! (`play_libretro`) | Directory cards `vfs/mc0` and `vfs/mc1` under the core's data path | — |

**Argosy (Android)**: from source (`PlatformSaveHandlerRegistry.kt`,
`SavePathRegistry.kt`).

- PS2 only through the Android PCSX2 forks (NetherSX2, AetherSX2, PCSX2),
  in **folder card** mode, in their `files/memcards` folder. File cards are
  not handled.
- **Upload**: a zip of **only this game's save folders**, rooted at the
  folders themselves (e.g. `BASLUS-20502/…`).
- **Download**: accepts that shape and a card-rooted zip, extracting only this
  game's folders into the card. It refuses when several cards hold the game.

### What Freegosy does today

- **PCSX2, folder card**: uploads only this game's save folders (the same
  shape as Argosy). Restore accepts `Mcd00N.ps2/…` bundles, superblock cards
  from other clients and bare save folders, and writes them into the first
  local folder card (or `Mcd001.ps2`). A whole file card from RomM has this
  game's saves taken off it and written in as folders.
- **PCSX2, file card**: uploads only this game's saves, taken off the card
  as save folders (local backups keep the whole card). A pull accepts save
  folders, whole folder cards and whole file cards, and merges only this
  game's saves into the card that holds them, after a `.bak`; the pull
  finishes before PCSX2 starts. Before, the whole 8 MB card went up as this
  game's save, and restoring it on another PC rolled back every other game
  on it.
- **RetroArch, PS2 (LRPS2)**: reads LRPS2's cards (the shared ones in the
  system folder, or the game's own with *Shared Memory Cards* off) and
  uploads only this game's save folders, found by its serial. A pull accepts
  save folders, whole folder cards and whole file cards, and merges only this
  game's saves into the card that holds them, after a `.bak`. Before this, the
  strategy looked in a `PCSX2` save folder that doesn't exist, so nothing was
  uploaded, and restores could land in another core's folder (seen on a real
  install: PS2 cards in `saves/Mupen64Plus-Next/`; fixed in #119).

### Interop matrix

| Made in → played in | Result | Why |
|---|---|---|
| PCSX2 folder card ↔ PCSX2 folder card | ✅ | Only this game's folders move. |
| PCSX2 file card ↔ PCSX2 file card | ✅ | Only this game's save folders move; other games on the card stay. |
| PCSX2 folder card ↔ PCSX2 file card (different PCs) | ✅ | Both upload save folders; a file card takes them onto the card, a folder card as folders (tested file → folder → file). A folder card receiving them gets no `_pcsx2_index`, which PCSX2 accepts (see gap 6). |
| PCSX2 folder card ↔ Argosy | ✅ verified | Both sides upload and restore this game's save folders; checked by hand both ways. |
| PCSX2 file card ↔ Argosy | ✅ | From code: the file card's save folders go into Argosy's folder card, and Argosy's save folders onto the file card. |
| RetroArch (LRPS2) ↔ RetroArch (LRPS2) | ✅ | Only this game's save folders move; checked on a copy of a real card (other games' saves unchanged, mymcplus finds no errors). Not yet verified in the app by hand. |
| PCSX2 folder card → RetroArch (LRPS2) | ✅ | From code: the game's save folders are merged into LRPS2's card; PCSX2's `_pcsx2_index` files are left out. |
| PCSX2 file card → RetroArch (LRPS2) | ✅ | From code: only this game's saves are taken from the whole uploaded card. |
| RetroArch (LRPS2) → PCSX2 folder card | ✅ | From code: the save folders land in the folder card, without a `_pcsx2_index`, which PCSX2 accepts (see gap 6). |
| RetroArch (LRPS2) → PCSX2 file card | ✅ | The save folders are merged into PCSX2's file card. |
| RetroArch (LRPS2) ↔ Argosy | ✅ | From code: both sides move this game's save folders. |
| Anything ↔ Play! | ❌ | Not supported by Freegosy. |

### Gaps and recommendations

1. **Done (RetroArch, every platform): the "newest core folder" fallback**
   (#119). Core folders use each core's `library_name` (`LRPS2` for PS2),
   and a first restore goes to the game's own core folder.
2. **Done (RetroArch, PS2): LRPS2's memory cards.** The strategy reads the
   shared cards in `system/pcsx2/memcards/` (or the game's own
   `<content>.ps2` with *Shared Memory Cards* off) and syncs only this game's
   save folders, merging them back without touching other games' saves.
3. **Done: a PS2 file-card reader/writer** (`Ps2MemoryCard`): reads a file
   card's file system, extracts one game's save directories and writes them
   into another card, keeping everything else byte for byte. Checked against
   mymcplus, an independent implementation.
4. **Done (PCSX2): file cards** sync this game's save folders instead of the
   whole card, and whole-card uploads land in folder cards as folders, which
   closes the folder card ↔ file card gap. With this every PS2 client
   Freegosy knows exchanges saves in one shape: the game's save folders.
5. **Later: Play!**: its directory cards hold the same save folders, so it
   would reuse the same shape.
6. **Verified**: PCSX2 folder card ↔ Argosy, by hand both ways. A save folder
   without its `_pcsx2_index` (file card and LRPS2 uploads have none) is fine
   from source: PCSX2's `MemoryCardFolder.cpp` supports "legacy folder
   memcards without the index file", taking the files' times from the host
   and listing them in directory order.

### Sources

- PCSX2: files of a real install (`inis/PCSX2.ini`, `memcards/Mcd001.ps2/`)
  and the PCSX2 strategy (`lib/core/save/strategies/pcsx2_save_strategy.dart`).
- [PCSX2/pcsx2](https://github.com/PCSX2/pcsx2):
  `pcsx2/SIO/Memcard/MemoryCardFolder.cpp` (folder cards, `_pcsx2_index`).
- [libretro/ps2](https://github.com/libretro/ps2) (LRPS2):
  `libretro/main.cpp` (`retro_load_game`, `library_name`),
  `libretro/libretro_core_options.h` (`pcsx2_shared_memory_cards`),
  `pcsx2/VMManager.cpp` (`LoadSettings`); a real RetroArch install
  (`system/pcsx2/memcards/`).
- [jpd002/Play-](https://github.com/jpd002/Play-): `Source/PS2VM.cpp`
  (`PREF_PS2_MC0_DIRECTORY`).
- [rommapp/argosy-launcher](https://github.com/rommapp/argosy-launcher):
  `PlatformSaveHandlerRegistry.kt` (`Ps2FolderHandler`),
  `SavePathRegistry.kt`.

## Nintendo 64

### Format

**From source.** RetroArch's N64 cores (Mupen64Plus-Next, ParaLLEl N64,
Mupen64Plus) keep one `<content>.srm` of 0x48800 bytes
(`save_memory_data` in `libretro/libretro_memory.h`): EEPROM (0x800),
four controller paks (4 × 0x8000), SRAM (0x8000), FlashRAM (0x20000).
SRAM and FlashRAM are stored as host-order 32-bit words
(`mem[addr ^ S8]`), so byte-reversed per word on a PC; EEPROM and paks are
in the N64's order. Unused parts are 0xFF, unused paks formatted
(`format_mempak`). ParaLLEl appends a 64DD disk area for 64DD games.

ares keeps one file per part the game uses, `<rom>.eeprom` (512 or 2048
bytes), `.ram`, `.flash`, big-endian (`ares/n64/memory/msb/writable.hpp`);
controller paks are separate files Freegosy doesn't sync.

### Interop matrix

| Made in → played in | Result | Why |
|---|---|---|
| RetroArch core ↔ RetroArch core, RomM's player, Argosy's RetroArch | ✅ | The same `.srm`. |
| RetroArch ↔ ares (Freegosy) | ❌ | Not converted: Freegosy's save formats cover raw saves and memory cards only. A save from the other emulator is shown as one that can't be used. |
| Project64, Mupen64Plus FZ (Android) → anywhere | ❌ | Their files aren't decoded. |

N64 saves move only between RetroArch's N64 cores (one format). Freegosy
converted between RetroArch and ares for a while; that code is on the
`feat/n64-save-conversion` branch of the fork, with the format notes above.

### Sources

- [libretro/mupen64plus-libretro-nx](https://github.com/libretro/mupen64plus-libretro-nx)
  (4bc73fb): `libretro/libretro_memory.h`, `libretro/libretro.c`
  (`format_saved_memory`), `mupen64plus-core/src/device/cart/{sram,flashram,eeprom}.c`,
  `device/controllers/paks/mempak.c`.
- [libretro/parallel-n64](https://github.com/libretro/parallel-n64) (0bd516e):
  `libretro/libretro_memory.h`, `libretro/libretro.c` (`retro_get_memory_size`).
- [ares-emulator/ares](https://github.com/ares-emulator/ares) (4cb8d92):
  `ares/n64/cartridge/cartridge.cpp`, `ares/n64/memory/msb/writable.hpp`,
  `mia/medium/nintendo-64.cpp`.
- [libretro/RetroArch](https://github.com/libretro/RetroArch) (b6f4143):
  `save.c` (`content_load_ram_file`: a shorter `.srm` is copied over the
  core's formatted memory).
