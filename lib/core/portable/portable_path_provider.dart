import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// `path_provider` for a portable copy: the app's own folders live in
/// `userdata\`; anything else (Downloads, …) still comes from [previous].
class PortablePathProvider extends PathProviderPlatform {
  PortablePathProvider({required this.dataDir, required this.previous});

  final String dataDir;
  final PathProviderPlatform previous;

  @override
  Future<String?> getApplicationSupportPath() async => p.join(dataDir, 'support');

  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(dataDir, 'documents');

  @override
  Future<String?> getTemporaryPath() async => p.join(dataDir, 'temp');

  @override
  Future<String?> getApplicationCachePath() async => p.join(dataDir, 'support', 'cache');

  @override
  Future<String?> getLibraryPath() => previous.getLibraryPath();

  @override
  Future<String?> getDownloadsPath() => previous.getDownloadsPath();

  @override
  Future<String?> getExternalStoragePath() => previous.getExternalStoragePath();

  @override
  Future<List<String>?> getExternalCachePaths() => previous.getExternalCachePaths();

  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) =>
      previous.getExternalStoragePaths(type: type);
}
