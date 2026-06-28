import 'package:flutter_test/flutter_test.dart';

/// Simulates the MelonDsSaveStrategy save directory resolution logic
/// for issue #42 — verifies expanded search paths work correctly.
///
/// Uses plain string matching instead of the `path` package to avoid
/// platform-specific separator issues when running tests on macOS/Linux
/// with Windows-style paths.
class MelonDsSaveDirSimulator {
  final String platform;
  final String home;
  final String? appData;
  final Map<String, bool> existingDirs;

  MelonDsSaveDirSimulator({
    required this.platform,
    this.home = '/home/user',
    this.appData,
    this.existingDirs = const {},
  });

  String resolveSaveDir(String romPath) {
    final romDir = _dirname(romPath);

    if (platform == 'linux') {
      final emuDir = '$home/.config/melonds';
      if (existingDirs[emuDir] == true) return emuDir;
    }

    // ROM-adjacent check
    if (existingDirs[romDir] == true) {
      final sep = platform == 'windows' ? '\\' : '/';
      final stem = _basenameWithoutExtension(romPath).toLowerCase();
      if (existingDirs['$romDir$sep$stem.sav'] == true ||
          existingDirs['$romDir$sep$stem.srm'] == true) {
        return romDir;
      }
    }

    // Windows: %APPDATA%\melonDS
    if (platform == 'windows' && appData != null) {
      for (final folderName in ['melonDS', 'melonds']) {
        final melonDir = '$appData\\$folderName';
        if (existingDirs[melonDir] == true) return melonDir;
      }
      // Also check USERPROFILE\Documents\melonDS
      final docsDir = '$home\\Documents\\melonDS';
      if (existingDirs[docsDir] == true) return docsDir;
    }

    // macOS: ~/Library/Application Support/melonDS
    if (platform == 'macos') {
      final macDir = '$home/Library/Application Support/melonDS';
      if (existingDirs[macDir] == true) return macDir;
    }

    return romDir; // Fallback
  }

  String _dirname(String path) {
    final sep = platform == 'windows' ? '\\' : '/';
    final lastSep = path.lastIndexOf(sep);
    if (lastSep <= 0) return platform == 'windows' ? '\\' : '/';
    return path.substring(0, lastSep);
  }

  String _basenameWithoutExtension(String path) {
    final sep = platform == 'windows' ? '\\' : '/';
    final lastSep = path.lastIndexOf(sep);
    final base = lastSep >= 0 ? path.substring(lastSep + 1) : path;
    final lastDot = base.lastIndexOf('.');
    if (lastDot <= 0) return base;
    return base.substring(0, lastDot);
  }
}

void main() {
  group('Issue #42 — MelonDS save directory resolution', () {
    test('finds save dir in ROM-adjacent location', () {
      final sim = MelonDsSaveDirSimulator(
        platform: 'windows',
        existingDirs: {
          'C:\\roms\\nds': true,
          'C:\\roms\\nds\\pokemon.sav': true,
        },
      );
      final result = sim.resolveSaveDir('C:\\roms\\nds\\pokemon.nds');
      expect(result, 'C:\\roms\\nds');
    });

    test('finds save dir in %APPDATA%\\melonDS on Windows', () {
      final sim = MelonDsSaveDirSimulator(
        platform: 'windows',
        home: 'C:\\Users\\player',
        appData: 'C:\\Users\\player\\AppData\\Roaming',
        existingDirs: {
          'C:\\Users\\player\\AppData\\Roaming\\melonDS': true,
        },
      );
      final result = sim.resolveSaveDir('C:\\roms\\nds\\game.nds');
      expect(result, 'C:\\Users\\player\\AppData\\Roaming\\melonDS');
    });

    test('finds save dir in %APPDATA%\\melonds (lowercase) on Windows', () {
      final sim = MelonDsSaveDirSimulator(
        platform: 'windows',
        home: 'C:\\Users\\player',
        appData: 'C:\\Users\\player\\AppData\\Roaming',
        existingDirs: {
          'C:\\Users\\player\\AppData\\Roaming\\melonds': true,
        },
      );
      final result = sim.resolveSaveDir('C:\\roms\\nds\\game.nds');
      expect(result, 'C:\\Users\\player\\AppData\\Roaming\\melonds');
    });

    test('finds save dir in Documents\\melonDS on Windows', () {
      final sim = MelonDsSaveDirSimulator(
        platform: 'windows',
        home: 'C:\\Users\\player',
        appData: 'C:\\Users\\player\\AppData\\Roaming',
        existingDirs: {
          'C:\\Users\\player\\Documents\\melonDS': true,
        },
      );
      final result = sim.resolveSaveDir('C:\\roms\\nds\\game.nds');
      expect(result, 'C:\\Users\\player\\Documents\\melonDS');
    });

    test('finds save dir in ~/Library/Application Support/melonDS on macOS', () {
      final sim = MelonDsSaveDirSimulator(
        platform: 'macos',
        home: '/Users/player',
        existingDirs: {
          '/Users/player/Library/Application Support/melonDS': true,
        },
      );
      final result = sim.resolveSaveDir('/roms/nds/game.nds');
      expect(result, '/Users/player/Library/Application Support/melonDS');
    });

    test('finds save dir in ~/.config/melonds on Linux', () {
      final sim = MelonDsSaveDirSimulator(
        platform: 'linux',
        home: '/home/player',
        existingDirs: {
          '/home/player/.config/melonds': true,
        },
      );
      final result = sim.resolveSaveDir('/roms/nds/game.nds');
      expect(result, '/home/player/.config/melonds');
    });

    test('falls back to ROM directory when nothing found', () {
      final sim = MelonDsSaveDirSimulator(
        platform: 'windows',
        home: 'C:\\Users\\player',
        appData: 'C:\\Users\\player\\AppData\\Roaming',
        existingDirs: {},
      );
      final result = sim.resolveSaveDir('C:\\roms\\nds\\game.nds');
      expect(result, 'C:\\roms\\nds');
    });

    test('ROM-adjacent check has priority over APPDATA on Windows', () {
      final sim = MelonDsSaveDirSimulator(
        platform: 'windows',
        home: 'C:\\Users\\player',
        appData: 'C:\\Users\\player\\AppData\\Roaming',
        existingDirs: {
          'C:\\roms\\nds': true,
          'C:\\roms\\nds\\game.sav': true,
          'C:\\Users\\player\\AppData\\Roaming\\melonDS': true,
        },
      );
      final result = sim.resolveSaveDir('C:\\roms\\nds\\game.nds');
      expect(result, 'C:\\roms\\nds'); // ROM-adjacent wins
    });
  });
}
