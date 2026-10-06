import 'package:freegosy/core/disc/serial_extraction_service.dart';
import 'package:freegosy/core/storage/directory_service.dart';
import 'package:freegosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DirectoryService with a fixed emulator executable and app-support folder.
class StubDirectoryService extends DirectoryService {
  StubDirectoryService._(super.prefs, this.exePath, this.appSupport);

  final String? exePath;
  final String appSupport;

  static Future<StubDirectoryService> create({String? exePath, String appSupport = ''}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    return StubDirectoryService._(prefs, exePath, appSupport);
  }

  /// The preferences [create] set up, for a strategy that takes its own.
  Future<SharedPreferencesAppPreferences> appPrefs() async =>
      SharedPreferencesAppPreferences(await SharedPreferences.getInstance());

  @override
  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async => exePath;

  @override
  Future<String> getEmulatorAppSupportDirectory(String emulatorName, {String? platformSlug}) async => appSupport;
}

/// Counts reads of the ROM; a test that expects none checks [reads] is 0.
class SpySerialExtractionService extends SerialExtractionService {
  SpySerialExtractionService(super.directoryService, super.prefs, {this.answer});

  final String? answer;
  int reads = 0;

  @override
  Future<String?> extractSerial({
    required String romPath,
    required RegExp bootLinePattern,
    required List<ChdmanCandidate> chdmanCandidates,
  }) async {
    reads++;
    return answer;
  }
}
