import 'package:dio/dio.dart';

class GiteaReleaseService {
  final Dio _dio;
  final String baseUrl;

  GiteaReleaseService(this._dio, {this.baseUrl = 'https://git.eden-emu.dev'});

  /// Fetches the latest release download URL from a Gitea repo
  /// that matches all [required] filters and none of the [excluded] filters.
  Future<String?> getLatestReleaseUrl({
    required String repo,
    required List<String> required,
    List<String> excluded = const [],
  }) async {
    try {
      // Gitea API: /api/v1/repos/{owner}/{repo}/releases/latest
      final response = await _dio.get(
        '$baseUrl/api/v1/repos/$repo/releases/latest',
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode != 200) return null;

      final assets = response.data['assets'] as List<dynamic>;

      for (final asset in assets) {
        final name = (asset['name'] as String).toLowerCase();
        final url = asset['browser_download_url'] as String;

        // Must match all required filters
        final matchesRequired = required.every((f) => name.contains(f.toLowerCase()));
        if (!matchesRequired) continue;

        // Must not match any excluded filters
        final matchesExcluded = excluded.any((f) => name.contains(f.toLowerCase()));
        if (matchesExcluded) continue;

        return url;
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
