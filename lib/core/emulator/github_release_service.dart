import 'package:dio/dio.dart';

class GithubReleaseService {
  final Dio _dio;

  GithubReleaseService(this._dio);

  /// Fetches the latest release download URL from a GitHub repo
  /// that matches all [required] filters and none of the [excluded] filters.
  Future<String?> getLatestReleaseUrl({
    required String repo,
    required List<String> required,
    List<String> excluded = const [],
  }) async {
    try {
      final response = await _dio.get(
        'https://api.github.com/repos/$repo/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
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