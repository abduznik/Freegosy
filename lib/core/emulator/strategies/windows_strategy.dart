import 'dart:io';
import 'package:freegosy/core/emulator/emulator_strategy.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/windows/windows_game_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WindowsStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;
  final WindowsGameService _windowsGameService;

  // Manual exe overrides per game id
  final Map<String, String> _exeOverrides = {};

  WindowsStrategy(this._directoryService)
      : _windowsGameService = WindowsGameService();

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'Windows';

  @override
  String get emulatorId => 'windows_native';

  @override
  List<String> get supportedSlugs => ['windows', 'pc', 'win'];

  @override
  String get windowsExecutable => '';

  @override
  String get linuxExecutable => '';

  @override
  bool get supportsSaveSync => true;

  static const String _prefsPrefix = 'win_exe_';

  Future<void> loadPersistedOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefsPrefix));
    for (final key in keys) {
      final gameId = key.substring(_prefsPrefix.length);
      final path = prefs.getString(key);
      if (path != null && path.isNotEmpty) _exeOverrides[gameId] = path;
    }
  }

  Future<void> setExeOverride(String gameId, String exePath) async {
    _exeOverrides[gameId] = exePath;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefsPrefix$gameId', exePath);
  }

  String? getExeOverride(String gameId) => _exeOverrides[gameId];

  @override
  Future<void> launch(Game game, String romPath) async {
    // romPath for Windows games is the extracted game folder
    String? exePath = _exeOverrides[game.id];

    // If stored override no longer exists on disk, discard and auto-detect
    if (exePath != null && exePath.isNotEmpty && !await File(exePath).exists()) {
      exePath = null;
    }

    if (exePath == null || exePath.isEmpty) {
      // Auto-detect exe in the game folder
      final isDir = await Directory(romPath).exists();
      final searchDir = isDir ? romPath : File(romPath).parent.path;
      exePath = await _windowsGameService.findExecutable(
        searchDir,
        hint: game.name,
      );
    }

    if (exePath == null) {
      throw Exception(
        'No executable found for ${game.name}. '
        'Please set the exe path manually.',
      );
    }

    final process = await Process.start(
      exePath,
      [],
      workingDirectory: File(exePath).parent.path,
    );

    // Wait up to 5 seconds — if process exits that fast it crashed
    final exitCode = await process.exitCode
        .timeout(const Duration(seconds: 5))
        .catchError((_) => -99999); // timeout = still running = fine

    if (exitCode != -99999 && exitCode != 0) {
      throw Exception(
        '${game.name} crashed immediately (exit code $exitCode). '
        'This is likely due to missing DirectX, Visual C++ redistributables, or other dependencies.',
      );
    }
  }

  @override
  Future<void> launchStandalone() async {}

  @override
  String resolveSavePath(Game game) => '';
}