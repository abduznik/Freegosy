import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Platform abstraction for testability.
///
/// Production code uses [PlatformInfo.current] which reads from `dart:io`.
/// Tests can inject a synthetic instance: `PlatformInfo('windows')`.
class PlatformInfo {
  final String os;
  final Map<String, String> environment;

  const PlatformInfo(this.os, {this.environment = const {}});

  bool get isWindows => os == 'windows';
  bool get isMacOS => os == 'macos';
  bool get isLinux => os == 'linux';

  /// Running in a browser: there is no `dart:io` platform, file system or
  /// emulator to launch.
  bool get isWeb => os == 'web';

  /// Returns the platform-specific path separator.
  String get pathSeparator => isWindows ? '\\' : '/';

  /// Returns the home directory for the current platform.
  String get homeDir {
    if (isWindows) return environment['USERPROFILE'] ?? environment['HOME'] ?? '';
    return environment['HOME'] ?? '';
  }

  /// Returns the AppData directory (Windows) or empty string.
  String get appData => environment['APPDATA'] ?? '';

  /// Returns the current platform from dart:io, or [web] in a browser, where
  /// `dart:io`'s Platform throws.
  static PlatformInfo get current => kIsWeb ? web : PlatformInfo(
    io.Platform.operatingSystem,
    environment: Map<String, String>.from(io.Platform.environment),
  );

  static const web = PlatformInfo('web');

  @override
  String toString() => 'PlatformInfo($os)';
}
