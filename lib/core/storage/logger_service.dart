import 'dart:async';
import 'package:flutter/foundation.dart';

class LogEntry {
  final DateTime timestamp;
  final String message;
  final String? level;

  LogEntry(this.message, {this.level, DateTime? timestamp}) 
      : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => '[${timestamp.toIso8601String().substring(11, 19)}] ${level != null ? '[$level] ' : ''}$message';
}

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  final List<LogEntry> _logs = [];
  final StreamController<List<LogEntry>> _controller = StreamController<List<LogEntry>>.broadcast();

  List<LogEntry> get logs => List.unmodifiable(_logs);
  Stream<List<LogEntry>> get logStream => _controller.stream;

  void log(String message, {String? level}) {
    final entry = LogEntry(message, level: level);
    _logs.add(entry);
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    _controller.add(logs);
  }

  void clear() {
    _logs.clear();
    _controller.add(logs);
  }

  static void init() {
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        LoggerService().log(message);
      }
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };
  }
}
