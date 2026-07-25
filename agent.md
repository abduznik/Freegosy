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
- Use `PlatformInfo` for cross-platform abstraction (file: `core/platform/platform_info.dart`). Accept it as a constructor parameter, never use `dart:io Platform` directly in services.
- ROM name sanitization: `!` must be included in the sanitization regex across all services (`extraction_service`, `directory_service`, `rom_lookup_service`) for consistent folder naming.
- Windows games are folder-based: `findMainRomInFolder()` returns the folder path for `windows`/`pc`/`win` slugs, not a file.

## File Map

### Entry Points
- `lib/main.dart` — App entry point. Initializes Riverpod ProviderScope. Calls app.dart.
- `lib/app.dart` — MaterialApp setup, theme, initial route, navigation shell.

### Core — RomM
- `lib/core/romm/romm_service.dart` — All RomM HTTP calls (Dio). Methods: getPlatforms(), getGames(), getAllGames(), getGamesPage(offset, limit, platformId, search), getSaves(), uploadSave(), getLatestSave(), downloadSave(), pruneOldSaves(), getRecentlyPlayed(), getRandomGame(), updateRomProps(), refreshToken(), fetchToken(). Includes silent re-authentication interceptor. Upload uses slot `'freegosy'` (not timestamped), `autocleanup: true`, `autocleanupLimit: 5`, `overwrite: 'force'`.
- `lib/core/romm/romm_models.dart` — Data models: Game, Platform (with fsSlug, displayName, gamesCount and flexible parsing), SaveFile, RomMConfig.
- `lib/core/romm/rom_constants.dart` — Platform slug-to-extension mappings. Windows/PC/Win slugs have empty extension lists (folder-based platforms). PSX/PS2 include `.chd`.

### Core — Save Sync
- `lib/core/save/save_strategy.dart` — Abstract base class SaveStrategy. Methods: getSaveDir(), getSaveFiles(), restoreSave(). Helpers: backupSave() keeps max 3 clean versions (.bak, .bak1, .bak2), getRomStem().
- `lib/core/save/save_sync_service.dart` — SaveSyncService. Methods: pushSaves(), pullSave(), getStrategyForSlug(). getStrategyForSlug() checks StrategyRegistry user preferences first before falling back to platform slug defaults. Wires all strategies to RommService. Exposes windowsSaveStrategy for external access. Has 60s pull cooldown per game ID (in-memory `Map<String, DateTime> _lastPullCheck`). Filename normalization strips RomM timestamp tags `[_timestampPattern]`.
- `lib/core/save/backup_entry.dart` — BackupEntry plain model + hand-written BackupEntryAdapter (typeId=1). Registered in main.dart.
- `lib/core/save/backup_repository.dart` — BackupRepository. Opens the 'freegosy_backups' Hive box. Methods: getEntries(), addEntry() (enforces 8-cap rotation + disk cleanup), removeEntry(), markAsSynced(), getUnsyncedEntries().
- `lib/core/save/backup_service.dart` — BackupService. Methods: createImmediate() (reuses ZipFileEncoder pipeline from SaveSyncService, writes to getApplicationSupportDirectory()/backups/), restore() (extracts chosen zip back to save dir using archive package).
- `lib/core/save/background_sync_queue.dart` — BackgroundSyncQueue. Processes unsynced local backups serially with a 5-second throttle. Triggered on app startup and network reconnection.
- `lib/core/save/strategies/ares_save_strategy.dart` — Ares emulator save strategy. Per-platform extension classification (confirmed/defaulted/log-only). Stem-prefix filename matching. Fresh-install directory creation. 30 platform slugs mapped to folder names.
- `lib/core/save/strategies/retroarch_save_strategy.dart` — RetroArch save strategy. Handles dual-stem matching for states.
- `lib/core/save/strategies/dolphin_save_strategy.dart` — Dolphin save strategy (GC/Wii).
- `lib/core/save/strategies/eden_save_strategy.dart` — Eden/Switch save strategy. Resolves title ID.
- `lib/core/save/strategies/azahar_save_strategy.dart` — Azahar/3DS save strategy. Zip-based sync for SDMC data.
- `lib/core/save/strategies/windows_save_strategy.dart` — Windows native game save strategy. Supports manual override. Recursive save folder search (up to 4 levels deep, skips `__MACOSX`/`_CommonRedist`). Per-file include/exclude filter via glob patterns (`*.ini`, `eeprom.*`, `saves/*`). PCGamingWiki path expansion with `_sanitizeWindowsPath()`.
- `lib/core/save/strategies/pcsx2_save_strategy.dart` — PCSX2 save strategy (PS2).
- `lib/core/save/strategies/rpcs3_save_strategy.dart` — RPCS3 save strategy (PS3). Extracts title ID.
- `lib/core/save/strategies/xenia_save_strategy.dart` — Xenia Canary save strategy (Xbox 360).
- `lib/core/save/strategies/duckstation_save_strategy.dart` — DuckStation save strategy (PS1).
- `lib/core/save/strategies/melonds_save_strategy.dart` — melonDS save strategy (NDS).
- `lib/core/save/strategies/mgba_save_strategy.dart` — mGBA save strategy (GBA/GBC/GB).
- `lib/core/save/strategies/ppsspp_save_strategy.dart` — PPSSPP save strategy (PSP).
- `lib/core/save/strategies/cemu_save_strategy.dart` — Cemu save strategy (Wii U).

