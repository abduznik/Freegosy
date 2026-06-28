# Changelog

## [0.5.10] - 2026-06-28

### Added
- **PlatformInfo abstraction**: Introduced injectable platform detection (`PlatformInfo`) replacing all 177+ direct `dart:io` `Platform.is*` checks across the entire codebase. Tests can now simulate any OS via `PlatformInfo('windows')`, `PlatformInfo('macos')`, `PlatformInfo('linux')`.
- **platformInfoProvider**: Riverpod provider exposing `PlatformInfo.current` for UI-layer platform access.
- **HTTP security warning**: Onboarding screen warns when a public IP is used over HTTP. Localhost and LAN addresses (`192.168.x.x`, `10.x.x.x`) are exempt.
- **19 new controller mappings**: DualShock 3, 8BitDo SN30 Pro, 8BitDo Lite, 8BitDo Zero 2, 8BitDo Ultimate C, Razer Kishi, Razer Wolverine, SteelSeries Nimbus, SteelSeries Stratus, Backbone One, GameSir G7, GameSir T4, Hori Fighting Commander, Hori Split Pad, Nacon Revolution, PDP, Scuf, ASUS ROG Raikiri, Flydigi, GuliKit, Amazon Luna, MSI Force GC.
- **107 new unit tests** across 14 test files covering ROM lookup, download cache, URL construction, SDL parser, extraction service, library snapshots, PCSX2 serial extraction, strategy registry, AppImage detection, gamepad debouncing, melonDS save paths, download extension preservation, directory service, ROM constants, and cross-platform simulation.
- **Cross-platform simulation tests**: 20 tests verifying critical logic works identically on simulated Windows, macOS, and Linux.

### Fixed
- **Single-file-foldered ROM downloads missing extension (issue #44)**: Games stored in RomM as `/platform/gamename/gamename.chd` were downloaded without the `.chd` extension, preventing emulators from opening them.
- **AppImage emulators not detected on Linux (issue #43)**: Expanded search paths to `~/.local/bin` and `~/bin`. Added fuzzy matching that strips architecture suffixes (`x86_64`, `amd64`, `linux`, `gtk`) and `.appimage` extensions. Added melonds/dolphin/duckstation/mgba to EmuDeck folder map.
- **Controller ghost/stuck inputs (issue #41)**: Added 80ms debounce on digital button presses to prevent rapid-fire ghost inputs on Steam Deck and third-party controllers.
- **melonDS save directory detection (issue #42)**: Added `%USERPROFILE%\Documents\melonDS` for Windows, `~/Library/Application Support/melonDS` for macOS, and RetroArch fallback on Linux.
- **pubspec.yaml description**: Updated from boilerplate "A new Flutter project." to actual project description.

### Changed
- **Full PlatformInfo migration**: All 177+ `dart:io` `Platform.isWindows/isMacOS/isLinux` and `Platform.environment` checks replaced with injectable `PlatformInfo` across 43 production files. `defaultTargetPlatform` checks in providers and UI also migrated.
- Added `plugin_platform_interface` and `path_provider_platform_interface` to dev_dependencies for test mocking.

## [0.5.10] - 2026-06-19

### Fixed
- **Controller input leaks to background apps**: Freegosy was processing gamepad input even when another app (e.g. a game) was in focus. Controller navigation now only activates when Freegosy's window is the focused app.
- **MelonDS launch regression**: melonDS was silently failing to start after the v0.5.9 launch refactor — it requires its working directory set to the exe folder to find `melonDS.ini` and firmware files. Restored per-platform launch overrides.
- **MelonDS hangs before launching**: The pre-launch sync was performing a push + pull sequentially (up to 5-minute timeout each). Now only pulls before launch with a 30-second hard timeout. Push happens after the game exits as intended.
- **Linux AppImages not detected (issue #43)**: Emulators installed as AppImages via EmuDeck (`~/Applications/`) or Gear Lever (`~/AppImages/`) are now detected automatically. Fixes Eden, PCSX2, DuckStation, Cemu not showing as installed.
- **Push button shows "Up to Date" when no saves found**: Manual push was reporting success even when Freegosy couldn't locate any save files. Now shows a clear "No Saves Found" message with guidance.
- **MelonDS save detection on Windows**: Added `%APPDATA%\melonDS` and `%APPDATA%\melonds` to the Windows save search path for users who configured a dedicated melonDS save folder.

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
