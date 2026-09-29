# Changelog

> **Windows Defender false positive notice (v0.5.10+):** Windows Defender may flag `freegosy.exe` as `Wacatac.B!ml`. This is a false positive affecting all unsigned Flutter apps. See the [README](README.md#other-platforms) for details.

## [Unreleased]

### Added
- **PS2 saves sync with RetroArch's PS2 core (LRPS2)**: LRPS2 keeps every game's saves on memory cards shared by all games in RetroArch's system folder (`system/pcsx2/memcards/Mcd001.ps2`, `Mcd002.ps2`), where Freegosy never looked, so its saves weren't synced at all. Freegosy now takes only the launched game's saves off the card, found by the game's serial, and uploads them as save folders (e.g. `BASLUS-20851AC5/…`), the same shape PCSX2 folder cards and Argosy use. Pulling puts them back on the card and leaves every other game's saves as they are, after a `.bak` of the card. A card that is full or can't be read is left untouched with a "Saves Not Synced" message, and the pull finishes before RetroArch starts. With LRPS2's *Shared Memory Cards* off, the game's own card in the save folder is used the same way.
- **Headless mode** (`--headless`): run Freegosy without a UI window — `list`/`search`, `download` (including multi-file/multi-disc), and `launch` (waits for exit, runs the same save-push/backup pipeline as the UI, reports pass/fail as JSON or plain text). Useful for scripting a launch/sync check or driving Freegosy from an agent/CI. See the README for usage.
- **PCSX2 save-state sync (opt-in)**: PCSX2 save states (`SERIAL (CRC).NN.p2s`, including the resume slot) now sync between your machines through RomM's dedicated states API, separately from game saves. Turn on "Sync save states" for PCSX2 in Settings → Emulators (off by default; the switch is disabled with "Not supported yet" for emulators that don't support it). States are pulled before launch and pushed after the emulator exits; if a state changed on both sides, a conflict found before launch prompts you to choose which copy to keep, while one found after the emulator exits is reported in a warning toast that stays until dismissed and has a "Resolve" button (the "Sync Save States" button on the game page offers the same choice); nothing is overwritten silently. That button also runs the sync on demand. States that only exist inside older cloud saves are no longer restored: states now sync only through this opt-in path, and restoring an older save skips them.
- **Resume Game**: when a game has save states, its page shows **Resume Game ▾** above **Play Game (fresh start)**. Resume loads the newest state (on this PC or, with state sync on, on RomM) with the emulator that made it; ▾ (or X on a controller) lists every slot with its time, emulator version and where it is, and warns when the version differs from the installed emulator. A state that can't be fetched starts nothing; a state from a different version that wasn't shown beforehand asks first. State uploads now carry the emulator id and the state's screenshot. PCSX2 first; other emulators can plug in through the same contract.
- **Fullscreen**: press **F11** to toggle fullscreen at any time, turn on "Start in fullscreen" in Settings → Display, or launch with `--fullscreen` (handy for a Steam non-Steam-game shortcut or Moonlight). Desktop only.
- **Cover size slider**: a new button in the library's top bar resizes covers without going to Settings, and the games-per-row range now goes up to 12 (was 8) so covers can be much smaller on big screens.
- **"Sync BIOS" covers every installed emulator**: the button in Settings → Emulators used to place firmware only in each platform's default emulator, so a second emulator chosen per game through the launch picker never got its BIOS. It now syncs each platform's firmware into every installed emulator that supports the platform.
- **ScummVM**: games on the `scummvm` platform launch in ScummVM, which detects and starts the game in the game's folder (`--auto-detect --path=…`); no file or disc picker is shown for these folder games. Freegosy finds ScummVM in your emulators folder, as a Flatpak (`org.scummvm.ScummVM`) or as a distribution package on Linux; it doesn't download ScummVM itself yet (set a download URL override in Settings → Emulators, or install it yourself). Save sync isn't supported for ScummVM yet.
- **DuckStation save-state sync and Resume Game**: DuckStation states (`SERIAL_N.sav` and the `SERIAL_resume.sav` written on exit) sync through the same opt-in "Sync save states" switch and show up under **Resume Game ▾**, which boots DuckStation with `-statefile`. DuckStation states don't record the build that made them, so the slot list shows their state format (e.g. "DuckStation state format 86") and never warns about versions. Their screenshot (raw pixels, zstd-compressed by default) is turned into the slot thumbnail and uploaded with the state, using the new `zstandard` dependency.

