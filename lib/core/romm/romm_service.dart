import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';
import '../platform/platform_info.dart';
import '../storage/app_preferences.dart';
import '../storage/secure_storage_service.dart';
import 'romm_models.dart';
import 'romm_state.dart';

class RommService implements RommStatesApi {
  RomMConfig _config;
  final Dio _dio;
  Options _authOptions;
  final ValueNotifier<bool> isOffline = ValueNotifier(false);
  Timer? _heartbeatTimer;
  final PlatformInfo _platform;

  RomMConfig get config => _config;

  static String get _ua => 'Freegosy/${AppConstants.version}';

  void updateConfig(RomMConfig newConfig) {
    _config = newConfig;
    _dio.options.baseUrl = _normalizeBaseUrl(newConfig.baseUrl);
    _authOptions = _computeAuthOptions(newConfig);
  }

  static String _normalizeBaseUrl(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// True only for the connectivity/capabilities poll (`GET /api/heartbeat`)
  /// — NOT `/api/activity/heartbeat` (issue #93), which merely contains the
  /// same substring. Used to quiet debug logging and skip retries for the
  /// former without also silencing the latter.
  static bool _isConnectivityHeartbeat(String path) => path == '/api/heartbeat';

  RommService(this._config, {Dio? dio, PlatformInfo? platform, bool skipConnectivityCheck = false})
      : _dio = dio ?? Dio(BaseOptions(
          baseUrl: _normalizeBaseUrl(_config.baseUrl),
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'User-Agent': _ua,
            'Accept': 'application/json',
          },
        )),
        _authOptions = _computeAuthOptions(_config),
        _platform = platform ?? PlatformInfo.current {
    
    if (dio != null) {
      _dio.options.baseUrl = _normalizeBaseUrl(_config.baseUrl);
    }

    if (_config.trustSelfSigned) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = io.HttpClient()
            ..badCertificateCallback = (cert, host, port) => true;
          return client;
        },
      );
    }
    
    if (kDebugMode || _platform.isLinux || _platform.isMacOS) {
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (!_isConnectivityHeartbeat(options.path) && !options.path.contains('/api/roms')) {
            debugPrint('[RomM-Network] -> ${options.method} ${options.uri}');
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          final path = response.requestOptions.path;
          if (!_isConnectivityHeartbeat(path) && !path.contains('/api/roms')) {
            debugPrint('[RomM-Network] <- ${response.statusCode} ${response.requestOptions.uri}');
          } else if (path.contains('/api/roms')) {
            final offset = response.requestOptions.queryParameters['offset'] ?? 0;
            final limit = response.requestOptions.queryParameters['limit'] ?? 'all';
            debugPrint('[RomM-Network] ~ Fetched games batch (offset: $offset, limit: $limit)');
          }
          return handler.next(response);
        },
        onError: (e, handler) {
          if (!_isConnectivityHeartbeat(e.requestOptions.path)) {
            debugPrint('[RomM-Network] ! ERROR ${e.requestOptions.uri}: ${e.message}');
          }
          return handler.next(e);
        },
      ));
    }

    _dio.interceptors.add(InterceptorsWrapper(
      onError: (DioException e, ErrorInterceptorHandler handler) async {
        // Retry logic for transient network errors (especially on Steam Deck wake-up)
        final path = e.requestOptions.path;
        final isRetryable = e.type != DioExceptionType.cancel &&
                          e.type != DioExceptionType.badResponse &&
                          e.requestOptions.extra['no_retry'] != true &&
                          !_isConnectivityHeartbeat(path);

        if (isRetryable && e.requestOptions.extra['retry_count'] == null) {
          e.requestOptions.extra['retry_count'] = 0;
        }

        final retryCount = e.requestOptions.extra['retry_count'] as int? ?? 0;
        
        if (isRetryable && retryCount < 2) {
          e.requestOptions.extra['retry_count'] = retryCount + 1;
          debugPrint('[RomM-Network] ! Retrying ${e.requestOptions.uri} (Attempt ${retryCount + 1})...');
          await Future.delayed(Duration(seconds: 1 * (retryCount + 1)));
          try {
            final response = await _dio.fetch(e.requestOptions);
            return handler.resolve(response);
          } catch (retryError) {
            return handler.next(retryError is DioException ? retryError : e);
          }
        }
        return handler.next(e);
      },
    ));
    
    if (!skipConnectivityCheck) {
      _initializeConnectivity();
    }
  }

  void startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        await _dio.get('/api/heartbeat', options: Options(
          headers: {'Authorization': _authOptions.headers?['Authorization']},
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ));
        if (isOffline.value) {
          isOffline.value = false;
        }
      } catch (e) {
        if (!isOffline.value) {
          isOffline.value = true;
        }
      }
    });
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
  }

  Future<void> _initializeConnectivity() async {
    try {
      final uri = Uri.parse(_config.baseUrl);
      final socket = await io.Socket.connect(
        uri.host, 
        uri.port == 0 ? (uri.scheme == 'https' ? 443 : 80) : uri.port, 
        timeout: const Duration(seconds: 2)
      );
      await socket.close();
      
      await getPlatforms();
      isOffline.value = false;
    } catch (e) {
      debugPrint('[RommService] Server unreachable, switching to offline mode.');
      isOffline.value = true;
    }
  }

  static Options _computeAuthOptions(RomMConfig config) {
    final headers = <String, dynamic>{};
    
    if (config.apiKey.isNotEmpty) {
      // Send both headers for maximum compatibility across all RomM versions and proxies.
      // Standard API Keys often work via X-Api-Key, while Client Tokens often require Bearer.
      // Many setups use the API Key in the Bearer field, so we provide both to be safe.
      headers['Authorization'] = 'Bearer ${config.apiKey}';
      headers['X-Api-Key'] = config.apiKey;
    } else if (config.token != null && config.token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.token}';
    } else if (config.username.isNotEmpty && config.password.isNotEmpty) {
      final basic = 'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
      headers['Authorization'] = basic;
    }
    
    return Options(headers: headers);
  }

  static Future<String> fetchToken(String baseUrl, String username, String password, AppPreferences prefs) async {
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

    await SecureStorageService.write('rommAuthToken', token, prefs);
    
    return token;
  }

  static Future<String> exchangePairingCode(String baseUrl, String code, {bool trustSelfSigned = false}) async {
    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    final dio = Dio(BaseOptions(
      baseUrl: normalizedUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': _ua},
    ));

    if (trustSelfSigned) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = io.HttpClient()
            ..badCertificateCallback = (cert, host, port) => true;
          return client;
        },
      );
    }

    const maxRetries = 2;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await dio.post(
          '/api/client-tokens/exchange',
          data: {'code': code},
        );

        final token = response.data['raw_token'] as String?;
        if (token == null || token.isEmpty) throw Exception('Pairing failed: no token in response');

        return token;
      } on DioException catch (e) {
        if (attempt < maxRetries && e.type != DioExceptionType.badResponse) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }

    throw Exception('Pairing failed after $maxRetries retries');
  }

  Future<void> refreshToken(AppPreferences prefs) async {
    try {
      if (_config.username.isEmpty || _config.password.isEmpty) return;
      final newToken = await fetchToken(_config.baseUrl, _config.username, _config.password, prefs);
      _config = _config.copyWith(token: newToken);
      _authOptions = _computeAuthOptions(_config);
    } catch (_) {}
  }

  Future<void> _ensureBearerToken(AppPreferences prefs) async {
    final authHeader = _authOptions.headers?['Authorization']?.toString() ?? '';
    if (!authHeader.startsWith('Bearer ')) {
      await refreshToken(prefs);
    }
  }

  // ---------------------------------------------------------------------------
  // Capabilities / version detection
  // ---------------------------------------------------------------------------

  /// Fetches [RommCapabilities] from /api/heartbeat once and caches the result.
  RommCapabilities _capabilities = RommCapabilities.unknown();
  bool _capabilitiesFetched = false;

  RommCapabilities get capabilities => _capabilities;

  Future<RommCapabilities> fetchCapabilities() async {
    if (_capabilitiesFetched) return _capabilities;
    try {
      final response = await _dio.get('/api/heartbeat', options: Options(
        headers: {'Authorization': _authOptions.headers?['Authorization']},
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      if (response.statusCode == 200) {
        final version = (response.data?['SYSTEM']?['VERSION'] as String?) ?? '0.0.0';
        _capabilities = RommCapabilities(version: version);
        debugPrint('[RomM] Detected version: $version → $_capabilities');
      }
    } catch (e) {
      debugPrint('[RomM] fetchCapabilities failed, defaulting to legacy: $e');
    }
    _capabilitiesFetched = true;
    return _capabilities;
  }

  // ---------------------------------------------------------------------------
  // Device registration (RomM 4.9+)
  // ---------------------------------------------------------------------------

  /// Registers this Freegosy install as a device and returns the persistent UUID.
  /// [allowExisting] = true recovers an existing registration on re-install.
  Future<String?> registerDevice({
    required String name,
    required String platform,
    String? clientVersion,
    bool allowExisting = true,
  }) async {
    try {
      final body = {
        'name': name,
        'platform': platform,
        'client': 'freegosy',
        'client_version': clientVersion ?? AppConstants.version,
      };
      final response = await _dio.post(
        '/api/devices',
        queryParameters: allowExisting ? {'allow_existing': 'true'} : null,
        data: body,
        options: _authOptions.copyWith(contentType: 'application/json'),
      );
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        final deviceId = response.data['device_id']?.toString() ??
            response.data['id']?.toString();
        debugPrint('[RomM] Registered device: $deviceId');
        return deviceId;
      }
    } catch (e) {
      debugPrint('[RomM] registerDevice error: $e');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // API Methods
  // ---------------------------------------------------------------------------

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

  Future<List<Game>> getRecentlyAdded({int limit = 15}) async {
    try {
      final response = await _dio.get(
        '/api/roms', 
        queryParameters: {
          'limit': limit, 
          'order_by': 'id', 
          'order_dir': 'desc', 
          'with_char_index': false, 
          'with_filter_values': false
        }, 
        options: _authOptions
      );
      if (response.statusCode == 200) {
        final List<dynamic> items = response.data is Map ? (response.data['items'] ?? []) : (response.data is List ? response.data : []);
        return items.map((e) => Game.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) { return []; }
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

  Future<List<Game>> searchRoms({String? sha1, String? md5, String? search, String? platformId}) async {
    final params = <String, dynamic>{
      'limit': 50,
      'offset': 0,
      'with_char_index': false,
      'with_filter_values': false,
    };
    if (sha1 != null) params['sha1'] = sha1;
    if (md5 != null) params['md5'] = md5;
    if (search != null) params['search_term'] = search;
    if (platformId != null) params['platform_id'] = platformId;

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
    String encoded = Uri.encodeComponent(name)
        .replaceAll("'", "%27")
        .replaceAll("(", "%28")
        .replaceAll(")", "%29");
    if (encoded.length > 100) {
      final ext = p.extension(name); final stem = p.basenameWithoutExtension(name);
      encoded = Uri.encodeComponent('${stem.substring(0, min(stem.length, 50))}$ext')
          .replaceAll("'", "%27")
          .replaceAll("(", "%28")
          .replaceAll(")", "%29");
    }
    final url = '$baseUrl/api/roms/${game.id}/content/$encoded';

    // Per RomM's API, the path filename above is only the zip output name -
    // it does not select which file gets served. The real selector is the
    // `file_ids` query param, built from files[] (each entry's real database
    // id). Passing it explicitly avoids relying on the server to guess the
    // right file from a reconstructed name, which is unreliable for
    // single-file-foldered roms (see issue #44).
    if (game.files.isNotEmpty) {
      final ids = game.files
          .map((f) => f['id'])
          .where((id) => id != null)
          .map((id) => id.toString())
          .toList();
      if (ids.isNotEmpty) {
        return '$url?file_ids=${ids.join(',')}';
      }
    }
    return url;
  }

  String get authHeader {
    if (_config.apiKey.isNotEmpty) return 'Bearer ${_config.apiKey}';
    if (_config.token != null && _config.token!.isNotEmpty) return 'Bearer ${_config.token}';
    return 'Basic ${base64Encode(utf8.encode('${_config.username}:${_config.password}'))}';
  }

  /// Uploads a save file to RomM.
  ///
  /// When [deviceId] is provided (RomM 4.9+), the server tracks sync state and
  /// returns 409 on conflict. [slot] groups saves into named categories.
  /// [autocleanup] + [autocleanupLimit] let the server prune old slot saves.
  /// [overwrite] bypasses server-side conflict detection (force-push).
  ///
  /// Returns `null` on a 409 conflict so callers can inspect the raw response;
  /// returns `true` on success; returns `false` on other errors.
  Future<({bool ok, Map<String, dynamic>? conflict})> uploadSave(
    String gameId,
    io.File saveFile, {
    String? slot,
    String? deviceId,
    bool autocleanup = false,
    int autocleanupLimit = 5,
    bool overwrite = false,
    io.File? screenshotFile,
    String? overrideFilename,
  }) async {
    try {
      final uploadFilename = overrideFilename ?? saveFile.uri.pathSegments.last;

      // Slot naming: always use 'freegosy' for consistency.
      // Previously used timestamped slots like 'freegosy-srm_2026-07-11_08-45-38'
      // which created duplicate records on RomM and caused the filename to be
      // corrupted with timestamps. RomM's autocleanup handles version pruning.
      // Do NOT add timestamps to the slot — it breaks save sync (issues #42, #28).
      final queryParams = <String, dynamic>{
        'rom_id': gameId,
        'emulator': 'freegosy',
        'slot': slot ?? 'freegosy',
      };
      // Autocleanup and overwrite are now available for ALL paths (not just 4.9+).
      // This ensures legacy RomM instances also get proper save management.
      if (deviceId != null) queryParams['device_id'] = deviceId;
      if (autocleanup) {
        queryParams['autocleanup'] = 'true';
        queryParams['autocleanup_limit'] = autocleanupLimit.toString();
      }
      if (overwrite) queryParams['overwrite'] = 'true';

      final formDataMap = <String, dynamic>{
        'saveFile': await MultipartFile.fromFile(saveFile.path, filename: uploadFilename),
      };
      if (screenshotFile != null && await screenshotFile.exists()) {
        formDataMap['screenshotFile'] = await MultipartFile.fromFile(
            screenshotFile.path, filename: screenshotFile.uri.pathSegments.last);
      }

      final response = await _dio.post(
        '/api/saves',
        queryParameters: queryParams,
        data: FormData.fromMap(formDataMap),
        options: _authOptions.copyWith(
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 409) {
        final detail = response.data is Map
            ? (response.data['detail'] as Map<String, dynamic>?)
            : null;
        debugPrint('[RomM] uploadSave 409 conflict: $detail');
        return (ok: false, conflict: detail);
      }

      final ok = response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
      return (ok: ok, conflict: null);
    } catch (e) {
      debugPrint('[RomM] uploadSave error: $e');
      return (ok: false, conflict: null);
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

  /// Lists saves for a game, sorted newest-first.
  ///
  /// Pass [deviceId] (RomM 4.9+) to receive `device_syncs[]` with `is_current`
  /// on each save. Pass [slot] to filter to a specific slot.
  Future<List<Map<String, dynamic>>> getSavesList(
    String gameId, {
    String? deviceId,
    String? slot,
  }) async {
    try {
      final params = <String, dynamic>{'rom_id': gameId};
      if (deviceId != null) params['device_id'] = deviceId;
      if (slot != null) params['slot'] = slot;

      final response =
          await _dio.get('/api/saves', queryParameters: params, options: _authOptions);
      if (response.statusCode != 200) return [];
      final List<dynamic> items =
          (response.data is Map && response.data.containsKey('items'))
              ? response.data['items']
              : (response.data is List ? response.data : []);
      final sorted =
          List<Map<String, dynamic>>.from(items.whereType<Map<String, dynamic>>());
      sorted.sort((a, b) {
        final ta = DateTime.tryParse(
                a['created_at']?.toString() ?? a['updated_at']?.toString() ?? '') ??
            DateTime(0);
        final tb = DateTime.tryParse(
                b['created_at']?.toString() ?? b['updated_at']?.toString() ?? '') ??
            DateTime(0);
        return tb.compareTo(ta);
      });
      return sorted;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getLatestSave(String gameId, {String? deviceId}) async {
    final items = await getSavesList(gameId, deviceId: deviceId);
    return items.isEmpty ? null : items.first;
  }

  /// Downloads save file bytes.
  ///
  /// Pass [deviceId] (RomM 4.9+) to trigger optimistic sync-record update on
  /// the server side (saves a separate /downloaded call).
  Future<Uint8List?> downloadSave(
    String saveUrl, {
    AppPreferences? prefs,
    String? deviceId,
  }) async {
    try {
      if (prefs != null) {
        await _ensureBearerToken(prefs);
      }
      var url =
          saveUrl.startsWith('http') ? saveUrl : '${_normalizeBaseUrl(_config.baseUrl)}$saveUrl';
      // 4.9+: append device_id for optimistic sync record update
      if (deviceId != null) {
        final separator = url.contains('?') ? '&' : '?';
        url = '$url${separator}device_id=${Uri.encodeComponent(deviceId)}&optimistic=true';
      }
      final response = await _dio.get<List<int>>(
          url, options: _authOptions.copyWith(responseType: ResponseType.bytes));
      return (response.statusCode == 200 && response.data != null)
          ? Uint8List.fromList(response.data!)
          : null;
    } catch (e) {
      debugPrint('[RomM] downloadSave error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Save states (/api/states) — per RomM user, private by default
  // ---------------------------------------------------------------------------

  Options get _stateOptions => _authOptions.copyWith(
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      );

  /// How long a state download may go without receiving data before it fails.
  /// Dio's receive timeout is the longest gap between data events, not a limit
  /// on the whole transfer, so a slow download that keeps progressing still
  /// finishes. Downloads run before launch (awaited), so a stalled server must
  /// not hold them for the 5 minutes uploads are allowed.
  static const Duration stateDownloadInactivityTimeout = Duration(seconds: 30);

  /// Options for [downloadState]: the short inactivity bound, and no retries
  /// (the sync stops at the first failed download instead).
  Options get _stateDownloadOptions => _authOptions.copyWith(
        responseType: ResponseType.bytes,
        receiveTimeout: stateDownloadInactivityTimeout,
        extra: {'no_retry': true},
      );

  @override
  Future<List<RommState>> listStates(String romId) async {
    final response = await _dio.get('/api/states',
        queryParameters: {'rom_id': romId}, options: _authOptions);
    final data = response.data;
    final List<dynamic> items = data is Map
        ? (data['items'] as List<dynamic>? ?? const [])
        : (data as List<dynamic>? ?? const []);
    return items
        .whereType<Map<String, dynamic>>()
        .map(RommState.fromJson)
        .toList();
  }

  Map<String, dynamic> _stateForm(MultipartFile state, String fileName, Uint8List? screenshot) => {
        'stateFile': state,
        if (screenshot != null)
          'screenshotFile': MultipartFile.fromBytes(screenshot, filename: '$fileName.png'),
      };

  @override
  Future<RommState> uploadState(String romId, io.File file,
      {required String fileName, String? emulator, Uint8List? screenshot}) async {
    final response = await _dio.post(
      '/api/states',
      queryParameters: {'rom_id': romId, 'emulator': ?emulator},
      data: FormData.fromMap(_stateForm(
          await MultipartFile.fromFile(file.path, filename: fileName), fileName, screenshot)),
      options: _stateOptions,
    );
    return RommState.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<RommState> updateState(int stateId, io.File file,
      {required String fileName, Uint8List? screenshot}) async {
    try {
      final response = await _dio.put(
        '/api/states/$stateId',
        data: FormData.fromMap(_stateForm(
            await MultipartFile.fromFile(file.path, filename: fileName), fileName, screenshot)),
        options: _stateOptions,
      );
      return RommState.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw RommStateNotFoundException(stateId);
      rethrow;
    }
  }

  @override
  Future<Uint8List> downloadState(int stateId) async {
    try {
      final response = await _dio.get<List<int>>(
        '/api/states/$stateId/content',
        options: _stateDownloadOptions,
      );
      return Uint8List.fromList(List<int>.from(response.data ?? const <int>[]));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw RommStateNotFoundException(stateId);
      rethrow;
    }
  }

  @override
  Future<Uint8List> downloadStateScreenshot(String url) async {
    final uri = Uri.parse(url);
    if (!url.startsWith('/') || uri.hasScheme || uri.hasAuthority) {
      throw ArgumentError.value(url, 'url', 'must be a server-relative path');
    }
    final response = await _dio.get<List<int>>(url, options: _stateDownloadOptions);
    return Uint8List.fromList(List<int>.from(response.data ?? const <int>[]));
  }

  // ---------------------------------------------------------------------------
  // Play session tracking (RomM 4.9+)
  // ---------------------------------------------------------------------------

  /// Records a completed play session with the server.
  ///
  /// Called after the emulator process exits on 4.9+ servers only.
  /// Silently no-ops on errors — play time tracking is best-effort.
  ///
  /// [romId]      — the game's RomM ID
  /// [deviceId]   — this device's registered UUID
  /// [startTime]  — when the emulator was launched
  /// [endTime]    — when the emulator process exited
  Future<void> recordPlaySession({
    required String romId,
    required String deviceId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      final id = int.tryParse(romId);
      if (id == null) return;

      final durationMs = endTime.difference(startTime).inMilliseconds;
      if (durationMs <= 0) return;

      await _dio.post(
        '/api/play-sessions',
        data: {
          'device_id': deviceId,
          'sessions': [
            {
              'rom_id': id,
              'start_time': startTime.toUtc().toIso8601String(),
              'end_time': endTime.toUtc().toIso8601String(),
              'duration_ms': durationMs,
            }
          ],
        },
        options: _authOptions.copyWith(contentType: 'application/json'),
      );
      debugPrint('[RomM] Recorded play session for rom $romId: ${durationMs}ms');
    } catch (e) {
      debugPrint('[RomM] recordPlaySession error (non-fatal): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Active session heartbeat (RomM 4.9+, issue #93)
  // ---------------------------------------------------------------------------

  /// Pings RomM's real-time "active sessions" board so other clients (the
  /// web UI, dashboard integrations, etc.) see this device as currently
  /// playing [romId]. Call once on launch, then repeat periodically while
  /// the game is running — the server expires the entry ~90s after the last
  /// heartbeat. Silently no-ops on errors; this is cosmetic only.
  Future<void> sendActivityHeartbeat({required String romId, required String deviceId}) async {
    final id = int.tryParse(romId);
    if (id == null) {
      debugPrint('[RomM] sendActivityHeartbeat skipped: romId "$romId" is not numeric');
      return;
    }
    try {
      await _dio.post(
        '/api/activity/heartbeat',
        data: {'rom_id': id, 'device_id': deviceId},
        options: _authOptions.copyWith(
          contentType: 'application/json',
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      debugPrint('[RomM] sendActivityHeartbeat ok (rom $id, device $deviceId)');
    } catch (e) {
      debugPrint('[RomM] sendActivityHeartbeat error (non-fatal): $e');
    }
  }

  /// Immediately clears this device's active session (e.g. on game exit),
  /// rather than waiting out the server's heartbeat TTL. Silently no-ops on
  /// errors; this is cosmetic only.
  Future<void> clearActivityHeartbeat({required String deviceId}) async {
    try {
      await _dio.delete(
        '/api/activity/heartbeat',
        queryParameters: {'device_id': deviceId},
        options: _authOptions.copyWith(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      debugPrint('[RomM] clearActivityHeartbeat ok (device $deviceId)');
    } catch (e) {
      debugPrint('[RomM] clearActivityHeartbeat error (non-fatal): $e');
    }
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

  Future<bool> updateRomProps(String romId, AppPreferences prefs, {bool? backlogged, bool? nowPlaying, int? rating, String? status, int? completion}) async {
    try {
      await _ensureBearerToken(prefs);
      final data = <String, dynamic>{};
      if (backlogged != null) data['backlogged'] = backlogged;
      if (nowPlaying != null) data['now_playing'] = nowPlaying;
      if (rating != null) data['rating'] = rating;
      if (status != null) data['status'] = status.toLowerCase();
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
