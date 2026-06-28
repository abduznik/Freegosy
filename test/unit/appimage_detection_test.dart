import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Simulates the AppImage fuzzy matching logic from NativeLinuxStrategy
/// for issue #43.
String? fuzzyAppImageMatch(String executableName, List<String> entries) {
  final targetLower = executableName.toLowerCase();

  for (final entry in entries) {
    final baseName = p.basename(entry);
    final baseNameLower = baseName.toLowerCase();

    // Exact match (case-insensitive)
    if (baseNameLower == targetLower) return entry;

    // Match AppImage files: e.g. "PCSX2.AppImage" matches "pcsx2"
    if (baseNameLower.endsWith('.appimage') &&
        baseNameLower == '$targetLower.appimage') {
      return entry;
    }

    // Fuzzy match: strip common suffixes and compare
    final stripped = baseNameLower
        .replaceAll(RegExp(r'[-_]?(x86_64|amd64|linux|gtk).*'), '')
        .replaceAll(RegExp(r'\.(appimage|AppImage)$'), '');
    if (stripped == targetLower) return entry;
  }

  return null;
}

void main() {
  group('Issue #43 — AppImage fuzzy matching', () {
    test('exact match (case-insensitive)', () {
      final result = fuzzyAppImageMatch('pcsx2', [
        '/home/user/Applications/PCSX2',
      ]);
      expect(result, '/home/user/Applications/PCSX2');
    });

    test('matches .AppImage suffix', () {
      final result = fuzzyAppImageMatch('pcsx2', [
        '/home/user/Applications/PCSX2.AppImage',
      ]);
      expect(result, '/home/user/Applications/PCSX2.AppImage');
    });

    test('matches with architecture suffix', () {
      final result = fuzzyAppImageMatch('duckstation', [
        '/home/user/AppImages/DuckStation-x86_64.AppImage',
      ]);
      expect(result, '/home/user/AppImages/DuckStation-x86_64.AppImage');
    });

    test('matches with linux suffix', () {
      final result = fuzzyAppImageMatch('cemu', [
        '/home/user/Applications/Cemu-linux.AppImage',
      ]);
      expect(result, '/home/user/Applications/Cemu-linux.AppImage');
    });

    test('matches with gtk suffix', () {
      final result = fuzzyAppImageMatch('eden', [
        '/home/user/Applications/Eden-gtk-x86_64.AppImage',
      ]);
      expect(result, '/home/user/Applications/Eden-gtk-x86_64.AppImage');
    });

    test('returns null when no match found', () {
      final result = fuzzyAppImageMatch('rpcs3', [
        '/home/user/Applications/SomeOtherApp.AppImage',
      ]);
      expect(result, isNull);
    });

    test('ignores non-file entries in concept', () {
      // In real code, only io.File entries are checked
      // Here we just verify the matching logic
      final result = fuzzyAppImageMatch('melonds', [
        '/home/user/Applications/some_dir',
        '/home/user/Applications/melonDS.AppImage',
      ]);
      expect(result, '/home/user/Applications/melonDS.AppImage');
    });

    test('matches multiple search directories', () {
      final dirs = [
        '/home/user/Applications/NotIt.AppImage',
        '/home/user/AppImages/PCSX2.AppImage',
        '/home/user/.local/bin/pcsx2',
      ];
      final result = fuzzyAppImageMatch('pcsx2', dirs);
      // Should match PCSX2.AppImage (case-insensitive)
      expect(result, '/home/user/AppImages/PCSX2.AppImage');
    });
  });
}
