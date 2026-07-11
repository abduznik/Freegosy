import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../platform/platform_info.dart';

class PcGamingWikiService {
  final Dio _dio;
  final PlatformInfo _platform;

  PcGamingWikiService(this._dio, {PlatformInfo? platform})
      : _platform = platform ?? PlatformInfo.current;

  static const String _apiUrl = 'https://www.pcgamingwiki.com/w/api.php';

  /// Finds the PCGamingWiki page title for [gameTitle].
  Future<String?> findPageTitle(String gameTitle) async {
    try {
      debugPrint('[PcGamingWiki] Searching for page: $gameTitle');
      // Try exact match first
      final exactResponse = await _dio.get(_apiUrl, queryParameters: {
        'action': 'query',
        'titles': gameTitle,
        'format': 'json',
      });

      if (exactResponse.statusCode == 200) {
        final pages = exactResponse.data['query']['pages'] as Map;
        for (final pageId in pages.keys) {
          if (pageId != '-1') {
            final title = pages[pageId]['title'] as String;
            debugPrint('[PcGamingWiki] Found exact match: $title');
            return title;
          }
        }
      }

      // Fall back to search
      debugPrint('[PcGamingWiki] No exact match, trying search...');
      final searchResponse = await _dio.get(_apiUrl, queryParameters: {
        'action': 'query',
        'list': 'search',
        'srsearch': gameTitle,
        'format': 'json',
      });

      if (searchResponse.statusCode == 200) {
        final results = searchResponse.data['query']['search'] as List;
        if (results.isNotEmpty) {
          final title = results.first['title'] as String;
          debugPrint('[PcGamingWiki] Search found: $title');
          return title;
        }
      }
    } catch (e) {
      debugPrint('[PcGamingWiki] Page lookup failed: $e');
    }
    debugPrint('[PcGamingWiki] No page found for: $gameTitle');
    return null;
  }

  /// Fetches the wikitext for [pageTitle].
  Future<String?> getWikitext(String pageTitle) async {
    try {
      debugPrint('[PcGamingWiki] Fetching wikitext for: $pageTitle');
      final response = await _dio.get(_apiUrl, queryParameters: {
        'action': 'parse',
        'page': pageTitle,
        'prop': 'wikitext',
        'format': 'json',
      });
      if (response.statusCode == 200) {
        final wikitext = response.data['parse']['wikitext']['*'] as String?;
        debugPrint('[PcGamingWiki] Got wikitext (${wikitext?.length ?? 0} chars)');
        return wikitext;
      }
    } catch (e) {
      debugPrint('[PcGamingWiki] Wikitext fetch failed: $e');
    }
    return null;
  }

  /// Returns expanded save locations for [gameTitle].
  Future<List<Map<String, String>>> getSaveLocations(String gameTitle, {String gameDir = ''}) async {
    try {
      debugPrint('[PcGamingWiki] Getting save locations for: $gameTitle (gameDir: $gameDir)');
      final pageTitle = await findPageTitle(gameTitle);
      if (pageTitle == null) {
        debugPrint('[PcGamingWiki] No wiki page found, cannot resolve save locations');
        return [];
      }

      final wikitext = await getWikitext(pageTitle);
      if (wikitext == null) {
        debugPrint('[PcGamingWiki] No wikitext available for $pageTitle');
        return [];
      }

      final locations = _parseSaveLocations(wikitext, gameTitle, gameDir);
      debugPrint('[PcGamingWiki] Parsed ${locations.length} save location(s) for $gameTitle');
      return locations;
    } catch (e) {
      debugPrint('[PcGamingWiki] getSaveLocations failed: $e');
      return [];
    }
  }

  List<Map<String, String>> _parseSaveLocations(String wikitext, String gameTitle, String gameDir) {
    final results = <Map<String, String>>[];
    final seen = <String>{};

    for (final line in wikitext.split('\n')) {
      if (!line.contains('Game data/saves')) continue;
      if (!line.contains('|Windows|')) continue;

      try {
        final after = line.split('|Windows|').last;
        final cleaned = after.endsWith('}}') ? after.substring(0, after.length - 2) : after;
        final paths = _safeSplitPaths(cleaned.trim());

        for (final raw in paths) {
          final trimmed = raw.trim();
          if (trimmed.isEmpty) continue;

          final lower = trimmed.toLowerCase();
          if (_shouldSkipPath(lower)) continue;

          final expanded = _expandWikiPath(trimmed, gameTitle, gameDir);
          if (expanded == null) continue;

          final normalizedLower = expanded.toLowerCase();
          if (seen.contains(normalizedLower)) continue;
          seen.add(normalizedLower);

          results.add({
            'raw': trimmed,
            'path': expanded,
          });
        }
      } catch (e) {
        //
      }
    }
    return results;
  }

