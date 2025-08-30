import 'dart:io';
import 'package:gpth/gpth-lib.dart';

/// Service for application logging with colored output and level filtering
///
/// Extracted from utils.dart to provide a clean, testable logging interface
/// that can be easily mocked and configured for different environments.
class LoggingService {
  /// Creates a new instance of LoggingService
  LoggingService({this.isVerbose = false, this.enableColors = true});

  /// Creates a logging service from processing configuration
  factory LoggingService.fromConfig(final ProcessingConfig config) =>
      LoggingService(
        isVerbose: config.verbose,
        enableColors:
            !Platform.isWindows || Platform.environment['TERM'] != null,
      );

  /// Test override for quit/exit to prevent actual process termination in tests
  static void Function(int code)? testExitOverride;

  /// Whether verbose logging is enabled
  final bool isVerbose;

  /// Whether to use colored output (disable for file logging)
  final bool enableColors;

  /// Collected warning messages during processing
  final List<String> _warnings = [];

  /// Collected error messages during processing
  final List<String> _errors = [];

  /// Log levels with associated colors
  static const Map<String, String> _levelColors = {
    'error': '\x1B[31m', // Red
    'warning': '\x1B[33m', // Yellow
    'info': '\x1B[32m', // Green
    'debug': '\x1B[36m', // Cyan
  };

  /// Logs a message with the specified level
  ///
  /// [message] The message to log
  /// [level] Log level: 'info', 'warning', 'error', 'debug'
  /// [forcePrint] If true, prints even when verbose mode is disabled
  void log(
    final String message, {
    final String level = 'info',
    final bool forcePrint = false,
  }) {
    if (isVerbose || forcePrint) {
      final String output = _formatMessage(message, level);
      print(output);
    }
  }

  /// Logs an info message
  void info(final String message, {final bool forcePrint = false}) {
    log(message, forcePrint: forcePrint);
  }

  /// Logs a warning message
  void warning(final String message, {final bool forcePrint = false}) {
    _warnings.add(message);
    log(message, level: 'warning', forcePrint: forcePrint);
  }

  /// Logs an error message
  void error(final String message, {final bool forcePrint = false}) {
    _errors.add(message);
    log(message, level: 'error', forcePrint: forcePrint);
  }

  /// Logs a debug message (only in verbose mode)
  void debug(final String message, {final bool forcePrint = false}) {
    log(message, level: 'debug', forcePrint: forcePrint);
  }

  /// Formats a message with level and color coding
  String _formatMessage(final String message, final String level) {
    final String levelUpper = level.toUpperCase();

    if (!enableColors) {
      return '[$levelUpper] $message';
    }

    final String color = _levelColors[level.toLowerCase()] ?? '';
    const String reset = '\x1B[0m';

    return '\r$color[$levelUpper] $message$reset';
  }

  /// Creates a child logger with the same configuration
  LoggingService copyWith({final bool? isVerbose, final bool? enableColors}) =>
      LoggingService(
        isVerbose: isVerbose ?? this.isVerbose,
        enableColors: enableColors ?? this.enableColors,
      );

  /// Gets all collected warning messages
  List<String> get warnings => List.unmodifiable(_warnings);

  /// Gets all collected error messages
  List<String> get errors => List.unmodifiable(_errors);

  /// Clears all collected warning and error messages
  void clearCollectedMessages() {
    _warnings.clear();
    _errors.clear();
  }

  /// Prints error message to stderr with newline
  void errorToStderr(final Object? object) => stderr.write('$object\n');

  /// Exits the program with optional code, showing interactive message if needed
  ///
  /// [code] Exit code (default: 1)
  Never quit([final int code = 1]) {
    // Allow tests to intercept exit to avoid terminating the test process
    final override = testExitOverride;
    if (override != null) {
      override(code);
      throw _LoggingTestExitException(code);
    }

    if (Platform.environment['INTERACTIVE'] == 'true') {
      print(
        '[gpth ${code != 0 ? 'quitted :(' : 'finished :)'} (code $code) - '
        'press enter to close]',
      );
      stdin.readLineSync();
    }
    exit(code);
  }
}

/// Extension to add logging capabilities to any class
mixin LoggerMixin {
  LoggingService? _logger;

  /// Gets or creates a logger instance with default configuration
  // ignore: prefer_expression_function_bodies
  LoggingService get logger {
    // Always use a default logger to avoid circular dependencies
    // Services that need specific logging configuration should inject it explicitly
    return _logger ??= LoggingService();
  }

  /// Sets a custom logger
  set logger(final LoggingService newLogger) => _logger = newLogger;

  /// Logs an info message
  void logInfo(final String message, {final bool forcePrint = false}) {
    logger.info(message, forcePrint: forcePrint);
  }

  /// Logs a warning message
  void logWarning(final String message, {final bool forcePrint = false}) {
    logger.warning(message, forcePrint: forcePrint);
  }

  /// Logs an error message
  void logError(final String message, {final bool forcePrint = false}) {
    logger.error(message, forcePrint: forcePrint);
  }

  /// Logs a debug message
  void logDebug(final String message, {final bool forcePrint = false}) {
    logger.debug(message, forcePrint: forcePrint);
  }
}

/// Exception thrown by quit when test override is active
class _LoggingTestExitException implements Exception {
  const _LoggingTestExitException(this.code);
  final int code;

  @override
  String toString() =>
      'Application attempted to quit with exit code $code. '
      'This indicates a fatal error or completion condition was reached. '
      'In production, this would terminate the application immediately. '
      'Review the logs above for the specific reason for termination.';
}
