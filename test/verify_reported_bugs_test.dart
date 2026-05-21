import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/backup_entry.dart';
import 'package:freegosy/core/save/backup_repository.dart';
import 'package:freegosy/providers/romm_provider.dart';
import 'package:freegosy/ui/widgets/backup_history_sheet.dart';
import 'package:freegosy/ui/widgets/game_detail/game_metadata_chip.dart';
import 'package:freegosy/ui/widgets/screenshot_gallery_dialog.dart';
import 'package:freegosy/ui/widgets/game_detail/game_action_button.dart';

// ---------------------------------------------------------------------------
// Fake BackupRepository that skips Hive
// ---------------------------------------------------------------------------
class FakeBackupRepository extends BackupRepository {
  final Map<String, List<BackupEntry>> _store = {};

  @override
  void initBox() {}

  @override
  List<BackupEntry> getEntries(String romId) {
    return _store[romId] ?? [];
  }

  void addEntries(String romId, List<BackupEntry> entries) {
    _store[romId] = entries;
  }
}

void main() {
  group('BUG 1: GameMetadataChip — RenderFlex overflow on long label', () {
    testWidgets('short label renders fine', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GameMetadataChip(label: 'Action', icon: Icons.star)),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Action'), findsOneWidget);
    });

    testWidgets('long label no longer overflows (fixed: Flexible + ellipsis)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GameMetadataChip(label: 'A' * 200, icon: Icons.star)),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('GameActionButton handles same length correctly (no overflow)', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GameActionButton(icon: Icons.star, label: 'A' * 200, onPressed: () {}),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('BUG 2: BackupHistorySheet — md5Hash substring crash', () {
    test('substring(0, 8) on short hash throws RangeError (direct proof)', () {
      const shortHash = 'abc';
      expect(
        () => shortHash.substring(0, 8),
        throwsA(isA<RangeError>()),
      );
    });

    test('substring(0, 8) on full MD5 works fine', () {
      const fullHash = 'd41d8cd98f00b204e9800998ecf8427e';
      expect(fullHash.substring(0, 8), 'd41d8cd9');
    });

    testWidgets('BackupHistorySheet no longer crashes when md5Hash is short (fixed: guard)', (tester) async {
      final repo = FakeBackupRepository();
      repo.addEntries('game_1', [
        BackupEntry(
          timestamp: DateTime(2025, 6, 15, 10, 30),
          md5Hash: 'abc',
          localZipPath: '/tmp/test.zip',
        ),
      ]);

      final game = Game(id: 'game_1', name: 'Test Game', fileSize: 0);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          backupRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => BackupHistorySheet.show(
                  context,
                  game: game,
                  romPath: '/roms/test.iso',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('abc'), findsOneWidget);
    });

    test('BackupEntry with valid MD5 shows first 8 chars correctly', () {
      final entry = BackupEntry(
        timestamp: DateTime.now(),
        md5Hash: 'abcdef1234567890abcdef1234567890',
        localZipPath: '/tmp/test.zip',
      );
      expect(entry.md5Hash.substring(0, 8), 'abcdef12');
    });
  });

  group('BUG 3: ScreenshotGalleryDialog — empty image list shows "1 / 0"', () {
    testWidgets('renders without crash when imageUrls is empty', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScreenshotGalleryDialog(initialIndex: 0, imageUrls: const []),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no indicator shown for empty image list (fixed)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScreenshotGalleryDialog(initialIndex: 0, imageUrls: const []),
      ));

      expect(find.textContaining('/'), findsNothing);
    });

    testWidgets('single image shows "1 / 1" correctly', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScreenshotGalleryDialog(
          initialIndex: 0,
          imageUrls: const ['https://example.com/screenshot.png'],
        ),
      ));
      // For a single image, (0 + 1) / 1 = "1 / 1" — correct
      expect(find.text('1 / 1'), findsOneWidget);
    });
  });
}
