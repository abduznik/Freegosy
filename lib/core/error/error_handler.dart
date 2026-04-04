import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

enum ErrorSeverity { info, warning, error, success }

class AppError {
  final String title;
  final String message;
  final ErrorSeverity severity;
  final String? technical; // raw error for debugging

  const AppError({
    required this.title,
    required this.message,
    this.severity = ErrorSeverity.error,
    this.technical,
  });
}

class ErrorHandler {
  /// Convert any exception into a user-friendly AppError.
  static AppError parse(Object error, {String? context}) {
    // Network/API errors
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return AppError(
            title: 'Connection Timeout',
            message: 'Could not reach the server. Check your network or RomM connection.',
            severity: ErrorSeverity.error,
            technical: error.toString(),
          );
        case DioExceptionType.connectionError:
          return AppError(
            title: 'Connection Failed',
            message: 'Cannot connect to RomM. Make sure the server is running.',
            severity: ErrorSeverity.error,
            technical: error.toString(),
          );
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          if (statusCode == 401 || statusCode == 403) {
            return AppError(
              title: 'Authentication Error',
              message: 'Session expired or invalid credentials. Please reconnect.',
              severity: ErrorSeverity.error,
              technical: error.toString(),
            );
          } else if (statusCode == 404) {
            return AppError(
              title: 'Not Found',
              message: context != null ? '$context was not found on the server.' : 'The requested resource was not found.',
              severity: ErrorSeverity.warning,
              technical: error.toString(),
            );
          } else if (statusCode == 422) {
            return AppError(
              title: 'Invalid Request',
              message: 'The server rejected the request. This may be a Freegosy bug.',
              severity: ErrorSeverity.error,
              technical: error.toString(),
            );
          } else if (statusCode != null && statusCode >= 500) {
            return AppError(
              title: 'Server Error',
              message: 'RomM encountered an error (HTTP $statusCode). Try again later.',
              severity: ErrorSeverity.error,
              technical: error.toString(),
            );
          }
          return AppError(
            title: 'Request Failed',
            message: 'Server returned an unexpected response (HTTP $statusCode).',
            severity: ErrorSeverity.error,
            technical: error.toString(),
          );
        default:
          return AppError(
            title: 'Network Error',
            message: 'A network error occurred. Please try again.',
            severity: ErrorSeverity.error,
            technical: error.toString(),
          );
      }
    }

    // File system errors
    if (error is FileSystemException) {
      return AppError(
        title: 'File Error',
        message: error.message.isNotEmpty ? error.message : 'A file system error occurred.',
        severity: ErrorSeverity.error,
        technical: error.toString(),
      );
    }

    // Save sync specific errors
    final errorStr = error.toString();
    if (errorStr.contains('Save directory not found')) {
      return AppError(
        title: 'Save Folder Not Found',
        message: 'Could find the emulator save folder. Launch the game at least once to create it.',
        severity: ErrorSeverity.warning,
        technical: errorStr,
      );
    }
    if (errorStr.contains('SaveMappingRequired')) {
      return AppError(
        title: 'Save Mapping Required',
        message: 'Cannot automatically find saves for this game. Manual mapping needed.',
        severity: ErrorSeverity.warning,
        technical: errorStr,
      );
    }
    if (errorStr.contains('No saves found') || errorStr.contains('saves list is empty')) {
      return AppError(
        title: 'No Saves Found',
        message: 'No local save files were found for this game. Play the game first.',
        severity: ErrorSeverity.info,
        technical: errorStr,
      );
    }
    if (errorStr.contains('emulator') && errorStr.contains('not found')) {
      return AppError(
        title: 'Emulator Not Found',
        message: 'The emulator executable could not be located. Check your settings.',
        severity: ErrorSeverity.warning,
        technical: errorStr,
      );
    }
    if (errorStr.contains('ROM file not found') || errorStr.contains('not downloaded')) {
      return AppError(
        title: 'ROM Not Downloaded',
        message: 'The ROM file was not found locally. Download it first.',
        severity: ErrorSeverity.warning,
        technical: errorStr,
      );
    }

    // Generic fallback
    return AppError(
      title: context ?? 'Something went wrong',
      message: 'An unexpected error occurred. Please try again.',
      severity: ErrorSeverity.error,
      technical: errorStr,
    );
  }

  /// Show a snackbar for an AppError.
  static void show(BuildContext context, AppError error) {
    if (!context.mounted) return;
    
    final color = switch (error.severity) {
      ErrorSeverity.success => const Color(0xFF2E7D32),
      ErrorSeverity.info    => const Color(0xFF1565C0),
      ErrorSeverity.warning => const Color(0xFFE65100),
      ErrorSeverity.error   => const Color(0xFFC62828),
    };

    final icon = switch (error.severity) {
      ErrorSeverity.success => Icons.check_circle_outline,
      ErrorSeverity.info    => Icons.info_outline,
      ErrorSeverity.warning => Icons.warning_amber_outlined,
      ErrorSeverity.error   => Icons.error_outline,
    };

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        duration: error.severity == ErrorSeverity.error
            ? const Duration(seconds: 6)
            : const Duration(seconds: 3),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    error.message,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: error.technical != null
            ? SnackBarAction(
                label: 'Details',
                textColor: Colors.white,
                onPressed: () => _showTechnicalDetails(context, error),
              )
            : null,
      ),
    );
  }

  /// Show an error parsed from an exception directly.
  static void showException(BuildContext context, Object error, {String? contextLabel}) {
    show(context, parse(error, context: contextLabel));
  }

  /// Show a success message.
  static void showSuccess(BuildContext context, String title, {String message = ''}) {
    show(context, AppError(
      title: title,
      message: message,
      severity: ErrorSeverity.success,
    ));
  }

  /// Show an info message.
  static void showInfo(BuildContext context, String title, {String message = ''}) {
    show(context, AppError(
      title: title,
      message: message,
      severity: ErrorSeverity.info,
    ));
  }

  static void _showTechnicalDetails(BuildContext context, AppError error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(error.title),
        content: SingleChildScrollView(
          child: SelectableText(
            error.technical ?? 'No details available',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
