/// Freegosy CLI — read-only interface to a RomM server.
/// Usage: dart run tool/cli.dart <command> [options]
///
/// Commands:
///   status                          Check server connectivity
///   platforms                       List all platforms
///   games [--platform <slug>]       List games (optionally filtered)
///   saves <game-id>                 List saves for a game
///   firmware [--platform <slug>]    List firmware files
///   search <query>                  Search games by name
///
/// Environment variables:
///   ROMM_URL     Server URL (e.g. https://romm.example.com)
///   ROMM_API_KEY API key for authentication

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ── Config ─────────────────────────────────────────────────────────────

String get _baseUrl {
  final url = Platform.environment['ROMM_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('Error: ROMM_URL environment variable not set.');
    stderr.writeln('  export ROMM_URL=https://your-romm-server.com');
    exit(1);
  }
  return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

String get _apiKey {
  final key = Platform.environment['ROMM_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('Error: ROMM_API_KEY environment variable not set.');
    stderr.writeln('  export ROMM_API_KEY=your_api_key_here');
    exit(1);
  }
  return key;
}

Map<String, String> get _headers => {
  'Authorization': 'Bearer $_apiKey',
  'X-Api-Key': _apiKey,
  'Accept': 'application/json',
  'User-Agent': 'Freegosy-CLI/0.5.10',
};

// ── API helpers ────────────────────────────────────────────────────────

Future<Map<String, dynamic>> _get(String path) async {
  final resp = await http.get(Uri.parse('$_baseUrl$path'), headers: _headers)
      .timeout(const Duration(seconds: 10));
  if (resp.statusCode >= 400) {
    stderr.writeln('HTTP ${resp.statusCode}: ${resp.body}');
    exit(1);
  }
  final decoded = jsonDecode(resp.body);
  if (decoded is Map<String, dynamic>) return decoded;
  // If the API returns a list directly (e.g. /api/platforms), wrap it
  return {'_list': decoded};
}

Future<List<dynamic>> _getList(String path) async {
  final data = await _get(path);
  if (data.containsKey('_list')) return data['_list'] as List;
  return (data['items'] ?? data['roms'] ?? data['platforms'] ?? data['firmware'] ?? []) as List;
}

// ── Commands ───────────────────────────────────────────────────────────

Future<void> _cmdStatus() async {
  try {
    final hb = await _get('/api/heartbeat');
    final version = hb['SYSTEM']?['VERSION'] ?? 'unknown';
    print('Server:   $_baseUrl');
    print('Version:  $version');
    print('Status:   OK');
  } catch (e) {
    stderr.writeln('Connection failed: $e');
    exit(1);
  }
}

Future<void> _cmdPlatforms() async {
  final platforms = await _getList('/api/platforms');
  print('Platforms (${platforms.length}):\n');
  for (final p in platforms) {
    final name = p['display_name'] ?? p['name'] ?? '?';
    final slug = p['slug'] ?? '?';
    final count = p['rom_count'] ?? p['roms_count'] ?? p['games_count'] ?? 0;
    final fw = p['firmware_count'] ?? 0;
    final fwTag = fw > 0 ? ' [$fw firmware]' : '';
    print('  ${slug.padRight(20)}${name.padRight(35)}$count games$fwTag');
  }
}

Future<void> _cmdGames(List<String> args) async {
  String? platformSlug;
  int limit = 25;
  String? search;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--platform' && i + 1 < args.length) {
      platformSlug = args[++i];
    } else if (args[i] == '--limit' && i + 1 < args.length) {
      limit = int.tryParse(args[++i]) ?? 25;
    } else if (args[i] == '--search' && i + 1 < args.length) {
      search = args[++i];
    }
  }

  String path = '/api/roms?limit=$limit&order_by=name';
  if (platformSlug != null) {
    // Get platform ID first
    final platforms = await _getList('/api/platforms');
    final match = platforms.firstWhere(
      (p) => p['slug'] == platformSlug,
      orElse: () => null,
    );
    if (match == null) {
      stderr.writeln('Platform "$platformSlug" not found.');
      stderr.writeln('Run "platforms" to see available platforms.');
      exit(1);
    }
    path += '&platform_ids=${match['id']}';
  }
  if (search != null) {
    path += '&search_term=${Uri.encodeComponent(search)}';
  }

  final games = await _getList(path);
  if (games.isEmpty) {
    print('No games found.');
    return;
  }

  print('Games (${games.length}):\n');
  for (final g in games) {
    final name = g['name'] ?? '?';
    final slug = g['platform_slug'] ?? '?';
    final id = g['id'] ?? '?';
    final multi = g['has_multiple_files'] == true ? ' [multi]' : '';
    final size = g['file_size_bytes'] ?? 0;
    final sizeStr = size > 0 ? ' (${(size / 1024 / 1024).toStringAsFixed(1)}MB)' : '';
    print('  [${"$id".toString().padLeft(5)}] ${slug.padRight(6)} $name$sizeStr$multi');
  }
}

