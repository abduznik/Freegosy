import 'package:path/path.dart' as p;

class RomConstants {
  // Known extensions per platform slug
  static const Map<String, List<String>> platformExtensions = {
    'switch': ['.nsp', '.xci', '.nsz', '.xcz'],
    'nintendo-switch': ['.nsp', '.xci', '.nsz', '.xcz'],
    'ns': ['.nsp', '.xci', '.nsz', '.xcz'],
    'gba': ['.gba', '.zip', '.7z'],
    'gbc': ['.gbc', '.gb', '.zip', '.7z'],
    'gb': ['.gb', '.gbc', '.zip', '.7z'],
    'nds': ['.nds', '.zip', '.7z'],
    'n64': ['.z64', '.n64', '.v64', '.zip', '.7z'],
    'snes': ['.sfc', '.smc', '.zip', '.7z'],
    'nes': ['.nes', '.zip', '.7z'],
    'psx': ['.bin', '.cue', '.iso', '.img', '.chd', '.pbp'],
    'ps2': ['.iso', '.bin', '.chd'],
    'ps3': ['.pkg', '.iso', '.bin', '.edat'],
    'psp': ['.iso', '.cso', '.pbp'],
    'gc': ['.iso', '.gcm', '.rvz', '.wbfs'],
    'gamecube': ['.iso', '.gcm', '.rvz', '.wbfs'],
    'wii': ['.iso', '.wbfs', '.rvz'],
    'dreamcast': ['.chd', '.gdi', '.cdi', '.iso'],
    'megadrive': ['.md', '.bin', '.gen', '.zip', '.7z'],
    'genesis': ['.md', '.bin', '.gen', '.zip', '.7z'],
    '3ds': ['.3ds', '.cia', '.app'],
    'wiiu': ['.wua', '.rpx', '.wud', '.wux'],
  };

  static bool isRomFile(String platformSlug, String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext.isEmpty) return false;
    final allowed = platformExtensions[platformSlug.toLowerCase()] ?? [];
    if (allowed.isEmpty) return true; // If no list, allow all (risky but fallback)
    return allowed.contains(ext);
  }
}
