import 'dart:convert';
import 'package:dio/dio.dart';
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
        ));

  /// Returns the appropriate auth Options for each request.
  /// Uses Bearer token if available, falls back to Basic auth.
  Options get _authOptions {
    final token = config.token;
    if (token != null && token.isNotEmpty) {
      return Options(headers: {'Authorization': 'Bearer $token'});
    }
    final basic = 'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
    return Options(headers: {'Authorization': basic});
  }

  /// Calls /api/token with username/password (OAuth2 password flow),
  /// stores the Bearer token in SharedPreferences, and returns it.
  static Future<String> fetchToken(String baseUrl, String username, String password) async {
    final dio = Dio(BaseOptions(
      baseUrl: _normalizeBaseUrl(baseUrl),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    final response = await dio.post(
      '/api/token',
      data: {'username': username, 'password': password, 'grant_type': 'password'},
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
    final name = game.fileName ?? game.fsName ?? game.name;
    final encoded = Uri.encodeComponent(name);
    final baseUrl = config.baseUrl.endsWith('/') ? config.baseUrl.substring(0, config.baseUrl.length - 1) : config.baseUrl;
    return '$baseUrl/api/roms/${game.id}/content/$encoded';
  }

  /// Returns the Authorization header value for downloads (Bearer if available, else Basic).
  String get authHeader {
    final token = config.token;
    if (token != null && token.isNotEmpty) return 'Bearer $token';
    return 'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
  }
}
