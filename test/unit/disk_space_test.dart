import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/storage/disk_space.dart';

void main() {
  const mb = 1024 * 1024, gb = 1024 * mb;

  test('parses df -Pk output', () {
    const out = 'Filesystem     1024-blocks      Used Available Capacity Mounted on\n'
        '/dev/mmcblk0p1    125829120  80000000  45829120      64% /run/media/deck\n';
    expect(DiskSpace.parseDfAvailableBytes(out), 45829120 * 1024);
  });

  test('garbage df output is unknown, not zero', () {
    expect(DiskSpace.parseDfAvailableBytes(''), isNull);
    expect(DiskSpace.parseDfAvailableBytes('only one line'), isNull);
    expect(DiskSpace.parseDfAvailableBytes('h\nx y'), isNull);
  });

  test('an archive needs twice its size, a plain image its size, plus the margin', () {
    expect(DiskSpace.neededFor(4 * gb, fileName: 'Game.iso'), 4 * gb + DiskSpace.margin);
    expect(DiskSpace.neededFor(4 * gb, fileName: 'Game.7z'), 8 * gb + DiskSpace.margin);
    expect(DiskSpace.neededFor(1 * gb, fileName: 'GAME.ZIP'), 2 * gb + DiskSpace.margin);
  });

  test('enough: known free space is compared, unknown never blocks', () {
    expect(SpaceCheck(5 * gb, 6 * gb).enough, isTrue);
    expect(SpaceCheck(5 * gb, 5 * gb).enough, isTrue);
    expect(SpaceCheck(5 * gb, 4 * gb).enough, isFalse);
    expect(SpaceCheck(5 * gb, null).enough, isTrue);
  });

  test('format', () {
    expect(DiskSpace.format(512 * 1024), '512 KB');
    expect(DiskSpace.format(300 * mb), '300 MB');
    expect(DiskSpace.format((1.5 * gb).round()), '1.5 GB');
    expect(DiskSpace.format(40 * gb), '40 GB');
  });

  test('freeBytes walks up to an existing folder and asks df about it', () async {
    final asked = <List<String>>[];
    final free = await DiskSpace.freeBytes('/tmp/does/not/exist/yet', run: (exe, args) async {
      asked.add([exe, ...args]);
      return ProcessResult(0, 0, 'h\n/dev/x 100 50 1000 5% /tmp\n', '');
    });
    if (Platform.isWindows) return;
    expect(asked.single, ['df', '-Pk', '/tmp']);
    expect(free, 1000 * 1024);
  });

  test('freeBytes is null when the command fails or throws', () async {
    expect(await DiskSpace.freeBytes('/tmp', run: (e, a) async => ProcessResult(0, 1, '', 'err')), isNull);
    expect(await DiskSpace.freeBytes('/tmp', run: (e, a) async => throw const ProcessException('df', [])), isNull);
  });

  test('the real df works on this machine', () async {
    if (Platform.isWindows) return;
    final free = await DiskSpace.freeBytes(Directory.systemTemp.path);
    expect(free, isNotNull);
    expect(free, greaterThan(0));
  });
}
