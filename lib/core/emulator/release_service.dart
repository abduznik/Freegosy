import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

enum ReleasePlatform {
  github,
  gitea,
}

class ReleaseService {
  final Dio _dio;
  final String? giteaBaseUrl;

  ReleaseService(this._dio, {this.giteaBaseUrl});

  /// Fetches available release assets from a repo (GitHub or Gitea).
  Future<List<Map<String, String>>> getLatestReleaseAssets({
    required ReleasePlatform platform,
    required String repo,
    List<String> requiredFilters = const [],
    List<String> excludedFilters = const [],
    String? baseUrl,
  }) async {
    try {
      String url;
      Map<String, String> headers;

      if (platform == ReleasePlatform.github) {
        url = 'https://api.github.com/repos/$repo/releases/latest';
        headers = {'Accept': 'application/vnd.github.v3+json'};
      } else {
        final base = baseUrl ?? giteaBaseUrl ?? 'https://git.eden-emu.dev';
        url = '$base/api/v1/repos/$repo/releases/latest';
        headers = {'Accept': 'application/json'};
      }

      try {
        final response = await _dio.get(
          url,
          options: Options(headers: headers),
        );

        if (response.statusCode == 200) {
          return _parseApiAssets(response.data['assets'], requiredFilters, excludedFilters);
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 403 || e.response?.statusCode == 429) {
          return await _scrapeFallback(platform, repo, requiredFilters, excludedFilters, baseUrl);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  List<Map<String, String>> _parseApiAssets(List<dynamic> assets, List<String> requiredFilters, List<String> excludedFilters) {
    List<Map<String, String>> matchingAssets = [];
    for (final asset in assets) {
      final name = (asset['name'] as String);
      final downloadUrl = asset['browser_download_url'] as String;

      final matchesRequired = requiredFilters.isEmpty ||
          requiredFilters.every((f) => name.toLowerCase().contains(f.toLowerCase()));
      final matchesExcluded = excludedFilters.any((f) => name.toLowerCase().contains(f.toLowerCase()));

      if (matchesRequired && !matchesExcluded) {
        matchingAssets.add({'name': name, 'url': downloadUrl});
      }
    }
    return matchingAssets;
  }

  Future<List<Map<String, String>>> _scrapeFallback(
      ReleasePlatform platform, String repo, List<String> requiredFilters, List<String> excludedFilters, String? baseUrl) async {
    try {
      final base = platform == ReleasePlatform.github ? 'https://github.com' : (baseUrl ?? giteaBaseUrl ?? 'https://git.eden-emu.dev');
      final url = '$base/$repo/releases/latest';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return [];

      final html = response.body;
      final regex = RegExp(r'href="([^"]+/releases/download/[^"]+)"');
      final matches = regex.allMatches(html);
      List<Map<String, String>> matchingAssets = [];

      for (final match in matches) {
        final path = match.group(1)!;
        final fullUrl = path.startsWith('http') ? path : '$base$path';
        final name = path.split('/').last;

        final matchesRequired = requiredFilters.isEmpty ||
            requiredFilters.every((f) => name.toLowerCase().contains(f.toLowerCase()));
        final matchesExcluded = excludedFilters.any((f) => name.toLowerCase().contains(f.toLowerCase()));

        if (matchesRequired && !matchesExcluded) {
          matchingAssets.add({'name': name, 'url': fullUrl});
        }
      }
      return matchingAssets;
    } catch (e) {
      return [];
    }
  }
}
