import 'package:dio/dio.dart';

enum ReleasePlatform {
  github,
  gitea,
}

class ReleaseService {
  final Dio _dio;
  final String? giteaBaseUrl;

  ReleaseService(this._dio, {this.giteaBaseUrl});

  /// Fetches the latest release download URL from a repo (GitHub or Gitea).
  Future<String?> getLatestReleaseUrl({
    required ReleasePlatform platform,
    required String repo,
    required List<String> requiredFilters,
    List<String> excludedFilters = const [],
  }) async {
    try {
      String url;
      Map<String, String> headers;

      if (platform == ReleasePlatform.github) {
        url = 'https://api.github.com/repos/$repo/releases/latest';
        headers = {'Accept': 'application/vnd.github.v3+json'};
      } else {
        final base = giteaBaseUrl ?? 'https://git.eden-emu.dev';
        url = '$base/api/v1/repos/$repo/releases/latest';
        headers = {'Accept': 'application/json'};
      }

      final response = await _dio.get(
        url,
        options: Options(headers: headers),
      );

      if (response.statusCode != 200) return null;

      final assets = response.data['assets'] as List<dynamic>;

      for (final asset in assets) {
        final name = (asset['name'] as String).toLowerCase();
        final downloadUrl = asset['browser_download_url'] as String;

        // Must match all required filters
        final matchesRequired = requiredFilters.every((f) => name.contains(f.toLowerCase()));
        if (!matchesRequired) continue;

        // Must not match any excluded filters
        final matchesExcluded = excludedFilters.any((f) => name.contains(f.toLowerCase()));
        if (matchesExcluded) continue;

        return downloadUrl;
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
