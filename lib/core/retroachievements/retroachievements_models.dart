/// Credentials for the RetroAchievements Web API.
///
/// RA authenticates every request via two query parameters (`u` for
/// username, `y` for the user's Web API key) rather than a bearer token or
/// session cookie — see https://api-docs.retroachievements.org/getting-started.html
class RetroAchievementsCredentials {
  final String username;
  final String webApiKey;

  const RetroAchievementsCredentials({required this.username, required this.webApiKey});

  /// True when the Web API can't be called (both fields are required there).
  bool get isEmpty => username.isEmpty || webApiKey.isEmpty;

  /// The Web API key is optional in Settings: without it Freegosy can still
  /// sign emulators in and show progress RomM synced, just not live data.
  bool get hasWebApiKey => webApiKey.isNotEmpty;
}

/// A user's profile summary, as returned by API_GetUserSummary.php.
///
/// RA's HTTP responses use PascalCase field names; this model exposes them
/// as idiomatic Dart camelCase properties.
class RetroAchievementsProfile {
  final String username;
  final int rank;
  final int totalPoints;
  final int totalTruePoints;
  final String? avatarUrl;
  final DateTime? memberSince;

  const RetroAchievementsProfile({
    required this.username,
    required this.rank,
    required this.totalPoints,
    required this.totalTruePoints,
    this.avatarUrl,
    this.memberSince,
  });

  factory RetroAchievementsProfile.fromJson(Map<String, dynamic> json) {
    final userPic = json['UserPic']?.toString();
    return RetroAchievementsProfile(
      username: json['User']?.toString() ?? json['Username']?.toString() ?? '',
      rank: int.tryParse(json['Rank']?.toString() ?? '') ?? 0,
      totalPoints: int.tryParse(json['TotalPoints']?.toString() ?? '') ?? 0,
      totalTruePoints: int.tryParse(json['TotalTruePoints']?.toString() ?? '') ?? 0,
      // UserPic is a site-relative path (e.g. "/UserPic/foo.png"); RA serves
      // avatars from the media host, not the main site host.
      avatarUrl: (userPic != null && userPic.isNotEmpty) ? 'https://media.retroachievements.org$userPic' : null,
      memberSince: DateTime.tryParse(json['MemberSince']?.toString() ?? ''),
    );
  }
}

/// Thrown when the RetroAchievements API rejects a request, most commonly
/// due to an invalid username/API key pair.
class RetroAchievementsAuthException implements Exception {
  final String message;
  const RetroAchievementsAuthException(this.message);

  @override
  String toString() => 'RetroAchievementsAuthException: $message';
}
