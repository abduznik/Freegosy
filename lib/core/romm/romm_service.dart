import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'romm_models.dart';

class RommService {
  final RomMConfig config;
  final Dio _dio;
  Options _authOptions;

  static String _normalizeBaseUrl(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  RommService(this.config)
      : _dio = Dio(BaseOptions(
          baseUrl: _normalizeBaseUrl(config.baseUrl),
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 10),
          headers: {
            'Expect': '', // Suppress 100-continue which chokes many reverse proxies
          },
        )),
        _authOptions = _computeAuthOptions(config) {
    
    // Add logging for Linux diagnostics
    if (kDebugMode || io.Platform.isLinux) {
      _dio.interceptors.add(LogInterceptor(
        requestHeader: true,
        requestBody: false,
        responseHeader: true,
        responseBody: false,
        logPrint: (obj) => debugPrint('[RomM-Network] $obj'),
      ));
    }

    // If the server rejects the Bearer token with 403, retry once with Basic auth.
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (DioException e, ErrorInterceptorHandler handler) async {
        // Check for 401 with API Key
        if (e.response?.statusCode == 401 && config.apiKey.isNotEmpty) {
          throw Exception('Invalid API key. Please check your token in RomM Settings → Client API Tokens.');
        }

        // Silent re-authentication on 401 (unauthorized) or 500 that looks auth-related
        final statusCode = e.response?.statusCode;
        if (statusCode == 401 || (statusCode == 500 && e.requestOptions.path != '/api/token')) {
          try {
            // Re-fetch token using stored credentials
            final prefs = await SharedPreferences.getInstance();
            final username = prefs.getString('romm_username') ?? config.username;
            final password = prefs.getString('romm_password') ?? config.password;

            if (username.isNotEmpty && password.isNotEmpty) {
              final tokenResponse = await _dio.post(
                '/api/token',
                data: {
                  'username': username,
                  'password': password,
                  'grant_type': 'password',
                },
                options: Options(
                  contentType: 'application/x-www-form-urlencoded',
                  validateStatus: (_) => true,
                ),
              );

              if (tokenResponse.statusCode == 200) {
                final newToken = tokenResponse.data['access_token']?.toString() ?? '';
                if (newToken.isNotEmpty) {
                  // Save new token
                  await prefs.setString('rommAuthToken', newToken);
                  // Update auth options
                  _authOptions = Options(headers: {'Authorization': 'Bearer $newToken'});
                  // Retry original request
                  final retryResponse = await _dio.fetch(e.requestOptions
                    ..headers['Authorization'] = 'Bearer $newToken');
                  return handler.resolve(retryResponse);
                }
              }
            }
          } catch (reAuthErr) {
            debugPrint('[RomM] Silent re-auth failed: $reAuthErr');
          }
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
  static Options _computeAuthOptions(RomMConfig config) {
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

  Future<void> refreshToken() async {
    // Don't refresh if API key is already configured - it takes priority
    if (config.apiKey.isNotEmpty) {
      debugPrint('[RomM] refreshToken: skipping - API key already set');
      return;
    }
    try {
      final username = config.username;
      final password = config.password;
      if (username.isEmpty || password.isEmpty) {
        return;
      }
      final newToken = await fetchToken(config.baseUrl, username, password);
      _authOptions = Options(headers: {'Authorization': 'Bearer $newToken'});
    } catch (e) {
      // Silence errors
    }
  }

  Future<void> _ensureBearerToken() async {
    // API key is already a valid Bearer token - no need to refresh
    if (config.apiKey.isNotEmpty) return;

    final authHeader = _authOptions.headers?['Authorization']?.toString() ?? '';
    if (!authHeader.startsWith('Bearer ')) {
      await refreshToken();
    }
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

  Future<List<Map<String, dynamic>>> getCollections() async {
    try {
      final response = await _dio.get('/api/collections', options: _authOptions);
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data is List ? response.data : [];
        return data.map((e) => e as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
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

  Future<List<Game>> getRecentlyPlayed({int limit = 15}) async {
    try {
      final params = <String, dynamic>{
        'limit': limit,
        'order_by': 'last_played',
        'order_dir': 'desc',
        'last_played': true,
        'with_char_index': false,
        'with_filter_values': false,
      };
      final response = await _dio.get(
        '/api/roms',
        queryParameters: params,
        options: _authOptions,
      );
      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> items = data is Map ? (data['items'] ?? []) : (data is List ? data : []);
        return items.map((e) => Game.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<({List<Game> games, int total})> getGamesPage({
    int offset = 0,
    int limit = 50,
    String? platformId,
    String? search,
    List<String> genres = const [],
    List<String> regions = const [],
    List<String> languages = const [],
    List<String> collections = const [],
    List<String> statuses = const [],
    bool? lastPlayed,
    bool withCharIndex = false,
    bool withFilterValues = false,
  }) async {
    final params = <String, dynamic>{
      'limit': limit,
      'offset': offset,
    };
    params['order_by'] = 'name';
    params['order_dir'] = 'asc';
    params['with_char_index'] = withCharIndex;
    params['with_filter_values'] = withFilterValues;
    if (lastPlayed != null) params['last_played'] = lastPlayed;
    if (platformId != null) params['platform_ids'] = [int.parse(platformId)];
    if (search != null && search.isNotEmpty) params['search_term'] = search;
    if (genres.isNotEmpty) params['genres'] = genres;
    if (regions.isNotEmpty) params['regions'] = regions;
    if (languages.isNotEmpty) params['languages'] = languages;
    if (collections.isNotEmpty) params['collection_id'] = int.tryParse(collections.first);
    if (statuses.isNotEmpty) {
      params['statuses'] = statuses;
      params['statuses_logic'] = 'any';
    }

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

  Future<Game?> getRandomGame() async {
    try {
      // Get total count with required params
      final countResponse = await _dio.get(
        '/api/roms',
        queryParameters: {
          'limit': 1,
          'offset': 0,
          'order_by': 'name',
          'order_dir': 'asc',
          'with_char_index': false,
          'with_filter_values': false,
        },
        options: _authOptions,
      );
      if (countResponse.statusCode != 200) return null;
      final data = countResponse.data;
      final total = (data is Map ? data['total'] : null) as int? ?? 0;
      if (total == 0) return null;

      // Pick truly random offset
      final randomOffset = Random().nextInt(total);

      // Fetch that single game
      final response = await _dio.get(
        '/api/roms',
        queryParameters: {
          'limit': 1,
          'offset': randomOffset,
          'order_by': 'name',
          'order_dir': 'asc',
          'with_char_index': false,
          'with_filter_values': false,
        },
        options: _authOptions,
      );
      if (response.statusCode != 200) return null;
      final responseData = response.data;
      final items = (responseData is Map ? responseData['items'] : null) as List<dynamic>? ?? [];
      if (items.isEmpty) return null;
      return Game.fromJson(items.first as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
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
    // If the API already provides a download URL, use it directly
    if (game.fileUrl != null && game.fileUrl!.isNotEmpty) {
      final host = _normalizeBaseUrl(config.baseUrl);
      return game.fileUrl!.startsWith('http') ? game.fileUrl! : '$host${game.fileUrl}';
    }

    final baseUrl = config.baseUrl.endsWith('/') 
        ? config.baseUrl.substring(0, config.baseUrl.length - 1) 
        : config.baseUrl;
    
    // For large files, sometimes the filename in the URL can cause issues with reverse proxies
    // RomM actually only needs the ID to find the file, the filename is often for the client.
    final name = game.fileName ?? game.fsName ?? game.name;
    String encoded = Uri.encodeComponent(name);
    
    // Truncate if extremely long to avoid 400/404 from proxy limits
    if (encoded.length > 100) {
      final ext = p.extension(name);
      final stem = p.basenameWithoutExtension(name);
      final shortStem = stem.substring(0, min(stem.length, 50));
      encoded = Uri.encodeComponent('$shortStem$ext');
    }

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
  Future<bool> uploadSave(String gameId, io.File saveFile, {String? slot}) async {
    try {
      final now = DateTime.now();
      final ts = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final effectiveSlot = slot ?? 'freegosy-srm_$ts';
      final fileName = saveFile.uri.pathSegments.last;
      
      // Explicitly set a clean boundary to avoid Linux dart:io quirks
      final boundary = '----FreegosyBoundary${DateTime.now().millisecondsSinceEpoch}';
      final formData = FormData.fromMap({
        'saveFile': await MultipartFile.fromFile(saveFile.path, filename: fileName),
      });
      
      final response = await _dio.post(
        '/api/saves',
        queryParameters: {'rom_id': gameId, 'emulator': 'freegosy', 'slot': effectiveSlot},
        data: formData,
        options: _authOptions.copyWith(
          headers: {
            ..._authOptions.headers ?? {},
            'Content-Type': 'multipart/form-data; boundary=$boundary',
          },
        ),
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
      final response = await _dio.get(
        '/api/saves',
        queryParameters: {'rom_id': gameId},
        options: opts,
      );

      if (response.statusCode != 200) return [];

      final List<dynamic> items;
      if (response.data is Map && response.data.containsKey('items')) {
        items = response.data['items'] as List<dynamic>;
      } else if (response.data is List) {
        items = response.data as List<dynamic>;
      } else {
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
      final response = await _dio.get(
        '/api/saves',
        queryParameters: {'rom_id': gameId},
        options: opts,
      );

      if (response.statusCode != 200) return null;

      final List<dynamic> items;
      if (response.data is Map && response.data.containsKey('items')) {
        items = response.data['items'] as List<dynamic>;
      } else if (response.data is List) {
        items = response.data as List<dynamic>;
      } else {
        return null;
      }

      if (items.isEmpty) {
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

      final response = await _dio.get<List<int>>(
        url,
        options: opts,
      );

      if (response.statusCode == 200 && response.data != null) {
        return Uint8List.fromList(response.data!);
      }
      return null;
    } catch (e) {
      debugPrint("ERROR in downloadSave: $e");
      return null;
    }
  }

  Future<List<Firmware>> getFirmware({String? platformId}) async {
    final params = <String, dynamic>{};
    if (platformId != null) {
      params['platform_id'] = platformId;
    }
    final response = await _dio.get('/api/firmware', queryParameters: params, options: _authOptions);
    if (response.statusCode == 200) {
      final List<dynamic> items;
      if (response.data is Map && response.data.containsKey('items')) {
        items = response.data['items'] as List<dynamic>;
      } else {
        items = response.data as List<dynamic>;
      }
      return items.map((item) => Firmware.fromJson(item)).toList();
    }
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
    );
  }

  String getFirmwareDownloadUrl(Firmware firmware) {
    final baseUrl = _normalizeBaseUrl(config.baseUrl);
    return '$baseUrl/api/firmware/${firmware.id}/content/${Uri.encodeComponent(firmware.fileName)}';
  }

  Future<Uint8List?> downloadFirmware(Firmware firmware, {void Function(int received, int total)? onProgress}) async {
    try {
      final url = getFirmwareDownloadUrl(firmware);
      final opts = _authOptions.copyWith(responseType: ResponseType.bytes);
      final response = await _dio.get<List<int>>(
        url,
        options: opts,
        onReceiveProgress: onProgress,
      );
      if (response.statusCode == 200 && response.data != null) {
        return Uint8List.fromList(response.data!);
      }
      return null;
    } catch (e) {
      debugPrint("ERROR in downloadFirmware: $e");
      return null;
    }
  }

  Future<bool> updateRomProps(
    String romId, {
    bool? backlogged,
    bool? nowPlaying,
    int? rating,
    String? status,
    int? completion,
  }) async {
    try {
      await _ensureBearerToken(); // ensure we have Bearer token
      final data = <String, dynamic>{};
      if (backlogged != null) data['backlogged'] = backlogged;
      if (nowPlaying != null) data['now_playing'] = nowPlaying;
      if (rating != null) data['rating'] = rating;
      if (status != null) data['status'] = status;
      if (completion != null) data['completion'] = completion;

      final response = await _dio.put(
        '/api/roms/$romId/props',
        data: jsonEncode({'data': data}),
        options: Options(
          headers: {
            'Authorization': _authOptions.headers?['Authorization'],
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }

  Future<List<RomNote>> getRomNotes(String romId) async {
    try {
      final response = await _dio.get('/api/roms/$romId/notes', options: _authOptions);
      if (response.statusCode == 200) {
        final List<dynamic> items;
        if (response.data is Map && response.data.containsKey('items')) {
          items = response.data['items'] as List<dynamic>;
        } else {
          items = response.data as List<dynamic>;
        }
        return items.map((item) => RomNote.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> createRomNote(String romId, String title, String content) async {
    try {
      final response = await _dio.post(
        '/api/roms/$romId/notes',
        data: {
          'title': title,
          'content': content,
        },
        options: _authOptions.copyWith(
          contentType: 'application/json',
        ),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }
}