### Core — Emulator
- `lib/core/emulator/emulator_strategy.dart` — Abstract base class for launch logic. Has `launchWithHandle()` returning `Process?`. `preLaunch()`/`postLaunch()` hooks.
- `lib/core/emulator/emulator_registry_data.dart` — Static definitions for emulator downloads and filters.
- `lib/core/emulator/strategy_registry.dart` — Registry for emulator strategies with conflict detection. OS-based strategy filtering. `detectConflicts()` returns merged slugs for dedup groups. Canonical slug: shortest without hyphens. Per-game emulator/core preference (`setGameEmulatorPreference`/`getGameEmulatorPreference`/`clearGameEmulatorPreference`). Per-platform core override (`setCoreOverride`/`getCoreOverride`/`clearCoreOverride`). Strategy resolution order: per-game > per-platform > fallback.
- `lib/core/emulator/retroarch_core_list.dart` — 197 libretro cores with searchable platform browser. Per-platform default core selection. Categories: recommended/official/alternative/community.
- `lib/core/emulator/emulator_download_service.dart` — Downloads emulators from direct URLs or GitHub.
- `lib/core/emulator/github_release_service.dart` — Resolves latest GitHub release assets.
- `lib/core/emulator/strategies/` — Specific implementations for each emulator (RetroArch, Dolphin, Eden, Ryujinx, RPCS3, PCSX2, Azahar, Cemu, DuckStation, Flycast, melonDS, PPSSPP, mGBA, MAME, Xemu, Xenia, Windows, Ares).
- `lib/core/emulator/strategies/ares_strategy.dart` — Ares emulator strategy. 30 platform slugs mapped to system names (`kAresSystemNames`). Build CLI args `['--system', systemName]` only (no `--fullscreen`/`--no-file-prompt`). Launch throws for unsupported platforms.
- `lib/core/emulator/strategies/windows_strategy.dart` — Windows native game strategy. `_resolveExePath()` shared by `launch()` and `launchWithHandle()`. `shouldSkipExe()` static filter. Launch args stored per game. `.bat`/`.cmd` launched via `cmd.exe /c`.
- `lib/core/emulator/linux_strategies/` — SteamOS/Linux environment strategies.
  - `linux_environment_strategy.dart` — Interface for ROM/Save/Tool path resolution on Linux.
  - `emudeck_strategy.dart` — EmuDeck-specific resolution (SD card detection, symlink saves).
  - `retrodeck_strategy.dart` — RetroDECK Flatpak resolution.
  - `native_linux_strategy.dart` — Default Linux directory structure.
  - `linux_native_game_service.dart` — Proton/Steam prefix path resolution for native PC games on Linux.

### Core — Extraction
- `lib/core/extraction/extraction_service.dart` — Unified extraction for .zip, .7z, .dmg, .tar.gz, .tar.xz, and .exe. Sanitizes macOS .app bundles. ROM name sanitization includes `!` in regex.

### Core — Downloader
- `lib/core/downloader/download_service.dart` — Stream-based HTTP ROM downloader. Uses `file_name` from API (not `full_path`) to avoid platform prefix duplication. Multi-file launch path joins `existingRomPath` + selected filename.

