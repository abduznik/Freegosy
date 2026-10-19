import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/platform/platform_info.dart';
import 'core/platform/window_service.dart';
import 'core/portable/portable_handover.dart';
import 'core/portable/portable_mode.dart';
import 'core/save/backup_entry.dart';
import 'core/storage/shared_preferences_app_preferences.dart';
import 'providers/shared_prefs_provider.dart';
import 'ui/screens/portable_error_app.dart';
import 'ui/widgets/storage_problem_reporter.dart';
import 'main_cli.dart' as headless;

import 'core/storage/logger_service.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Settings couldn't be saved or read (portable drive removed, damaged file
/// kept aside).
final _storageProblems = StorageProblemReporter(scaffoldMessengerKey);

void main(List<String> args) async {
  // Portable mode must be decided before anything reads settings or app
  // folders — including headless mode below.
  PortableMode.launchArgs = args;
  PortableModeException? portableError;
  final portableRoot = PortableMode.detectRoot();
  if (portableRoot != null) {
    try {
      await PortableMode.install(portableRoot, onProblem: _storageProblems.report);
    } on PortableModeException catch (e) {
      portableError = e;
    }
  }

  // Headless mode — game launch + save sync verification without the UI.
  // Dispatched before any GUI init (Hive/license registry/runApp) so
  // headless mode does its own minimal setup instead. See main_cli.dart.
  if (args.isNotEmpty && args.first == '--headless') {
    if (portableError != null) {
      io.stderr.writeln(portableError);
      io.exit(1);
    }
    await headless.runHeadless(args.skip(1).toList());
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  if (portableError != null) await showPortableError(portableError);
  try {
    await _startApp(args);
  } catch (e, s) {
    // The window only appears once Flutter draws a frame, so a failure
    // before runApp would leave Freegosy running with nothing on screen.
    debugPrint('[Startup] Freegosy could not start: $e\n$s');
    showStartupError(e);
  }
}

Future<void> _startApp(List<String> args) async {
  LoggerService.init();
  await AppConstants.init(); // Read version from pubspec.yaml

  LicenseRegistry.addLicense(() {
    return Stream<LicenseEntry>.fromIterable([
      const LicenseEntryWithLineBreaks(
        ['Freegosy'],
        '''
MIT License

Copyright (c) 2026 abduznik

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''',
      ),
    ]);
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['libchdr', 'MAME'],
      await rootBundle.loadString('thirdparty/libchdr_license.txt'),
    );
  });

  Hive.registerAdapter(BackupEntryAdapter());
  if (PlatformInfo.current.isLinux) {
    final dir = await getApplicationSupportDirectory();
    await Hive.initFlutter(dir.path);
  } else {
    await Hive.initFlutter();
  }
  await Hive.openBox<List>('freegosy_backups');
  final prefs = await SharedPreferences.getInstance();
  await PortableHandover.run(
    prefs: SharedPreferencesAppPreferences(prefs),
    backups: Hive.box<List>('freegosy_backups'),
    platformSecrets: const FlutterSecretStore(),
    portableSecrets: PortableMode.current?.credentials,
  );
  await WindowService.init(
    fullscreen: WindowService.shouldStartFullscreen(args, prefs.getBool(WindowService.launchFullscreenPrefKey)),
  );
  
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const FreegosyApp(),
    ),
  );
  // A problem found while settings were first read (before runApp) waits
  // until the app can show it.
  WidgetsBinding.instance.addPostFrameCallback((_) => _storageProblems.showPending());
}
