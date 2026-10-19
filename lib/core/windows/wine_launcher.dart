import 'dart:io';
import 'package:path/path.dart' as p;

/// What to run to start a Windows program on Linux.
class WineCommand {
  final String executable;
  final List<String> args;
  final Map<String, String> environment;

  /// "umu-run" (Proton) or "wine", for messages and logs.
  final String runner;

  const WineCommand({required this.executable, required this.args, required this.environment, required this.runner});
}

/// Starts Windows games on Linux through Proton or Wine.
///
/// [umu-run](https://github.com/Open-Wine-Components/umu-launcher) is preferred: it runs Proton outside Steam,
/// downloads it on first use and sets up the prefix. Plain `wine` is the fallback. Each game gets a prefix of
/// its own so one game's tweaks and installed redistributables never leak into another's.
class WineLauncher {
  /// Runners to look for, best first.
  static const runners = ['umu-run', 'wine'];

  /// Where programs live when the PATH Freegosy inherited (an AppImage, a gamescope session) omits them.
  static const fallbackDirs = ['/usr/bin', '/usr/local/bin', '/bin'];

  /// The prefix a Windows game runs in: one folder per game under [supportBase] (see WindowsStrategy).
  static String prefixDirFor(String supportBase, String gameId) => p.join(supportBase, 'prefixes', gameId);

  /// Windows programs that go through Wine/Proton rather than being started directly.
  static bool needsWine(String exePath) {
    final lower = exePath.toLowerCase();
    return lower.endsWith('.exe') || lower.endsWith('.bat') || lower.endsWith('.cmd');
  }

  /// The newest Proton already on this computer: a custom build in Steam's `compatibilitytools.d` (GE-Proton),
  /// else one of Steam's own (`steamapps/common/Proton*`), numbered versions before "Proton - Experimental".
  /// Null when there is none, and umu-run is left to download GE-Proton itself.
  static String? findInstalledProton({Map<String, String>? environment, List<String>? steamRoots}) {
    final env = environment ?? Platform.environment;
    final home = env['HOME'];
    final roots = steamRoots ??
        [
          if (home != null) ...[
            p.join(home, '.local', 'share', 'Steam'),
            p.join(home, '.steam', 'steam'),
            p.join(home, '.var', 'app', 'com.valvesoftware.Steam', 'data', 'Steam'),
          ],
        ];
    List<Directory> dirsIn(String path, bool Function(String name) keep) {
      final dir = Directory(path);
      if (!dir.existsSync()) return [];
      return dir.listSync().whereType<Directory>().where((d) => keep(p.basename(d.path))).toList();
    }

    int version(String name) {
      final m = RegExp(r'(\d+)(?:[.-](\d+))?(?:[.-](\d+))?').firstMatch(name);
      if (m == null) return 0;
      return int.parse(m.group(1)!) * 1000000 + int.parse(m.group(2) ?? '0') * 1000 + int.parse(m.group(3) ?? '0');
    }

    for (final root in roots) {
      final custom = dirsIn(p.join(root, 'compatibilitytools.d'), (n) => n.toLowerCase().contains('proton'))
        ..sort((a, b) => version(p.basename(b.path)).compareTo(version(p.basename(a.path))));
      if (custom.isNotEmpty) return custom.first.path;
    }
    for (final root in roots) {
      final steam = dirsIn(p.join(root, 'steamapps', 'common'), (n) => n.startsWith('Proton'))
          // A directory without the proton script is not a Proton install.
          .where((d) => File(p.join(d.path, 'proton')).existsSync())
          .toList()
        ..sort((a, b) {
          final an = p.basename(a.path), bn = p.basename(b.path);
          final ae = an.contains('Experimental'), be = bn.contains('Experimental');
          if (ae != be) return ae ? 1 : -1;
          return version(bn).compareTo(version(an));
        });
      if (steam.isNotEmpty) return steam.first.path;
    }
    return null;
  }

  /// The full path of [name], looked up on PATH and then in [fallbackDirs] (or [dirs] when given).
  static String? find(String name, {Map<String, String>? environment, List<String>? dirs}) {
    final env = environment ?? Platform.environment;
    final searched = dirs ??
        [
          ...(env['PATH'] ?? '').split(':').where((d) => d.isNotEmpty),
          if (env['HOME'] != null) p.join(env['HOME']!, '.local', 'bin'),
          ...fallbackDirs,
        ];
    for (final dir in searched) {
      final file = File(p.join(dir, name));
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  /// The command that starts [exePath] with [args] in [prefixDir], or null when neither umu-run nor wine is
  /// installed. [preference] is `auto`, `umu` or `wine`.
  static WineCommand? build({
    required String exePath,
    required List<String> args,
    required String prefixDir,
    String preference = 'auto',
    Map<String, String>? environment,
    List<String>? dirs,
    String? protonPath,
  }) {
    final env = environment ?? Platform.environment;
    final order = switch (preference) {
      'umu' => ['umu-run'],
      'wine' => ['wine'],
      _ => runners,
    };
    for (final name in order) {
      final path = find(name, environment: env, dirs: dirs);
      if (path == null) continue;
      final shared = {'WINEPREFIX': prefixDir, 'WINEDEBUG': env['WINEDEBUG'] ?? '-all'};
      if (name == 'umu-run') {
        return WineCommand(
          executable: path,
          args: [exePath, ...args],
          // umu-0 is umu's id for "no known game". PROTONPATH is a Proton already installed (Steam's or GE-Proton),
          // else GE-Proton, which umu downloads on first use.
          environment: {...shared, 'GAMEID': env['GAMEID'] ?? 'umu-0', 'PROTONPATH': env['PROTONPATH'] ?? protonPath ?? 'GE-Proton'},
          runner: name,
        );
      }
      return WineCommand(executable: path, args: [exePath, ...args], environment: shared, runner: name);
    }
    return null;
  }
}
