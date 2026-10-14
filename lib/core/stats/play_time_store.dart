import 'dart:convert';

import '../storage/app_preferences.dart';

/// What Freegosy has measured for one game on this machine.
class PlayStats {
  final Duration total;
  final int sessions;
  final DateTime? lastPlayed;
  const PlayStats({required this.total, required this.sessions, this.lastPlayed});
}

/// Local play-time totals per game, kept in preferences. Independent of RomM,
/// so it works on servers older than 4.9 and offline; sessions are measured
/// from emulator launch to exit, the same span sent to RomM.
class PlayTimeStore {
  final AppPreferences _prefs;
  PlayTimeStore(this._prefs);

  /// Sessions shorter than this are a launch that failed or was closed at once.
  static const minSession = Duration(seconds: 10);

  static String _key(String gameId) => 'playtime_$gameId';

  Future<void> record(String gameId, DateTime start, DateTime end) async {
    final length = end.difference(start);
    if (length < minSession) return;
    final now = statsFor(gameId);
    await _prefs.setString(
      _key(gameId),
      jsonEncode({
        'ms': (now?.total ?? Duration.zero).inMilliseconds + length.inMilliseconds,
        'sessions': (now?.sessions ?? 0) + 1,
        'last': end.toUtc().toIso8601String(),
      }),
    );
  }

  PlayStats? statsFor(String gameId) {
    final raw = _prefs.getString(_key(gameId));
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return PlayStats(
        total: Duration(milliseconds: (m['ms'] as num).toInt()),
        sessions: (m['sessions'] as num?)?.toInt() ?? 1,
        lastPlayed: DateTime.tryParse(m['last']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  /// "45m", "2h 15m", "12h", "under a minute".
  static String format(Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 1) return 'under a minute';
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60, m = minutes % 60;
    if (h >= 10 || m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  /// "just now", "5 minutes ago", "yesterday", "3 days ago", "2 months ago".
  static String ago(DateTime when, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(when);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} minute${d.inMinutes == 1 ? '' : 's'} ago';
    if (d.inHours < 24) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 30) return '${d.inDays} days ago';
    final months = d.inDays ~/ 30;
    if (months < 12) return '$months month${months == 1 ? '' : 's'} ago';
    return '${d.inDays ~/ 365} year${d.inDays ~/ 365 == 1 ? '' : 's'} ago';
  }
}