### Core — Input
- `lib/core/input/gamepad_service.dart` — GamepadService. `_getMappingFor()` resolution: custom mappings → SDL database → known_controllers → empty-token fallback warning → kDefaultMapping. Controller hold detection (500ms → `confirmHold`). Focus gating via `AppLifecycleState`.
- `lib/core/input/gamepad_utils.dart` — GamepadUtils: `decodePOV()` (8 cardinal + diagonal directions), `backendHandledActions()`, `encodeKey()`/`decodeKey()` (polarity suffix), `tokenize()` (strips noise words: usb, hid, gamepad, controller, wireless, device, for, the, by).
- `lib/core/input/known_controllers.dart` — `kControllerMappings` database. PlayStation entries: DualSense, DualShock 4, PS4 Controller (Windows USB), PS5 Controller (Windows USB), PS5 Access Controller, Sony ISE Wireless Controller (macOS/Linux). All PS entries share cross→confirm, circle→back, square→detail, triangle→favorite.
- `lib/core/input/sdl_parser.dart` — SDLMappingParser: SDL key-to-GameAction mapping (15 known keys), SDL format string parsing.
- `lib/core/input/custom_controller_mappings.dart` — Persistence for custom controller mappings via SharedPreferences.
- `lib/core/input/deadzone_config.dart` — Configurable deadzone (0-50%) with per-controller overrides. `applyDeadzone()` rescales `[deadzone, 1.0]` to `[0.0, 1.0]`. DirectInput axes normalized from 0-65535 to -1.0..1.0.

### Core — Platform
- `lib/core/platform/platform_info.dart` — PlatformInfo abstraction for cross-platform testability. Accepts platform name and optional environment map. Used instead of `dart:io Platform` in all services.

### Core — Storage
- `lib/core/storage/directory_service.dart` — Manages paths. Linux Sync Presets (Default/EmuDeck) and EmuDeck root path management. Emulator path overrides via `setEmulatorPathOverride()`/`getEmulatorPathOverride()`. ROM name sanitization includes `!` in regex.
- `lib/core/storage/download_cache_service.dart` — Manages and persists a set of downloaded filenames mapped by platform slug. Uses SharedPreferences.
- `lib/core/storage/rom_lookup_service.dart` — ROM file lookup by name. `findMainRomInFolder()` returns folder path for folder-based platforms (`windows`/`pc`/`win`/`ps3`/`switch`). Fuzzy matching with token-based scoring. `resolveFuzzyRomFile()` for path override resolution.

### Core — Windows
- `lib/core/windows/windows_game_service.dart` — Native execution helper. `findExecutable()` searches `.exe`/`.bat`/`.cmd`. Skips `__MACOSX`/`_CommonRedist`/`._` prefixed files. Token-based fuzzy hint matching. `shouldSkipExe()` filters vcredist, setup, uninstall, etc.
- `lib/core/windows/pcgamingwiki_service.dart` — Queries PCGamingWiki for save locations. `{{p|game}}` uses gameDir directly. `_sanitizeWindowsPath()` strips invalid Windows filename chars (keeps drive letter colons).

### Core — Error
- `lib/core/error/error_handler.dart` — Centralized error handling and snackbar notifications.

### Providers
- `lib/providers/romm_provider.dart` — Riverpod providers for RomM services. Added downloadCacheServiceProvider.
- `lib/providers/library_provider.dart` — Platform and display setting providers.
- `lib/providers/paginated_games_provider.dart` — Server-side pagination. Added recentlyPlayedProvider and statuses support in ActiveFilters.
- `lib/providers/download_provider.dart` — Active download state tracking.

### UI — Screens
- `lib/ui/screens/library_screen.dart` — Main library grid. Includes "Continue Playing" section. Uses LibraryActionsMixin.
- `lib/ui/screens/library_actions.dart` — LibraryActionsMixin containing shared operation logic (download, launch, sync, delete). Integrated with ErrorHandler and MultiDiscPicker. Save pull is non-blocking (`unawaited`). 60s pull cooldown prevents redundant network requests.
- `lib/ui/screens/settings_screen.dart` — Global settings UI. Scroll to Emulators section.
- `lib/ui/screens/settings_emulators_section.dart` — Emulator management UI. Per-game toggle. Emulator status refreshes on screen open.
- `lib/ui/screens/settings_controller_section.dart` — Controller/gamepad settings UI.
- `lib/ui/screens/settings_deadzone_section.dart` — Analog deadzone configuration UI.
- `lib/ui/screens/game_detail_screen.dart` — Expanded game info and actions. Now a StatefulWidget for managing personal game properties (rating, status, completion).

