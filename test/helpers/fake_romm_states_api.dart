import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:freegosy/core/romm/romm_state.dart';

class _Stored {
  _Stored(this.romId, this.fileName, this.bytes, this.updatedAt, {this.emulator, this.screenshot});

  final String romId;
  final String fileName;
  List<int> bytes;
  String updatedAt;
  String? emulator;
  List<int>? screenshot;
}

/// In-memory stand-in for one RomM user's `/api/states`. Every call is
/// appended to [calls] (`list`, `POST <name>`, `PUT <id>`, `GET <id>`), and
/// `updated_at` changes on every write, like RomM.
class FakeRommStatesApi implements RommStatesApi {
  final Map<int, _Stored> _states = {};
  final List<String> calls = [];
  int _nextId = 1;
  int _clock = 0;

  /// Make [listStates] throw, simulating an unreachable server.
  bool failList = false;

  /// When set, [listStates] waits for it (after recording `list`), so a test
  /// can hold a pull open while it does something else.
  Completer<void>? listGate;

  /// Per file name: [uploadState] waits for the gate (after recording its
  /// `POST` call), so a test can hold one upload of a run open.
  final Map<String, Completer<void>> uploadGates = {};

  /// Per state id: [downloadState] waits for the gate (after recording its
  /// `GET` call), so a test can hold one download of a run open.
  final Map<int, Completer<void>> downloadGates = {};

  /// Make [downloadState] throw a plain [Exception] (after recording its `GET`
  /// call), simulating a download that stalled, timed out or lost the
  /// connection.
  bool failDownloads = false;

  /// State ids whose [downloadState] throws [RommStateNotFoundException] (after
  /// recording its `GET` call): listed by the server but gone by the time the
  /// download starts.
  final Set<int> vanishOnDownload = {};

  /// Make the next [updateState] behave as if the state vanished between the
  /// list call and the PUT (deleted on the server / other account).
  bool nextUpdateIs404 = false;

  /// Make [downloadStateScreenshot] throw, simulating a failed screenshot
  /// fetch.
  bool failScreenshots = false;

  /// Called on every download after recording it; returning true fails that
  /// download like a stall.
  bool Function()? failDownloadsAfterFirst;

  String _stamp() =>
      DateTime.utc(2026, 1, 1).add(Duration(minutes: ++_clock)).toIso8601String();

  RommState _view(int id) {
    final stored = _states[id]!;
    return RommState(
      id: id,
      fileName: stored.fileName,
      updatedAt: stored.updatedAt,
      emulator: stored.emulator,
      screenshotUrl: stored.screenshot == null ? null : '/fake/screenshot/$id',
    );
  }

  /// Simulates a state uploaded from another machine.
  RommState seed(String romId, String fileName, List<int> bytes,
      {String? emulator, List<int>? screenshot}) {
    final id = _nextId++;
    _states[id] = _Stored(romId, fileName, bytes, _stamp(),
        emulator: emulator, screenshot: screenshot);
    return _view(id);
  }

  /// Simulates another machine replacing the bytes of an existing state.
  void touch(int id, List<int> bytes) {
    _states[id]!
      ..bytes = bytes
      ..updatedAt = _stamp();
  }

  void remove(int id) => _states.remove(id);

  List<int> bytesOf(int id) => _states[id]!.bytes;

  int get count => _states.length;

  String? emulatorOf(int id) => _states[id]!.emulator;
  List<int>? screenshotOf(int id) => _states[id]!.screenshot;

  @override
  Future<List<RommState>> listStates(String romId) async {
    calls.add('list');
    final gate = listGate;
    if (gate != null) await gate.future;
    if (failList) throw Exception('network down');
    return [
      for (final entry in _states.entries)
        if (entry.value.romId == romId) _view(entry.key),
    ];
  }

  @override
  Future<RommState> uploadState(String romId, File file,
      {required String fileName, String? emulator, Uint8List? screenshot}) async {
    calls.add('POST $fileName');
    final gate = uploadGates[fileName];
    if (gate != null) await gate.future;
    final id = _nextId++;
    _states[id] = _Stored(romId, fileName, await file.readAsBytes(), _stamp(),
        emulator: emulator, screenshot: screenshot);
    return _view(id);
  }

  @override
  Future<RommState> updateState(int stateId, File file,
      {required String fileName, Uint8List? screenshot}) async {
    calls.add('PUT $stateId');
    if (nextUpdateIs404) {
      nextUpdateIs404 = false;
      _states.remove(stateId);
      throw RommStateNotFoundException(stateId);
    }
    final stored = _states[stateId];
    if (stored == null) throw RommStateNotFoundException(stateId);
    stored
      ..bytes = await file.readAsBytes()
      ..updatedAt = _stamp();
    if (screenshot != null) stored.screenshot = screenshot;
    return _view(stateId);
  }

  @override
  Future<Uint8List> downloadState(int stateId) async {
    calls.add('GET $stateId');
    if (failDownloadsAfterFirst?.call() == true) throw Exception('download stalled');
    final gate = downloadGates[stateId];
    if (gate != null) await gate.future;
    if (failDownloads) throw Exception('download stalled');
    if (vanishOnDownload.contains(stateId)) throw RommStateNotFoundException(stateId);
    final stored = _states[stateId];
    if (stored == null) throw RommStateNotFoundException(stateId);
    return Uint8List.fromList(stored.bytes);
  }

  @override
  Future<Uint8List> downloadStateScreenshot(String url) async {
    calls.add('SHOT $url');
    if (failScreenshots) throw Exception('screenshot download failed');
    final id = int.parse(url.substring(url.lastIndexOf('/') + 1));
    final screenshot = _states[id]?.screenshot;
    if (screenshot == null) throw RommStateNotFoundException(id);
    return Uint8List.fromList(screenshot);
  }
}
