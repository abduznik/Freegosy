import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/secure_storage_service.dart';
import 'romm_models.dart';

class RommService {
  RomMConfig _config;
  final Dio _dio;
  Options _authOptions;

  RomMConfig get config => _config;

  static const String _ua = 'Freegosy/0.3.2';

  void updateConfig(RomMConfig newConfig) {
    _config = newConfig;
    _dio.options.baseUrl = _normalizeBaseUrl(newConfig.baseUrl);
    _authOptions = _computeAuthOptions(newConfig);
  }

  static String _normalizeBaseUrl(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  RommService(this._config)
      : _dio = Dio(BaseOptions(
          baseUrl: _normalizeBaseUrl(_config.baseUrl),
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 10),
          headers: {
            'User-Agent': _ua,
            'Accept': 'application/json',
          },
        )),
        _authOptions = _computeAuthOptions(_config) {
    
    if (kDebugMode || io.Platform.isLinux || io.Platform.isMacOS) {
      _dio.interceptors.add(LogInterceptor(
        requestHeader: true,
        requestBody: true,
        responseHeader: true,
        responseBody: true,
        logPrint: (obj) => debugPrint('[RomM-Network] $obj'),
      ));
    }

    _dio.interceptors.add(InterceptorsWrapper(
      onError: (DioException e, ErrorInterceptorHandler handler) async {
        final statusCode = e.response?.statusCode;
        final path = e.requestOptions.path;
        final isAuthRetry = e.requestOptions.extra['_isAuthRetry'] == true;

        if (!isAuthRetry && (statusCode == 401 || statusCode == 403 || statusCode == 500) && path != '/api/token') {
          if (_config.username.isNotEmpty && _config.password.isNotEmpty) {
            debugPrint('[RomM] Auth error ($statusCode), attempting fresh login...');
            try {
              final newToken = await fetchToken(_config.baseUrl, _config.username, _config.password);
              if (newToken.isNotEmpty) {
                _config = _config.copyWith(token: newToken, apiKey: '');
                _authOptions = _computeAuthOptions(_config);
                
                final opts = e.requestOptions.copyWith(
                  headers: Map<String, dynamic>.from(e.requestOptions.headers)
                    ..remove('X-Api-Key')
                    ..['Authorization'] = 'Bearer $newToken',
                )..extra['_isAuthRetry'] = true;
                
                final retryResponse = await _dio.fetch(opts);
                return handler.resolve(retryResponse);
              }
            } catch (_) {}
          }
        }
        return handler.next(e);
      },
    ));
  }

  /// Use standard Bearer format for both API keys and JWTs, as it's the most widely supported.
  static Options _computeAuthOptions(RomMConfig config) {
    final headers = <String, dynamic>{};
    
    if (config.apiKey.isNotEmpty) {
      // Standard RomM API keys work best as a Bearer token in most Nginx configs
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    } else if (config.token != null && config.token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.token}';
    } else if (config.username.isNotEmpty && config.password.isNotEmpty) {
      final basic = 'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
      headers['Authorization'] = basic;
    }
    
