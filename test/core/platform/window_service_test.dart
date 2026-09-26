import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/platform/window_service.dart';

void main() {
  group('WindowService.shouldStartFullscreen', () {
    test('the --fullscreen flag wins over the setting', () {
      expect(WindowService.shouldStartFullscreen(['--fullscreen'], false), isTrue);
      expect(WindowService.shouldStartFullscreen(['--fullscreen'], null), isTrue);
    });

    test('follows the "Start in fullscreen" setting without the flag', () {
      expect(WindowService.shouldStartFullscreen(const [], true), isTrue);
      expect(WindowService.shouldStartFullscreen(const [], false), isFalse);
    });

    test('defaults to windowed', () {
      expect(WindowService.shouldStartFullscreen(const [], null), isFalse);
    });
  });

  test('window calls are no-ops before init and never throw', () async {
    expect(await WindowService.isFullScreen(), isFalse);
    await WindowService.setFullScreen(true);
    await WindowService.toggleFullScreen();
  });
}
