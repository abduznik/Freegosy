import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'platform_info.dart';

/// Desktop window control (issue #74): start in fullscreen and toggle it.
///
/// Every call is a no-op off desktop and never throws — a window that can't
/// go fullscreen (no plugin in tests, an odd compositor) must not stop the
/// app from starting.
class WindowService {
  WindowService._();

  /// Command-line flag that starts Freegosy in fullscreen whatever the
  /// "Start in fullscreen" setting says, e.g. for a Steam shortcut.
  static const fullscreenFlag = '--fullscreen';

  /// SharedPreferences key of the "Start in fullscreen" setting.
  static const launchFullscreenPrefKey = 'launch_fullscreen';

  static bool _initialized = false;

  static bool get _isDesktop {
    final platform = PlatformInfo.current;
    return !kIsWeb && (platform.isWindows || platform.isLinux || platform.isMacOS);
  }

  /// Whether the app should start fullscreen for these [args] and the stored
  /// [launchFullscreenPref].
  static bool shouldStartFullscreen(List<String> args, bool? launchFullscreenPref) =>
      args.contains(fullscreenFlag) || (launchFullscreenPref ?? false);

  /// Sets up the window plugin and enters fullscreen if [fullscreen].
  static Future<void> init({required bool fullscreen}) async {
    if (!_isDesktop) return;
    try {
      await windowManager.ensureInitialized();
      _initialized = true;
      if (fullscreen) await windowManager.setFullScreen(true);
    } catch (e) {
      debugPrint('[Window] init failed (non-fatal): $e');
    }
  }

  static Future<bool> isFullScreen() async {
    if (!_initialized) return false;
    try {
      return await windowManager.isFullScreen();
    } catch (e) {
      debugPrint('[Window] isFullScreen failed: $e');
      return false;
    }
  }

  static Future<void> setFullScreen(bool value) async {
    if (!_initialized) return;
    try {
      await windowManager.setFullScreen(value);
    } catch (e) {
      debugPrint('[Window] setFullScreen($value) failed: $e');
    }
  }

  static Future<void> toggleFullScreen() async => setFullScreen(!await isFullScreen());
}
