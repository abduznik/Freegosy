import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/linux_strategies/linux_environment_strategy.dart';

void main() {
  group('resolveFlatpakExecutable', () {
    test('the first PATH entry holding flatpak wins', () {
      final checked = <String>[];
      final exe = LinuxEnvironmentStrategy.resolveFlatpakExecutable(
        pathEnv: '/opt/one:/opt/two:/usr/bin',
        fileExists: (path) {
          checked.add(path);
          return path == '/opt/two/flatpak' || path == '/usr/bin/flatpak';
        },
      );
      expect(exe, '/opt/two/flatpak');
      expect(checked, ['/opt/one/flatpak', '/opt/two/flatpak']);
    });

    test('empty PATH entries are skipped rather than probed as the working directory', () {
      final checked = <String>[];
      LinuxEnvironmentStrategy.resolveFlatpakExecutable(
        pathEnv: ':/opt/bin::',
        fileExists: (path) {
          checked.add(path);
          return false;
        },
      );
      expect(checked.first, '/opt/bin/flatpak');
      expect(checked.where((c) => c == 'flatpak'), isEmpty);
    });

    test('fallback locations are tried in order after PATH', () {
      final checked = <String>[];
      final exe = LinuxEnvironmentStrategy.resolveFlatpakExecutable(
        pathEnv: '/home/deck/bin',
        fileExists: (path) {
          checked.add(path);
          return path == '/bin/flatpak';
        },
      );
      expect(exe, '/bin/flatpak');
      expect(checked, ['/home/deck/bin/flatpak', ...LinuxEnvironmentStrategy.flatpakFallbackLocations]);
    });

    test('a hit in PATH is returned without probing the fallback locations', () {
      final checked = <String>[];
      LinuxEnvironmentStrategy.resolveFlatpakExecutable(
        pathEnv: '/usr/local/sbin',
        fileExists: (path) {
          checked.add(path);
          return true;
        },
      );
      expect(checked, ['/usr/local/sbin/flatpak']);
    });
  });

  group('splitCommand', () {
    test('keeps every argument after `flatpak` in order', () {
      final (exe, args) = LinuxEnvironmentStrategy.splitCommand('flatpak run --command=retroarch org.libretro.RetroArch');
      expect(LinuxEnvironmentStrategy.isFlatpakExecutable(exe), isTrue);
      expect(args, ['run', '--command=retroarch', 'org.libretro.RetroArch']);
    });

    test('only a leading `flatpak ` command is split', () {
      for (final path in ['/opt/flatpak run/app', 'flatpakx run org.x', '/home/me/Emulators/flatpak']) {
        final (exe, args) = LinuxEnvironmentStrategy.splitCommand(path);
        expect(exe, path);
        expect(args, isEmpty);
      }
    });
  });

  group('isFlatpakExecutable', () {
    test('matches the flatpak binary wherever it lives', () {
      expect(LinuxEnvironmentStrategy.isFlatpakExecutable('/var/lib/flatpak/flatpak'), isTrue);
    });

    test('does not match look-alike tools', () {
      for (final exe in ['flatpak-spawn', '/usr/bin/flatpak-builder', '/usr/bin/flatpak.sh', '']) {
        expect(LinuxEnvironmentStrategy.isFlatpakExecutable(exe), isFalse, reason: exe);
      }
    });
  });
}
