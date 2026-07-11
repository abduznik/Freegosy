import 'package:package_info_plus/package_info_plus.dart';

class AppConstants {
  /// App version, read from pubspec.yaml at startup via package_info_plus.
  /// Update only in pubspec.yaml — this field is populated automatically.
  static String version = '0.0.0'; // Overwritten in main() from pubspec.yaml

  /// Call once in main() before runApp() to populate [version].
  static Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    version = info.version;
  }
}
