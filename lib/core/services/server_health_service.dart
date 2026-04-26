import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

enum HealthState { connected, checking, disconnected }

class ServerHealthService {
  final Dio _dio;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;
  
  HealthState state = HealthState.connected;
  Timer? _timer;
  int _failedBurstCount = 0;
  bool _isBurstMode = false;

  ServerHealthService(this._dio, this.scaffoldMessengerKey);

  void start({required String baseUrl, required String apiKey}) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _ping(baseUrl, apiKey));
  }

  Future<bool> verifyConnection(String baseUrl, String apiKey) async {
    state = HealthState.checking;
    try {
      final response = await _dio.get(
        '$baseUrl/api/heartbeat',
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );
      if (response.statusCode == 200) {
        _resetTimer(baseUrl, apiKey);
        state = HealthState.connected;
        _isBurstMode = false;
        _failedBurstCount = 0;
        return true;
      }
    } catch (_) {}
    
    _enterBurstMode(baseUrl, apiKey);
    return false;
  }

  Future<void> _ping(String baseUrl, String apiKey) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/heartbeat',
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );
      if (response.statusCode == 200) {
        if (_isBurstMode) _resetTimer(baseUrl, apiKey);
        state = HealthState.connected;
        _isBurstMode = false;
        _failedBurstCount = 0;
        return;
      }
    } catch (_) {}
    
    _enterBurstMode(baseUrl, apiKey);
  }

  void _enterBurstMode(String baseUrl, String apiKey) {
    if (_isBurstMode) {
      _failedBurstCount++;
      if (_failedBurstCount >= 3) {
        state = HealthState.disconnected;
        _showDisconnectedSnackbar();
      }
      return;
    }

    _isBurstMode = true;
    _failedBurstCount = 1;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _ping(baseUrl, apiKey));
  }

  void _resetTimer(String baseUrl, String apiKey) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _ping(baseUrl, apiKey));
  }

  void _showDisconnectedSnackbar() {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Text('Connection to RomM lost'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () {
            // Navigation handled by the UI layer passing a callback or using global context
          },
        ),
      ),
    );
  }
}