### UI — Widgets
- `lib/ui/widgets/game_card.dart` — Grid item for games.
- `lib/ui/widgets/filter_bottom_sheet.dart` — Library filtering UI. Updated to use status lists.
- `lib/ui/widgets/platform_filter_bar.dart` — Horizontal platform selector.
- `lib/ui/widgets/windows_game_config_dialog.dart` — Manual path override UI. Per-file save filter field (comma-separated globs). Browse button for interactive file picker.
- `lib/ui/widgets/multi_disc_picker.dart` — Bottom sheet for selecting discs in multi-file games. Filters `.m3u`/`.cue`/`.ccd`/`.mds`/`.toc`/`.sub`.
- `lib/ui/widgets/retroarch_core_picker_dialog.dart` — Per-game RetroArch core selection dialog. Searchable platform browser.
- `lib/ui/widgets/gamepad_slider.dart` — GamepadSlider widget (Select to enter, D-pad to adjust deadzone).
- `lib/ui/widgets/screenshot_gallery_dialog.dart` — Fullscreen swipeable screenshot gallery with zoom support.
- `lib/ui/widgets/backup_history_sheet.dart` — Bottom sheet listing up to 8 local backup checkpoints per game. Includes Restore button with pre-restore safety snapshot.

## Key Contracts

### EmulatorStrategy
```dart
abstract class EmulatorStrategy {
  final PlatformInfo _platform;
  String get name;
  String get emulatorId;
  List<String> get supportedSlugs;
  String get windowsExecutable;
  String get linuxExecutable;
  String get macosExecutable;
  bool get supportsSaveSync;
  DirectoryService get directoryService;
  List<String> get launchArgs => [];
  String getExecutableForPlatform();
  Future<String?> findExecutable();
  Future<void> launch(Game game, String romPath);
  Future<Process?> launchWithHandle(Game game, String romPath, {String? coreName});
  Future<void> launchStandalone();
  String resolveSavePath(Game game);
}
```

### PlatformInfo
```dart
class PlatformInfo {
  final String _platformName;
  final Map<String, String> _environment;
  bool get isWindows;
  bool get isLinux;
  bool get isMacOS;
  String get pathSeparator; // '/' on unix, '\\' on windows
}
```

### GamepadUtils
```dart
class GamepadUtils {
  static List<GameAction> decodePOV(int value); // 8 cardinal + diagonal
  static Set<GameAction> backendHandledActions(Set<String> keys);
  static String encodeKey(String key, int polarity);
  static (String, int) decodeKey(String encoded);
  static bool hasPolaritySuffix(String key);
  static Set<String> tokenize(String name); // strips noise words
}
```

## Testing

### Framework
- `flutter_test` (core) + `mockito` (mocking) + `http_mock_adapter` (HTTP) + `fake_async` (async timing)
- Mocks are generated via `@GenerateMocks` annotation + `build_runner`. Generated in `.mocks.dart` files.

### Test Structure
- `test/unit/` — Pure logic tests (42 files)
- `test/widgets/` — Widget rendering tests (6 files)
- `test/core/` — Integration-level core logic (5 files)
- `test/health/` — Smoke checks (1 file)
- `test/mock_romm_server.py` — Flask mock server for integration tests
- `test/save_sync_integration_test.py` — End-to-end save sync tests

### Test Conventions
- Regression tests: `test/unit/*_regression_test.dart` (save_sync, controller_settings)
- Feature tests: `test/unit/<feature>_test.dart` (ares_strategy, ares_save_strategy, etc.)
- Issue-specific tests: `test/unit/<issue>_<feature>_test.dart` (appimage_detection, download_extension, etc.)

### Key Test Files (713 tests as of v0.5.10-pre)
- `controller_settings_regression_test.dart` — 94 tests: built-in mappings, POV decoding, SDL parsing, custom mapping persistence, deadzone config, PS4/PS5 USB controller entries, empty-token fallback
- `ares_strategy_test.dart` — 14 tests: getSystemNameForSlug, supportedSlugs, launch args regression (no --fullscreen/--no-file-prompt), unsupported platform throws
- `ares_save_strategy_test.dart` — 34 tests: extension classification, state file exclusion, stem-prefix matching, restoreSave directory creation
- `save_sync_regression_test.dart` — 8 tests: slot naming, autocleanup, overwrite, pull cooldown, no pruneOldSaves
- `rom_naming_test.dart` — 16 tests: exclamation mark sanitization, stem-prefix matching
- `multi_disc_filter_test.dart` — 13 tests: .m3u/.cue/.ccd/.mds/.toc filtering
- `windows_game_lookup_test.dart` — 11 tests: folder-based platforms, exe detection, nested folders
- `windows_save_filter_test.dart` — 10 tests: glob pattern matching, filter parsing

### Running Tests
```bash
flutter test                    # Full suite (~30s)
flutter test test/unit/ares_strategy_test.dart  # Single file
flutter analyze                 # Lint check
```

### Pre-existing Widget Test Flaky
- `settings_screen_test.dart: "renders emulator section"` — ambiguous ListView finder on macOS. Fixed with `.first` on the finder.

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
