# Freegosy

A cross-platform Flutter app for browsing your RomM library, downloading ROMs, and launching games directly in emulators—all from one intuitive interface.

## What's New in 0.0.2

### Full Windows Native Game Support
- Download Windows games (.zip and .7z) with automatic extraction
- Auto-detection of game executables in extracted folders
- Manual exe and save path configuration via long-press on any Windows game card
- Crash detection on launch — if a game exits immediately, a clear error message explains likely causes (missing DirectX, Visual C++ redistributables, etc.)
- Save sync for Windows games via PCGamingWiki automatic save path detection, with manual override support
- All exe and save path overrides persist across app restarts

### Expanded Save Sync
- **PCSX2 (PS2)**: Syncs memory cards (Mcd001.ps2, Mcd002.ps2) and save states
- **RPCS3 (PS3)**: Syncs save data folders by title ID
- **Xenia Canary (Xbox 360)**: Syncs content save folders by title ID
- **Windows games**: Full save directory packaging into zip for upload, auto-extraction on restore
- All multi-file save strategies package saves as a single zip for clean cloud storage

### 7-Zip Support
- Bundled 7zr.exe for .7z extraction — no manual installation required
- Automatically extracted to AppData on first run
- Full .7z support for Windows game downloads

### Quality of Life
- Launch error messages now display for 8 seconds for better readability
- Stale exe overrides (pointing to moved/deleted files) are automatically discarded and re-detected
- ROM detection improved for Windows games — returns game folder instead of individual file

## Currently Working

- **RomM Integration**: Browse and filter your entire RomM library by platform or search
- **ROM Downloads**: Download games via HTTP from your RomM server with progress tracking
- **Archive Extraction**: Automatic extraction of .zip and .7z archives on download
- **Game Launching**: Launch games directly from the app using:
  - RetroArch (GBA, GBC, GB, NES, SNES, N64, NDS, PSX, PSP, Dreamcast, Megadrive, and more)
  - Dolphin (GameCube & Wii)
  - Eden (Nintendo Switch)
  - RPCS3 (PlayStation 3)
  - PCSX2 (PlayStation 2)
  - DuckStation (PlayStation 1)
  - Azahar (Nintendo 3DS)
  - Cemu (Wii U)
  - Xemu (Xbox)
  - Xenia Canary (Xbox 360)
  - Windows Native (PC games)
- **Emulator Downloads**: One-tap emulator download and installation from Settings
- **Save Sync**: Two-way save synchronization with RomM cloud for:
  - RetroArch (all supported platforms)
  - Dolphin (GameCube/Wii)
  - Eden (Switch)
  - PCSX2 (PS2)
  - RPCS3 (PS3)
  - Xenia Canary (Xbox 360)
  - Windows native games (via PCGamingWiki auto-detection)

## Roadmap

### Near Term

- **Cemu save sync** — Wii U saves at mlc01/usr/save/
- **Azahar save sync** — 3DS saves via SDMC folder
- **MelonDS support** — better NDS emulation alternative
- **macOS & Linux support** — platform detection and path resolution already structured for future expansion

### End-Game Features

- Automatic emulator updates
- Custom ROM platform tagging
- Mobile companion app for on-the-go library browsing

### Cross-Platform Vision

Freegosy is designed as a truly cross-platform experience. The codebase is structured to support Windows, macOS, and Linux with platform-specific code isolated behind strategy patterns and service abstractions.

## Status

Actively under development. Release 0.0.2 focuses on Windows game support and expanded save sync coverage.

## About RomM

Freegosy is built to complement [RomM](https://github.com/rommapp/romm), a modern ROM manager. It connects to your RomM instance to provide a lightweight, portable way to access and play your games.

## Contributing

Check out `agent.md` for the full file map, coding rules, and contracts for adding new emulators, save strategies, or features.