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

  /// Windows programs that go through Wine/Proton rather than being started directly.
  static bool needsWine(String exePath) {
    final lower = exePath.toLowerCase();
    return lower.endsWith('.exe') || lower.endsWith('.bat') || lower.endsWith('.cmd');
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
          // umu-0 is umu's id for "no known game"; PROTONPATH=GE-Proton makes it fetch the latest GE-Proton.
          environment: {...shared, 'GAMEID': env['GAMEID'] ?? 'umu-0', 'PROTONPATH': env['PROTONPATH'] ?? 'GE-Proton'},
          runner: name,
        );
      }
      return WineCommand(executable: path, args: [exePath, ...args], environment: shared, runner: name);
    }
    return null;
  }
}
