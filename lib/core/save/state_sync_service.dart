import 'dart:io' as io;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../romm/romm_models.dart';
import '../romm/romm_state.dart';
import '../storage/app_preferences.dart';
import 'save_strategy.dart';
import 'state_sync_capable.dart';
import 'state_sync_record.dart';

typedef SaveStrategyResolver = SaveStrategy? Function(Game game,
    {String? emulatorId});

/// A state file that changed both locally and on RomM since the last sync (or
/// that exists on both sides without ever having been synced) and now needs
/// the user to choose which copy to keep.
class StateConflict {
  final Game game;
  final String romPath;
  final String? emulatorId;
  final String fileName;
  final String localPath;
  final int cloudStateId;

  /// RomM's `updated_at` when the conflict was found; stored as the new
  /// baseline if the user keeps the cloud copy.
  final String? cloudUpdatedAt;
  final DateTime localTime;
  final DateTime cloudTime;

  const StateConflict({
    required this.game,
    required this.romPath,
    required this.emulatorId,
    required this.fileName,
    required this.localPath,
    required this.cloudStateId,
    required this.cloudUpdatedAt,
    required this.localTime,
    required this.cloudTime,
  });
}

class StateSyncResult {
  final int downloaded;
  final int uploaded;
  final List<StateConflict> conflicts;

  /// True when nothing could be synced at all: sync is not available for the
  /// game's emulator, or the game could not be identified or its state folder
  /// found. Lets a manual sync say so instead of reporting "0 downloaded".
  final bool skipped;

  /// True when the game already had a sync operation running and this call did
  /// nothing at all. Lets a manual sync say so instead of reporting a
  /// successful "0 downloaded, 0 uploaded".
  final bool busy;

  /// Names of the state files a pull wrote to disk (empty for a push).
  final Set<String> downloadedFiles;

  /// Names of the state files a pull found already identical to the current
  /// server copy (RomM only re-stamped it, or first contact with the same
  /// bytes) and so did not need to download. Empty for a push.
  final Set<String> upToDateFiles;

  /// Every state file a pull left matching the current server copy:
  /// [downloadedFiles] and [upToDateFiles].
  Set<String> get currentFiles => {...downloadedFiles, ...upToDateFiles};

  const StateSyncResult({
    this.downloaded = 0,
    this.uploaded = 0,
    this.conflicts = const [],
    this.skipped = false,
    this.busy = false,
    this.downloadedFiles = const {},
    this.upToDateFiles = const {},
  });

  /// A run that had nothing to do.
  static const none = StateSyncResult();

  /// A run that could not start; see [skipped].
  static const unavailable = StateSyncResult(skipped: true);

  /// The game already had a sync operation running, so nothing was done; see
  /// [busy].
  static const busyGame = StateSyncResult(busy: true);
}

/// A state download failed for a reason other than the state being gone
/// (see [StateSyncService._fetch]). Keeps the original error for the log.
class _TransferFailed implements Exception {
  _TransferFailed(this.fileName, this.cause);

  final String fileName;
  final Object cause;

  @override
  String toString() => 'download of $fileName failed: $cause';
}

class _Ctx {
  const _Ctx(this.strategy, this.dir, this.matches, this.game, this.romPath,
      this.emulatorId);

  final StateSyncCapable strategy;
  final io.Directory dir;
  final bool Function(String fileName) matches;
  final Game game;
  final String romPath;
  final String? emulatorId;
}

/// Syncs an emulator's save states with RomM's `/api/states`, separately from
/// game saves. Emulator specifics come from [StateSyncCapable]; everything
/// else (hashing, records, transfers, backups, conflicts) lives here.
class StateSyncService {
  /// Smaller files are treated as empty/aborted writes and never uploaded or
  /// accepted from the server.
  static const int minValidStateBytes = 100;

  static String enabledKey(String emulatorId) => 'state_sync_enabled_$emulatorId';

  final RommStatesApi _api;
  final AppPreferences _prefs;
  final SaveStrategyResolver _resolveStrategy;
  final StateRecordStore _records;
  final Duration _listTimeout;

