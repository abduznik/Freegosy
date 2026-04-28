import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'main.dart' show scaffoldMessengerKey;
import 'providers/library_provider.dart';
import 'providers/romm_provider.dart';
import 'core/emulator/strategy_registry.dart';
import 'core/save/save_sync_service.dart';
import 'core/save/background_sync_queue.dart';
import 'ui/screens/library_screen.dart';
import 'ui/screens/download_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'providers/ui_provider.dart';
import 'core/storage/file_sanity_service.dart';

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

    // Listen to RommService initialization to hook up background sync queue
    ref.listen(rommServiceProvider, (previous, next) {
      if (previous != next && next != null) {
        // 1. Attempt to sync immediately on startup if online (wait for first frame so context is valid)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!next.isOffline.value) {
            final backupRepo = ref.read(backupRepositoryProvider);
            BackgroundSyncQueue.processQueue(next, backupRepo);
          }
        });

        // 2. Listen to future network state changes (e.g., coming back online)
        next.isOffline.addListener(() {
          if (!next.isOffline.value) {
            final backupRepo = ref.read(backupRepositoryProvider);
            BackgroundSyncQueue.processQueue(next, backupRepo);
          }
        });
      }
    });

    // Keep the file sanity service alive and running in the background
    ref.watch(fileSanityServiceProvider);

    final currentIndex = ref.watch(currentTabIndexProvider);

    return ExcludeSemantics(
      child: MaterialApp(
        title: 'Freegosy',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: scaffoldMessengerKey,
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
        home: Consumer(
          builder: (context, ref, _) {
            final isOnboardedAsync = ref.watch(rommConfigProvider);
            
            return isOnboardedAsync.when(
              data: (config) {
                if (config.baseUrl.isEmpty) {
                  return const OnboardingScreen();
                }

                return Scaffold(
                  body: _screens[currentIndex],
                  bottomNavigationBar: NavigationBar(
                    selectedIndex: currentIndex,
                    onDestinationSelected: (index) {
                      ref.read(currentTabIndexProvider.notifier).state = index;
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
                );
              },
              loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
              error: (e, s) => Scaffold(body: Center(child: Text('Error: $e'))),
            );
          },
        ),
      ),
    );
  }
}
