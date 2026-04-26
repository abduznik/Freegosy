import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'app.dart';
import 'providers/shared_prefs_provider.dart';
import 'core/services/server_health_service.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio();
  
  final healthService = ServerHealthService(dio, scaffoldMessengerKey);
  final baseUrl = prefs.getString('romm_url') ?? '';
  final apiKey = prefs.getString('romm_api_key') ?? '';

  bool connected = false;
  if (baseUrl.isNotEmpty && apiKey.isNotEmpty) {
    connected = await healthService.verifyConnection(baseUrl, apiKey);
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: connected ? const FreegosyApp() : const Scaffold(
          body: Center(child: Text("Redirecting to settings...")),
        ),
      ),
    ),
  );
}
