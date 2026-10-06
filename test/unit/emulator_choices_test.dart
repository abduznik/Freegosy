import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/strategy_registry.dart';
import 'package:freegosy/core/romm/romm_models.dart';
import 'package:freegosy/core/save/catalog/save_maker.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:freegosy/ui/play/emulator_choices.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final game = Game(id: '7', name: 'Mario Kart 64', fsName: 'mk', platformSlug: 'n64', fileSize: 0);

  Future<StrategyRegistry> registryRemembering(String emulatorId) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final registry = StrategyRegistry(DirectoryService(prefs), prefs);
    await registry.setGameEmulatorPreference(game.id, emulatorId);
    return registry;
  }

  test('a remembered emulator that is no longer installed is not the one the game plays in', () async {
    final choices = EmulatorChoices.of(await registryRemembering('ares'), const {'ares': false, 'retroarch': true}, game);

    expect(choices.remembered, isNull);
    expect(choices.forThisGame?.emulatorId, 'retroarch');
  });

  test('an installed remembered emulator is', () async {
    final choices = EmulatorChoices.of(await registryRemembering('ares'), const {'ares': true, 'retroarch': true}, game);

    expect(choices.forThisGame, const SaveMaker('ares'));
  });
}
