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
- New screen = new file in `ui/screens/`.
- New reusable widget = new file in `ui/widgets/`.
- Providers are thin — they call services, they do not contain business logic.

## File Map

### Entry Points
- `lib/main.dart` — App entry point. Initializes Riverpod ProviderScope. Calls app.dart.
- `lib/app.dart` — MaterialApp setup, theme, initial route, navigation shell.

### Core — RomM
- `lib/core/romm/romm_service.dart` — All RomM HTTP calls (Dio). Methods: getPlatforms(), getGames(), getSaves(). Returns typed models.
- `lib/core/romm/romm_models.dart` — Data models: Game, Platform, SaveFile, RomMConfig.

### Core — Emulator
- `lib/core/emulator/emulator_strategy.dart` — Abstract base class. Fields: name, emulatorId, supportedSlugs, windowsExecutable, linuxExecutable. Methods: launch(Game, romPath), resolveSavePath(Game), getExecutableForPlatform().
- `lib/core/emulator/emulator_registry_data.dart` — Static data for emulator definitions.
- `lib/core/emulator/strategy_registry.dart` — Registry for emulator strategies. Methods: getStrategyForSlug(), getDefinition().
- `lib/core/emulator/strategies/retroarch_strategy.dart` — RetroArch strategy implementation.
- `lib/core/emulator/strategies/dolphin_strategy.dart` — Dolphin strategy implementation.
- `lib/core/emulator/strategies/eden_strategy.dart` — Eden strategy implementation.
- `lib/core/emulator/emulator_download_service.dart` — Service for downloading and extracting emulators.

### Core — Downloader
- `lib/core/downloader/download_service.dart` — HTTP ROM download via Dio. Exposes a Stream<DownloadProgress> for UI progress tracking. Updated to use DirectoryService.

### Core — Storage
- `lib/core/storage/directory_service.dart` — Manages ROMs and emulator directories, including persistence via SharedPreferences.

### Core — Updater
- `lib/core/updater/updater_service.dart` — Checks GitHub Releases API for new version. Downloads new binary to temp, swaps, relaunches.

### Providers
- `lib/providers/romm_provider.dart` — Riverpod providers for RomM config, connection state, DirectoryService, and EmulatorDownloadService.
- `lib/providers/library_provider.dart` — Riverpod providers for platforms list and games list. Includes search and filtering logic.
- `lib/providers/download_provider.dart` — Riverpod providers for active downloads and progress.

### UI — Screens
- `lib/ui/screens/library_screen.dart` — Main screen. Shows platform filter bar, game grid, search bar, and game count display.
- `lib/ui/screens/download_screen.dart` — Active downloads list with progress bars.
- `lib/ui/screens/settings_screen.dart` — Storage and Emulator management section. Includes path selection, emulator installation status, and download buttons.

### UI — Widgets
- `lib/ui/widgets/game_card.dart` — Single game tile. Shows cover, name, platform. Tappable to launch or download.
- `lib/ui/widgets/download_progress_card.dart` — Single download row with progress bar and cancel button.
- `lib/ui/widgets/platform_filter_bar.dart` — Horizontal scrollable platform chip row with distinct styling for selected/unselected states.

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
- `shared_preferences` — persist RomM config locally
- `package_info_plus` — read current app version for updater
- `archive` — for zip extraction
- `file_picker` — for directory selection
