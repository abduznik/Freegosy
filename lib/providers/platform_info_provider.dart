import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/platform/platform_info.dart';

/// Provider that exposes the current [PlatformInfo].
/// Defaults to [PlatformInfo.current] (reads from dart:io).
/// Can be overridden in tests with a simulated platform.
final platformInfoProvider = Provider<PlatformInfo>((ref) {
  return PlatformInfo.current;
});
