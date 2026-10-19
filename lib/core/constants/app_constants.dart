import 'package:package_info_plus/package_info_plus.dart';

class AppConstants {
  /// App version, read from pubspec.yaml at startup via package_info_plus.
  /// Update only in pubspec.yaml — this field is populated automatically.
  static String version = '0.0.0'; // Overwritten in main() from pubspec.yaml

  /// Set by the nightly workflow (`--dart-define=FREEGOSY_CHANNEL=nightly`). A
  /// nightly carries the plain version number, so this is how the app knows it
  /// is one, and so should only be replaced by a newer nightly or a newer release.
  static const String buildChannel = String.fromEnvironment('FREEGOSY_CHANNEL');
  static bool get isNightlyBuild => buildChannel == 'nightly';

  /// [raw] without a leading `v`: the release workflow passes the tag
  /// (`v0.6.1`) as the Linux/macOS build name, and the UI adds its own `v`.
  static String normalizeVersion(String raw) => raw.trim().replaceFirst(RegExp(r'^[vV]'), '');

  /// Call once in main() before runApp() to populate [version].
  static Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    version = normalizeVersion(info.version);
  }
}
