import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freegosy/core/emulator/emulator_registry_data.dart';

void main() {
  test('Audit all emulator download sources', () async {
    final client = HttpClient();

    for (final definition in kEmulatorDefinitions) {
      final String id = definition['id'] as String;
      final String name = definition['name'] as String;
      final String type = definition['type'] as String;

      debugPrint('--- Auditing Emulator: $name ($id) ---');

      // Helper to print colored status
      void logStatus(int? statusCode, String message) {
        String symbol = '●'; // Default
        if (statusCode == 200 || statusCode == 302) {
          symbol = '\x1B[32m$symbol\x1B[0m'; // Green
        } else if (statusCode == 403) {
          symbol = '\x1B[33m$symbol\x1B[0m'; // Yellow
        } else {
          symbol = '\x1B[31m$symbol\x1B[0m'; // Red
        }
        debugPrint('$symbol $message');
      }

      try {
        if (type == 'direct') {
          for (final key in ['windows_url', 'macos_url', 'linux_url']) {
            if (definition.containsKey(key)) {
              final url = definition[key] as String;
              try {
                final request = await client.headUrl(Uri.parse(url));
                final response = await request.close();
                if (response.statusCode == 200 || response.statusCode == 302) {
                  logStatus(response.statusCode, '[$name] $key OK');
                } else {
                  logStatus(response.statusCode, '[$name] Broken direct URL ($key): $url (Status: ${response.statusCode})');
                }
              } catch (e) {
                logStatus(0, '[$name] Failed to reach $key ($url): $e');
              }
            }
          }
        } else if (type == 'gitea') {
          final host = definition['gitea_host'] as String;
          final repo = definition['gitea_repo'] as String;
          try {
            final request = await client.getUrl(Uri.parse('https://$host/api/v1/repos/$repo/releases/latest'));
            request.headers.add('User-Agent', 'Freegosy-Test-Suite');
            final response = await request.close();
            
            if (response.statusCode == 200) {
              logStatus(200, '[$name] Gitea API OK');
            } else {
              logStatus(response.statusCode, '[$name] Failed to fetch Gitea releases (Status: ${response.statusCode})');
              continue;
            }

            final body = await response.transform(utf8.decoder).join();
            final json = jsonDecode(body);
            final List assets = json['assets'] ?? [];

            for (final platform in ['windows', 'macos', 'linux']) {
              final requiredKey = 'gitea_asset_required_$platform';
              final excludedKey = 'gitea_asset_excluded'; 

              final requiredFilters = List<String>.from(definition[requiredKey] ?? definition['gitea_asset_required'] ?? []);
              final excludedFilters = List<String>.from(definition[excludedKey] ?? []);

              bool found = false;
              for (final asset in assets) {
                final String assetName = asset['name'] as String;
                final matchesRequired = requiredFilters.isEmpty ||
                    requiredFilters.every((f) => assetName.toLowerCase().contains(f.toLowerCase()));
                final matchesExcluded = excludedFilters.any((f) => assetName.toLowerCase().contains(f.toLowerCase()));

                if (matchesRequired && !matchesExcluded) {
                  found = true;
                  break;
                }
              }

              if (!found) {
                logStatus(404, '[$name] No matching asset found on Gitea for platform: $platform (Required: $requiredFilters)');
              }
            }
          } catch (e) {
            logStatus(0, '[$name] Unexpected error during Gitea audit: $e');
          }
        } else if (type == 'github') {
          final repo = definition['github_repo'] as String;
          try {
            final request = await client.getUrl(Uri.parse('https://api.github.com/repos/$repo/releases/latest'));
            request.headers.add('User-Agent', 'Freegosy-Test-Suite');
            request.headers.add('Accept', 'application/vnd.github.v3+json');
            final response = await request.close();
            
            if (response.statusCode == 200) {
              logStatus(200, '[$name] GitHub API OK');
            } else {
              logStatus(response.statusCode, '[$name] Failed to fetch GitHub releases (Status: ${response.statusCode})');
              continue;
            }

            final body = await response.transform(utf8.decoder).join();
            final json = jsonDecode(body);
            final List assets = json['assets'] ?? [];

            for (final platform in ['windows', 'macos', 'linux']) {
              final requiredKey = 'github_asset_required_$platform';
              final baseExcluded = List<String>.from(definition['github_asset_excluded'] ?? []);
              final platformExcluded = List<String>.from(definition['github_asset_excluded_$platform'] ?? []);
              final excludedFilters = {...baseExcluded, ...platformExcluded}.toList();

              final requiredFilters = List<String>.from(definition[requiredKey] ?? definition['github_asset_required'] ?? []);

              bool found = false;
              for (final asset in assets) {
                final String assetName = asset['name'] as String;
                final matchesRequired = requiredFilters.isEmpty ||
                    requiredFilters.every((f) => assetName.toLowerCase().contains(f.toLowerCase()));
                final matchesExcluded = excludedFilters.any((f) => assetName.toLowerCase().contains(f.toLowerCase()));

                if (matchesRequired && !matchesExcluded) {
                  found = true;
                  break;
                }
              }

              if (!found) {
                logStatus(404, '[$name] No matching asset found on GitHub for platform: $platform (Required: $requiredFilters)');
              }
            }
          } catch (e) {
            logStatus(0, '[$name] Unexpected error during GitHub audit: $e');
          }
        } else if (type == 'github_multi') {
          final repos = definition['github_repos'] as Map<String, dynamic>;
          for (final platform in ['windows', 'macos', 'linux']) {
            if (!repos.containsKey(platform)) continue;
            final repo = repos[platform] as String;
            try {
              final request = await client.getUrl(Uri.parse('https://api.github.com/repos/$repo/releases/latest'));
              request.headers.add('User-Agent', 'Freegosy-Test-Suite');
              request.headers.add('Accept', 'application/vnd.github.v3+json');
              final response = await request.close();

              if (response.statusCode != 200) {
                logStatus(response.statusCode, '[$name] Failed to fetch GitHub releases for $platform (Status: ${response.statusCode})');
                continue;
              }

              final body = await response.transform(utf8.decoder).join();
              final List assets = jsonDecode(body)['assets'] ?? [];

              final requiredKey = 'github_asset_required_$platform';
              final baseExcluded = List<String>.from(definition['github_asset_excluded'] ?? []);
              final platformExcluded = List<String>.from(definition['github_asset_excluded_$platform'] ?? []);
              final excludedFilters = {...baseExcluded, ...platformExcluded}.toList();
              final requiredFilters = List<String>.from(definition[requiredKey] ?? []);

              bool found = false;
              for (final asset in assets) {
                final String assetName = asset['name'] as String;
                final matchesRequired = requiredFilters.isEmpty ||
                    requiredFilters.every((f) => assetName.toLowerCase().contains(f.toLowerCase()));
                final matchesExcluded = excludedFilters.any((f) => assetName.toLowerCase().contains(f.toLowerCase()));

                if (matchesRequired && !matchesExcluded) {
                  found = true;
                  break;
                }
              }

              if (!found) {
                logStatus(404, '[$name] No matching asset found on GitHub for platform: $platform (Required: $requiredFilters)');
              } else {
                logStatus(200, '[$name] GitHub API OK for $platform');
              }
            } catch (e) {
              logStatus(0, '[$name] Unexpected error during GitHub multi-audit for $platform: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ WARNING: [$name] Unexpected error during audit: $e');
      }
    }
    client.close();
  });
}
