# Freegosy — Agent Map
> This file is the source of truth for all LLM agents (Claude, Gemini) working on this codebase.
> Read this before touching any file. Update this file if you create or split any file.

## Project Overview
Freegosy is a cross-platform Flutter app for browsing a RomM library, downloading ROMs via HTTP, and launching emulators. Built with Riverpod for state management.

## Rules (MANDATORY)
- No file exceeds 600 lines. If adding code would exceed this, split the file first and update this map.
- All RomM API calls go through `romm_service.dart` only. Never call the API directly from UI or providers.
- All emulator logic goes through the strategy pattern. Never hardcode emulator behavior in UI.
- New emulator = new file in `core/emulator/strategies/`, register in `strategy_registry.dart` only.
- New save strategy = new file in `core/save/strategies/`, register in `save_sync_service.dart` only.
- New screen = new file in `ui/screens/`.
- New reusable widget = new file in `ui/widgets/`.
- Providers are thin — they call services, they do not contain business logic.
- Never use `Platform.environment` or `Platform.isWindows` directly — causes conflicts with flutter/foundation.dart. Use `import 'dart:io' as io;` and `io.Platform` or `defaultTargetPlatform == TargetPlatform.windows`.

## File Map

### Entry Points
- `lib/main.dart` — App entry point. Initializes Riverpod ProviderScope. Calls app.dart.
- `lib/app.dart` — MaterialApp setup, theme, initial route, navigation shell.

### Core — RomM
- `lib/core/romm/romm_service.dart` — All RomM HTTP calls (Dio). Methods: getPlatforms(), getGames(), getAllGames(), getGamesPage(offset, limit, platformId, search), getSaves(), uploadSave(), getLatestSave(), downloadSave(), pruneOldSaves(). getGamesPage() uses platform_ids (array), order_by, order_dir params per RomM 4.x API spec. Returns typed models.
- `lib/core/romm/romm_models.dart` — Data models: Game, Platform, SaveFile, RomMConfig.

