import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../emulator/emulator_strategy.dart';
import '../romm/romm_models.dart';
import '../romm/romm_state.dart';
import '../storage/app_preferences.dart';
import 'save_state_info.dart';
import 'save_strategy.dart';
import 'state_sync_capable.dart';
import 'state_sync_record.dart';
import 'state_sync_service.dart';

/// Where a resumable state is.
enum ResumeWhere { thisPc, romm, both }

/// One save state the game can be resumed from.
@immutable
class ResumeEntry {
  const ResumeEntry({
    required this.emulatorId,
    required this.emulatorName,
    required this.fileName,
    required this.slot,
    required this.savedAt,
    required this.where,
    this.newerOnRomm = false,
    this.emulatorVersion,
    this.installedVersion,
    this.compat = StateCompat.unknown,
    this.localFile,
    this.remoteId,
    this.remoteUpdatedAt,
    this.remoteScreenshotUrl,
    this.romPath,
  });

  final String emulatorId;
  final String emulatorName;
  final String fileName;
  final StateSlot slot;
  final DateTime savedAt;
  final ResumeWhere where;

  /// On both sides and the server copy changed since the last sync: the
  /// pre-launch pull will replace the local copy. [emulatorVersion] is then
  /// null (unknown until downloaded).
  final bool newerOnRomm;
  final String? emulatorVersion;
  final String? installedVersion;
  final StateCompat compat;
  final io.File? localFile;
  final int? remoteId;
  final String? remoteUpdatedAt;
  final String? remoteScreenshotUrl;

  /// The ROM file the state was identified with. A state belongs to one disc
  /// (its serial), so a resume boots exactly this file.
  final String? romPath;
}

/// The outcome of [ResumeService.checkBeforeLaunch].
sealed class ResumeCheck {
  const ResumeCheck();
}

/// Load `path`. `stale`: a newer RomM copy was expected but did not arrive,
/// so the older local copy is loaded. `prompt`: ask before loading.
final class ResumeReady extends ResumeCheck {
  const ResumeReady(this.path, {this.stale = false, this.prompt});
  final String path;
  final bool stale;
  final ({String stateVersion, String installed})? prompt;
}

/// The chosen state is not on disk: nothing may be launched.
final class ResumeMissing extends ResumeCheck {
  const ResumeMissing();
}

/// What to tell the user when the chosen state turned out missing right
/// before launch ([ResumeMissing]), or when there was no resume service to
/// check it with ([serviceAvailable] false).
String resumeMissingMessage(ResumeEntry entry, {required bool serviceAvailable}) {
  if (!serviceAvailable) return "Resume isn't available right now. Nothing was started.";
  final fromRomm = entry.where == ResumeWhere.romm || entry.newerOnRomm;
  return fromRomm
      ? "Couldn't get ${entry.slot.label} from RomM. Nothing was started."
      : "Couldn't find ${entry.slot.label} on this PC. Nothing was started.";
}

/// One emulator's view of one ROM file: a multi-disc game has one source per
/// emulator and disc, each accepting only its own disc's states.
class _Source {
  _Source(this.emulator, this.strategy, this.dir, this.matches, this.installed, this.romPath);
  final EmulatorStrategy emulator;
  final StateSyncCapable strategy;
  final io.Directory dir;
  final bool Function(String) matches;
  final String? installed;
  final String romPath;
}

/// Answers "what can this game be resumed from, and with which emulator?".
/// Emulator-agnostic: every emulator detail comes from [EmulatorStrategy] and
/// [StateSyncCapable].
class ResumeService {
  ResumeService({
    required List<EmulatorStrategy> Function(String platformSlug) emulatorsFor,
    required SaveStrategy? Function(Game game, {String? emulatorId}) resolveSaveStrategy,
    required AppPreferences prefs,
    RommStatesApi? api,
    bool Function()? isOffline,
    Duration listTimeout = StateSyncService.defaultListTimeout,
  })  : _emulatorsFor = emulatorsFor,
        _resolve = resolveSaveStrategy,
        _prefs = prefs,
        _records = StateRecordStore(prefs),
        _api = api,
        _isOffline = isOffline ?? (() => false),
        _listTimeout = listTimeout;

