import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/portable/portable_path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Original extends PathProviderPlatform {
  @override
  Future<String?> getDownloadsPath() async => '/real/Downloads';
  @override
  Future<String?> getLibraryPath() async => '/real/Library';
  @override
  Future<String?> getApplicationSupportPath() async => '/real/support';
}

void main() {
  final provider = PortablePathProvider(dataDir: p.join('E:', 'Freegosy', 'userdata'), previous: _Original());
  final data = p.join('E:', 'Freegosy', 'userdata');

  test('app folders point into data', () async {
    expect(await provider.getApplicationSupportPath(), p.join(data, 'support'));
    expect(await provider.getApplicationDocumentsPath(), p.join(data, 'documents'));
    expect(await provider.getTemporaryPath(), p.join(data, 'temp'));
    expect(await provider.getApplicationCachePath(), p.join(data, 'support', 'cache'));
  });

  test('other folders come from the original provider', () async {
    expect(await provider.getDownloadsPath(), '/real/Downloads');
    expect(await provider.getLibraryPath(), '/real/Library');
  });

  test('it can be installed as the platform instance', () {
    final before = PathProviderPlatform.instance;
    addTearDown(() => PathProviderPlatform.instance = before);
    PathProviderPlatform.instance = provider;
    expect(PathProviderPlatform.instance, same(provider));
  });
}
