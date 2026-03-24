import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class PcGamingWikiService {
  final Dio _dio;

  PcGamingWikiService(this._dio);

  static const String _apiUrl = 'https://www.pcgamingwiki.com/w/api.php';

  /// Finds the PCGamingWiki page title for [gameTitle].
  Future<String?> findPageTitle(String gameTitle) async {
    try {
      // Try exact match first
      final exactResponse = await _dio.get(_apiUrl, queryParameters: {
        'action': 'query',
        'titles': gameTitle,
        'format': 'json',
      });

      if (exactResponse.statusCode == 200) {
        final pages = exactResponse.data['query']['pages'] as Map;
        for (final pageId in pages.keys) {
          if (pageId != '-1') return pages[pageId]['title'] as String;
        }
      }

      // Fall back to search
      final searchResponse = await _dio.get(_apiUrl, queryParameters: {
        'action': 'query',
        'list': 'search',
        'srsearch': gameTitle,
        'format': 'json',
      });

      if (searchResponse.statusCode == 200) {
        final results = searchResponse.data['query']['search'] as List;
        if (results.isNotEmpty) return results.first['title'] as String;
      }
    } catch (e) {
      debugPrint('[PcGamingWiki] findPageTitle error: $e');
    }
    return null;
  }

  /// Fetches the wikitext for [pageTitle].
  Future<String?> getWikitext(String pageTitle) async {
    try {
      final response = await _dio.get(_apiUrl, queryParameters: {
        'action': 'parse',
        'page': pageTitle,
        'prop': 'wikitext',
        'format': 'json',
      });
      if (response.statusCode == 200) {
        return response.data['parse']['wikitext']['*'] as String?;
      }
    } catch (e) {
      debugPrint('[PcGamingWiki] getWikitext error: $e');
    }
    return null;
  }

  /// Returns expanded save locations for [gameTitle].
  Future<List<Map<String, String>>> getSaveLocations(String gameTitle, {String gameDir = ''}) async {
    try {
      final pageTitle = await findPageTitle(gameTitle);
      if (pageTitle == null) return [];

      final wikitext = await getWikitext(pageTitle);
      if (wikitext == null) return [];

      return _parseSaveLocations(wikitext, gameTitle, gameDir);
    } catch (e) {
      debugPrint('[PcGamingWiki] getSaveLocations error: $e');
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
        debugPrint('[PcGamingWiki] parse error on line: $e');
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
    final appData = Platform.environment['APPDATA'] ?? '';
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    final programData = Platform.environment['PROGRAMDATA'] ?? '';
    final public = Platform.environment['PUBLIC'] ?? '';

    final subs = <String, String>{
      '{{p|appdata}}': appData,
      '{{p|localappdata}}': localAppData,
      '{{p|userprofile}}': userProfile,
      '{{p|programdata}}': programData,
      '{{p|public}}': public,
      '{{p|game}}': gameDir.isNotEmpty ? '$gameDir/$gameTitle' : '',
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

    return expanded.replaceAll('/', '\\');
  }
}