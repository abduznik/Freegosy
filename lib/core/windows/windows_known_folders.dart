import 'dart:io';
import 'package:path/path.dart' as p;
import '../platform/platform_info.dart';

/// Where Windows' well-known folders are on this computer, so a save found by name (PCGamingWiki's
/// `{{p|appdata}}\Game`) or stored by name (a synced save's `['APPDATA']\Game`) lands in the right place.
///
/// On Windows they come from the environment. On Linux a Windows game runs in a Wine/Proton prefix, so they
/// are the prefix's own `drive_c/users/<user>` folders; without a prefix there is nothing to map and the
/// result is empty.
class WindowsKnownFolders {
  /// Portable token -> absolute local path. The tokens (`['APPDATA']`...) are what a synced save's
  /// `freegosy_sync.txt` stores, so they stay as they are.
  final Map<String, String> byToken;

  /// Path rules for these folders: Windows' on Windows, POSIX inside a Wine prefix.
  final p.Context _ctx;

  WindowsKnownFolders(this.byToken, {bool windowsPaths = false})
      : _ctx = p.Context(style: windowsPaths ? p.Style.windows : p.Style.posix);

  static const appData = "['APPDATA']";
  static const localAppData = "['LOCALAPPDATA']";
  static const userProfile = "['USERPROFILE']";
  static const programData = "['PROGRAMDATA']";
  static const publicFolder = "['PUBLIC']";

  factory WindowsKnownFolders.forPlatform(PlatformInfo platform, {String? prefixDir}) {
    if (platform.isWindows) {
      final env = platform.environment;
      return WindowsKnownFolders(windowsPaths: true, {
        for (final e in {
          appData: env['APPDATA'],
          localAppData: env['LOCALAPPDATA'],
          userProfile: env['USERPROFILE'],
          programData: env['PROGRAMDATA'],
          publicFolder: env['PUBLIC'],
        }.entries)
          if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
      });
    }
    if (prefixDir == null) return WindowsKnownFolders({});
    final cDrive = p.join(prefixDir, 'drive_c');
    final users = p.join(cDrive, 'users');
    final profile = p.join(users, _prefixUser(users));
    return WindowsKnownFolders({
      userProfile: profile,
      appData: p.join(profile, 'AppData', 'Roaming'),
      localAppData: p.join(profile, 'AppData', 'Local'),
      programData: p.join(cDrive, 'ProgramData'),
      publicFolder: p.join(users, 'Public'),
    });
  }

  /// Proton always uses `steamuser`; plain Wine names it after the Linux user.
  static String _prefixUser(String usersDir) {
    final dir = Directory(usersDir);
    if (!dir.existsSync()) return 'steamuser';
    final names = dir.listSync().whereType<Directory>().map((d) => p.basename(d.path)).toList();
    if (names.contains('steamuser')) return 'steamuser';
    return names.firstWhere((n) => n != 'Public', orElse: () => 'steamuser');
  }

  bool get isEmpty => byToken.isEmpty;

  /// PCGamingWiki's `{{p|...}}` names for the same folders (lowercase), including the subfolders it
  /// writes as `{{p|userprofile\documents}}`.
  Map<String, String> get byWikiTemplate {
    final out = <String, String>{};
    void add(String name, String? path) {
      if (path != null && path.isNotEmpty) out['{{p|$name}}'] = path;
    }

    add('appdata', byToken[appData]);
    add('localappdata', byToken[localAppData]);
    add('programdata', byToken[programData]);
    add('public', byToken[publicFolder]);
    final profile = byToken[userProfile];
    add('userprofile', profile);
    if (profile != null) {
      add(r'userprofile\documents', _ctx.join(profile, 'Documents'));
      add(r'userprofile\saved games', _ctx.join(profile, 'Saved Games'));
      add(r'userprofile\appdata\locallow', _ctx.join(profile, 'AppData', 'LocalLow'));
    }
    return out;
  }

  /// [absolute] with its leading known folder replaced by the folder's token (`['APPDATA']\Game\Saves`,
  /// always with `\`), or [absolute] unchanged when it is under none of them. The longest folder wins, so
  /// `...\AppData\Local` is not mistaken for the profile folder above it.
  String toPortable(String absolute, {String? gameDir}) {
    final folders = {...byToken, if (gameDir != null && gameDir.isNotEmpty) '[GAMEDIR]': gameDir};
    final ordered = folders.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final e in ordered) {
      final root = _ctx.normalize(e.value);
      if (_ctx.equals(absolute, root) || _ctx.isWithin(root, absolute)) {
        final rest = _ctx.relative(absolute, from: root);
        return rest == '.' ? e.key : '${e.key}\\${rest.replaceAll('/', '\\')}';
      }
    }
    return absolute;
  }

  /// The reverse of [toPortable] for this computer: a stored `['APPDATA']\Game` becomes a local path.
  /// A path with no token comes back as it is.
  String fromPortable(String portable, {String? gameDir, required bool posix}) {
    final folders = {...byToken, if (gameDir != null && gameDir.isNotEmpty) '[GAMEDIR]': gameDir};
    for (final e in folders.entries) {
      if (portable.startsWith(e.key)) {
        final rest = portable.substring(e.key.length).replaceAll(RegExp(r'^[\\/]+'), '');
        final tail = posix ? rest.replaceAll('\\', '/') : rest;
        return tail.isEmpty ? e.value : _ctx.join(e.value, tail);
      }
    }
    return portable;
  }
}
