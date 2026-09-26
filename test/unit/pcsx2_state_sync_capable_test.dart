import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/state_sync_capable.dart';
import 'package:path/path.dart' as p;

import '../helpers/pcsx2_test_env.dart';

void main() {
  late Directory base;
  late Pcsx2TestEnv env;
  final game = Game(id: 'g1', name: 'Ico (SCUS-97113)', platformSlug: 'ps2', fileSize: 0);

  setUp(() async {
    base = await Directory.systemTemp.createTemp('pcsx2_state_caps');
    env = await Pcsx2TestEnv.create(base);
  });

  tearDown(() => base.delete(recursive: true));

  String romPath() => p.join(base.path, 'Ico (SCUS-97113).iso');

  test('Pcsx2SaveStrategy is StateSyncCapable', () {
    expect(env.strategy, isA<StateSyncCapable>());
  });

  test('stateDirectory is <portable root>/sstates', () async {
    expect(await env.strategy.stateDirectory(game, romPath()), env.statesDir);
  });

  test('matcher accepts numbered and resume slots for the game\'s serial', () async {
    final matches = (await env.strategy.stateFileMatcher(game, romPath()))!;

    expect(matches('SCUS-97113 (A1B2C3D4).01.p2s'), isTrue);
    expect(matches('SCUS-97113 (A1B2C3D4).10.p2s'), isTrue);
    expect(matches('SCUS-97113 (a1b2c3d4).resume.p2s'), isTrue);
  });

  test('matcher rejects other serials, backups, non-states and path tricks', () async {
    final matches = (await env.strategy.stateFileMatcher(game, romPath()))!;

    expect(matches('SLUS-20312 (A1B2C3D4).01.p2s'), isFalse, reason: 'another game');
    expect(matches('SCUS-97113 (A1B2C3D4).01.p2s.backup'), isFalse, reason: 'PCSX2 backup');
    expect(matches('SCUS-97113 (A1B2C3D4).01.p2s.bak'), isFalse, reason: 'Freegosy backup');
    expect(matches('SCUS-97113 (A1B2C3D4).01.p2s.freegosy_tmp'), isFalse);
    expect(matches('SCUS-97113 (A1B2C3D4).01.png'), isFalse);
    expect(matches(r'..\SCUS-97113 (A1B2C3D4).01.p2s'), isFalse, reason: 'path traversal');
    expect(matches('../SCUS-97113 (A1B2C3D4).01.p2s'), isFalse, reason: 'path traversal');
    expect(matches('SCUS-97113.01.p2s'), isFalse, reason: 'no CRC');
  });

  test('matcher is null when the game serial cannot be determined', () async {
    final unknown = Game(id: 'g2', name: 'No Serial Here', platformSlug: 'ps2', fileSize: 0);

    expect(await env.strategy.stateFileMatcher(unknown, p.join(base.path, 'No Serial Here.iso')), isNull);
  });

  test('looksLikeValidState requires the zip header and end record PCSX2 states carry', () {
    const end = [0x50, 0x4B, 5, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    expect(env.strategy.looksLikeValidState(Uint8List.fromList([0x50, 0x4B, 3, 4, 0, ...end])), isTrue);
    expect(env.strategy.looksLikeValidState(Uint8List.fromList([0x50, 0x4B, 3, 4, ...List.filled(40, 0)])), isFalse,
        reason: 'no end record: the write was cut off');
    expect(env.strategy.looksLikeValidState(Uint8List.fromList([1, 2, 3, 4, 5, ...end])), isFalse);
    expect(env.strategy.looksLikeValidState(Uint8List(0)), isFalse);
  });
}