### Fixed
- **Sega 32X games showed "No Emulator Configured", and Atari Jaguar games launched with a core that doesn't exist**: no RetroArch core listed RomM's 32X platform (`sega32`); it now launches in RetroArch with PicoDrive, and its saves go to PicoDrive's save folder. The core list also held three cores that exist nowhere, "ProSystem Jaguar" (`jaguar_libretro`), Oricium and MultiCore. The Jaguar one was listed first, so Jaguar games were started with it and RetroArch couldn't load it; they now use Virtual Jaguar. The three are removed, so Oric has no RetroArch core.
- **RetroArch saves: the folder of the core the game really runs in, on every platform**: the save folder came from a table of its own that often named a different core than the one Freegosy launches. A pulled PS1 save went to `saves/PCSX-ReARMed/` while the game ran in Beetle PSX HW, which reads `saves/Beetle PSX HW/`, so on a new PC the game didn't see its save. Game Boy / Game Boy Color (mGBA vs Gambatte) and NES / FDS (FCEUmm vs Mesen) had the same problem. 117 platforms with a RetroArch core weren't in the table at all, so their saves never synced. The folder now follows the core the game is launched with (the game's core, the platform's chosen core, else its default core) and is named after that core's `library_name` from libretro's core info, for every core. RetroArch's last-used core now only counts for a platform it runs: with mGBA last used, a PS1 save went to `saves/mGBA/`. Saves on RomM are tagged with that same core. **Heads-up, if you haven't chosen a core for these platforms:** save sync now uses `saves/Beetle PSX HW/` for PS1, `saves/Gambatte/` for Game Boy / Game Boy Color and `saves/Mesen/` for NES / FDS, the folders of the cores Freegosy has been launching them with, instead of `saves/PCSX-ReARMed/`, `saves/mGBA/` and `saves/FCEUmm/`. Those old folders are left as they are. What you played through Freegosy is already in the new ones; files in the old ones came from earlier pulls, which the running core never read, or from playing in that core outside Freegosy. If you play one of these platforms in the other core, choose it in Settings → Emulators (or for the game), and sync uses its folder as before. A save in another core's folder is still found when this core has no folder yet.
- **TurboGrafx-CD / PC Engine CD games failed with "No Emulator Configured"** (#120): RomM calls the platform `turbografx-cd`, which no RetroArch core listed. It now launches in RetroArch with Beetle PCE (`mednafen_pce`), the core RomM's own player uses, and so does RomM's `supergrafx`, which had no default core either. Sync BIOS now places the CD BIOS (`syscard3.pce`) for them too: it skipped the platform, which had no emulator. TurboGrafx-16 (`tg16`), TurboGrafx-CD and SuperGrafx saves now go to RetroArch's `Beetle PCE` save folder, like PC Engine's.
- **RetroArch from EmuDeck for Windows: "No Saves Found"** (#79): Freegosy only looked for EmuDeck's RetroArch in `%USERPROFILE%\emudeck\EmulationStation-DE\Emulators\RetroArch`; it now also finds `%USERPROFILE%\EmuDeck\Emulators\RetroArch`. A game's save lying directly in RetroArch's save folder is now found even when Freegosy assumes "Sort Saves into Folders by Core" is on (RetroArch's default, used when its setting can't be read); before, only the core folders were searched.
- **PC-98 BIOS was put where Neko Project II Kai doesn't look**: Sync BIOS placed PC-98 firmware directly in RetroArch's `system` folder, but the core reads it from `system/np2kai/`. It now goes there. (RomM's `pc-9800-series` platform isn't recognised yet, so this applies to a platform named `pc98` / `pc-98`.) Behind it, several BIOS entries were filed under names no RetroArch core has (`beetle_saturn` instead of `mednafen_saturn`, `neko_project_ii_kai` instead of `np2kai`, ...), so they were never used; they now use the core names. For PlayStation (Beetle PSX HW), Saturn and PC-FX this also turns on the MD5 check, so a damaged BIOS already in `system` is downloaded again.
- **Games on platforms RomM names differently showed "No Emulator Configured"**: RomM names platforms by IGDB's slugs, and for many systems Freegosy emulates those weren't the names it knew, e.g. `famicom`, `pc-fx`, `pc-9800-series`, `neo-geo-pocket-color`, `wonderswan-color`, `neo-geo-cd`, `zxs` (ZX Spectrum), `amiga-cd32`, `sfam`, `satellaview`, `nintendo-dsi`, `philips-cd-i`, `tic-80`, and hardware variants like `game-boy-pocket` or `sega-nomad`. They now get the same emulator, RetroArch core, save folder, ROM folder and BIOS as the system's usual name. Platforms Freegosy has no emulator for are unchanged.
- **RetroArch games on many platforms couldn't load**: when none of a platform's RetroArch cores was marked recommended, Freegosy started RetroArch with the ROM but no core, so RetroArch tried whichever core it had loaded last, usually one for another system. About 85 platforms were affected, among them Vectrex, Atari Jaguar, PC-FX, Neo Geo CD, SG-1000, VIC-20, ZX81, PICO-8, Pokémon Mini and Game & Watch. They now use their first listed core; platforms with a recommended core keep it.
- **Saves on RomM showed "freegosy" as their emulator, and RomM's in-browser player hid them**: every save Freegosy uploaded was tagged `emulator=freegosy`, and RomM's player only offers saves tagged with the core it runs. Saves are now tagged with the emulator that made them: the RetroArch core without `_libretro` (e.g. `pcsx_rearmed`, `mgba`, the names RomM's player and Argosy use), otherwise the emulator (e.g. `pcsx2`, `duckstation`). They stay in the `freegosy` slot, so RomM still keeps only Freegosy's last versions. Saves already on RomM keep their old tag; Freegosy pulls them as before.
- **PCSX2 memory card files rolled back other games' saves**: with PCSX2's default "file" memory card (`memcards/Mcd001.ps2`, one 8 MB image shared by every game), the whole card went to RomM as the launched game's save, and pulling it on another PC replaced the local card, rolling back every other game on it. Now only the launched game's saves leave the card, as save folders (the shape folder cards, LRPS2 and Argosy use), and a pull merges them back into the card that holds them after a `.bak`, leaving the other games' saves as they are. A whole card from RomM onto a folder card now lands as folders instead of failing. A card that is full or can't be read, or a game whose serial can't be read, is left untouched with a "Saves Not Synced" message, and the pull finishes before PCSX2 starts.
- **RetroArch saves could be restored into another core's folder**: with "Sort Saves into Folders by Core" on, RetroArch names each core's save and state folder after the core (`Mupen64Plus-Next`, `FCEUmm`, `LRPS2`, ...), but Freegosy's table mostly held guesses (`N64`, `NES`, `PCSX2`, `States/…`). When the guessed folder didn't exist, a restore went to whichever core folder was modified last, so PS2 memory cards could end up in the N64 core's folder, where nothing reads them. The table now uses each core's real name, from libretro's core info, and a first restore goes to the game's own core folder. Beetle PSX and Beetle PSX HW are now recognised as the active core too.
- **RetroArch didn't load PS1 memory cards made by DuckStation**: a PS1 `.mcd` card on RomM (uploaded by DuckStation, or another client's `<serial>_1.mcd`) was restored under its own name, which RetroArch's PS1 cores never open. RetroArch save sync now restores a port-1 card as the game's `<ROM name>.srm`, where every RetroArch PS1 core keeps card 1 by default. The two are the same raw 128 KB format.
- **Web build stuck on the splash screen**: the browser version crashed at startup reading the operating system, which doesn't exist in a browser. It now starts and browses your RomM library (platforms, games, game pages, settings). Storage setup explains that there's nothing to set up in the browser, and Download/Play say they need the desktop app instead of starting something that can only fail.
- **Linux: emulator launches via Flatpak failed with "No such file or directory"**: `flatpak` was looked up in the PATH Freegosy inherited, which on some sessions (Steam Deck game mode, AppImage or Steam launches) doesn't include `/usr/bin`. Freegosy now finds `flatpak` itself (PATH, then `/usr/bin`, `/usr/local/bin`, `/bin`). The EmuDeck preset, which had no fallback at all, is covered too.
- **PCSX2 state sync could upload a damaged save state**: the upload after the emulator exits only checked a state's size, so a state PCSX2 failed to write (cut off partway or zero-filled) could replace the good copy on RomM. States are now checked before every upload, and the PCSX2 check also requires the end record of the state's zip, so a state that was cut off is rejected on download and on "Use Local Version" too.
- **DuckStation memory cards now follow DuckStation's Memory Card Type setting**: Freegosy reads it from DuckStation's `settings.ini` (and a game's own `gamesettings/<SERIAL>.ini`) and syncs exactly the card DuckStation uses for the game: `<serial>_N.mcd`, `<title>_N.mcd` (the title from DuckStation's own game database, one card for all discs of a multi-disc game when that option is on) or `<ROM file name>_N.mcd`, for every port with a per-game card. Before, cards were matched by words from the ROM name, so "Separate Card Per Game (Serial)" cards were usually not found. A card is restored under the name *this* PC's DuckStation uses, so PCs set to different types share the save. **A memory card shared by all games now syncs only the launched game's saves**: before, the whole card was uploaded as that game's save, and restoring it on another PC rolled back every other game on the card. Now the game's saves (found by their product code, including every disc of a multi-disc game) are copied into a card of their own for the upload, `<serial>_N.mcd`, which a PC with per-game cards restores like any other; downloading replaces only that game's saves on the local shared card, leaving every other save byte for byte, after a `.bak` of the card. A card too full for the download, or one that doesn't read as a PS1 memory card, is left untouched with a "Saves Not Synced" message saying why. For a shared card the pre-launch pull finishes (up to 20 s) before DuckStation starts. Local backups still keep the whole shared card. With "No Memory Card" or "Non-Persistent" there is nothing to sync, and Freegosy says so. A PS1 card uploaded by Argosy (RetroArch keeps it as `<ROM name>.srm`) is now restored too, when it is a real 128 KB card; before, anything but `.mcd` was ignored. The other way round, DuckStation's port-1 card is now uploaded as `<ROM name>.srm`: the same bytes (a DuckStation `.mcd` and a RetroArch PS1 `.srm` are the same raw card) under the name RetroArch's PS1 cores and Argosy use, so a DuckStation save can be played on in RetroArch. Other ports keep DuckStation's `<name>_N.mcd`. See `docs/save-interop.md` for how PS1 saves move between DuckStation, the RetroArch cores and Argosy.
- **PCSX2 save states could end up in the game-save upload**: state files could be bundled into the same RomM save zip as the memory cards when the ROM name happened to occur in the state's file name, but PCSX2's real names (`SERIAL (CRC).NN.p2s`) normally never matched, so in practice states did not sync. PCSX2 game saves now contain memory cards only; states use the new opt-in state sync above. DuckStation had the same problem (its `savestates/` folder was matched by ROM name, which normally never matched its serial-named states); its game saves now contain memory cards only too, and restoring an older save skips any states in it.
- **Controller mapping wizard could bind the wrong button/axis on Linux**: the wizard's press/release detection compared raw event values against thresholds meant for a normalized -1.0..1.0 range, but Linux (`/dev/input/js*`) reports axes as raw int16 magnitudes (roughly -32767..32767). Any nonzero jitter on an idle axis read as fully "pressed" and almost never "released", so background noise on one axis could hijack the wizard mid-sequence and get bound to whichever action you were currently mapping. Raw axis values are now rescaled to -1.0..1.0 before those thresholds are applied. **Note:** this fixes the threshold miscalibration, not general cross-talk — on marginal/noisy pads that report genuine simultaneous activity on more than one axis (e.g. a D-pad that physically drives two raw axes at once), the wizard's capture can still occasionally get preempted by a second input. This reduces how often that happens; it isn't a guarantee.
- **Xbox 360 pad D-pad triggered Select/Start instead of navigating on Linux**: on Linux, `/dev/input/js*` reports raw numeric indices that a button and an axis can share (e.g. Back = button 6, D-pad X = axis 6), and the controller mapping/sniff wizard stored them under the same bare key. Pressing D-pad right or down could fire Select or Start instead of moving focus. Numeric keys are now tagged by event type (button vs. axis) before storage/lookup, so they can no longer collide.
- **RetroArch could upload another game's save**: when no save file had exactly the ROM's name, RetroArch save sync took the first save containing *any* word of the name, and the name check itself was a bare prefix. In a save folder shared by several games, "Crash Bandicoot 2" could pick up `Crash Bandicoot (Europe).srm` and "Crash Bandicoot" could pick up `Crash Bandicoot 2.srm`, uploading the wrong game's save to RomM. A save now matches when it is the ROM's name followed by an extension, or else has the same title: every word, numbers included, ignoring case, punctuation, word order and `(…)`/`[…]` tags, so `Crash Bandicoot (USA).srm` still matches a `(Europe)` ROM.
- **Save sync used the wrong emulator's data (issues #79, #42, #28)**: pushing/pulling/backing up a save after launch always resolved the *platform's globally-configured default emulator*, even if you actually launched via a different one (e.g. through the per-game picker). Save sync now uses the emulator that actually launched the game.
- **Eden save sync picked the wrong profile (issue #68)**: with multiple Eden user profiles, saves could resolve under the most globally-active profile instead of the one that actually holds the current game's save, reporting "no save files found" for a game with a real, valid save.
- **Ares save sync didn't recognize PlayStation (and similar) saves**: Ares bundles the real memory card together with save-state files in a single per-game `.zip`; this is now correctly unpacked on push/pull instead of being invisible to sync entirely.
- **Amstrad CPC games showed "no emulator configured" (issue #78)**: RomM's platform slug for Amstrad CPC (`acpc`, from IGDB) wasn't recognized by any registered core.
- **Windows native games with custom launch arguments could crash/black-screen (issue #47)**: the game's folder path was being silently appended after your configured launch arguments, breaking shared multi-game launchers (e.g. OpenGOAL's `gk.exe --game jak1`).
- **Downloaded ROM missing its file extension (issue #44)**: games stored in RomM as a per-game folder with a single file inside could download without the file's extension, especially via the simple "Download" button — the fix only reliably triggered when full file metadata had already been fetched separately.
- **`strategyId` mismatches in debug logs**: Eden and Azahar's save strategies logged the wrong internal name (`switch`/`3ds` instead of `eden`/`azahar`), making `[SaveSync]` log output misleading when diagnosing which emulator actually resolved.
- Fixed several correctness/reliability issues found while stress-testing headless mode: a concurrent-process race on the local backups database could hang the process indefinitely instead of failing cleanly; `--limit=0` (and negative) sent an invalid request to RomM instead of being rejected client-side; an empty `--name`/`--game-id` value silently searched for everything instead of being treated as missing.

## [0.5.11] - 2026-07-29

See [Releases](https://github.com/abduznik/Freegosy/releases/tag/v0.5.11) for full release notes.

## [0.5.10] - 2026-07-28

### Added
- **PlatformInfo abstraction**: Introduced injectable platform detection (`PlatformInfo`) replacing all 177+ direct `dart:io` `Platform.is*` checks across the entire codebase. Tests can now simulate any OS via `PlatformInfo('windows')`, `PlatformInfo('macos')`, `PlatformInfo('linux')`.
- **platformInfoProvider**: Riverpod provider exposing `PlatformInfo.current` for UI-layer platform access.
- **HTTP security warning**: Onboarding screen warns when a public IP is used over HTTP. Localhost and LAN addresses (`192.168.x.x`, `10.x.x.x`) are exempt.
- **19 new controller mappings**: DualShock 3, 8BitDo SN30 Pro, 8BitDo Lite, 8BitDo Zero 2, 8BitDo Ultimate C, Razer Kishi, Razer Wolverine, SteelSeries Nimbus, SteelSeries Stratus, Backbone One, GameSir G7, GameSir T4, Hori Fighting Commander, Hori Split Pad, Nacon Revolution, PDP, Scuf, ASUS ROG Raikiri, Flydigi, GuliKit, Amazon Luna, MSI Force GC.
- **107 new unit tests** across 14 test files covering ROM lookup, download cache, URL construction, SDL parser, extraction service, library snapshots, PCSX2 serial extraction, strategy registry, AppImage detection, gamepad debouncing, melonDS save paths, download extension preservation, directory service, ROM constants, and cross-platform simulation.
- **Cross-platform simulation tests**: 20 tests verifying critical logic works identically on simulated Windows, macOS, and Linux.
- **Save sync debug logging**: Unified `[SaveSync]` logging across all save strategies showing game name, slug, romPath, strategy selected, files found with paths/sizes, and upload/download results. Helps users and developers troubleshoot save sync issues (issues #42, #24, #28).

### Fixed
- **Single-file-foldered ROM downloads missing extension (issue #44)**: Games stored in RomM as `/platform/gamename/gamename.chd` were downloaded without the `.chd` extension, preventing emulators from opening them.
- **AppImage emulators not detected on Linux (issue #43)**: Expanded search paths to `~/.local/bin` and `~/bin`. Added fuzzy matching that strips architecture suffixes (`x86_64`, `amd64`, `linux`, `gtk`) and `.appimage` extensions. Added melonds/dolphin/duckstation/mgba to EmuDeck folder map.
- **Controller ghost/stuck inputs (issue #41)**: Added 80ms debounce on digital button presses to prevent rapid-fire ghost inputs on Steam Deck and third-party controllers.
- **melonDS save directory detection (issue #42)**: Added `%USERPROFILE%\Documents\melonDS` for Windows, `~/Library/Application Support/melonDS` for macOS, and RetroArch fallback on Linux.
- **MelonDS launch regression**: melonDS was silently failing to start after the v0.5.9 launch refactor — it requires its working directory set to the exe folder to find `melonDS.ini` and firmware files. Restored per-platform launch overrides.
- **MelonDS hangs before launching**: The pre-launch sync was performing a push + pull sequentially (up to 5-minute timeout each). Now only pulls before launch with a 30-second hard timeout. Push happens after the game exits as intended.
- **Linux AppImages not detected (issue #43)**: Emulators installed as AppImages via EmuDeck (`~/Applications/`) or Gear Lever (`~/AppImages/`) are now detected automatically. Fixes Eden, PCSX2, DuckStation, Cemu not showing as installed.
- **Push button shows "Up to Date" when no saves found**: Manual push was reporting success even when Freegosy couldn't locate any save files. Now shows a clear "No Saves Found" message with guidance.
- **MelonDS save detection on Windows**: Added `%APPDATA%\melonDS` and `%APPDATA%\melonds` to the Windows save search path for users who configured a dedicated melonDS save folder.
- **pubspec.yaml description**: Updated from boilerplate "A new Flutter project." to actual project description.

### Changed
- **Full PlatformInfo migration**: All 177+ `dart:io` `Platform.isWindows/isMacOS/isLinux` and `Platform.environment` checks replaced with injectable `PlatformInfo` across 43 production files. `defaultTargetPlatform` checks in providers and UI also migrated.
- Added `plugin_platform_interface` and `path_provider_platform_interface` to dev_dependencies for test mocking.

## [0.5.9] - 2026-06-13

### Added
- **RomM 4.9 device sync**: Saves are now tagged to your device (`device_id`) when uploading to RomM 4.9+, preventing cross-device conflicts. Falls back to legacy mode on older RomM versions automatically.
- **Play session tracking**: Game sessions are automatically recorded to RomM 4.9+ (`POST /api/play-sessions`) with start time, end time, and duration.
- **PCSX2 per-game folder saves**: PCSX2 Qt (1.7+) stores saves in `saves/{Serial}/` folders. Freegosy now extracts the PS2 serial from the ROM filename or ISO `SYSTEM.CNF` and syncs that folder. Legacy `Mcd001/Mcd002.ps2` memcards remain as a fallback for older setups.
- **Controller polarity-encoded axis mapping**: Analog sticks and hat switches are now stored as `key+` / `key-` pairs, matching the convention used by Dolphin, RetroArch, and other emulators. Fixes D-pad directions mapping to the same value and analog axes flooding the filter popup.
- **SDL GameControllerDB hat switch parsing**: Auto-map now correctly parses hat switch entries (`h0.1`, `h0.2`, `h0.4`, `h0.8`) from SDL mapping strings.
- **Reset controller mapping**: New Reset button in the controller setup dialog lets you clear a broken or unwanted custom profile.

### Fixed
- **Dolphin GameCube saves — multiple uploads**: `getSaveFiles()` was returning every `.gci` in the Card A folder, including Dolphin's own timestamped backup copies and saves from unrelated games (loose name match). Now uses strict game ID matching and picks only the newest matching `.gci`.
- **Dolphin Wii saves silently dropped**: `_filterFilesMap` was discarding directory-type entries; Wii save directories now pass through correctly.
- **DuckStation — multiple `.mcd` uploads**: Now keeps only the newest matching memcard file instead of all matches.
- **PPSSPP — multiple SAVEDATA folders**: Word-token matching could return saves from multiple games sharing a common word. Now scores matches and picks the single best-scoring folder.
- **Cemu — always uploading**: `getSaveFiles()` had no `sessionStart` check, causing the entire `00050000` save directory to upload on every sync regardless of changes.
- **Session-start boundary race**: Save files written at the exact moment of session start could be excluded. All strategies now apply a 2-second grace window so files modified up to 2 seconds before `sessionStart` are included.
- **Empty controller mapping saved**: Completing the sniff wizard without mapping any buttons would save a blank profile that permanently shadowed the built-in mapping. The Save button is now disabled when the mapping is empty, and a warning is shown.

## [0.5.4+1] - 2026-05-28
### Added
- Flatpak auto-detection and command override support for Linux emulators
- Custom emulator dialog now supports command override field for Flatpak
- NativeLinuxStrategy auto-detects installed Flatpak emulators via `flatpak list`
- Known Flatpak package mappings for 12 emulators



## [0.5.0] - 2026-05-17

### Added
- **Full Gamepad/Controller Support**:
  - Centralized global gamepad input service supporting all standard Switch, Xbox, PlayStation, and generic USB controllers.
  - Custom controller focus-effects engine with gorgeous premium glassmorphism glow borders and scale effects.
  - Universal gamepad hold-down D-pad/Joystick auto-scroll support with a 500ms delay and 120ms repeating snap navigation.
- **Premium UI Redesign**:
  - Overhauled visual styling and matching theme colors across Settings dropdowns, toggles, layout sliders, and dialogs.
  - Modernized Downloads management screen with high-fidelity progress cards, pause/resume, and safe overlay calculations.
- **Smart Global Search**:
  - Re-architected search bar to search globally across all platforms.
  - Automatically shifts view to the "All" tab when active, and smoothly returns to the "Home" dashboard when cleared.
- **Official Licensing**: Added official MIT License and registered it directly into the application's license registry.

### Fixed
- **Layout Calculations**: Resolved a critical layout intrinsic height crash inside overlay alert dialogs by passing `useSafeScale: false`.
- **Platform Chip Navigation**: Fixed reactivity issues where selecting a platform chip visual tab updated the filter state but did not trigger an API/SQLite load.
- **Dolphin Save Sync on Linux**: Fixed save synchronization for Dolphin emulator on Linux platforms.
- **Single-File Foldered Games Download**: Fixed download logic for single-file games stored in folders.
- **GameMetadataChip Overflow**: Wrapped label text in `Flexible` + `TextOverflow.ellipsis` to prevent `RenderFlex` overflow on long labels.
- **BackupHistorySheet Crash**: Guarded `md5Hash.substring(0, 8)` to prevent `RangeError` on short hashes.
- **ScreenshotGalleryDialog Empty State**: Hidden page indicator when `imageUrls` is empty (was showing "1 / 0").
- **MultiDiscPicker ListTile Ink**: Wrapped `ListTile` in a `Material` widget to fix ink splash warnings when rendered outside a bottom sheet.

### Changed
- Updated dependencies for improved stability and compatibility.

## [0.4.1] - 2026-05-12

### Added
- Initial preparation for 0.4.1 updates.

## [0.4.0] - 2026-05-04

### Added
- **Steam Deck & Linux Support**: Full integration with **EmuDeck** and **RetroDECK** environments.
  - Automatic detection of EmuDeck/RetroDECK folder structures.
  - Support for SteamOS-specific launcher scripts (`.sh` files).
  - High-precision path resolution for emulator saves, including Flatpak sandboxes and EmuDeck symlinks.
- **Serial Background Sync**: Implementation of a background queue for game save backups. Offline saves are now automatically synchronized to RomM when a connection is restored.
- **Recently Added Widget**: Optimized "Recently Added" section on the home screen, now sorted by RomM ID for true chronological discovery.
- **Automated Linux Validation**: Comprehensive unit test suite for Linux path resolution strategies to ensure stability across SteamOS updates.

### Fixed
- **ROM Scanning**: Resolved issues with PS3 and Nintendo Switch ROM scanning and name normalization.
- **Download Reliability**: Fixed filesystem access errors (errno 5) during game downloads on certain OS configurations.
- **UI/UX Polishing**: Improved alignment and visual consistency in the Settings screen and Game Detail views.

### Changed
- Refactored Linux strategy logic into isolated, testable classes (`EmuDeckStrategy`, `RetroDeckStrategy`).
- Optimized metadata caching for faster offline library browsing.

---

## [0.3.0] - 2026-04-20

### Added
- **macOS Texture Processing**: Support for Ryujinx asset processing and texture conversion.
- **Multi-Platform Native Support**: Initial support for macOS and Windows.
- **Save Sync**: Bidirectional sync for major emulators.
- **BIOS Management**: Automatic BIOS placement and downloading.
