/// Per-game RetroAchievements data: the achievement set of a game and a
/// user's progress through it.
///
/// Two sources feed these models:
///  * RomM, which stores a game's achievement list (no user progress) in
///    `merged_ra_metadata` once its RetroAchievements metadata provider has
///    matched the ROM — see [RetroAchievement.fromRommJson].
///  * The RA Web API's API_GetGameInfoAndUserProgress.php, which adds the
///    connected user's unlock dates — see [RetroAchievementsGameProgress.fromJson].
library;

const _mediaBase = 'https://media.retroachievements.org';

int _int(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

/// RA serves timestamps as "YYYY-MM-DD HH:MM:SS" in UTC.
DateTime? _raDate(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s.contains('T') ? s : '${s.replaceFirst(' ', 'T')}Z');
}

class RetroAchievement {
  final int id;
  final String title;
  final String description;
  final int points;
  final String badgeName;
  final int displayOrder;

  /// `progression`, `win_condition`, `missable`, or null for unlabelled.
  final String? type;
  final int numAwarded;
  final int numAwardedHardcore;
  final DateTime? dateEarned;
  final DateTime? dateEarnedHardcore;

  const RetroAchievement({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.badgeName,
    this.displayOrder = 0,
    this.type,
    this.numAwarded = 0,
    this.numAwardedHardcore = 0,
    this.dateEarned,
    this.dateEarnedHardcore,
  });

  RetroAchievement withUnlock({DateTime? earned, DateTime? earnedHardcore}) => RetroAchievement(
        id: id,
        title: title,
        description: description,
        points: points,
        badgeName: badgeName,
        displayOrder: displayOrder,
        type: type,
        numAwarded: numAwarded,
        numAwardedHardcore: numAwardedHardcore,
        dateEarned: earned,
        dateEarnedHardcore: earnedHardcore,
      );

  bool get isUnlocked => dateEarned != null || dateEarnedHardcore != null;
  bool get isUnlockedHardcore => dateEarnedHardcore != null;

  String get badgeUrl => '$_mediaBase/Badge/$badgeName.png';
  String get lockedBadgeUrl => '$_mediaBase/Badge/${badgeName}_lock.png';

  /// Parses an entry from the RA Web API's `Achievements` map.
  factory RetroAchievement.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString();
    return RetroAchievement(
      id: _int(json['ID']),
      title: json['Title']?.toString() ?? '',
      description: json['Description']?.toString() ?? '',
      points: _int(json['Points']),
      badgeName: json['BadgeName']?.toString() ?? '',
      displayOrder: _int(json['DisplayOrder']),
      type: (type == null || type.isEmpty) ? null : type,
      numAwarded: _int(json['NumAwarded']),
      numAwardedHardcore: _int(json['NumAwardedHardcore']),
      dateEarned: _raDate(json['DateEarned']),
      dateEarnedHardcore: _raDate(json['DateEarnedHardcore']),
    );
  }

  /// Parses an entry from RomM's `merged_ra_metadata.achievements`.
  factory RetroAchievement.fromRommJson(Map<String, dynamic> json) {
    final type = json['type']?.toString();
    return RetroAchievement(
      id: _int(json['ra_id']),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      points: _int(json['points']),
      badgeName: json['badge_id']?.toString() ?? '',
      displayOrder: _int(json['display_order']),
      type: (type == null || type.isEmpty) ? null : type,
      numAwarded: _int(json['num_awarded']),
      numAwardedHardcore: _int(json['num_awarded_hardcore']),
    );
  }

  /// Serializes back to RomM's shape so it round-trips through the offline
  /// metadata cache alongside the rest of [Game.toJson].
  Map<String, dynamic> toRommJson() => {
        'ra_id': id,
        'title': title,
        'description': description,
        'points': points,
        'badge_id': badgeName,
        'display_order': displayOrder,
        'type': type,
        'num_awarded': numAwarded,
        'num_awarded_hardcore': numAwardedHardcore,
      };
}

/// Sorts the way RA's own game page does: by display order, then by id.
List<RetroAchievement> sortAchievements(Iterable<RetroAchievement> list) =>
    list.toList()..sort((a, b) {
      final byOrder = a.displayOrder.compareTo(b.displayOrder);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });

/// The highest award a user holds for a game, from `HighestAwardKind`.
enum RetroAchievementsAward {
  mastered('Mastered'),
  completed('Completed'),
  beatenHardcore('Beaten'),
  beatenSoftcore('Beaten (softcore)');

  final String label;
  const RetroAchievementsAward(this.label);

  static RetroAchievementsAward? parse(String? kind) => switch (kind) {
        'mastered' => mastered,
        'completed' => completed,
        'beaten-hardcore' => beatenHardcore,
        'beaten-softcore' => beatenSoftcore,
        _ => null,
      };
}

class RetroAchievementsGameProgress {
  final int gameId;
  final String title;
  final String consoleName;
  final String? iconUrl;
  final List<RetroAchievement> achievements;
  final RetroAchievementsAward? highestAward;

  const RetroAchievementsGameProgress({
    required this.gameId,
    required this.title,
    required this.consoleName,
    required this.achievements,
    this.iconUrl,
    this.highestAward,
  });

  int get totalCount => achievements.length;
  int get unlockedCount => achievements.where((a) => a.isUnlocked).length;
  int get unlockedHardcoreCount => achievements.where((a) => a.isUnlockedHardcore).length;
  int get totalPoints => achievements.fold(0, (sum, a) => sum + a.points);
  int get earnedPoints => achievements.where((a) => a.isUnlocked).fold(0, (sum, a) => sum + a.points);

  factory RetroAchievementsGameProgress.fromJson(Map<String, dynamic> json) {
    // PHP serializes an empty associative array as `[]`, so a game with no
    // achievements comes back as a List rather than a Map.
    final raw = json['Achievements'];
    final achievements = raw is Map
        ? raw.values.whereType<Map<String, dynamic>>().map(RetroAchievement.fromJson)
        : const <RetroAchievement>[];
    final icon = json['ImageIcon']?.toString();
    return RetroAchievementsGameProgress(
      gameId: _int(json['ID']),
      title: json['Title']?.toString() ?? '',
      consoleName: json['ConsoleName']?.toString() ?? '',
      iconUrl: (icon != null && icon.isNotEmpty) ? '$_mediaBase$icon' : null,
      achievements: sortAchievements(achievements),
      highestAward: RetroAchievementsAward.parse(json['HighestAwardKind']?.toString()),
    );
  }

  /// Builds progress from what RomM synced: the achievement set RomM stored
  /// for the game plus the user's `ra_progression` entry for it, whose
  /// `earned_achievements` are `{id, date, date_hardcore}` records.
  factory RetroAchievementsGameProgress.fromRomm({
    required int gameId,
    required List<RetroAchievement> achievements,
    required Map<String, dynamic> progression,
  }) {
    final earned = <int, Map<String, dynamic>>{
      for (final e in (progression['earned_achievements'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>())
        _int(e['id']): e,
    };
    return RetroAchievementsGameProgress(
      gameId: gameId,
      title: '',
      consoleName: '',
      achievements: [
        for (final a in achievements)
          earned.containsKey(a.id)
              ? a.withUnlock(earned: _raDate(earned[a.id]!['date']), earnedHardcore: _raDate(earned[a.id]!['date_hardcore']))
              : a,
      ],
      highestAward: RetroAchievementsAward.parse(progression['highest_award_kind']?.toString()),
    );
  }
}