### Core — Save Sync
- `lib/core/save/save_strategy.dart` — Abstract base class SaveStrategy. Methods: getSaveDir(), getSaveFiles(), restoreSave(). Helpers: backupSave() keeps max 3 clean versions (.bak, .bak1, .bak2) — never creates chained .bak.bak files., getRomStem().
- `lib/core/save/save_sync_service.dart` — SaveSyncService. Methods: pushSaves(), pullSave(), getStrategyForSlug(). getStrategyForSlug() checks StrategyRegistry user preferences first before falling back to platform slug defaults. Accepts StrategyRegistry as constructor parameter. Wires all strategies to RommService. Exposes windowsSaveStrategy for external access.
- `lib/core/save/strategies/retroarch_save_strategy.dart` — RetroArch save strategy (GBA/GBC/GB/SNES/NES/N64/NDS/PSX/PSP/Dreamcast/Megadrive). Reads saves/{coreName}/{stem}.srm and .state.auto. PSP special case returns entire saves/PPSSPP/PSP directory as zip. All platforms use dual-stem (getRomStem + romPath filename) for state file matching. Directory existence check handles both File and Directory types.
- `lib/core/save/strategies/dolphin_save_strategy.dart` — Dolphin save strategy (GC/Wii). Reads User/GC/{region}/Card A/*.gci. Supports macOS via ~/Library/Application Support/Dolphin resolution.
- `lib/core/save/strategies/eden_save_strategy.dart` — Eden/Switch save strategy. Resolves title ID via filename regex, XCI header parse, or save folder scan. Zips save folder for upload.
- `lib/core/save/strategies/azahar_save_strategy.dart` — Azahar/3DS save strategy. Uses manual folder mapping and zip-based sync for SDMC data.
- `lib/core/save/strategies/windows_save_strategy.dart` — Windows native game save strategy. Uses PCGamingWiki API for auto-detection, supports manual override. Zips entire save directory for upload, extracts on restore. Persists overrides via SharedPreferences (prefix `win_save_`).
- `lib/core/save/strategies/pcsx2_save_strategy.dart` — PCSX2 save strategy (PS2). Memcards: {systemDir}/memcards/*.ps2. States: {systemDir}/sstates/{stem}.*. Supports cross-platform system directory resolution (Application Support on macOS, APPDATA on Windows).
- `lib/core/save/strategies/rpcs3_save_strategy.dart` — RPCS3 save strategy (PS3). Saves at %APPDATA%pcs3\dev_hdd0\home\00000001\savedata\{titleId}\ (Windows) or ~/Library/Application Support/rpcs3/... (macOS). Extracts title ID via regex [A-Z]{4}\d{5}. Zips save folder for upload.
- `lib/core/save/strategies/xenia_save_strategy.dart` — Xenia Canary save strategy (Xbox 360). Saves at {emulatorDir}\content\{titleId}\00000001\. Extracts title ID via 8-char hex regex. Zips save folder for upload.
- `lib/core/save/strategies/duckstation_save_strategy.dart` — DuckStation save strategy (PS1). Checks for portable.txt in emulator dir — if present uses {emulatorDir}/memcards/{stem}.mcd, otherwise falls back to %LOCALAPPDATA%\DuckStation\memcards\{stem}.mcd.
- `lib/core/save/strategies/melonds_save_strategy.dart` — melonDS save strategy (NDS). Saves .sav file next to ROM, derived from actual romPath filename not game name.
- `lib/core/save/strategies/mgba_save_strategy.dart` — mGBA save strategy (GBA/GBC/GB). Saves .sav file next to ROM, derived from actual romPath filename.
- `lib/core/save/strategies/ppsspp_save_strategy.dart` — PPSSPP save strategy (PSP). Saves at {emulatorDir}/memstick/PSP/SAVEDATA/, states at PPSSPP_STATE/. Returns entire PSP/SAVEDATA directory as zip. Restore strips top-level SAVEDATA folder to extract directly into memstick/PSP/SAVEDATA/.
- `lib/core/save/strategies/cemu_save_strategy.dart` — Cemu save strategy (Wii U). Zips {emulatorDir}/mlc01/usr/save/00050000/ for upload. Restore extracts zip directly into mlc01/usr/save/ skipping .bak entries.

### Core — Emulator
- `lib/core/emulator/emulator_strategy.dart` — Abstract base class. Fields: name, emulatorId, supportedSlugs, windowsExecutable, linuxExecutable, macosExecutable. Methods: launch(Game, romPath), launchStandalone(), resolveSavePath(Game), getExecutableForPlatform(). Optional launchWithHandle(Game, romPath) returns Process handle for auto-sync.
- `lib/core/emulator/emulator_registry_data.dart` — Static data for emulator definitions. Supports platform-specific GitHub repo keys (github_repo_macos) and asset filters (github_asset_required_macos).
- `lib/core/emulator/strategy_registry.dart` — Registry for emulator strategies. Includes conflict detection and canonical slug grouping. getStrategyById(id) provides direct strategy access.
- `lib/core/emulator/emulator_download_service.dart` — Service for downloading emulators. Supports direct URL and platform-aware GitHub release resolution.
- `lib/core/emulator/github_release_service.dart` — Fetches latest release asset URL from GitHub API with required/excluded name filters.
- `lib/core/emulator/strategies/retroarch_strategy.dart` — RetroArch strategy. Automates 3DS setup (citra/sysdata/config) and downloads shared_font.bin from mirror. Standalone launch uses 'open' for macOS .app.
- `lib/core/emulator/strategies/dolphin_strategy.dart` — Dolphin strategy. Slugs: gc/gamecube/wii/ngc. Supports macOS .app bundle launching.
- `lib/core/emulator/strategies/eden_strategy.dart` — Eden strategy. Slugs: switch/nintendo-switch/ns. Supports macOS .app bundle launching.
- `lib/core/emulator/strategies/rpcs3_strategy.dart` — RPCS3 strategy. Slugs: ps3/playstation-3/playstation3. Supports macOS native binaries and .app bundle launching.
- `lib/core/emulator/strategies/pcsx2_strategy.dart` — PCSX2 strategy. Slugs: ps2/playstation-2/playstation2.
- `lib/core/emulator/strategies/azahar_strategy.dart` — Azahar strategy. Slugs: 3ds/n3ds/nintendo-3ds/nintendo3ds/new-nintendo-3ds/new-nintendo-3ds-xl. Automates 3DS shared font download and system directory (~/Library/Application Support/Azahar on macOS).
- `lib/core/emulator/strategies/cemu_strategy.dart` — Cemu strategy. Slugs: wiiu/wii-u/nintendo-wii-u/nintendo-wiiu.
- `lib/core/emulator/strategies/duckstation_strategy.dart` — DuckStation strategy. Slugs: ps1/playstation/psx.
- `lib/core/emulator/strategies/flycast_strategy.dart` — Flycast strategy. Slugs: dc/dreamcast/naomi/naomi2/atomiswave/cave/hikaru.
- `lib/core/emulator/strategies/melonds_strategy.dart` — melonDS strategy. Slugs: nds/nintendo-ds/ds.
- `lib/core/emulator/strategies/ppsspp_strategy.dart` — PPSSPP strategy. Slugs: psp/playstation-portable. Implements launchWithHandle().
- `lib/core/emulator/strategies/mgba_strategy.dart` — mGBA strategy. Slugs: gba/gbc/gb/game-boy-advance/game-boy-color/game-boy.
- `lib/core/emulator/strategies/mame_strategy.dart` — MAME strategy. Slugs: arcade/mame. Handles self-extracting .exe downloads.
- `lib/core/emulator/strategies/xemu_strategy.dart` — Xemu strategy. Slugs: xbox.
- `lib/core/emulator/strategies/xenia_strategy.dart` — Xenia Canary strategy. Slugs: xbox360/xbla.
- `lib/core/emulator/strategies/windows_strategy.dart` — Windows native game strategy. Auto-detects exe in game folder.

### Core — Extraction
- `lib/core/extraction/extraction_service.dart` — Unified extraction service. Handles .zip, .7z (via bundled 7zr.exe/7zz), .dmg (macOS), .tar.gz, .tar.xz, and self-extracting .exe files. Sanitizes macOS .app bundles (xattr -cr).

### Core — Downloader
- `lib/core/downloader/download_service.dart` — HTTP ROM download via Dio. Stream<DownloadProgress> for UI.

### Core — Storage
- `lib/core/storage/directory_service.dart` — Manages ROMs and emulator directories. resolveSevenZipPath() extracts bundled 7zr.exe (Windows) or 7zz (macOS) and ensures executable permissions. getEmulatorSystemDirectory() resolves platform-specific system paths (e.g. Application Support).

### Core — Windows
- `lib/core/windows/windows_game_service.dart` — Finds main exe in game folder. Launches via Process.start detached.
- `lib/core/windows/pcgamingwiki_service.dart` — Queries PCGamingWiki API for Windows game save locations.

### Providers
- `lib/providers/romm_provider.dart` — Riverpod providers for RomM config, connection state, DirectoryService, StrategyRegistry, SaveSyncService.
- `lib/providers/library_provider.dart` — Riverpod providers for platforms and display settings.
- `lib/providers/paginated_games_provider.dart` — PaginatedGamesNotifier. Handles all game fetching with server-side pagination.
- `lib/providers/download_provider.dart` — Riverpod providers for active downloads.

### UI — Screens
- `lib/ui/screens/library_screen.dart` — Main screen. Game grid. Implements 3DS aes_keys.txt existence check before launch.
- `lib/ui/screens/settings_screen.dart` — Server config and storage paths.
- `lib/ui/screens/settings_emulators_section.dart` — Emulator management UI. Includes "Launch Standalone" button for installed emulators.

## Key Contracts

### EmulatorStrategy
```dart
abstract class EmulatorStrategy {
  String get name;
  String get emulatorId;
  List<String> get supportedSlugs;
  String getExecutableForPlatform();
  Future<void> launch(Game game, String romPath);
  Future<void> launchStandalone();
  String resolveSavePath(Game game);
  bool get supportsSaveSync;
}
```

## Dependencies (pubspec.yaml)
- `flutter_riverpod` — state management
- `dio` — HTTP client
- `path_provider` — platform-safe file paths
- `shared_preferences` — persistence
- `archive` — zip utilities
- `cached_network_image` — image caching
- `file_picker` — file selection
- `path` — path manipulation
- `thirdparty/7zr.exe` — bundled 7-Zip (Windows)
- `thirdparty/7zz` — bundled 7-Zip (macOS)