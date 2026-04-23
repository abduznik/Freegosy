import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/library_provider.dart';
import 'providers/romm_provider.dart';
import 'core/emulator/strategy_registry.dart';
import 'core/save/save_sync_service.dart';
import 'ui/screens/library_screen.dart';
import 'ui/screens/download_screen.dart';
import 'ui/screens/settings_screen.dart';

class CustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class FreegosyApp extends ConsumerStatefulWidget {
  const FreegosyApp({super.key});

  @override
  ConsumerState<FreegosyApp> createState() => _FreegosyAppState();
}

class _FreegosyAppState extends ConsumerState<FreegosyApp> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    LibraryScreen(),
    DownloadScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Listen for NDS core changes and apply them to services
    ref.listen(retroarchNdsCoreProvider, (previous, next) {
      final StrategyRegistry? registry = ref.read(strategyRegistryProvider).asData?.value;
      final SaveSyncService? syncService = ref.read(saveSyncServiceProvider).asData?.value;
      if (registry != null) {
        registry.setNdsCore(next);
      }
      if (syncService != null) {
        syncService.setNdsCore(next);
      }
    });

    return ExcludeSemantics(
      child: MaterialApp(
        title: 'Freegosy',
        debugShowCheckedModeBanner: false,
        scrollBehavior: CustomScrollBehavior(),
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
      ),
    );
  }
}