  final List<EmulatorStrategy> Function(String) _emulatorsFor;
  final SaveStrategy? Function(Game, {String? emulatorId}) _resolve;
  final AppPreferences _prefs;
  final StateRecordStore _records;
  final RommStatesApi? _api;
  final bool Function() _isOffline;
  final Duration _listTimeout;
  final Map<String, Uint8List?> _thumbnails = {};

  /// Save strategy per emulator id, as last resolved by [_sources]; used for
  /// local thumbnails (a strategy's screenshot reader does not depend on the game).
  final Map<String, StateSyncCapable> _strategyByEmulator = {};

  /// Local entries first, then (when some emulator syncs states and RomM is
  /// reachable) the list merged with RomM's. [romPaths] are the game's ROM
  /// files (every disc of a multi-disc game); each entry's `romPath` is the
  /// one its state belongs to. When several ROM files of the same emulator
  /// claim a state (the tracks of a cue/bin disc, two copies of one disc),
  /// the first in path order owns it, so it is listed once. Never errors.
  Stream<List<ResumeEntry>> entriesFor(Game game, List<String> romPaths) async* {
    final sources = <_Source>[];
    final versions = <String, String?>{}; // installed version per emulator, asked once
    for (final romPath in [...romPaths]..sort()) {
      sources.addAll(await _sources(game, romPath, versions));
    }
    final local = <String, ResumeEntry>{};
    for (final source in sources) {
      for (final entry in (await _localEntries(source)).entries) {
        local.putIfAbsent(entry.key, () => entry.value);
      }
    }
    yield _sorted(local.values);

    final syncing = sources
        .where((s) => _prefs.getBool(StateSyncService.enabledKey(s.emulator.emulatorId)) == true)
        .toList();
    final api = _api;
    if (api == null || syncing.isEmpty || _isOffline()) return;
    final List<RommState> remote;
    try {
      remote = await api.listStates(game.id).timeout(_listTimeout);
    } catch (e) {
      debugPrint('[Resume] ${game.name}: RomM list failed, local states only: $e');
      return;
    }
    final records = _records.load(game.id);
    final merged = Map<String, ResumeEntry>.of(local);
    for (final state in remote) {
      final owner = _ownerOf(state, sources, syncing);
      if (owner == null) continue;
      final key = _key(owner.emulator.emulatorId, state.fileName);
      final remoteTime =
          DateTime.tryParse(state.updatedAt ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
      final existing = merged[key];
      final record = records[state.fileName];
      if (existing == null) {
        // Synced once and since deleted on this PC: the pull deliberately
        // never restores it, so resuming it could only fail.
        if (record != null && record.hasSynced) continue;
        merged[key] = ResumeEntry(
          emulatorId: owner.emulator.emulatorId,
          emulatorName: owner.emulator.name,
          fileName: state.fileName,
          slot: owner.strategy.slotOf(state.fileName),
          savedAt: remoteTime,
          where: ResumeWhere.romm,
          installedVersion: owner.installed,
          remoteId: state.id,
          remoteUpdatedAt: state.updatedAt,
          remoteScreenshotUrl: state.screenshotUrl,
          romPath: owner.romPath,
        );
        continue;
      }
      final newer = record != null &&
          (record.rommStateId != state.id || record.serverUpdatedAt != state.updatedAt);
      merged[key] = ResumeEntry(
        emulatorId: existing.emulatorId,
        emulatorName: existing.emulatorName,
        fileName: existing.fileName,
        slot: existing.slot,
        savedAt: newer && remoteTime.isAfter(existing.savedAt) ? remoteTime : existing.savedAt,
        where: ResumeWhere.both,
        newerOnRomm: newer,
        emulatorVersion: newer ? null : existing.emulatorVersion,
        installedVersion: existing.installedVersion,
        compat: newer ? StateCompat.unknown : existing.compat,
        localFile: existing.localFile,
        remoteId: state.id,
        remoteUpdatedAt: state.updatedAt,
        remoteScreenshotUrl: state.screenshotUrl,
        romPath: existing.romPath,
      );
    }
    yield _sorted(merged.values);
  }

  /// Checks the chosen state right before launch (after the pre-launch pull).
  /// [pulled] and [conflicted] are the file names that pull downloaded and
  /// reported as conflicts; both null when no pull ran.
  Future<ResumeCheck> checkBeforeLaunch(ResumeEntry entry, Game game, String romPath,
      {Set<String>? pulled, Set<String>? conflicted}) async {
    final sources = await _sources(game, romPath, {});
    final source = _firstWhereOrNull(sources, (s) => s.emulator.emulatorId == entry.emulatorId);
    if (source == null) return const ResumeMissing();
    final file = io.File(p.join(source.dir.path, entry.fileName));
    try {
      if (!await file.exists() || await file.length() < StateSyncService.minValidStateBytes) {
        debugPrint('[Resume] ${entry.fileName} missing after pull: aborting');
        return const ResumeMissing();
      }
    } catch (e) {
      debugPrint('[Resume] ${entry.fileName}: cannot check the file after pull: $e');
      return const ResumeMissing();
    }
    // describeState/installedVersion are contractually not supposed to
    // throw, but a strategy implementation could still break that: fall back
    // to "version unknown" (no prompt) rather than losing the resume launch.
    String? stateVersion;
    String? installed;
    try {
      stateVersion = (await source.strategy.describeState(file)).emulatorVersion;
      installed = source.installed;
    } catch (e) {
      debugPrint('[Resume] ${entry.fileName}: version check failed, treating as unknown: $e');
    }
    final compat = compatOf(stateVersion, installed);
    // "Seen" only when the list itself showed the mismatch (its warning) for
    // this very state version; an emulator updated since the list must ask.
    final seen = entry.compat == StateCompat.mismatch &&
        entry.emulatorVersion != null &&
        stateVersion != null &&
        sameEmulatorVersion(entry.emulatorVersion!, stateVersion);
    final prompt = compat == StateCompat.mismatch && !seen
        ? (stateVersion: stateVersion!, installed: installed!)
        : null;
    // Stale: a newer RomM copy was expected but the pull did not bring it
    // down. A conflict is not stale: the copy on disk is the user's choice.
    final stale = entry.newerOnRomm &&
        !(pulled?.contains(entry.fileName) ?? false) &&
        !(conflicted?.contains(entry.fileName) ?? false);
    debugPrint('[Resume] version ${stateVersion ?? 'unknown'} vs installed '
        '${installed ?? 'unknown'}: ${prompt != null ? 'asking' : compat.name}');
    return ResumeReady(file.path, stale: stale, prompt: prompt);
  }

  @visibleForTesting
  int get thumbnailCacheSize => _thumbnails.length;

  /// Thumbnail for [entry] (local via the emulator, remote via RomM). Null on
  /// any failure. Successful results (including "this state has no
  /// screenshot") are cached for the session, at most [_thumbnailCacheLimit]
  /// of them; a failure is not, so the next call tries again.
  Future<Uint8List?> thumbnailFor(ResumeEntry entry) async {
    final key = '${entry.emulatorId}|${entry.fileName}|${entry.savedAt.millisecondsSinceEpoch}';
    if (_thumbnails.containsKey(key)) return _thumbnails[key];
    Uint8List? bytes;
    try {
      final local = entry.localFile;
      if (local != null && !entry.newerOnRomm) {
        bytes = await _strategyByEmulator[entry.emulatorId]?.stateScreenshot(local);
      } else if (entry.remoteScreenshotUrl != null && _api != null) {
        bytes = await _api.downloadStateScreenshot(entry.remoteScreenshotUrl!);
      }
    } catch (e) {
      debugPrint('[Resume] thumbnail for ${entry.fileName} failed: $e');
      return null;
    }
    _thumbnails.remove(key);
    _thumbnails[key] = bytes;
    while (_thumbnails.length > _thumbnailCacheLimit) {
      _thumbnails.remove(_thumbnails.keys.first); // oldest first (insertion order)
    }
    return bytes;
  }

  static const int _thumbnailCacheLimit = 32;

  /// [versions] caches each emulator's installed version for the caller's
  /// run (one question per emulator, not per disc).
  Future<List<_Source>> _sources(Game game, String romPath, Map<String, String?> versions) async {
    final result = <_Source>[];
    for (final emulator in _emulatorsFor(game.platformSlug ?? '')) {
      if (!emulator.supportsStateLoadOnLaunch) continue;
      try {
        final strategy = _resolve(game, emulatorId: emulator.emulatorId);
        if (strategy is! StateSyncCapable) continue;
        final matches = await strategy.stateFileMatcher(game, romPath);
        if (matches == null) {
          debugPrint('[Resume] ${game.name}: ${emulator.emulatorId} cannot identify the game');
          continue;
        }
        final dir = io.Directory(await strategy.stateDirectory(game, romPath));
        _strategyByEmulator[emulator.emulatorId] = strategy;
        final id = emulator.emulatorId;
        final installed =
            versions.containsKey(id) ? versions[id] : (versions[id] = await emulator.installedVersion());
        result.add(_Source(emulator, strategy, dir, matches, installed, romPath));
      } catch (e) {
        debugPrint('[Resume] ${game.name}: ${emulator.emulatorId} skipped: $e');
      }
    }
    return result;
  }

  Future<Map<String, ResumeEntry>> _localEntries(_Source source) async {
    final result = <String, ResumeEntry>{};
    try {
      if (!await source.dir.exists()) return result;
      await for (final entity in source.dir.list(followLinks: false)) {
        if (entity is! io.File) continue;
        final name = p.basename(entity.path);
        if (!source.matches(name)) continue;
        if (await entity.length() < StateSyncService.minValidStateBytes) continue;
        final info = await source.strategy.describeState(entity);
        result[_key(source.emulator.emulatorId, name)] = ResumeEntry(
          emulatorId: source.emulator.emulatorId,
          emulatorName: source.emulator.name,
          fileName: name,
          slot: source.strategy.slotOf(name),
          savedAt: info.savedAt,
          where: ResumeWhere.thisPc,
          emulatorVersion: info.emulatorVersion,
          installedVersion: source.installed,
          compat: compatOf(info.emulatorVersion, source.installed),
          localFile: entity,
          romPath: source.romPath,
        );
      }
    } catch (e) {
      debugPrint('[Resume] listing ${source.dir.path} failed: $e');
    }
    return result;
  }

  /// The source a RomM state belongs to: among the sources whose matcher
  /// accepts the name (only those of the tagged emulator when its `emulator`
  /// tag is one of ours), the first, provided they are all the same emulator
  /// ([all] is in ROM path order, see [entriesFor]). Candidates of different
  /// emulators, or none, is no owner.
  _Source? _ownerOf(RommState state, List<_Source> all, List<_Source> syncing) {
    final name = state.fileName;
    if (!StateSyncService.isSafeStateName(name)) return null;
    final tag = state.emulator?.toLowerCase();
    var candidates = all.where((s) => s.matches(name)).toList();
    if (all.any((s) => s.emulator.emulatorId.toLowerCase() == tag)) {
      candidates = candidates.where((s) => s.emulator.emulatorId.toLowerCase() == tag).toList();
    }
    if (candidates.isEmpty) return null;
    final owner = candidates.first;
    if (candidates.any((s) => s.emulator.emulatorId != owner.emulator.emulatorId)) return null;
    return syncing.contains(owner) ? owner : null;
  }

  static String _key(String emulatorId, String fileName) => '$emulatorId|$fileName';

  static T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  static List<ResumeEntry> _sorted(Iterable<ResumeEntry> entries) =>
      entries.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));
}
