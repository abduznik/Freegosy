import 'dart:io';
import 'package:path/path.dart' as p;

class LinuxNativeGameService {
  /// Maps a Windows-style path to its equivalent Proton prefix path.
  /// [steamId] is the Steam AppID or shortcut ID used for the compatdata folder.
  /// [windowsPath] is the path as it would appear on Windows (e.g., "C:\\Users\\user\\AppData\\Roaming\\Game").
  String? resolveProtonPath(String steamId, String windowsPath) {
    final home = Platform.environment['HOME'] ?? '';
    final prefixBase = p.join(home, '.steam', 'steam', 'steamapps', 'compatdata', steamId, 'pfx', 'drive_c');
    
    // Normalize windows path
    String normalized = windowsPath.replaceAll('\\', '/');
    if (normalized.startsWith('C:/')) {
      normalized = normalized.substring(3);
    } else if (normalized.startsWith('c:/')) {
      normalized = normalized.substring(3);
    }

    // Handle common user folders
    // Windows: Users/steamuser/AppData/Roaming
    // Windows: Users/steamuser/Documents
    // Windows: Users/steamuser/Saved Games
    
    // Replace standard Windows user folders with Proton equivalent 'steamuser'
    final userPattern = RegExp(r'^Users/[^/]+/', caseSensitive: false);
    normalized = normalized.replaceFirst(userPattern, 'users/steamuser/');

    return p.join(prefixBase, normalized);
  }

  /// Tries to find common save locations for a game within its Proton prefix.
  Future<List<String>> findCommonSaveLocations(String steamId) async {
    final home = Platform.environment['HOME'] ?? '';
    final prefixBase = p.join(home, '.steam', 'steam', 'steamapps', 'compatdata', steamId, 'pfx', 'drive_c', 'users', 'steamuser');
    
    final locations = [
      p.join(prefixBase, 'AppData', 'Roaming'),
      p.join(prefixBase, 'AppData', 'Local'),
      p.join(prefixBase, 'Documents'),
      p.join(prefixBase, 'Saved Games'),
    ];

    final existing = <String>[];
    for (final loc in locations) {
      if (await Directory(loc).exists()) {
        existing.add(loc);
      }
    }
    return existing;
  }
}
