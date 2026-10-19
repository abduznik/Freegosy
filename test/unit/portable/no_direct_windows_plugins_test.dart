import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';

/// Portable mode redirects storage through the plugins' platform instances.
/// Code that imports the Windows implementations directly would bypass that
/// and write outside the portable folder.
void main() {
  test('nothing under lib/ imports path_provider_windows or shared_preferences_windows', () {
    final offenders = <String>[];
    for (final entity in io.Directory('lib').listSync(recursive: true)) {
      if (entity is! io.File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (text.contains('package:path_provider_windows') || text.contains('package:shared_preferences_windows')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
