import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'romm_models.dart';

class RommService {
  final RomMConfig config;
  final Dio _dio;

  static String _normalizeBaseUrl(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  RommService(this.config)
      : _dio = Dio(BaseOptions(
          baseUrl: _normalizeBaseUrl(config.baseUrl),
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 2),
        )) {
    // If the server rejects the Bearer token with 403, retry once with Basic auth.
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (DioException e, ErrorInterceptorHandler handler) async {
        // Check for 401 with API Key
        if (e.response?.statusCode == 401 && config.apiKey.isNotEmpty) {
          throw Exception('Invalid API key. Please check your token in RomM Settings → Client API Tokens.');
        }

        // If the server rejects the Bearer token with 403, retry once with Basic auth.
        if (e.response?.statusCode == 403 &&
          e.requestOptions.extra['_basicRetry'] != true &&
          e.requestOptions.data is! FormData &&
          config.token != null &&
          config.token!.isNotEmpty) {
          final basic = 'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
          final opts = e.requestOptions
            ..headers['Authorization'] = basic
            ..extra['_basicRetry'] = true;
          try {
            final response = await _dio.fetch(opts);
            handler.resolve(response);
            return;
          } catch (_) {}
        }
        handler.next(e);
      },
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        handler.next(options);
      },
    ));
  }

  /// Returns the appropriate auth Options for each request.
  /// Uses Bearer token if available, falls back to Basic auth.
  Options get _authOptions {
    // Check for API Key first
    if (config.apiKey.isNotEmpty) {
      return Options(headers: {'Authorization': 'Bearer ${config.apiKey}'});
    }
    // Fallback to existing token logic
    final token = config.token;
    if (token != null && token.isNotEmpty) {
      return Options(headers: {'Authorization': 'Bearer $token'});
    }
    // Fallback to Basic auth
    final basic = 'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
    return Options(headers: {'Authorization': basic});
  }

  /// Calls /api/token with username/password (OAuth2 password flow),
  /// stores the Bearer token in SharedPreferences, and returns it.
  static Future<String> fetchToken(String baseUrl, String username, String password) async {
    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    final dio = Dio(BaseOptions(
      baseUrl: normalizedUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 2),
    ));
    final response = await dio.post(
      '/api/token',
      data: {
        'username': username,
        'password': password,
        'grant_type': 'password',
        'scope': 'me.read me.write platforms.read roms.read assets.read assets.write roms.user.read roms.user.write',
      },
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    final token = response.data['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Login failed: no access_token in response');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rommAuthToken', token);
    return token;
  }

  Future<List<Platform>> getPlatforms() async {
    final response = await _dio.get('/api/platforms', options: _authOptions);
    if (response.statusCode == 200) {
      final List<dynamic> items;
      if (response.data is Map && response.data.containsKey('items')) {
        items = response.data['items'] as List<dynamic>;
      } else {
        items = response.data as List<dynamic>;
      }
      return items.map((item) => Platform.fromJson(item)).toList();
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
    );
  }

  String? resolveCoverUrl(Game game) {
    final host = _normalizeBaseUrl(config.baseUrl);
    String? path = game.pathCoverLarge ?? game.pathCoverSmall;
    if (path != null && path.isNotEmpty) {
      return path.startsWith('http') ? path : "$host$path";
    }
    String? url = game.urlCover;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('//')) return "https:$url";
      return url;
    }
    return null;
  }

  Future<List<Game>> getGames(String platformId) async {
    return _fetchPaginatedGames({'platform_id': int.parse(platformId)});
  }

  Future<List<Game>> getAllGames({String? platformId}) async {
    final params = <String, dynamic>{};
    if (platformId != null) {
      params['platform_id'] = int.parse(platformId);
    }
    return _fetchPaginatedGames(params);
  }

  Future<({List<Game> games, int total})> getGamesPage({
    int offset = 0,
    int limit = 50,
    String? platformId,
    String? search,
  }) async {
    final params = <String, dynamic>{
      'limit': limit,
      'offset': offset,
    };
    params['order_by'] = 'name';
    params['order_dir'] = 'asc';
    if (platformId != null) params['platform_ids'] = [int.parse(platformId)];
    if (search != null && search.isNotEmpty) params['search_term'] = search;

    final response = await _dio.get('/api/roms', queryParameters: params, options: _authOptions);
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = response.data is Map ? response.data : {'items': response.data};
      final List<dynamic> items = data['items'] ?? [];
      final int total = data['total'] ?? items.length;
      return (games: items.map((e) => Game.fromJson(e)).toList(), total: total);
    }
    throw DioException(requestOptions: response.requestOptions, response: response, type: DioExceptionType.badResponse);
  }

  Future<List<Game>> _fetchPaginatedGames(Map<String, dynamic> params) async {
    int offset = 0;
    const int limit = 100;
    List<Game> allGames = [];
    int total = 0;

    do {
      final response = await _dio.get(
        '/api/roms',
        queryParameters: {
          ...params,
          'limit': limit,
          'offset': offset,
        },
        options: _authOptions,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = response.data is Map ? response.data : {'items': response.data};
        final List<dynamic> items = data['items'] ?? [];
        total = data['total'] ?? items.length;
        allGames.addAll(items.map((item) => Game.fromJson(item)).toList());
        offset += limit;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
        );
      }
    } while (allGames.length < total && offset < total);

    return allGames;
  }

  Future<List<SaveFile>> getSaves(String gameId) async {
    final response = await _dio.get(
      '/api/saves',
      queryParameters: {'game_id': gameId},
      options: _authOptions,
    );
    if (response.statusCode == 200) {
      final List<dynamic> items;
      if (response.data is Map && response.data.containsKey('items')) {
        items = response.data['items'] as List<dynamic>;
      } else {
        items = response.data as List<dynamic>;
      }
      return items.map((item) => SaveFile.fromJson(item)).toList();
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
    );
  }

  String getDownloadUrl(Game game) {
    final baseUrl = config.baseUrl.endsWith('/') 
        ? config.baseUrl.substring(0, config.baseUrl.length - 1) 
        : config.baseUrl;
    
    final name = game.fileName ?? game.fsName ?? game.name;
    final encoded = Uri.encodeComponent(name);
    return '$baseUrl/api/roms/${game.id}/content/$encoded';
  }

  /// Returns the Authorization header value for downloads (Bearer if available, else Basic).
  String get authHeader {
    if (config.apiKey.isNotEmpty) return 'Bearer ${config.apiKey}';
    final token = config.token;
    if (token != null && token.isNotEmpty) return 'Bearer $token';
    return 'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
  }

  // ─── Save sync ─────────────────────────────────────────────────────────────

  /// Uploads [saveFile] for [gameId] to RomM via POST /api/saves.
  Future<bool> uploadSave(String gameId, File saveFile, {String? slot}) async {
    try {
      final now = DateTime.now();
      final ts = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final effectiveSlot = slot ?? 'freegosy-srm_$ts';
      final fileName = saveFile.uri.pathSegments.last;
      final formData = FormData.fromMap({
        'saveFile': await MultipartFile.fromFile(saveFile.path, filename: fileName),
      });
      final response = await _dio.post(
        '/api/saves',
        queryParameters: {'rom_id': gameId, 'emulator': 'freegosy', 'slot': effectiveSlot},
        data: formData,
        options: _authOptions,
      );
      final ok = response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
      if (ok) {
        debugPrint('[RomM] Uploaded save: slot=$effectiveSlot');
      }
      return ok;
    } catch (e) {
      debugPrint('[RomM] Upload error: $e');
      return false;
    }
  }

  Future<void> pruneOldSaves(String gameId, {int keepCount = 5}) async {
    try {
      final saves = await getSavesList(gameId);
      final freegosySaves = saves.where((s) =>
        (s['emulator']?.toString() ?? '') == 'freegosy'
      ).toList();
      if (freegosySaves.length <= keepCount) return;
      final toDelete = freegosySaves.sublist(keepCount);
      for (final save in toDelete) {
        final saveId = save['id'];
        if (saveId == null) continue;
        try {
          await _dio.delete('/api/saves/$saveId', options: _authOptions);
          debugPrint('[RomM] Pruned old save: id=$saveId');
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[RomM] Prune error: $e');
    }
  }

  /// Returns all save objects for [gameId], sorted newest first.
  Future<List<Map<String, dynamic>>> getSavesList(String gameId) async {
    try {
      final opts = _authOptions;
      debugPrint("=== ROMM API REQUEST (getSavesList) ===");
      debugPrint("URL: ${config.baseUrl}/api/saves?rom_id=$gameId");
      
      final response = await _dio.get(
        '/api/saves',
        queryParameters: {'rom_id': gameId},
        options: opts,
      );

      debugPrint("=== ROMM API RESPONSE ===");
      debugPrint("Status Code: ${response.statusCode}");

      if (response.statusCode != 200) return [];

      final List<dynamic> items;
      if (response.data is Map && response.data.containsKey('items')) {
        items = response.data['items'] as List<dynamic>;
      } else if (response.data is List) {
        items = response.data as List<dynamic>;
      } else {
        debugPrint("WARNING: Unexpected API response structure for getSavesList.");
        return [];
      }

      final sorted = List<Map<String, dynamic>>.from(
        items.whereType<Map<String, dynamic>>(),
      );
      
      // Sort by created_at descending (newest first)
      sorted.sort((a, b) {
        final ta = DateTime.tryParse(a['created_at']?.toString() ?? a['updated_at']?.toString() ?? '') ?? DateTime(0);
        final tb = DateTime.tryParse(b['created_at']?.toString() ?? b['updated_at']?.toString() ?? '') ?? DateTime(0);
        return tb.compareTo(ta);
      });

      if (sorted.isEmpty) {
        debugPrint("WARNING: Parsed saves list is empty.");
      }

      return sorted;
    } catch (e) {
      debugPrint("ERROR in getSavesList: $e");
      return [];
    }
  }

  /// Returns the most recently updated save object for [gameId], or null.
  Future<Map<String, dynamic>?> getLatestSave(String gameId) async {
    try {
      final opts = _authOptions;
      debugPrint("=== ROMM API REQUEST (getLatestSave) ===");
      debugPrint("URL: ${config.baseUrl}/api/saves?rom_id=$gameId");
      final headers = Map<String, dynamic>.from(opts.headers ?? {});
      if (headers.containsKey('Authorization')) {
        headers['Authorization'] = 'Bearer ***';
      }
      debugPrint("Headers: $headers");

      final response = await _dio.get(
        '/api/saves',
        queryParameters: {'rom_id': gameId},
        options: opts,
      );

      debugPrint("=== ROMM API RESPONSE ===");
      debugPrint("Status Code: ${response.statusCode}");
      debugPrint("Body: ${response.data}");

      if (response.statusCode != 200) return null;

      final List<dynamic> items;
      if (response.data is Map && response.data.containsKey('items')) {
        items = response.data['items'] as List<dynamic>;
      } else if (response.data is List) {
        items = response.data as List<dynamic>;
      } else {
        debugPrint("WARNING: Unexpected API response structure for getLatestSave.");
        return null;
      }

      if (items.isEmpty) {
        debugPrint("WARNING: Parsed saves list is empty. Check if the API response structure matches the parsing logic.");
        return null;
      }

      // Sort by updated_at descending, return the most recent
      final sorted = List<Map<String, dynamic>>.from(
        items.whereType<Map<String, dynamic>>(),
      );
      sorted.sort((a, b) {
        final ta = DateTime.tryParse(a['updated_at']?.toString() ?? '') ?? DateTime(0);
        final tb = DateTime.tryParse(b['updated_at']?.toString() ?? '') ?? DateTime(0);
        return tb.compareTo(ta);
      });
      return sorted.first;
    } catch (e) {
      debugPrint("ERROR in getLatestSave: $e");
      return null;
    }
  }

  /// Downloads save bytes from [saveUrl]. Returns null on failure.
  Future<Uint8List?> downloadSave(String saveUrl) async {
    try {
      // Resolve relative paths against the base URL
      final url = saveUrl.startsWith('http')
          ? saveUrl
          : '${_normalizeBaseUrl(config.baseUrl)}$saveUrl';

      final opts = _authOptions.copyWith(responseType: ResponseType.bytes);
      debugPrint("=== ROMM API REQUEST (downloadSave) ===");
      debugPrint("URL: $url");
      final headers = Map<String, dynamic>.from(opts.headers ?? {});
      if (headers.containsKey('Authorization')) {
        headers['Authorization'] = 'Bearer ***';
      }
      debugPrint("Headers: $headers");

      final response = await _dio.get<List<int>>(
        url,
        options: opts,
      );

      debugPrint("=== ROMM API RESPONSE ===");
      debugPrint("Status Code: ${response.statusCode}");
      if (response.data != null) {
        debugPrint("Body Length: ${response.data!.length} bytes");
      }

      if (response.statusCode == 200 && response.data != null) {
        return Uint8List.fromList(response.data!);
      }
      return null;
    } catch (e) {
      debugPrint("ERROR in downloadSave: $e");
      return null;
    }
  }
}
