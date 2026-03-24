import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
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
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        )) {
    debugPrint('[RommService] created — baseUrl=${_normalizeBaseUrl(config.baseUrl)} user=${config.username} hasToken=${config.token != null && config.token!.isNotEmpty}');
    // _dio.interceptors.add(LogInterceptor(
    //   requestHeader: true,
    //   responseHeader: false,
    //   responseBody: true,
    //   requestBody: true,
    //   logPrint: (o) => debugPrint('[DIO] $o'),
    // ));
    // If the server rejects the Bearer token with 403, retry once with Basic auth.
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (DioException e, ErrorInterceptorHandler handler) async {
        if (e.response?.statusCode == 403 &&
          e.requestOptions.extra['_basicRetry'] != true &&
          e.requestOptions.data is! FormData &&
          config.token != null &&
          config.token!.isNotEmpty) {
          debugPrint('[RommService] Bearer got 403 — retrying with Basic auth');
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
  }

  /// Returns the appropriate auth Options for each request.
  /// Uses Bearer token if available, falls back to Basic auth.
  Options get _authOptions {
    final token = config.token;
    if (token != null && token.isNotEmpty) {
      debugPrint('[RommService] _authOptions using Bearer token');
      return Options(headers: {'Authorization': 'Bearer $token'});
    }
    debugPrint('[RommService] _authOptions using Basic auth user=${config.username} passLen=${config.password.length}');
    final basic = 'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
    return Options(headers: {'Authorization': basic});
  }

  /// Calls /api/token with username/password (OAuth2 password flow),
  /// stores the Bearer token in SharedPreferences, and returns it.
  static Future<String> fetchToken(String baseUrl, String username, String password) async {
    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    debugPrint('[fetchToken] POST $normalizedUrl/api/token user=$username');
    final dio = Dio(BaseOptions(
      baseUrl: normalizedUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true, logPrint: (o) => debugPrint('[DIO/token] $o')));
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
    debugPrint('[fetchToken] response status=${response.statusCode} data=${response.data}');
    final token = response.data['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Login failed: no access_token in response');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rommAuthToken', token);
    debugPrint('[fetchToken] token stored OK');
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

  Future<List<Game>> getAllGames() async {
    return _fetchPaginatedGames({});
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
        if (offset == 0 && items.isNotEmpty) {
        debugPrint('[RommService] sample raw game: ${items.first}');
        }
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
    
    debugPrint('[RommService] getDownloadUrl: name=${game.name} fileName=${game.fileName} fsName=${game.fsName} isMultiFile=${game.isMultiFile}');

    final name = game.fileName ?? game.fsName ?? game.name;
    final encoded = Uri.encodeComponent(name);
    return '$baseUrl/api/roms/${game.id}/content/$encoded';
  }

  /// Returns the Authorization header value for downloads (Bearer if available, else Basic).
  String get authHeader {
    final token = config.token;
    if (token != null && token.isNotEmpty) return 'Bearer $token';
    return 'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
  }

  // ─── Save sync ─────────────────────────────────────────────────────────────

  /// Uploads [saveFile] for [gameId] to RomM via POST /api/saves.
  Future<bool> uploadSave(String gameId, File saveFile, {String slot = 'freegosy'}) async {
    try {
      final fileName = saveFile.uri.pathSegments.last;
      final formData = FormData.fromMap({
        'saveFile': await MultipartFile.fromFile(saveFile.path, filename: fileName),
      });
      final response = await _dio.post(
        '/api/saves',
        queryParameters: {'rom_id': gameId, 'emulator': 'freegosy', 'slot': slot},
        data: formData,
        options: _authOptions,
      );
      final ok = response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
      debugPrint('[RommService] uploadSave ${ok ? 'ok' : 'failed'} status=${response.statusCode} file=$fileName');
      return ok;
    } catch (e) {
      debugPrint('[RommService] uploadSave error: $e');
      return false;
    }
  }

  /// Returns the most recently updated save object for [gameId], or null.
  Future<Map<String, dynamic>?> getLatestSave(String gameId) async {
    try {
      final response = await _dio.get(
        '/api/saves',
        queryParameters: {'rom_id': gameId},
        options: _authOptions,
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

      if (items.isEmpty) return null;

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
      debugPrint('[RommService] getLatestSave error: $e');
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

      final response = await _dio.get<List<int>>(
        url,
        options: _authOptions.copyWith(responseType: ResponseType.bytes),
      );
      if (response.statusCode == 200 && response.data != null) {
        return Uint8List.fromList(response.data!);
      }
      return null;
    } catch (e) {
      debugPrint('[RommService] downloadSave error: $e');
      return null;
    }
  }
}
