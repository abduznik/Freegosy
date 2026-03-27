# Freegosy

A cross-platform Flutter app for browsing your RomM library, downloading ROMs, and launching games directly in emulators—all from one intuitive interface.

## What's New in 0.1.2

### Paginated Library Loading
- Library now loads 50 games at a time instead of fetching everything at once
- Scroll to the bottom to automatically load more games
- Supports libraries with 2000+ games without performance issues

### Server-Side Platform Filtering
- Switching platforms now fetches only that platform's games from the server
- Fixed RomM 4.x API compatibility — correctly uses `platform_ids` parameter
- Platform results are cached in memory for instant switching on revisit

### Search Improvements
- Search is now debounced — waits 300ms after typing before firing the API call
- No more per-keystroke requests hammering your RomM server

### UX Fixes
- F5 refresh now correctly shows the loading animation and clears cache
- Pull-to-refresh always fetches fresh data from the server

## What's New in 0.1.1

- API key token verification improvements

## What's New in 0.1.0

### New Emulator Support
- **Flycast** (Dreamcast, Naomi, Atomiswave)
- **melonDS** (Nintendo DS)
- **PPSSPP** standalone (PlayStation Portable)
- **mGBA** standalone (Game Boy Advance, GBC, GB)
- **MAME** (Arcade)

### Expanded Save Sync
- **DuckStation** (PS1): Memory card save sync
- **melonDS** (NDS): Save file sync
- **mGBA** (GBA/GBC/GB): Save file sync
- **PPSSPP** (PSP): Entire SAVEDATA directory with automatic folder structure restoration
- **Cemu** (Wii U): Full mlc01/usr/save/ directory packaging and restore
- All new strategies support both push (upload) and pull (download) operations

### Auto-Sync on Game Close
- Saves automatically push to cloud when you close the emulator
- Available for all supported emulators via `launchWithHandle()`
- Seamless background operation—no manual intervention needed
- Works alongside pre-launch save push and manual sync

### Smart Emulator Management
- **Conflict Resolver**: When multiple emulators support the same platform, choose which one to use in Settings
- **Path Overrides**: Point Freegosy to existing emulator installations via Settings folder icon (no need to re-download)
- **Preference Persistence**: Your emulator choices and custom paths are saved across app restarts

### RetroArch Core Auto-Download
- Missing cores are detected at launch time
- User is offered to auto-download and install the required core
- Full core list support via RetroArch buildbot

### Performance & UX Enhancements
- Library grid renders without blocking—0% CPU while idle
- Cached images (memCache) for fast card rendering
- Optimized grid with extended cache extent and dual-stem state file matching for RetroArch
- **Library Display Presets**: Windows, Steam Deck, Cozy, Compact—quick-switch your layout
- **Launch Status Snackbars**: Real-time feedback showing "Pushing saves / Syncing saves / Launching / Auto-syncing" at each stage
- **Downloads Tab**: Emulator downloads now show alongside game downloads with progress tracking

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
  - Flycast (Dreamcast, Naomi, Atomiswave)
  - melonDS (Nintendo DS)
  - PPSSPP (PlayStation Portable)
  - mGBA (Game Boy Advance/Color/Game Boy)
  - MAME (Arcade)
  - Windows Native (PC games)
- **Emulator Downloads**: One-tap emulator download and installation from Settings
- **Save Sync**: Bidirectional save synchronization with RomM cloud for:
  - RetroArch (all supported platforms)
  - Dolphin (GameCube/Wii)
  - Eden (Switch)
  - PCSX2 (PS2)
  - RPCS3 (PS3)
  - DuckStation (PS1)
  - melonDS (NDS)
  - mGBA (GBA/GBC/GB)
  - PPSSPP (PSP)
  - Cemu (Wii U)
  - Xenia Canary (Xbox 360)
  - Windows native games (via PCGamingWiki auto-detection)

## Roadmap

### In Progress
- **Linux/macOS support** — Platform detection and path resolution already structured; adding platform-specific executable paths and environment variable resolution

### Near Term
- **Auto-update emulators** — Keep emulators fresh without manual downloads
- **Android support** — Deep links to app stores for Play Store/Epic Games/etc.
- **Recently played / play time tracking** — See your gaming stats at a glance

### End-Game Features
- Custom ROM platform tagging
- Mobile companion app for on-the-go library browsing

### Cross-Platform Vision
Freegosy is designed as a truly cross-platform experience. The codebase is structured to support Windows, macOS, Linux, and Android with platform-specific code isolated behind strategy patterns and service abstractions.

## Status

Actively under development. Release 0.1.2 brings paginated library loading and server-side platform filtering for large library support.

## About RomM

Freegosy is built to complement [RomM](https://github.com/rommapp/romm), a modern ROM manager. It connects to your RomM instance to provide a lightweight, portable way to access and play your games.

## Contributing

Check out `agent.md` for the full file map, coding rules, and contracts for adding new emulators, save strategies, or features.