  /// Longest a server list call may take. Only the list is bounded: it lets an
  /// unreachable server fail fast instead of stalling the launch, and abandons
  /// nothing that writes. Downloads and uploads are never timed out here; a
  /// stalled download gives up on its own (see
  /// `RommService.stateDownloadInactivityTimeout`) and stops the pull.
  static const Duration defaultListTimeout = Duration(seconds: 20);

  StateSyncService(this._api, this._prefs, this._resolveStrategy,
      {Duration listTimeout = defaultListTimeout})
      : _records = StateRecordStore(_prefs),
        _listTimeout = listTimeout;

  bool isEnabledFor(String emulatorId) =>
      _prefs.getBool(enabledKey(emulatorId)) ?? false;

  /// True when [game]'s emulator implements state sync and the user turned it
  /// on. When [emulatorId] is unknown the strategy id stands in for it (they
  /// match for every emulator that supports state sync today).
  bool isAvailableFor(Game game, {String? emulatorId}) =>
      availabilityReason(game, emulatorId: emulatorId) == _available;

  static const String _available = 'available';

  /// [_available] when [isAvailableFor] is true, otherwise a short human reason
  /// why state sync cannot run for [game]. Read-only; for logging.
  String availabilityReason(Game game, {String? emulatorId}) {
    final strategy = _resolveStrategy(game, emulatorId: emulatorId);
    if (strategy is! StateSyncCapable) return _unsupportedReason(emulatorId, strategy);
    final key = emulatorId ?? strategy.strategyId;
    if (!isEnabledFor(key)) return _offReason(key);
    return _available;
  }

  static String _unsupportedReason(String? emulatorId, SaveStrategy? strategy) =>
      "no state-sync support for emulator '${emulatorId ?? strategy?.strategyId ?? 'unknown'}' "
      '(strategy ${strategy?.strategyId ?? 'none'})';

  static String _offReason(String key) =>
      "state sync is off for '$key': switch it on in Settings > Emulators";

  /// Null when state sync cannot run for this game (not capable, turned off,
  /// game not identified, state folder unresolved). Never throws.
  Future<_Ctx?> _context(Game game, String romPath, String? emulatorId) async {
    try {
      final strategy = _resolveStrategy(game, emulatorId: emulatorId);
      if (strategy is! StateSyncCapable) {
        debugPrint('[StateSync] ${game.name}: ${_unsupportedReason(emulatorId, strategy)}');
        return null;
      }
      final key = emulatorId ?? strategy.strategyId;
      if (!isEnabledFor(key)) {
        debugPrint('[StateSync] ${game.name}: ${_offReason(key)}');
        return null;
      }
      final matches = await strategy.stateFileMatcher(game, romPath);
      if (matches == null) {
        debugPrint('[StateSync] ${game.name}: cannot identify the game — skipping');
        return null;
      }
      final dir = io.Directory(await strategy.stateDirectory(game, romPath));
      return _Ctx(strategy, dir, matches, game, romPath, emulatorId);
    } catch (e) {
      debugPrint('[StateSync] cannot set up state sync for ${game.name}: $e — skipping');
      return null;
    }
  }

  // ─── Pull ────────────────────────────────────────────────────────────────

  /// Games with a pull, push or conflict resolution currently running. The
  /// pre-launch pull is awaited and the post-exit push is fire-and-forget, so a
  /// second Play tap or a quick relaunch can start another operation for the
  /// same game while one is still open. Each operation loads the record map at
  /// its start, so two at once would overwrite each other's updates and leave
  /// stale baselines (false conflict prompts). A busy game makes the others do
  /// nothing.
  final Set<String> _busyGames = {};