    return Options(headers: headers);
  }

  static Future<String> fetchToken(String baseUrl, String username, String password) async {
    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    final dio = Dio(BaseOptions(
      baseUrl: normalizedUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 2),
      headers: {'User-Agent': _ua},
    ));

    final response = await dio.post(
      '/api/token',
      data: {'username': username, 'password': password, 'grant_type': 'password'},
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );

    final token = response.data['access_token'] as String?;
    if (token == null || token.isEmpty) throw Exception('Login failed: no access_token');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rommAuthToken', token);
    await SecureStorageService.write('rommAuthToken', token);
    
    return token;
  }

  Future<void> refreshToken() async {
    try {
      if (_config.username.isEmpty || _config.password.isEmpty) return;
      final newToken = await fetchToken(_config.baseUrl, _config.username, _config.password);
      _config = _config.copyWith(token: newToken);
      _authOptions = _computeAuthOptions(_config);
    } catch (_) {}
  }

  Future<void> _ensureBearerToken() async {
    final authHeader = _authOptions.headers?['Authorization']?.toString() ?? '';
    if (!authHeader.startsWith('Bearer ')) {
      await refreshToken();
    }
  }

  // --- API Methods ---

  Future<Game?> getGame(String id) async {
    try {
      final response = await _dio.get('/api/roms/$id', options: _authOptions);
      if (response.statusCode == 200) return Game.fromJson(response.data);
      return null;
    } catch (_) { return null; }
  }

  Future<List<Platform>> getPlatforms() async {
    final response = await _dio.get('/api/platforms', options: _authOptions);
    if (response.statusCode == 200) {
      final List<dynamic> items = (response.data is Map && response.data.containsKey('items')) 
          ? response.data['items'] : response.data as List<dynamic>;
      return items.map((item) => Platform.fromJson(item)).toList();
    }
    throw DioException(requestOptions: response.requestOptions, response: response, type: DioExceptionType.badResponse);
  }

  Future<List<Map<String, dynamic>>> getCollections() async {
    try {
      final response = await _dio.get('/api/collections', options: _authOptions);
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data is List ? response.data : [];
        return data.map((e) => e as Map<String, dynamic>).toList();
      }
      return [];
    } catch (_) { return []; }
  }

  String? resolveCoverUrl(Game game) {
    final host = _normalizeBaseUrl(_config.baseUrl);
    String? path = game.pathCoverLarge ?? game.pathCoverSmall;
    if (path != null && path.isNotEmpty) return path.startsWith('http') ? path : "$host$path";
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
    final params = platformId != null ? {'platform_id': int.parse(platformId)} : <String, dynamic>{};
    return _fetchPaginatedGames(params);
  }

  Future<List<Game>> getRecentlyPlayed({int limit = 15}) async {
    try {
      final response = await _dio.get('/api/roms', queryParameters: {'limit': limit, 'order_by': 'last_played', 'order_dir': 'desc', 'last_played': true, 'with_char_index': false, 'with_filter_values': false}, options: _authOptions);
      if (response.statusCode == 200) {
        final List<dynamic> items = response.data is Map ? (response.data['items'] ?? []) : (response.data is List ? response.data : []);
        return items.map((e) => Game.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) { return []; }
  }

  Future<List<Game>> searchRoms({String? sha1, String? md5, String? search}) async {
    final params = <String, dynamic>{
      'limit': 10,
      'offset': 0,
      'with_char_index': false,
      'with_filter_values': false,
    };
    if (sha1 != null) params['sha1'] = sha1;
    if (md5 != null) params['md5'] = md5;
    if (search != null) params['search_term'] = search;

    try {
      final response = await _dio.get('/api/roms', queryParameters: params, options: _authOptions);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = response.data is Map ? response.data : {'items': response.data};
        final List<dynamic> items = data['items'] ?? [];
        return items.map((e) => Game.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[RomM] searchRoms error: $e');
      return [];
    }
  }

  Future<({List<Game> games, int total})> getGamesPage({int offset = 0, int limit = 50, String? platformId, String? search, List<String> genres = const [], List<String> regions = const [], List<String> languages = const [], List<String> collections = const [], List<String> statuses = const [], bool? lastPlayed, bool withCharIndex = false, bool withFilterValues = false}) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset, 'order_by': 'name', 'order_dir': 'asc', 'with_char_index': withCharIndex, 'with_filter_values': withFilterValues};
    if (lastPlayed != null) params['last_played'] = lastPlayed;
    if (platformId != null) params['platform_ids'] = [int.parse(platformId)];
    if (search != null && search.isNotEmpty) params['search_term'] = search;
    if (genres.isNotEmpty) params['genres'] = genres;
    if (regions.isNotEmpty) params['regions'] = regions;
    if (languages.isNotEmpty) params['languages'] = languages;
    if (collections.isNotEmpty) params['collection_id'] = int.tryParse(collections.first);
    if (statuses.isNotEmpty) { params['statuses'] = statuses; params['statuses_logic'] = 'any'; }

    final response = await _dio.get('/api/roms', queryParameters: params, options: _authOptions);
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = response.data is Map ? response.data : {'items': response.data};
      final List<dynamic> items = data['items'] ?? [];
      final int totalCount = (data['total'] as num?)?.toInt() ?? items.length;
      return (games: items.map((e) => Game.fromJson(e)).toList(), total: totalCount);
    }
    throw DioException(requestOptions: response.requestOptions, response: response, type: DioExceptionType.badResponse);
  }

  Future<List<Game>> _fetchPaginatedGames(Map<String, dynamic> params) async {
    int offset = 0; const int limit = 100; List<Game> allGames = []; int total = 0;
    do {
      final response = await _dio.get('/api/roms', queryParameters: {...params, 'limit': limit, 'offset': offset}, options: _authOptions);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = response.data is Map ? response.data : {'items': response.data};
        final List<dynamic> items = data['items'] ?? [];
        total = data['total'] ?? items.length;
        allGames.addAll(items.map((item) => Game.fromJson(item)).toList());
        offset += limit;
      } else { throw DioException(requestOptions: response.requestOptions, response: response, type: DioExceptionType.badResponse); }
    } while (allGames.length < total && offset < total);
    return allGames;
  }

  Future<Game?> getRandomGame() async {
    try {
      final countResponse = await _dio.get('/api/roms', queryParameters: {'limit': 1, 'offset': 0, 'order_by': 'name', 'order_dir': 'asc', 'with_char_index': false, 'with_filter_values': false}, options: _authOptions);
      if (countResponse.statusCode != 200) return null;
      final total = (countResponse.data is Map ? countResponse.data['total'] : null) as int? ?? 0;
      if (total == 0) return null;
      final response = await _dio.get('/api/roms', queryParameters: {'limit': 1, 'offset': Random().nextInt(total), 'order_by': 'name', 'order_dir': 'asc', 'with_char_index': false, 'with_filter_values': false}, options: _authOptions);
      final items = (response.data is Map ? response.data['items'] : null) as List<dynamic>? ?? [];
      return items.isEmpty ? null : Game.fromJson(items.first as Map<String, dynamic>);
    } catch (_) { return null; }
  }

  Future<List<SaveFile>> getSaves(String gameId) async {
    final response = await _dio.get('/api/saves', queryParameters: {'rom_id': gameId}, options: _authOptions);
    if (response.statusCode == 200) {
      final List<dynamic> items = (response.data is Map && response.data.containsKey('items')) ? response.data['items'] : response.data as List<dynamic>;
      return items.map((item) => SaveFile.fromJson(item)).toList();
    }
    throw DioException(requestOptions: response.requestOptions, response: response, type: DioExceptionType.badResponse);
  }

  String getDownloadUrl(Game game) {
    if (game.fileUrl != null && game.fileUrl!.isNotEmpty) {
      final host = _normalizeBaseUrl(_config.baseUrl);
      return game.fileUrl!.startsWith('http') ? game.fileUrl! : '$host${game.fileUrl}';
    }
    final baseUrl = _normalizeBaseUrl(_config.baseUrl);
    final name = game.fileName ?? game.fsName ?? game.name;
    String encoded = Uri.encodeComponent(name);
    if (encoded.length > 100) {
      final ext = p.extension(name); final stem = p.basenameWithoutExtension(name);
      encoded = Uri.encodeComponent('${stem.substring(0, min(stem.length, 50))}$ext');
    }
    return '$baseUrl/api/roms/${game.id}/content/$encoded';
  }

  String get authHeader {
    if (_config.apiKey.isNotEmpty) return 'Bearer ${_config.apiKey}';
    if (_config.token != null && _config.token!.isNotEmpty) return 'Bearer ${_config.token}';
    return 'Basic ${base64Encode(utf8.encode('${_config.username}:${_config.password}'))}';
  }

  Future<bool> uploadSave(String gameId, io.File saveFile, {String? slot, io.File? screenshotFile, String? overrideFilename}) async {
    try {
      final now = DateTime.now(); final ts = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final effectiveSlot = slot ?? 'freegosy-srm_$ts';
      final uploadFilename = overrideFilename ?? saveFile.uri.pathSegments.last;
      
      final formDataMap = <String, dynamic>{
        'saveFile': await MultipartFile.fromFile(saveFile.path, filename: uploadFilename)
      };
      if (screenshotFile != null && await screenshotFile.exists()) {
        formDataMap['screenshotFile'] = await MultipartFile.fromFile(screenshotFile.path, filename: screenshotFile.uri.pathSegments.last);
      }
      
      final response = await _dio.post(
        '/api/saves', 
        queryParameters: {'rom_id': gameId, 'emulator': 'freegosy', 'slot': effectiveSlot}, 
        data: FormData.fromMap(formDataMap), 
        options: _authOptions.copyWith()
      );
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (e) { 
      debugPrint('[RomM] uploadSave error: $e');
      return false; 
    }
  }

  Future<bool> deleteSaves(List<int> saveIds) async {
    if (saveIds.isEmpty) return true;
    try {
      final response = await _dio.post(
        '/api/saves/delete',
        data: {'saves': saveIds},
        options: _authOptions.copyWith(contentType: 'application/json'),
      );
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (e) {
      debugPrint('[RomM] deleteSaves error: $e');
      return false;
    }
  }

  Future<void> pruneOldSaves(String gameId, {int keepCount = 5}) async {
    try {
      final saves = await getSavesList(gameId);
      final freegosySaves = saves.where((s) => (s['emulator']?.toString() ?? '') == 'freegosy').toList();
      if (freegosySaves.length <= keepCount) return;
      
      final toDelete = freegosySaves.sublist(keepCount);
      final idsToDelete = toDelete
          .map((s) => int.tryParse(s['id']?.toString() ?? ''))
          .whereType<int>()
          .toList();

      if (idsToDelete.isNotEmpty) {
        debugPrint('[RomM] Pruning ${idsToDelete.length} old saves for game $gameId');
        await deleteSaves(idsToDelete);
      }
    } catch (e) {
      debugPrint('[RomM] pruneOldSaves error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getSavesList(String gameId) async {
    try {
      final response = await _dio.get('/api/saves', queryParameters: {'rom_id': gameId}, options: _authOptions);
      if (response.statusCode != 200) return [];
      final List<dynamic> items = (response.data is Map && response.data.containsKey('items')) ? response.data['items'] : (response.data is List ? response.data : []);
      final sorted = List<Map<String, dynamic>>.from(items.whereType<Map<String, dynamic>>());
      sorted.sort((a, b) {
        final ta = DateTime.tryParse(a['created_at']?.toString() ?? a['updated_at']?.toString() ?? '') ?? DateTime(0);
        final tb = DateTime.tryParse(b['created_at']?.toString() ?? b['updated_at']?.toString() ?? '') ?? DateTime(0);
        return tb.compareTo(ta);
      });
      return sorted;
    } catch (_) { return []; }
  }

  Future<Map<String, dynamic>?> getLatestSave(String gameId) async {
    final items = await getSavesList(gameId);
    return items.isEmpty ? null : items.first;
  }

  Future<Uint8List?> downloadSave(String saveUrl) async {
    try {
      final url = saveUrl.startsWith('http') ? saveUrl : '${_normalizeBaseUrl(_config.baseUrl)}$saveUrl';
      final response = await _dio.get<List<int>>(url, options: _authOptions.copyWith(responseType: ResponseType.bytes));
      return (response.statusCode == 200 && response.data != null) ? Uint8List.fromList(response.data!) : null;
    } catch (_) { return null; }
  }

  Future<List<Firmware>> getFirmware({String? platformId}) async {
    final params = platformId != null ? {'platform_id': platformId} : <String, dynamic>{};
    final response = await _dio.get('/api/firmware', queryParameters: params, options: _authOptions);
    if (response.statusCode == 200) {
      final List<dynamic> items = (response.data is Map && response.data.containsKey('items')) ? response.data['items'] : response.data as List<dynamic>;
      return items.map((item) => Firmware.fromJson(item)).toList();
    }
    throw DioException(requestOptions: response.requestOptions, response: response, type: DioExceptionType.badResponse);
  }

  String getFirmwareDownloadUrl(Firmware firmware) {
    final baseUrl = _normalizeBaseUrl(_config.baseUrl);
    return '$baseUrl/api/firmware/${firmware.id}/content/${Uri.encodeComponent(firmware.fileName)}';
  }

  Future<Uint8List?> downloadFirmware(Firmware firmware, {void Function(int received, int total)? onProgress}) async {
    try {
      final url = getFirmwareDownloadUrl(firmware);
      final response = await _dio.get<List<int>>(url, options: _authOptions.copyWith(responseType: ResponseType.bytes), onReceiveProgress: onProgress);
      return (response.statusCode == 200 && response.data != null) ? Uint8List.fromList(response.data!) : null;
    } catch (_) { return null; }
  }

  Future<bool> updateRomProps(String romId, {bool? backlogged, bool? nowPlaying, int? rating, String? status, int? completion}) async {
    try {
      await _ensureBearerToken();
      final data = <String, dynamic>{};
      if (backlogged != null) data['backlogged'] = backlogged;
      if (nowPlaying != null) data['now_playing'] = nowPlaying;
      if (rating != null) data['rating'] = rating;
      if (status != null) data['status'] = status;
      if (completion != null) data['completion'] = completion;
      final response = await _dio.put('/api/roms/$romId/props', data: {'data': data, 'update_last_played': false, 'remove_last_played': false}, options: Options(headers: Map<String, dynamic>.from(_authOptions.headers ?? {})..['Content-Type'] = 'application/json', validateStatus: (status) => status != null && status < 500));
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) { return false; }
  }

  Future<List<RomNote>> getRomNotes(String romId) async {
    try {
      final response = await _dio.get('/api/roms/$romId/notes', options: _authOptions);
      if (response.statusCode == 200) {
        final List<dynamic> items = (response.data is Map && response.data.containsKey('items')) ? response.data['items'] : response.data as List<dynamic>;
        return items.map((item) => RomNote.fromJson(item)).toList();
      }
      return [];
    } catch (_) { return []; }
  }

  Future<bool> createRomNote(String romId, String title, String content) async {
    try {
      final response = await _dio.post('/api/roms/$romId/notes', data: {'title': title, 'content': content, 'is_public': true, 'tags': []}, options: _authOptions.copyWith(contentType: 'application/json'));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) { return false; }
  }

  Future<bool> deleteRomNote(String romId, int noteId) async {
    try {
      final response = await _dio.delete('/api/roms/$romId/notes/$noteId', options: _authOptions);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) { return false; }
  }
}