Future<void> _cmdSaves(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: saves <game-id>');
    exit(1);
  }
  final gameId = args[0];

  final saves = await _getList('/api/saves?rom_id=$gameId');
  if (saves.isEmpty) {
    print('No saves found for game $gameId.');
    return;
  }

  print('Saves for game $gameId (${saves.length}):\n');
  for (final s in saves) {
    final id = s['id'] ?? '?';
    final emulator = s['emulator'] ?? '?';
    final slot = s['slot'] ?? '?';
    final size = s['file_size_bytes'] ?? 0;
    final updated = s['updated_at'] ?? '?';
    final hash = s['content_hash'] ?? '';
    final hashStr = hash.isNotEmpty ? ' hash=${hash.substring(0, hash.length.clamp(0, 8))}' : '';
    print('  [$id] emulator=$emulator slot=$slot size=$size updated=$updated$hashStr');
  }
}

Future<void> _cmdFirmware(List<String> args) async {
  String? platformSlug;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--platform' && i + 1 < args.length) {
      platformSlug = args[++i];
    }
  }

  String path = '/api/firmware';
  if (platformSlug != null) {
    final platforms = await _getList('/api/platforms');
    final match = platforms.firstWhere(
      (p) => p['slug'] == platformSlug,
      orElse: () => null,
    );
    if (match != null) {
      path += '?platform_id=${match['id']}';
    }
  }

  final firmware = await _getList(path);
  if (firmware.isEmpty) {
    print('No firmware found.');
    return;
  }

  print('Firmware (${firmware.length}):\n');
  for (final fw in firmware) {
    final id = fw['id'] ?? '?';
    final name = fw['file_name'] ?? '?';
    final filePath = fw['file_path'] ?? '?';
    final ext = fw['file_extension'] ?? '?';
    final size = fw['file_size_bytes'] ?? 0;
    final verified = fw['is_verified'] == true ? ' [verified]' : '';
    print('  [$id] $name ext=$ext path="$filePath" size=${(size / 1024).toStringAsFixed(1)}KB$verified');
  }
}

Future<void> _cmdSearch(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: search <query>');
    exit(1);
  }
  final query = args.join(' ');

  final games = await _getList('/api/roms?limit=20&order_by=name&search_term=${Uri.encodeComponent(query)}');
  if (games.isEmpty) {
    print('No results for "$query".');
    return;
  }

  print('Search results for "$query" (${games.length}):\n');
  for (final g in games) {
    final name = g['name'] ?? '?';
    final slug = g['platform_slug'] ?? '?';
    final id = g['id'] ?? '?';
    print('  [${"$id".toString().padLeft(5)}] ${slug.padRight(6)} $name');
  }
}

// ── Main ───────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Freegosy CLI — read-only RomM interface\n');
    print('Usage: dart run tool/cli.dart <command> [options]\n');
    print('Commands:');
    print('  status                          Check server connectivity');
    print('  platforms                       List all platforms');
    print('  games [--platform <slug>]       List games');
    print('  saves <game-id>                 List saves for a game');
    print('  firmware [--platform <slug>]    List firmware files');
    print('  search <query>                  Search games by name');
    print('\nEnvironment:');
    print('  ROMM_URL      Server URL');
    print('  ROMM_API_KEY  API key');
    return;
  }

  final cmd = args[0];
  final cmdArgs = args.sublist(1);

  switch (cmd) {
    case 'status':
      await _cmdStatus();
    case 'platforms':
      await _cmdPlatforms();
    case 'games':
      await _cmdGames(cmdArgs);
    case 'saves':
      await _cmdSaves(cmdArgs);
    case 'firmware':
      await _cmdFirmware(cmdArgs);
    case 'search':
      await _cmdSearch(cmdArgs);
    default:
      stderr.writeln('Unknown command: $cmd');
      stderr.writeln('Run without arguments to see usage.');
      exit(1);
  }
}