  /// Brings server states down before launch. Never throws: failures are
  /// logged and reported as "nothing done". A pull for a busy game (another
  /// pull, a push or a resolve is running) does nothing and returns
  /// [StateSyncResult.busyGame]: the local files are the newer side while a
  /// push is open. The first failed download (other than a state that vanished)
  /// ends the pull: a stalling server would otherwise cost every remaining
  /// state its own timeout before the launch this pull is holding up.
  /// [priority], when given, is downloaded before any other state (a Resume
  /// of that slot must not wait behind, or be stopped by, another slot's
  /// download).
  Future<StateSyncResult> pullStates(Game game, String romPath,
      {String? emulatorId, String? priority}) async {
    if (!_busyGames.add(game.id)) {
      debugPrint('[StateSync] ${game.id} is busy — skipping pull');
      return StateSyncResult.busyGame;
    }
    try {
      final ctx = await _context(game, romPath, emulatorId);
      if (ctx == null) return StateSyncResult.unavailable;

      debugPrint('[StateSync] pull ${game.name} (rom ${game.id}, emulator '
          '${emulatorId ?? ctx.strategy.strategyId}): states folder ${ctx.dir.path}');
      var downloaded = 0;
      final downloadedFiles = <String>{};
      var stopNote = '';
      final restamped = <String>{}; // for the log only, see _pullOne
      final upToDate = <String>{};
      final conflicts = <StateConflict>[];
      try {
        final remote = await _list(game.id);
        final ordered = priority == null
            ? remote
            : [...remote.where((s) => s.fileName == priority),
               ...remote.where((s) => s.fileName != priority)];
        final matching = remote
            .where((s) => isSafeStateName(s.fileName) && ctx.matches(s.fileName))
            .length;
        debugPrint('[StateSync] pull: RomM lists ${remote.length} state(s), '
            '$matching match this game${matching == 0 ? ' (nothing to download)' : ''}');
        final local = await _localStates(ctx);
        final records = _records.load(game.id);
        for (final state in ordered) {
          final name = state.fileName;
          if (!isSafeStateName(name) || !ctx.matches(name)) continue;
          try {
            final outcome =
                await _pullOne(ctx, state, local[name], records, restamped, upToDate);
            if (outcome.downloaded) {
              downloaded++;
              downloadedFiles.add(name);
            }
            if (outcome.conflict != null) conflicts.add(outcome.conflict!);
          } on _TransferFailed catch (e) {
            // The server is stalling or unreachable: the remaining downloads
            // would each wait out their own timeout before a launch that is
            // waiting on this pull. What was saved per file above stays.
            debugPrint('[StateSync] $e — stopping the pull');
            stopNote = ' (stopped early: a download failed)';
            break;
          } catch (e) {
            debugPrint('[StateSync] pull of $name failed: $e');
          }
          // After every file, so quitting mid-run keeps the finished work.
          await _records.save(game.id, records);
        }
      } catch (e) {
        debugPrint('[StateSync] pull failed: $e');
        stopNote = ' (stopped early: the pull failed)';
      }
      debugPrint('[StateSync] pull done: downloaded=$downloaded '
          'restamped=${restamped.length} conflicts=${conflicts.length}$stopNote');
      return StateSyncResult(
          downloaded: downloaded,
          conflicts: conflicts,
          downloadedFiles: downloadedFiles,
          upToDateFiles: upToDate);
    } finally {
      _busyGames.remove(game.id);
    }
  }

  Future<({bool downloaded, StateConflict? conflict})> _pullOne(
    _Ctx ctx,
    RommState remote,
    io.File? local,
    Map<String, StateSyncRecord> records,
    Set<String> restamped,
    Set<String> upToDate,
  ) async {
    const none = (downloaded: false, conflict: null);
    final name = remote.fileName;
    final path = p.join(ctx.dir.path, name);
    final record = records[name];

    if (local == null) {
      if (record != null && record.hasSynced) {
        debugPrint('[StateSync] $name was deleted locally — not restoring it');
        return none;
      }
      final bytes = await _fetch(ctx, remote);
      if (bytes == null) return none;
      await _writeStateFile(ctx, path, bytes);
      records[name] = _synced(remote, bytes);
      debugPrint('[StateSync] downloaded $name');
      return (downloaded: true, conflict: null);
    }

    if (record != null && record.conflict) {
      debugPrint('[StateSync] conflict $name (still unresolved from an earlier sync)');
      return (
        downloaded: false,
        conflict: _conflict(ctx, name, local, remote),
      );
    }

    final localHash = await _hashFile(local);
    if (record == null || !record.hasSynced) {
      final conflict =
          await _linkOrFlag(ctx, name, local, localHash, remote, records,
              upToDate: upToDate);
      return (downloaded: false, conflict: conflict);
    }

    final serverMoved =
        remote.id != record.rommStateId || remote.updatedAt != record.serverUpdatedAt;
    if (!serverMoved) {
      debugPrint(localHash != record.lastSyncedHash
          ? '[StateSync] kept local $name (changed locally, will upload after exit)'
          : '[StateSync] unchanged $name');
      return none;
    }

    if (localHash != record.lastSyncedHash) {
      records[name] = record.copyWith(conflict: true);
      debugPrint('[StateSync] conflict $name (changed on both sides)');
      return (
        downloaded: false,
        conflict: _conflict(ctx, name, local, remote),
      );
    }

    final bytes = await _fetch(ctx, remote);
    if (bytes == null) return none;
    if (_hashBytes(bytes) == localHash) {
      // Same bytes: RomM just re-stamped the state (e.g. a rescan).
      records[name] = _synced(remote, bytes);
      restamped.add(name);
      upToDate.add(name);
      debugPrint(restampedLine(name, remote, record));
      return none;
    }
    await _writeStateFile(ctx, path, bytes);
    records[name] = _synced(remote, bytes);
    debugPrint('[StateSync] downloaded $name');
    return (downloaded: true, conflict: null);
  }