  bool _shouldSkipPath(String lower) {
    return lower.contains('steam') ||
        lower.contains('linux') ||
        lower.contains('wine') ||
        lower.contains('{{p|uid}}') ||
        lower.contains('{{p|hkcu}}') ||
        lower.contains('{{p|osxhome}}') ||
        lower.contains('{{p|xdg') ||
        lower.contains('{{p|linux');
  }

  List<String> _safeSplitPaths(String s) {
    final parts = <String>[];
    int depth = 0;
    final current = StringBuffer();
    int i = 0;
    while (i < s.length) {
      if (i + 1 < s.length && s[i] == '{' && s[i + 1] == '{') {
        depth++;
        current.write('{{');
        i += 2;
        continue;
      }
      if (i + 1 < s.length && s[i] == '}' && s[i + 1] == '}') {
        depth--;
        current.write('}}');
        i += 2;
        continue;
      }
      if (s[i] == '|' && depth == 0) {
        parts.add(current.toString().trim());
        current.clear();
        i++;
        continue;
      }
      current.write(s[i]);
      i++;
    }
    if (current.isNotEmpty) parts.add(current.toString().trim());
    return parts.where((p) => p.isNotEmpty).toList();
  }

  String? _expandWikiPath(String path, String gameTitle, String gameDir) {
    final appData = _platform.environment['APPDATA'] ?? '';
    final localAppData = _platform.environment['LOCALAPPDATA'] ?? '';
    final userProfile = _platform.environment['USERPROFILE'] ?? '';
    final programData = _platform.environment['PROGRAMDATA'] ?? '';
    final public = _platform.environment['PUBLIC'] ?? '';

    final subs = <String, String>{
      '{{p|appdata}}': appData,
      '{{p|localappdata}}': localAppData,
      '{{p|userprofile}}': userProfile,
      '{{p|programdata}}': programData,
      '{{p|public}}': public,
      // Use gameDir directly — it's already the game's install folder.
      // Don't append gameTitle as it may contain invalid chars (e.g., colons).
      '{{p|game}}': gameDir,
    };

    String expanded = path;
    for (final entry in subs.entries) {
      if (entry.value.isEmpty && expanded.toLowerCase().contains(entry.key)) {
        return null;
      }
      expanded = expanded.replaceAll(
        RegExp(RegExp.escape(entry.key), caseSensitive: false),
        entry.value,
      );
    }

    // If any unresolved templates remain, skip
    if (expanded.toLowerCase().contains('{{p|')) return null;

    // Strip wildcard filenames e.g. \*.dat
    expanded = expanded.replaceAll(RegExp(r'[/\\]\*\.[a-zA-Z0-9]+$'), '');

    // Strip bare filenames with extension at end
    if (RegExp(r'\.[a-zA-Z0-9]{2,4}$').hasMatch(expanded)) {
      expanded = File(expanded).parent.path;
    }

    // Strip invalid Windows characters from path segments (colons, etc.)
    expanded = _sanitizeWindowsPath(expanded);

    // Normalize trailing slashes
    expanded = expanded.replaceAll(RegExp(r'[/\\]+$'), '');

    return expanded.replaceAll('/', '\\');
  }

  /// Strips characters that are invalid in Windows file paths.
  /// Keeps drive letter colons (e.g., C:\) but removes others.
  static String _sanitizeWindowsPath(String path) {
    // Split into segments, sanitize each one
    final parts = path.split(RegExp(r'[/\\]'));
    final sanitized = <String>[];
    for (int i = 0; i < parts.length; i++) {
      String part = parts[i];
      // Keep drive letter colons (e.g., "C:")
      if (i == 0 && RegExp(r'^[A-Za-z]:$').hasMatch(part)) {
        sanitized.add(part);
        continue;
      }
      // Strip invalid Windows filename characters
      part = part.replaceAll(RegExp(r'[<>:"|?*]'), '_');
      sanitized.add(part);
    }
    return sanitized.join('\\');
  }
}