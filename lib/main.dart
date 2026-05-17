import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/save/backup_entry.dart';
import 'providers/shared_prefs_provider.dart';

import 'core/storage/logger_service.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LoggerService.init();

  Hive.registerAdapter(BackupEntryAdapter());
  await Hive.initFlutter();
  await Hive.openBox<List>('freegosy_backups');
  
  final prefs = await SharedPreferences.getInstance();
  
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const FreegosyApp(),
    ),
  );
}