  /// The log line for a state RomM re-stamped: says which of the state id and
  /// `updated_at` moved, since only what differs is worth reporting.
  @visibleForTesting
  static String restampedLine(
      String name, RommState remote, StateSyncRecord record) {
    final changes = [
      if (remote.id != record.rommStateId)
        'state id changed (was ${record.rommStateId}, now ${remote.id})',
      if (remote.updatedAt != record.serverUpdatedAt)
        'updated_at changed (was ${record.serverUpdatedAt}, now ${remote.updatedAt})',
    ];
    return '[StateSync] restamped $name (state id ${remote.id}): '
        '${changes.join(' and ')}, the bytes are identical so nothing was written';
  }

  // ─── Push ────────────────────────────────────────────────────────────────

  /// Uploads changed states, normally right after the emulator exits. With a
  /// [sessionStart] only files modified during that session are considered.
  /// Never throws: failures are logged and reported as "nothing done". A push
  /// for a busy game (see [_busyGames]) does nothing and returns
  /// [StateSyncResult.busyGame].
  Future<StateSyncResult> pushStates(Game game, String romPath,
      {DateTime? sessionStart, String? emulatorId}) async {
    if (!_busyGames.add(game.id)) {
      debugPrint('[StateSync] ${game.id} is busy — skipping push');
      return StateSyncResult.busyGame;
    }
    try {
      final ctx = await _context(game, romPath, emulatorId);
      if (ctx == null) return StateSyncResult.unavailable;

      var uploaded = 0;
      final conflicts = <StateConflict>[];
      try {
        final candidates = await _pushCandidates(ctx, sessionStart);
        if (candidates.isEmpty) {
          debugPrint('[StateSync] push: nothing to upload (no matching state of '
              'at least $minValidStateBytes bytes '
              '${sessionStart == null ? 'found' : 'was modified this session'})');
          return StateSyncResult.none;
        }

        final server = {
          for (final state in await _list(game.id)) state.fileName: state,
        };
        final records = _records.load(game.id);
        for (final entry in candidates.entries) {
          try {
            final outcome = await _pushOne(
                ctx, entry.key, entry.value, server[entry.key], records);
            if (outcome.uploaded) uploaded++;
            if (outcome.conflict != null) conflicts.add(outcome.conflict!);
          } catch (e) {
            debugPrint('[StateSync] push of ${entry.key} failed: $e');
          }
          // After every file, so quitting mid-run keeps the finished uploads.
          await _records.save(game.id, records);
        }
      } catch (e) {
        debugPrint('[StateSync] push failed: $e');
      }
      debugPrint('[StateSync] push done: uploaded=$uploaded conflicts=${conflicts.length}');
      return StateSyncResult(uploaded: uploaded, conflicts: conflicts);
    } finally {
      _busyGames.remove(game.id);
    }
  }

