import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/library_provider.dart';
import 'ui/screens/library_screen.dart';
import 'ui/screens/download_screen.dart';
import 'ui/screens/settings_screen.dart';

class FreegosyApp extends ConsumerStatefulWidget {
  const FreegosyApp({super.key});

  @override
  ConsumerState<FreegosyApp> createState() => _FreegosyAppState();
}

class _FreegosyAppState extends ConsumerState<FreegosyApp> {
  int _currentIndex = 0;
  bool _settingsLoaded = false;

  final List<Widget> _screens = const [
    LibraryScreen(),
    DownloadScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    Future.wait([
      ref.read(cardAspectRatioLoaderProvider.future),
      ref.read(retroarchSyncModeLoaderProvider.future),
      ref.read(columnCountLoaderProvider.future),
      ref.read(cardSpacingLoaderProvider.future),
      ref.read(showTitleLoaderProvider.future),
      ref.read(showButtonsOnHoverLoaderProvider.future),
      ref.read(activePresetLoaderProvider.future),
    ]).then((_) {
      if (mounted) {
        setState(() => _settingsLoaded = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF0f0f0f),
          body: Center(
            child: CircularProgressIndicator(
              color: Colors.deepPurple,
            ),
          ),
        ),
      );
    }
    return MaterialApp(
      title: 'Freegosy',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
          surface: const Color(0xFF1a1a1a),
        ),
        scaffoldBackgroundColor: const Color(0xFF0f0f0f),
        cardTheme: const CardThemeData(
          color: Color(0xFF1a1a1a),
          elevation: 2,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0f0f0f),
          foregroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF1a1a1a),
          indicatorColor: Colors.deepPurple.withValues(alpha: 0.3),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1a1a1a),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.deepPurple.shade800),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.deepPurple.shade900),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: Scaffold(
        body: _screens[_currentIndex],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.library_books),
              label: 'Library',
            ),
            NavigationDestination(
              icon: Icon(Icons.download),
              label: 'Downloads',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
