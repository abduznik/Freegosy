import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/downloader/download_service.dart';
import 'package:freegosy/providers/download_provider.dart';
import 'package:freegosy/ui/screens/download_screen.dart';
import 'package:freegosy/providers/shared_prefs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDownloadNotifier extends DownloadNotifier {
  MockDownloadNotifier(super.ref);
  
  void setDownloads(Map<String, DownloadProgress> downloads) {
    state = downloads;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('DownloadScreen', () {
    testWidgets('shows active downloads with progress bars', (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      final downloads = {
        '1': DownloadProgress(
          id: '1',
          gameName: 'Game 1',
          percent: 0.5,
          status: 'Downloading...',
        ),
      };

      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          downloadProvider.overrideWith((ref) => MockDownloadNotifier(ref)..setDownloads(downloads)),
        ],
        child: const MaterialApp(home: DownloadScreen()),
      ));

      expect(find.text('Game 1'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('50.0%'), findsOneWidget);
    });

    testWidgets('shows empty state when no downloads', (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          downloadProvider.overrideWith((ref) => MockDownloadNotifier(ref)..setDownloads({})),
        ],
        child: const MaterialApp(home: DownloadScreen()),
      ));

      expect(find.text('No active downloads'), findsOneWidget);
    });
  });
}