  Future<Map<String, io.File>> _pushCandidates(
      _Ctx ctx, DateTime? sessionStart) async {
    final cutoff = sessionStart?.subtract(const Duration(seconds: 2));
    final result = <String, io.File>{};
    final local = await _localStates(ctx);
    for (final entry in local.entries) {
      if (cutoff != null && !entry.value.lastModifiedSync().isAfter(cutoff)) continue;
      if (entry.value.lengthSync() < minValidStateBytes) continue;
      result[entry.key] = entry.value;
    }
    debugPrint('[StateSync] push ${ctx.game.name} (rom ${ctx.game.id}): '
        '${result.length} of ${local.length} local state(s) eligible ('
        '${sessionStart == null ? 'any modification time' : 'modified since ${sessionStart.toIso8601String()}'}'
        ', at least $minValidStateBytes bytes)');
    return result;
  }

  Future<({bool uploaded, StateConflict? conflict})> _pushOne(
    _Ctx ctx,
    String name,
    io.File file,
    RommState? server,
    Map<String, StateSyncRecord> records,
  ) async {
    const none = (uploaded: false, conflict: null);
    var record = records[name];

    // A flagged slot is only skipped while its server copy still exists. If
    // that copy is gone (deleted on RomM, other account) there is nothing left
    // to conflict with and nothing is overwritten: the local state is uploaded
    // again below, which replaces the record and clears the flag. Skipping it
    // instead would leave the slot flagged for good, because a pull only
    // reports conflicts for server states that exist, so no dialog could ever
    // resolve it.
    if (record != null && record.conflict && server != null) {
      debugPrint('[StateSync] conflict $name (still unresolved from an earlier sync)');
      return (
        uploaded: false,
        conflict: _conflict(ctx, name, file, server),
      );
    }

    final hash = await _hashFile(file);
    if (record != null && record.hasSynced && record.lastSyncedHash == hash) {
      debugPrint('[StateSync] unchanged $name');
      return none; // unchanged since the last sync
    }

    if (record != null && record.conflict && server == null) {
      debugPrint('[StateSync] $name was flagged as a conflict but its server '
          'copy is gone — uploading the local state again');
    }

    if (server != null && (record == null || !record.hasSynced)) {
      // Same name on both sides with no shared history: never overwrite.
      final conflict =
          await _linkOrFlag(ctx, name, file, hash, server, records);
      if (conflict != null) return (uploaded: false, conflict: conflict);
      record = records[name];
      if (record != null && record.hasSynced && record.lastSyncedHash == hash) {
        return none; // identical bytes: linked, nothing to upload
      }
      // The server copy was unreadable (corrupt/empty): replace it below.
    } else if (server != null &&
        record != null &&
        (server.id != record.rommStateId || server.updatedAt != record.serverUpdatedAt)) {
      // Local changed (hash differs) AND the server copy moved: conflict.
      records[name] = record.copyWith(conflict: true);
      debugPrint('[StateSync] conflict $name (changed on both sides)');
      return (
        uploaded: false,
        conflict: _conflict(ctx, name, file, server),
      );
    }

    // No server copy means never uploaded, or the copy is gone (deleted /
    // other account): create it.
    final saved = await _upload(ctx, file, name, server: server);
    records[name] = StateSyncRecord(
      rommStateId: saved.id,
      lastSyncedHash: hash,
      serverUpdatedAt: saved.updatedAt,
    );
    return (uploaded: true, conflict: null);
  }

  // ─── Conflict resolution ─────────────────────────────────────────────────

  /// Applies the user's choice for [conflict]: `'local'` uploads the local
  /// state over the server copy, `'cloud'` replaces the local state with the
  /// server copy (backing the local one up first). Either way the record is
  /// re-baselined so the conflict flag clears. Returns false on any failure,
  /// and when the game is busy (see [_busyGames]).
  Future<bool> resolveConflict(StateConflict conflict,
      {required String choice}) async {
    final gameId = conflict.game.id;
    if (!_busyGames.add(gameId)) {
      debugPrint('[StateSync] $gameId is busy — not resolving ${conflict.fileName}');
      return false;
    }
    try {
      return await _resolve(conflict, choice);
    } finally {
      _busyGames.remove(gameId);
    }
  }

