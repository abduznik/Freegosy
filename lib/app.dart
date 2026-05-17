import 'package:flutter/material.dart';
import 'dart:async';
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
import 'core/input/gamepad_service.dart';
import 'core/input/input_action_bus.dart';
import 'package:flutter/services.dart';

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
  StreamSubscription<GameAction>? _inputSub;

  @override
  void initState() {
    super.initState();
    
    // Global Keyboard Listener - Maps physical keys to Action Bus commands
    HardwareKeyboard.instance.addHandler((event) {
      if (event is KeyDownEvent) {
        // Protection: Ignore if typing in a text field
        final focusNode = FocusManager.instance.primaryFocus;
        if (focusNode?.context?.widget is EditableText) {
          return false; 
        }

        final action = _mapPhysicalKeyToAction(event.logicalKey);
        if (action != null) {
          // 1. Switch to Keyboard Mode
          if (ref.read(inputModeProvider) != InputMode.keyboard) {
            debugPrint('⌨️ Switching to KEYBOARD mode.');
            ref.read(inputModeProvider.notifier).state = InputMode.keyboard;
          }
          
          // 2. Broadcast the action
          inputActionBus.add(action);
        }
      }
      return false;
    });

    // Global Action Executor: Listen for actions that apply everywhere
    _inputSub = inputActionBus.stream.listen((action) {
      if (action == GameAction.confirm) {
        final focusedAction = ref.read(focusedActionProvider);
        if (focusedAction != null) {
          debugPrint('🎯 Global: Executing focused action.');
          focusedAction();
        }
      } else if (action == GameAction.l1) {
        final current = ref.read(currentTabIndexProvider);
        if (current > 0) {
          ref.read(currentTabIndexProvider.notifier).state = current - 1;
        }
      } else if (action == GameAction.r1) {
        final current = ref.read(currentTabIndexProvider);
        if (current < _screens.length - 1) {
          ref.read(currentTabIndexProvider.notifier).state = current + 1;
        }
      }
    });
  }

  @override
  void dispose() {
    _inputSub?.cancel();
    super.dispose();
  }

  GameAction? _mapPhysicalKeyToAction(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.escape) return GameAction.back;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) return GameAction.confirm;
    if (key == LogicalKeyboardKey.arrowUp) return GameAction.up;
    if (key == LogicalKeyboardKey.arrowDown) return GameAction.down;
    if (key == LogicalKeyboardKey.arrowLeft) return GameAction.left;
    if (key == LogicalKeyboardKey.arrowRight) return GameAction.right;
    if (key == LogicalKeyboardKey.keyX) return GameAction.detail;
    if (key == LogicalKeyboardKey.keyY) return GameAction.favorite;
    if (key == LogicalKeyboardKey.keyQ) return GameAction.l1;
    if (key == LogicalKeyboardKey.keyE) return GameAction.r1;
    return null;
  }


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

    // Keep services alive in the background
    ref.watch(fileSanityServiceProvider);
    ref.watch(gamepadServiceProvider);

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
