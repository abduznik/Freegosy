import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'app_path_resolver.dart';

/// [AppPathResolver] backed by `path_provider`/`rootBundle` — used by the
/// Flutter app. Requires a running Flutter engine.
class FlutterAppPathResolver implements AppPathResolver {
  const FlutterAppPathResolver();

  @override
  Future<String> getApplicationSupportPath() async => (await getApplicationSupportDirectory()).path;

  @override
  Future<String> getTemporaryPath() async => (await getTemporaryDirectory()).path;

  @override
  Future<Uint8List?> loadAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