  Future<bool> _resolve(StateConflict conflict, String choice) async {
    final ctx =
        await _context(conflict.game, conflict.romPath, conflict.emulatorId);
    if (ctx == null) return false;
    final records = _records.load(conflict.game.id);
    final file = io.File(conflict.localPath);
    debugPrint('[StateSync] resolve ${conflict.fileName}: keep $choice');
    try {
      if (choice == 'cloud') {
        final bytes = await _fetch(ctx, _cloudState(conflict));
        if (bytes == null) return false;
        await _writeStateFile(ctx, conflict.localPath, bytes);
        records[conflict.fileName] = StateSyncRecord(
          rommStateId: conflict.cloudStateId,
          lastSyncedHash: _hashBytes(bytes),
          serverUpdatedAt: conflict.cloudUpdatedAt,
        );
      } else if (choice == 'local') {
        if (!await file.exists()) {
          debugPrint('[StateSync] local copy of ${conflict.fileName} no longer exists');
          return false;
        }
        // Read once: the same bytes are validated, uploaded and hashed.
        final bytes = await file.readAsBytes();
        if (bytes.length < minValidStateBytes ||
            !ctx.strategy.looksLikeValidState(Uint8List.fromList(bytes))) {
          debugPrint('[StateSync] local copy of ${conflict.fileName} is not a valid state (${bytes.length} bytes) — not uploading');
          return false;
        }
        final saved = await _upload(ctx, file, conflict.fileName,
            server: _cloudState(conflict));
        records[conflict.fileName] = StateSyncRecord(
          rommStateId: saved.id,
          lastSyncedHash: _hashBytes(bytes),
          serverUpdatedAt: saved.updatedAt,
        );
      } else {
        debugPrint('[StateSync] resolve ${conflict.fileName}: unknown choice '
            "'$choice' — nothing done");
        return false;
      }
      await _records.save(conflict.game.id, records);
      debugPrint('[StateSync] resolve ${conflict.fileName}: keep $choice -> '
          "${choice == 'local' ? 'uploaded' : 'restored'}");
      return true;
    } on RommStateNotFoundException {
      debugPrint('[StateSync] ${conflict.fileName} no longer exists on RomM');
      return false;
    } catch (e) {
      debugPrint('[StateSync] resolving ${conflict.fileName} failed: $e');
      return false;
    }
  }

  // ─── Shared helpers ──────────────────────────────────────────────────────

  /// The one place the server list is fetched, bounded by the list timeout. A
  /// [TimeoutException] is handled like any other failed list call.
  Future<List<RommState>> _list(String gameId) =>
      _api.listStates(gameId).timeout(_listTimeout);

  /// A local file and a server state exist with no shared history. Identical
  /// bytes: record them as synced. Different bytes: flag a conflict and leave
  /// both untouched. Returns null when linked or when the server copy could
  /// not be read.
  Future<StateConflict?> _linkOrFlag(
    _Ctx ctx,
    String name,
    io.File local,
    String localHash,
    RommState remote,
    Map<String, StateSyncRecord> records, {
    Set<String>? upToDate,
  }) async {
    final bytes = await _fetch(ctx, remote);
    if (bytes == null) return null;
    if (_hashBytes(bytes) == localHash) {
      records[name] = _synced(remote, bytes);
      upToDate?.add(name);
      debugPrint('[StateSync] linked $name (identical bytes)');
      return null;
    }
    records[name] = StateSyncRecord(
        rommStateId: remote.id, serverUpdatedAt: remote.updatedAt, conflict: true);
    debugPrint('[StateSync] conflict $name (on both sides with no shared history, '
        'contents differ)');
    return _conflict(ctx, name, local, remote);
  }

