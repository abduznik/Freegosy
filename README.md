# Freegosy

A cross-platform Flutter app for browsing your RomM library, downloading ROMs, and launching games directly in emulators—all from one intuitive interface.

## What's New in 0.2.0

### Full macOS Support
- Native support for macOS (ARM64 and Intel)
- Automated `.app` bundle detection and stable launching via the `open` command
- Native `.dmg` and `.tar.xz` extraction support
- Platform-specific path resolution for Application Support and User directories
- Fully enabled cross-platform Save Sync for macOS users

### Enhanced Emulator Management
- **One-Tap Uninstall**: New red trash bin button in Settings to completely remove an emulator and its local files
- **Easy Updates**: New blue update button to fetch the latest release from GitHub/Direct links
- **Smart Filtering**: The Emulators list in Settings now only shows emulators supported on your current OS (Windows/macOS/Linux)

### UI & UX Improvements
- **Clean Filter Bar**: Platforms with zero games are now automatically filtered out of the main library view
- **Automatic Renaming**: Extracted versioned emulators (e.g. `PCSX2-v2.6.3.app`) are automatically renamed to their canonical names (`PCSX2.app`) for stable detection
- **Recursive Discovery**: Deep search for `.app` bundles allows Freegosy to find emulators even when they are extracted into nested folders
- **Flexible RomM Integration**: Added support for multiple game-count field names (`rom_count`, `roms_count`, `games_count`) for better compatibility with different RomM versions

## What's New in 0.1.2

### Paginated Library Loading
- Library now loads 50 games at a time instead of fetching everything at once
- Scroll to the bottom to automatically load more games
- Supports libraries with 2000+ games without performance issues

### Server-Side Platform Filtering
- Switching platforms now fetches only that platform's games from the server
- Fixed RomM 4.x API compatibility — correctly uses `platform_ids` parameter
- Platform results are cached in memory for instant switching on revisit

## Currently Working

- **RomM Integration**: Browse and filter your entire RomM library by platform or search
- **ROM Downloads**: Download games via HTTP from your RomM server with progress tracking
- **Archive Extraction**: Automatic extraction of .zip, .7z, .dmg, .tar.gz, and .tar.xz archives
- **Game Launching**: Launch games directly from the app using:
  - RetroArch (All major retro platforms)
  - Dolphin (GameCube & Wii)
  - Eden (Nintendo Switch)
  - RPCS3 (PlayStation 3)
  - PCSX2 (PlayStation 2)
  - DuckStation (PlayStation 1)
  - Azahar (Nintendo 3DS)
  - Cemu (Wii U)
  - Xemu (Xbox)
  - Xenia Canary (Xbox 360)
  - Flycast (Dreamcast, Naomi, Atomiswave)
  - melonDS (Nintendo DS)
  - PPSSPP (PlayStation Portable)
  - mGBA (Game Boy Advance/Color/Game Boy)
  - MAME (Arcade)
  - Windows Native (PC games)
- **Emulator Management**: Download, update, and uninstall emulators directly from Settings
- **Save Sync**: Bidirectional save synchronization with RomM cloud for almost all supported emulators including cross-platform path resolution.

## Roadmap

### Near Term
- **Linux support** — Enhancing native binary detection and system path resolution
- **Android support** — Deep links to app stores for Play Store/Epic Games/etc.
- **Recently played / play time tracking** — See your gaming stats at a glance

### End-Game Features
- Custom ROM platform tagging
- Mobile companion app for on-the-go library browsing

### Cross-Platform Vision
Freegosy is designed as a truly cross-platform experience. The codebase is structured to support Windows, macOS, Linux, and Android with platform-specific code isolated behind strategy patterns and service abstractions.

## Status

Actively under development. Release 0.2.0 brings full macOS support and major UI management improvements.

## About RomM

Freegosy is built to complement [RomM](https://github.com/rommapp/romm), a modern ROM manager. It connects to your RomM instance to provide a lightweight, portable way to access and play your games.

## Contributing

Check out `agent.md` for the full file map, coding rules, and contracts for adding new emulators, save strategies, or features.
