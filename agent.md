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
- Never use `Platform.environment` or `Platform.isWindows` directly — causes conflicts with flutter/foundation.dart. Use `Process.run('cmd', ['/c', 'echo %APPDATA%'])` for env vars, and `defaultTargetPlatform == TargetPlatform.windows` for platform checks.

## File Map

### Entry Points
- `lib/main.dart` — App entry point. Initializes Riverpod ProviderScope. Calls app.dart.
- `lib/app.dart` — MaterialApp setup, theme, initial route, navigation shell.

### Core — RomM
- `lib/core/romm/romm_service.dart` — All RomM HTTP calls (Dio). Methods: getPlatforms(), getGames(), getSaves(), uploadSave(), getLatestSave(), downloadSave(). Returns typed models.
- `lib/core/romm/romm_models.dart` — Data models: Game, Platform, SaveFile, RomMConfig.

### Core — Save Sync
- `lib/core/save/save_strategy.dart` — Abstract base class SaveStrategy. Methods: getSaveDir(), getSaveFiles(), restoreSave(). Helpers: backupSave() (3-version rotation), getRomStem().
- `lib/core/save/save_sync_service.dart` — SaveSyncService. Methods: pushSaves(), pullSave(), getStrategyForSlug(). Wires all strategies to RommService. Exposes windowsSaveStrategy for external access.
- `lib/core/save/strategies/retroarch_save_strategy.dart` — RetroArch save strategy (GBA/GBC/GB/SNES/NES/N64/NDS/PSX/PSP/Dreamcast/Megadrive). Reads saves/{coreName}/{stem}.srm and .state.auto.
- `lib/core/save/strategies/dolphin_save_strategy.dart` — Dolphin save strategy (GC/Wii). Reads User/GC/{region}/Card A/*.gci.
- `lib/core/save/strategies/eden_save_strategy.dart` — Eden/Switch save strategy. Resolves title ID via filename regex, XCI header parse, or save folder scan. Zips save folder for upload.
- `lib/core/save/strategies/windows_save_strategy.dart` — Windows native game save strategy. Uses PCGamingWiki API for auto-detection, supports manual override. Zips entire save directory for upload, extracts on restore. Persists overrides via SharedPreferences (prefix `win_save_`).
- `lib/core/save/strategies/pcsx2_save_strategy.dart` — PCSX2 save strategy (PS2). Memcards: {emulatorDir}/memcards/Mcd001.ps2, Mcd002.ps2. States: {emulatorDir}/sstates/{stem}.000 etc.
- `lib/core/save/strategies/rpcs3_save_strategy.dart` — RPCS3 save strategy (PS3). Saves at %APPDATA%\rpcs3\dev_hdd0\home\00000001\savedata\{titleId}\. Extracts title ID via regex [A-Z]{4}\d{5}. Zips save folder for upload. Uses Process.run for APPDATA resolution.
- `lib/core/save/strategies/xenia_save_strategy.dart` — Xenia Canary save strategy (Xbox 360). Saves at {emulatorDir}\content\{titleId}\00000001\. Extracts title ID via 8-char hex regex. Zips save folder for upload.

### Core — Emulator
- `lib/core/emulator/emulator_strategy.dart` — Abstract base class. Fields: name, emulatorId, supportedSlugs, windowsExecutable, linuxExecutable. Methods: launch(Game, romPath), resolveSavePath(Game), getExecutableForPlatform().
- `lib/core/emulator/emulator_registry_data.dart` — Static data for emulator definitions.
- `lib/core/emulator/strategy_registry.dart` — Registry for emulator strategies. Methods: getStrategyForSlug(), getDefinition().
- `lib/core/emulator/emulator_download_service.dart` — Service for downloading and extracting emulators. Supports direct URL and GitHub release types. Handles .zip and .7z extraction.
- `lib/core/emulator/github_release_service.dart` — Fetches latest release asset URL from GitHub API with required/excluded name filters.
- `lib/core/emulator/strategies/retroarch_strategy.dart` — RetroArch strategy. Slugs: gba/gbc/gb/nes/snes/n64/nds/psx/ps1/psp/dc/dreamcast/megadrive/genesis/md etc.
- `lib/core/emulator/strategies/dolphin_strategy.dart` — Dolphin strategy. Slugs: gc/gamecube/wii/ngc.
- `lib/core/emulator/strategies/eden_strategy.dart` — Eden strategy. Slugs: switch/nintendo-switch/ns.
- `lib/core/emulator/strategies/rpcs3_strategy.dart` — RPCS3 strategy. Slugs: ps3/playstation-3/playstation3.
- `lib/core/emulator/strategies/pcsx2_strategy.dart` — PCSX2 strategy. Slugs: ps2/playstation-2/playstation2.
- `lib/core/emulator/strategies/azahar_strategy.dart` — Azahar strategy. Slugs: 3ds/n3ds/nintendo-3ds/nintendo3ds/new-nintendo-3ds/new-nintendo-3ds-xl.
- `lib/core/emulator/strategies/cemu_strategy.dart` — Cemu strategy. Slugs: wiiu/wii-u/nintendo-wii-u/nintendo-wiiu.
- `lib/core/emulator/strategies/duckstation_strategy.dart` — DuckStation strategy. Slugs: ps1/playstation/psx.
- `lib/core/emulator/strategies/xemu_strategy.dart` — Xemu strategy. Slugs: xbox.
- `lib/core/emulator/strategies/xenia_strategy.dart` — Xenia Canary strategy. Slugs: xbox360/xbla.
- `lib/core/emulator/strategies/windows_strategy.dart` — Windows native game strategy. Auto-detects exe in game folder, validates stored override exists on disk before using. Launches via Process.start. Monitors exit code for 5s — throws if crashed. Persists overrides via SharedPreferences (prefix `win_exe_`).

### Core — Downloader
- `lib/core/downloader/download_service.dart` — HTTP ROM download via Dio. Stream<DownloadProgress> for UI. Handles .zip extraction via archive package and .7z via bundled 7zr.exe (resolved via DirectoryService.resolveSevenZipPath()). Windows games (.zip/.7z) always extracted regardless of isMultiFile flag.

### Core — Storage
- `lib/core/storage/directory_service.dart` — Manages ROMs and emulator directories. Persists paths via SharedPreferences. resolveSevenZipPath() extracts bundled 7zr.exe from Flutter assets to %APPDATA%\Freegosy\thirdparty\ on first run. Uses defaultTargetPlatform for Windows check, Process.run for APPDATA resolution.

### Core — Windows
- `lib/core/windows/windows_game_service.dart` — Finds main exe in game folder (hint match then largest). Skips uninstall/setup/redist/etc. Launches via Process.start detached.
- `lib/core/windows/pcgamingwiki_service.dart` — Queries PCGamingWiki API for Windows game save locations. Parses MediaWiki markup, expands environment variables (APPDATA, LOCALAPPDATA etc), returns resolved paths.

### Core — Updater
- `lib/core/updater/updater_service.dart` — Checks GitHub Releases API for new version. Downloads new binary to temp, swaps, relaunches.

### Providers
- `lib/providers/romm_provider.dart` — Riverpod providers for RomM config, connection state, DirectoryService, StrategyRegistry (loads WindowsStrategy persisted overrides on init), SaveSyncService (loads WindowsSaveStrategy persisted overrides on init).
- `lib/providers/library_provider.dart` — Riverpod providers for platforms list and games list. Includes search, filtering, card aspect ratio, and RetroArch sync mode persistence.
- `lib/providers/download_provider.dart` — Riverpod providers for active downloads and progress.

### UI — Screens
- `lib/ui/screens/library_screen.dart` — Main screen. Game grid with search, platform filter, download, launch, save sync. Windows games support long-press to open config dialog and auto-show config on missing exe. Launch errors show for 8 seconds.
- `lib/ui/screens/download_screen.dart` — Active downloads list with progress bars.
- `lib/ui/screens/settings_screen.dart` — RomM server config, card aspect ratio, storage paths, RetroArch sync mode, emulator download/install status.

### UI — Widgets
- `lib/ui/widgets/game_card.dart` — Single game tile. Shows cover, name, download/launch/sync buttons. Green dot when downloaded.
- `lib/ui/widgets/download_progress_card.dart` — Single download row with progress bar and cancel button.
- `lib/ui/widgets/platform_filter_bar.dart` — Horizontal scrollable platform chip row with distinct styling for selected/unselected states.
- `lib/ui/widgets/windows_game_config_dialog.dart` — Dialog for configuring Windows game exe path and save directory. Browse buttons for both. Returns `Map<String, String>` with keys `exe` and `save`. Only shown for Windows platform games.

## Key Contracts

### EmulatorStrategy (never change these signatures)
```dart
abstract class EmulatorStrategy {
  String get name;
  String get emulatorId;
  List<String> get supportedSlugs;
  String get windowsExecutable;
  String get linuxExecutable;
  String getExecutableForPlatform();
  Future<void> launch(Game game, String romPath);
  String resolveSavePath(Game game);
  bool get supportsSaveSync;
}
```

### DownloadProgress
```dart
class DownloadProgress {
  final String id; // e.g., game ID or emulator ID
  final String gameName; // display name (game.name or emulator name)
  final double percent;
  final int bytesReceived;
  final int totalBytes;
  final bool isComplete;
  final String? error;
}
```

### RomMConfig
```dart
class RomMConfig {
  final String baseUrl;
  final String username;
  final String password;
}
```

## Dependencies (pubspec.yaml)
- `flutter_riverpod` — state management
- `dio` — HTTP client for API calls and downloads
- `path_provider` — platform-safe file paths
- `shared_preferences` — persist RomM config, card ratio, sync mode, Windows exe/save overrides
- `package_info_plus` — read current app version for updater
- `archive` — zip extraction and creation (ZipDecoder, ZipFileEncoder)
- `file_picker` — directory and file selection
- `path` — path manipulation utilities
- `thirdparty/7zr.exe` — bundled 7-Zip console executable for .7z extraction (Flutter asset)