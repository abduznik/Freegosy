# Moving save sync to argosy-sigil: plan

Status: **plan only, nothing implemented.** Facts below come from the
[argosy-sigil](https://github.com/rommapp/argosy-sigil) README and its
`docs/sync.md` / `include/sigil.h` (checked October 2026) and from this repo.
Things not yet checked against real files are marked **to verify**.

## What sigil is

A C library (pre-1.0, no tagged release; its README tells consumers to pin a
commit) that, for one game and one emulator:

- reads the game's own title id out of the ROM (`sigil_extract_from_path`),
- finds that game's saves in the emulator's save folder (`sigil_save_resolve`),
- packs them into one **unit** (`sigil_collect`: a single file, a zip of
  files, or a zip of save folders, depending on the system),
- writes a downloaded unit back without touching other games' saves
  (`sigil_restore`), and keeps an opaque **state blob** the caller stores per
  game between calls.

Bindings exist for C, Kotlin (Android/JNI), Go and Python. There is none for
Dart, so Freegosy would call the C ABI through `dart:ffi`.

RomM side: units are uploaded to the **`autosave` slot** with RomM's
`content_hash`, which is how Argosy, the web player and sigil clients see the
same save. Freegosy uploads to the `freegosy` slot today.

## Why it is worth doing

- One save format shared with Argosy and the web player, instead of the
  per-emulator interop work in [save-interop.md](save-interop.md).
- Systems Freegosy handles by hand today (shared PS1/PS2 cards, GameCube
  `.gci`, Wii/3DS/Switch folders) are already solved there, with ECC, card
  directories and profile ids handled.
- Bugs of the "wrong file, wrong name" kind (for example the lowercased Ares
  restore fixed in #172) go away for the systems it covers.

## Converting existing saves: no migration job needed

sigil's `restore` also reads the shapes clients uploaded **before** sigil
("Units from before sigil" in its `docs/sync.md`): a raw PS1 card, a zip of
PCSX2 save folders, raw or zipped `.gci`, a libretro `.srm`, a zip of N64
files, and so on. It writes the save exactly as it would from its own unit,
and the next `collect` returns the sigil form. So:

1. On the first pull for a game after switching, take the newest save from
   either slot (`freegosy` or `autosave`), as Gargosy does.
2. Restore it with sigil. That is the conversion.
3. The next push uploads sigil's unit to `autosave`.
4. Never delete the old `freegosy`-slot saves; they stay as a fallback.

**To verify** with real files before shipping, per system: that what Freegosy
uploaded yesterday restores to a card the emulator loads.

## Coverage against Freegosy's emulators

"Collect/restore" is sigil's own column: where it says `no`, sigil can find
the save files but the client still uploads them as they are.

| Freegosy emulator | System | sigil collect/restore | Plan |
|---|---|---|---|
| DuckStation, RetroArch (PS1 cores) | PlayStation | yes | wave 1 |
| PCSX2 | PlayStation 2 | yes (shared cards, ECC) | wave 1 |
| Dolphin | GameCube, Wii | yes | wave 2 |
| PPSSPP | PSP | yes | wave 2 |
| Azahar | 3DS | yes | wave 3 |
| Eden, Ryujinx | Switch | yes (device vs account saves) | wave 3 |
| RPCS3 | PS3 | yes | wave 3 |
| Cemu | Wii U | yes | wave 3 |
| mGBA, RetroArch (GB/GBC) | Game Boy / Color | yes | wave 2 |
| mGBA, RetroArch (GBA), melonDS, Ares, Xenia, Windows games | various | `no` or not listed | keep current strategy |

## Design

1. **Vendor and load.** Pin a sigil commit under `thirdparty/` (as
   `thirdparty/gamepads_linux` already is), build `libsigil` with CMake for
   Linux, Windows and macOS in `release.yml`, and bundle it. Load it lazily
   through `dart:ffi`. The release workflow check added in #170
   (`tool/check_bundle_libs.sh`) catches an unbundled dependency.
2. **Wrap, don't replace.** A `SigilSaveStrategy` wraps an emulator's existing
   `SaveStrategy` for the systems sigil handles. If the library is missing or
   sigil refuses a unit, fall back to the old strategy and log why. This keeps
   every emulator working while waves roll out.
3. **Layout per game.** sigil's layout id for libretro is the core name
   without `_libretro`, which `RetroArchSaveStrategy.coreIdFor` already
   produces; `sigil_layouts()` says which cores have their own row.
4. **Persist the state blob** per game next to the existing hash/last-pull
   records in `AppPreferences`, and clear it with the existing "reset sync"
   action.
5. **Managed vs unmanaged.** Freegosy launches the game and pushes after it
   closes, so use sigil's *managed* mode for shared cards: collect after exit,
   upload, then restore before the next launch. Handle `SIGIL_ERR_UNCOLLECTED`
   by collecting first. Show *unclaimed saves* to the user instead of
   uploading them under a guessed game.
6. **Rollout.** One wave at a time behind a per-emulator setting, default off
   in the first release, then default on once Argosy/web-player interop has
   been confirmed on real saves.

## Risks and open questions

- sigil is pre-1.0: function signatures and struct layouts can change, so pin
  a commit and keep the FFI layer thin.
- Native build in CI for three platforms is new work and a new thing to break.
- Mixed fleets: a user on an old Freegosy and a new one share `autosave` and
  `freegosy` slots; "newest of either" must not clobber progress. **To
  verify** with the mock server (`test/mock_romm_server.py`) first.
- Licence: sigil's licence and trademark notes (`TRADEMARKS.md`) must be
  compatible with bundling it in releases. **To check.**
- A fork (GargIT/Gargosy) already did stage 1 for PCSX2, DuckStation, Dolphin,
  PPSSPP, Flycast and mGBA; its approach and tests are the best reference.
