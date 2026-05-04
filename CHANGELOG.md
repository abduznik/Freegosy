# Changelog

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
