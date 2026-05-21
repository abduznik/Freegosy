# Changelog

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