  StateConflict _conflict(
      _Ctx ctx, String name, io.File local, RommState remote) {
    return StateConflict(
      game: ctx.game,
      romPath: ctx.romPath,
      emulatorId: ctx.emulatorId,
      fileName: name,
      localPath: local.path,
      cloudStateId: remote.id,
      cloudUpdatedAt: remote.updatedAt,
      localTime: local.lastModifiedSync(),
      cloudTime: DateTime.tryParse(remote.updatedAt ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  StateSyncRecord _synced(RommState remote, List<int> bytes) => StateSyncRecord(
        rommStateId: remote.id,
        lastSyncedHash: _hashBytes(bytes),
        serverUpdatedAt: remote.updatedAt,
      );

  /// Puts [file] on RomM as [name]: replaces [server] in place when given (a
  /// vanished server copy is re-created), creates a new state otherwise. New
  /// states are tagged with the emulator id; both paths send the state's
  /// screenshot when the emulator provides one.
  Future<RommState> _upload(_Ctx ctx, io.File file, String name,
      {RommState? server}) async {
    final screenshot = await _screenshotFor(ctx, file);
    int? goneId;
    if (server != null) {
      try {
        final saved = await _api.updateState(server.id, file, fileName: name, screenshot: screenshot);
        debugPrint('[StateSync] uploaded $name (PUT, id ${saved.id})');
        return saved;
      } on RommStateNotFoundException {
        goneId = server.id;
      }
    }
    final saved = await _api.uploadState(ctx.game.id, file,
        fileName: name,
        emulator: ctx.emulatorId ?? ctx.strategy.strategyId,
        screenshot: screenshot);
    debugPrint('[StateSync] uploaded $name (POST, id ${saved.id})'
        "${goneId == null ? '' : ' - re-created: state $goneId is gone from RomM'}");
    return saved;
  }

  /// The emulator's screenshot for [file]; never fails an upload.
  Future<Uint8List?> _screenshotFor(_Ctx ctx, io.File file) async {
    try {
      return await ctx.strategy.stateScreenshot(file);
    } catch (e) {
      debugPrint('[StateSync] no screenshot for ${p.basename(file.path)}: $e');
      return null;
    }
  }

  /// The server copy [conflict] was found against.
  RommState _cloudState(StateConflict conflict) => RommState(
        id: conflict.cloudStateId,
        fileName: conflict.fileName,
        updatedAt: conflict.cloudUpdatedAt,
      );

  /// Downloads [state], or returns null if it is gone or fails validation. Any
  /// other download failure (stalled, timed out, connection lost) is thrown as
  /// a [_TransferFailed]; [pullStates] stops at the first one.
  Future<Uint8List?> _fetch(_Ctx ctx, RommState state) async {
    final Uint8List bytes;
    try {
      bytes = await _api.downloadState(state.id);
    } on RommStateNotFoundException {
      debugPrint('[StateSync] ${state.fileName} vanished from RomM before download');
      return null;
    } catch (e) {
      throw _TransferFailed(state.fileName, e);
    }
    if (bytes.length < minValidStateBytes || !ctx.strategy.looksLikeValidState(bytes)) {
      debugPrint('[StateSync] rejected ${state.fileName}: not a valid state (${bytes.length} bytes)');
      return null;
    }
    return bytes;
  }

  /// Replaces a state via a temp file + rename, after backing up whatever is
  /// there now, so a crash mid-write never leaves a half-written state.
  ///
  /// `backupSave` swallows its own failures, so this checks that the `.bak`
  /// really exists before replacing a state that was there. If it cannot be
  /// made the existing state is left untouched and a [io.FileSystemException]
  /// is thrown. The temp file never outlives a failed write.
  Future<void> _writeStateFile(_Ctx ctx, String path, Uint8List bytes) async {
    await io.File(path).parent.create(recursive: true);
    final temp = io.File('$path.freegosy_tmp');
    try {
      final existed = await io.File(path).exists();
      await temp.writeAsBytes(bytes, flush: true);
      await ctx.strategy.backupSave(path);
      if (existed && !await io.File('${p.normalize(path)}.bak').exists()) {
        throw io.FileSystemException(
            'Could not back up the existing state before replacing it', path);
      }
      await temp.rename(path);
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // Best effort: a leftover temp file is overwritten by the next write.
      }
    }
  }

  /// Local state files that belong to the game, by file name.
  Future<Map<String, io.File>> _localStates(_Ctx ctx) async {
    final result = <String, io.File>{};
    if (!await ctx.dir.exists()) return result;
    await for (final entity in ctx.dir.list()) {
      if (entity is! io.File) continue;
      final name = p.basename(entity.path);
      if (ctx.matches(name)) result[name] = entity;
    }
    return result;
  }

  /// Server-supplied names become local paths, so reject anything that isn't
  /// a bare file name.
  static bool isSafeStateName(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      p.basename(name) == name &&
      !name.contains('/') &&
      !name.contains(r'\');

  Future<String> _hashFile(io.File file) async =>
      _hashBytes(await file.readAsBytes());

  String _hashBytes(List<int> bytes) => md5.convert(bytes).toString();
}
