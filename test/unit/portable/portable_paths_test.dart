import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/portable/portable_paths.dart';

void main() {
  PortablePaths at(String root, {Set<String> existing = const {}}) =>
      PortablePaths(root: root, exists: (path) => existing.contains(path));

  group('toStored', () {
    final paths = at(r'E:\Freegosy');

    test('a path on the same drive is stored relative, with the absolute as fallback', () {
      expect(paths.toStored(r'E:\ROMs'), r'@freegosy:..\ROMs|E:\ROMs');
      expect(paths.toStored(r'E:\Freegosy\data\support\ROMs'),
          r'@freegosy:data\support\ROMs|E:\Freegosy\data\support\ROMs');
    });

    test('the drive letter is compared without case', () {
      expect(paths.toStored(r'e:\ROMs'), r'@freegosy:..\ROMs|e:\ROMs');
    });

    test('other drives, UNC paths and non-paths are unchanged', () {
      for (final value in [
        r'D:\ROMs',
        r'\\nas\roms',
        'E:',
        'e:/forward/slashes',
        'https://romm.example/api',
        'retroarch',
        '',
        r'@freegosy:..\ROMs|E:\ROMs',
      ]) {
        expect(paths.toStored(value), value, reason: value);
      }
    });
  });

  group('fromStored', () {
    test('a drive-letter change resolves through the relative part', () {
      final paths = at(r'F:\Freegosy', existing: {r'F:\ROMs'});
      expect(paths.fromStored(r'@freegosy:..\ROMs|E:\ROMs'), r'F:\ROMs');
    });

    test('a moved folder falls back to the absolute part when it still exists', () {
      final paths = at(r'D:\Freegosy', existing: {r'C:\Games\ROMs'});
      expect(paths.fromStored(r'@freegosy:..\..\Games\ROMs|C:\Games\ROMs'), r'C:\Games\ROMs');
    });

    test('when neither exists the relative result is returned', () {
      final paths = at(r'F:\Freegosy');
      expect(paths.fromStored(r'@freegosy:..\ROMs|E:\ROMs'), r'F:\ROMs');
    });

    test('values without the prefix are unchanged', () {
      final paths = at(r'F:\Freegosy');
      expect(paths.fromStored(r'D:\ROMs'), r'D:\ROMs');
      expect(paths.fromStored('hello|world'), 'hello|world');
    });
  });

  group('static helpers', () {
    tearDown(() => PortablePaths.active = null);

    test('store() is a no-op when not portable', () {
      PortablePaths.active = null;
      expect(PortablePaths.store(r'E:\ROMs'), r'E:\ROMs');
    });

    test('store() converts when portable', () {
      PortablePaths.active = at(r'E:\Freegosy');
      expect(PortablePaths.store(r'E:\ROMs'), r'@freegosy:..\ROMs|E:\ROMs');
    });

    test('resolve() leaves plain values alone without touching the file system', () {
      PortablePaths.active = null;
      expect(PortablePaths.resolve(r'C:\x'), r'C:\x');
    });

    test('resolve() uses the active root', () {
      PortablePaths.active = at(r'G:\Freegosy');
      expect(PortablePaths.resolve(r'@freegosy:..\ROMs|E:\ROMs'), r'G:\ROMs');
    });
  });
}
