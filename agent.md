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
- `lib/core/romm/romm_service.dart` — All RomM HTTP calls (Dio). Methods: getPlatforms(), getGames(), getAllGames(), getGamesPage(offset, limit, platformId, search), getSaves(), uploadSave(), getLatestSave(), downloadSave(), pruneOldSaves(), getRecentlyPlayed(), getRandomGame(). getGamesPage() uses platform_ids (array), order_by, order_dir, statuses (list) params.
- `lib/core/romm/romm_models.dart` — Data models: Game, Platform (with fsSlug, displayName, gamesCount and flexible parsing), SaveFile, RomMConfig.

### Core — Save Sync
- `lib/core/save/save_strategy.dart` — Abstract base class SaveStrategy. Methods: getSaveDir(), getSaveFiles(), restoreSave(). Helpers: backupSave() keeps max 3 clean versions (.bak, .bak1, .bak2), getRomStem().
- `lib/core/save/save_sync_service.dart` — SaveSyncService. Methods: pushSaves(), pullSave(), getStrategyForSlug(). getStrategyForSlug() checks StrategyRegistry user preferences first before falling back to platform slug defaults. Wires all strategies to RommService. Exposes windowsSaveStrategy for external access.
- `lib/core/save/strategies/retroarch_save_strategy.dart` — RetroArch save strategy. Handles dual-stem matching for states.
- `lib/core/save/strategies/dolphin_save_strategy.dart` — Dolphin save strategy (GC/Wii).
- `lib/core/save/strategies/eden_save_strategy.dart` — Eden/Switch save strategy. Resolves title ID.
- `lib/core/save/strategies/azahar_save_strategy.dart` — Azahar/3DS save strategy. Zip-based sync for SDMC data.
- `lib/core/save/strategies/windows_save_strategy.dart` — Windows native game save strategy. Supports manual override.
- `lib/core/save/strategies/pcsx2_save_strategy.dart` — PCSX2 save strategy (PS2).
- `lib/core/save/strategies/rpcs3_save_strategy.dart` — RPCS3 save strategy (PS3). Extracts title ID.
- `lib/core/save/strategies/xenia_save_strategy.dart` — Xenia Canary save strategy (Xbox 360).
- `lib/core/save/strategies/duckstation_save_strategy.dart` — DuckStation save strategy (PS1).
- `lib/core/save/strategies/melonds_save_strategy.dart` — melonDS save strategy (NDS).
- `lib/core/save/strategies/mgba_save_strategy.dart` — mGBA save strategy (GBA/GBC/GB).
- `lib/core/save/strategies/ppsspp_save_strategy.dart` — PPSSPP save strategy (PSP).
- `lib/core/save/strategies/cemu_save_strategy.dart` — Cemu save strategy (Wii U).

### Core — Emulator
- `lib/core/emulator/emulator_strategy.dart` — Abstract base class for launch logic.
- `lib/core/emulator/emulator_registry_data.dart` — Static definitions for emulator downloads and filters.
- `lib/core/emulator/strategy_registry.dart` — Registry for emulator strategies with conflict detection.
- `lib/core/emulator/emulator_download_service.dart` — Downloads emulators from direct URLs or GitHub.
- `lib/core/emulator/github_release_service.dart` — Resolves latest GitHub release assets.
- `lib/core/emulator/strategies/` — Specific implementations for each emulator (RetroArch, Dolphin, Eden, RPCS3, PCSX2, Azahar, Cemu, DuckStation, Flycast, melonDS, PPSSPP, mGBA, MAME, Xemu, Xenia, Windows).

### Core — Extraction
- `lib/core/extraction/extraction_service.dart` — Unified extraction for .zip, .7z, .dmg, .tar.gz, .tar.xz, and .exe. Sanitizes macOS .app bundles.

### Core — Downloader
- `lib/core/downloader/download_service.dart` — Stream-based HTTP ROM downloader.

### Core — Storage
- `lib/core/storage/directory_service.dart` — Manages paths. Added getAllDownloadedFileNamesByPlatform() for cache mapping.
- `lib/core/storage/download_cache_service.dart` — Manages and persists a set of downloaded filenames mapped by platform slug. Uses SharedPreferences.

### Core — Windows
- `lib/core/windows/windows_game_service.dart` — Native execution helper.
- `lib/core/windows/pcgamingwiki_service.dart` — Queries PCGamingWiki for save locations.

### Core — Error
- `lib/core/error/error_handler.dart` — Centralized error handling and snackbar notifications.

### Providers
- `lib/providers/romm_provider.dart` — Riverpod providers for RomM services. Added downloadCacheServiceProvider.
- `lib/providers/library_provider.dart` — Platform and display setting providers.
- `lib/providers/paginated_games_provider.dart` — Server-side pagination. Added recentlyPlayedProvider and statuses support in ActiveFilters.
- `lib/providers/download_provider.dart` — Active download state tracking.

### UI — Screens
- `lib/ui/screens/library_screen.dart` — Main library grid. Includes "Continue Playing" section. Uses LibraryActionsMixin.
- `lib/ui/screens/library_actions.dart` — LibraryActionsMixin containing shared operation logic (download, launch, sync, delete). Integrated with ErrorHandler and MultiDiscPicker.
- `lib/ui/screens/settings_screen.dart` — Global settings UI.
- `lib/ui/screens/settings_emulators_section.dart` — Emulator management UI.
- `lib/ui/screens/game_detail_screen.dart` — Expanded game info and actions.

### UI — Widgets
- `lib/ui/widgets/game_card.dart` — Grid item for games.
- `lib/ui/widgets/filter_bottom_sheet.dart` — Library filtering UI. Updated to use status lists.
- `lib/ui/widgets/platform_filter_bar.dart` — Horizontal platform selector.
- `lib/ui/widgets/windows_game_config_dialog.dart` — Manual path override UI.
- `lib/ui/widgets/multi_disc_picker.dart` — Bottom sheet for selecting discs in multi-file games.

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
