import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

enum ReleasePlatform {
  github,
  gitea,
  dolphin,
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
      } else if (platform == ReleasePlatform.dolphin) {
        // For Dolphin, we scrape the official download page
        return await _scrapeDolphin(requiredFilters, excludedFilters);
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
      ReleasePlatform platform, String repo, List<String> requiredFilters, 
      List<String> excludedFilters, String? baseUrl) async {
    try {
      if (platform == ReleasePlatform.gitea) {
        // Gitea HTML scrape still works fine
        final base = baseUrl ?? giteaBaseUrl ?? 'https://git.eden-emu.dev';
        return await _htmlScrape('$base/$repo/releases/latest', base, requiredFilters, excludedFilters);
      }

      // GitHub: use Atom feed to get latest tag, then construct asset URLs
      final feedUrl = 'https://github.com/$repo/releases.atom';
      final feedResponse = await http.get(Uri.parse(feedUrl), headers: {'User-Agent': 'Freegosy'});
      if (feedResponse.statusCode != 200) return [];

      // Extract latest release tag from Atom feed
      final tagRegex = RegExp(r'<id>tag:github\.com,2008:Repository/\d+/([^<]+)</id>');
      final tagMatch = tagRegex.firstMatch(feedResponse.body);
      if (tagMatch == null) return [];
      final tag = tagMatch.group(1)!;

      // Now fetch the release page for that specific tag to get asset links
      final releasePage = 'https://github.com/$repo/releases/expanded_assets/$tag';
      final pageResponse = await http.get(Uri.parse(releasePage), headers: {'User-Agent': 'Freegosy'});
      if (pageResponse.statusCode != 200) return [];

      return _parseHtmlAssets(pageResponse.body, 'https://github.com', requiredFilters, excludedFilters);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, String>>> _htmlScrape(String url, String base, 
      List<String> requiredFilters, List<String> excludedFilters) async {
    final response = await http.get(Uri.parse(url), headers: {'User-Agent': 'Freegosy'});
    if (response.statusCode != 200) return [];
    return _parseHtmlAssets(response.body, base, requiredFilters, excludedFilters);
  }

  List<Map<String, String>> _parseHtmlAssets(String html, String base,
      List<String> requiredFilters, List<String> excludedFilters) {
    final regex = RegExp(r'href="([^"]+/releases/download/[^"]+)"');
    final matches = regex.allMatches(html);
    final List<Map<String, String>> matchingAssets = [];

    for (final match in matches) {
      final path = match.group(1)!;
      final fullUrl = path.startsWith('http') ? path : '$base$path';
      final name = fullUrl.split('/').last;

      final matchesRequired = requiredFilters.isEmpty ||
          requiredFilters.every((f) => name.toLowerCase().contains(f.toLowerCase()));
      final matchesExcluded = excludedFilters.any((f) => name.toLowerCase().contains(f.toLowerCase()));

      if (matchesRequired && !matchesExcluded) {
        matchingAssets.add({'name': name, 'url': fullUrl});
      }
    }
    return matchingAssets;
  Future<List<Map<String, String>>> _scrapeDolphin(List<String> requiredFilters, List<String> excludedFilters) async {
    try {
      final response = await http.get(Uri.parse('https://dolphin-emu.org/download/'), headers: {'User-Agent': 'Freegosy'});
      if (response.statusCode != 200) return [];

      final html = response.body;
      // Scrape for dl.dolphin-emu.org links within the "download-releases" section
      // The links look like: https://dl.dolphin-emu.org/releases/2603a/dolphin-2603a-x64.7z
      final regex = RegExp(r'href="(https://dl\.dolphin-emu\.org/releases/[^"]+)"');
      final matches = regex.allMatches(html);
      final List<Map<String, String>> matchingAssets = [];

      for (final match in matches) {
        final fullUrl = match.group(1)!;
        final name = fullUrl.split('/').last;

        final matchesRequired = requiredFilters.isEmpty ||
            requiredFilters.every((f) => name.toLowerCase().contains(f.toLowerCase()));
        final matchesExcluded = excludedFilters.any((f) => name.toLowerCase().contains(f.toLowerCase()));

        if (matchesRequired && !matchesExcluded) {
          // Check if we already added this URL (prevent duplicates from different sections)
          if (!matchingAssets.any((a) => a['url'] == fullUrl)) {
            matchingAssets.add({'name': name, 'url': fullUrl});
          }
        }
      }
      
      // Sort to get the most recent version first (if there are multiple versions on page)
      // Usually the latest is first in the HTML anyway.
      return matchingAssets;
    } catch (e) {
      debugPrint('[Dolphin Scrape] Error: $e');
      return [];
    }
  }
}
