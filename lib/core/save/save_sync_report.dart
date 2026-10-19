/// One local save file that a push would consider.
class LocalSaveInfo {
  final String name;
  final int size;
  final DateTime modified;
  const LocalSaveInfo(this.name, this.size, this.modified);
}

/// The newest save RomM holds for the game.
class CloudSaveInfo {
  final String name;
  final int? size;
  final DateTime? updated;
  const CloudSaveInfo(this.name, this.size, this.updated);
}

enum FindingLevel { ok, info, warning, problem }

class SyncFinding {
  final FindingLevel level;
  final String text;
  const SyncFinding(this.level, this.text);
}

/// What "Check save sync" tells the user about one game: where its saves are
/// looked for, what is there, what RomM has, and what looks wrong.
class SaveSyncReport {
  final String gameName;
  final String? emulator;
  final String? saveDir;
  final List<LocalSaveInfo> localSaves;
  final CloudSaveInfo? cloud;
  final List<SyncFinding> findings;

  const SaveSyncReport({
    required this.gameName,
    required this.emulator,
    required this.saveDir,
    required this.localSaves,
    required this.cloud,
    required this.findings,
  });

  bool get hasProblems => findings.any((f) => f.level == FindingLevel.problem);
  bool get hasWarnings => findings.any((f) => f.level == FindingLevel.warning);

  /// Pure analysis of what was gathered; no I/O.
  ///
  /// [noStrategy]: no save strategy handles this game's emulator/platform.
  /// [blockedReason]: the strategy refuses to sync (see `saveSyncBlockedReason`).
  /// [cloudError]: RomM could not be asked.
  static SaveSyncReport analyze({
    required String gameName,
    required String? emulator,
    required bool noStrategy,
    String? blockedReason,
    required String? saveDir,
    required List<LocalSaveInfo> localSaves,
    required CloudSaveInfo? cloud,
    String? cloudError,
    String? locationHint,
    int minValidSaveBytes = 100,
  }) {
    final f = <SyncFinding>[];

    if (noStrategy) {
      f.add(const SyncFinding(FindingLevel.problem,
          'Save sync is not available for this emulator or platform.'));
    } else if (blockedReason != null) {
      f.add(SyncFinding(FindingLevel.problem, blockedReason));
    } else {
      if (saveDir == null) {
        f.add(const SyncFinding(FindingLevel.warning,
            'The emulator\'s save folder was not found. Play the game once and close the emulator normally so it creates its saves.'));
      }
      if (locationHint != null && localSaves.isEmpty) f.add(SyncFinding(FindingLevel.info, locationHint));
      if (localSaves.isEmpty) {
        if (saveDir != null) {
          f.add(const SyncFinding(FindingLevel.warning, 'No save file for this game was found in the save folder.'));
        }
      } else {
        for (final s in localSaves) {
          if (s.size < minValidSaveBytes) {
            f.add(SyncFinding(FindingLevel.warning,
                '${s.name} is only ${s.size} bytes, so it is treated as empty and will not be uploaded.'));
          }
        }
        final byLower = <String, List<String>>{};
        for (final s in localSaves) {
          byLower.putIfAbsent(s.name.toLowerCase(), () => []).add(s.name);
        }
        for (final names in byLower.values.where((n) => n.length > 1)) {
          f.add(SyncFinding(FindingLevel.warning,
              'These saves differ only in letter case, and an emulator reads just one of them: ${names.join(', ')}.'));
        }
      }

      if (cloudError != null) {
        f.add(SyncFinding(FindingLevel.warning, 'Could not reach RomM: $cloudError'));
      } else if (cloud == null) {
        f.add(SyncFinding(
            FindingLevel.info,
            localSaves.isEmpty
                ? 'RomM has no save for this game yet.'
                : 'RomM has no save for this game yet. Push Saves will upload the local one.'));
      } else if (localSaves.isNotEmpty && cloud.updated != null) {
        final newestLocal = localSaves.map((s) => s.modified).reduce((a, b) => a.isAfter(b) ? a : b);
        if (newestLocal.isAfter(cloud.updated!.add(const Duration(seconds: 2)))) {
          f.add(const SyncFinding(FindingLevel.info, 'The local save is newer than the one on RomM; it uploads after you play or on Push Saves.'));
        } else if (cloud.updated!.isAfter(newestLocal.add(const Duration(seconds: 2)))) {
          f.add(const SyncFinding(FindingLevel.info, 'The save on RomM is newer than the local one; it downloads on the next launch or with Pull Saves.'));
        } else {
          f.add(const SyncFinding(FindingLevel.ok, 'The local save and the save on RomM are about the same age.'));
        }
      }

      if (f.every((x) => x.level == FindingLevel.info || x.level == FindingLevel.ok) && saveDir != null && localSaves.isNotEmpty) {
        f.insert(0, const SyncFinding(FindingLevel.ok, 'Local saves were found and can be synced.'));
      }
    }

    return SaveSyncReport(
      gameName: gameName,
      emulator: emulator,
      saveDir: saveDir,
      localSaves: localSaves,
      cloud: cloud,
      findings: f,
    );
  }

  /// Plain text for the dialog and for pasting into a bug report.
  String toText() {
    String when(DateTime? d) => d == null ? 'unknown time' : d.toLocal().toString().split('.').first;
    final b = StringBuffer()
      ..writeln('Save sync check: $gameName')
      ..writeln('Emulator: ${emulator ?? 'none'}')
      ..writeln('Save folder: ${saveDir ?? 'not found'}');
    b.writeln(localSaves.isEmpty ? 'Local saves: none' : 'Local saves:');
    for (final s in localSaves) {
      b.writeln('  - ${s.name} (${s.size} bytes, ${when(s.modified)})');
    }
    b.writeln(cloud == null
        ? 'RomM: no save'
        : 'RomM: ${cloud!.name}${cloud!.size != null ? ' (${cloud!.size} bytes' : ' ('}, ${when(cloud!.updated)})');
    b.writeln('');
    const marks = {
      FindingLevel.ok: '[ok]',
      FindingLevel.info: '[info]',
      FindingLevel.warning: '[warning]',
      FindingLevel.problem: '[problem]',
    };
    for (final x in findings) {
      b.writeln('${marks[x.level]} ${x.text}');
    }
    return b.toString().trimRight();
  }
}
