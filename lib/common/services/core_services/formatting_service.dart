import 'dart:io';

import 'package:gpth/gpth_lib_exports.dart';
import 'package:proper_filesize/proper_filesize.dart';

/// Consolidated utility service for common formatting and utility operations
///
/// This service consolidates formatting functionality that was previously
/// scattered across multiple services, providing a single source of truth
/// for common utility operations.
class FormattingService {
  /// Creates a new instance of FormattingService
  const FormattingService();

  /// Test override for exitProgram to prevent actual process termination in tests
  static void Function(int code)? testExitOverride;

  // ============================================================================
  // FORMATTING OPERATIONS
  // ============================================================================

  /// Formats byte count into a human-readable file size string.
  ///
  /// [bytes] Number of bytes to format.
  /// Returns a formatted string like "1.50 MB".
  String formatFileSize(final int bytes) {
    if (bytes <= 0) return '0 B';
    return FileSize.fromBytes(bytes).toString(
      unit: Unit.auto(size: bytes, baseType: BaseType.metric),
      decimals: 2,
    );
    // Note: proper_filesize returns a String; no double/int issues here.
  }

  /// Formats a [Duration] to a concise human-readable string.
  ///
  /// Examples: "45s", "1m 30s", "2h 05m".
  String formatDuration(final Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) return '${seconds}s';

    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes < 60) {
      return remainingSeconds > 0
          ? '${minutes}m ${remainingSeconds}s'
          : '${minutes}m';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes > 0
        ? '${hours}h ${remainingMinutes}m'
        : '${hours}h';
  }

  /// Formats an integer with thousands separators.
  ///
  /// [number] The number to format.
  /// Returns a string like "1,234,567".
  String formatNumber(final int number) => number.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (final Match m) => '${m[1]},',
  );

  // ============================================================================
  // FILE OPERATIONS
  // ============================================================================

  /// Finds a unique file name by appending "(1)", "(2)", etc. until it doesn't exist.
  ///
  /// [initialFile] Desired file path.
  /// Returns a [File] with a non-existing path.
  File findUniqueFileName(final File initialFile) {
    if (!initialFile.existsSync()) return initialFile;

    final String directory = initialFile.parent.path;
    final String nameWithoutExtension = initialFile.nameWithoutExtension;
    final String extension = initialFile.extension;

    int counter = 1;
    while (true) {
      final String newName = '$nameWithoutExtension($counter)$extension';
      final candidate = File('$directory${Platform.pathSeparator}$newName');
      if (!candidate.existsSync()) return candidate;
      counter++;
    }
  }

  // ============================================================================
  // VALIDATION OPERATIONS
  // ============================================================================

  /// Validates that a directory exists and is accessible.
  ///
  /// [directory] Directory to validate.
  /// [shouldExist] Whether the directory should exist (default: true).
  FormattingValidationResult validateDirectory(
    final Directory directory, {
    final bool shouldExist = true,
  }) {
    final exists = directory.existsSync();

    if (shouldExist && !exists) {
      return FormattingValidationResult.failure(
        'Directory does not exist: ${directory.path}',
      );
    }

    if (!shouldExist && exists) {
      return FormattingValidationResult.failure(
        'Directory already exists: ${directory.path}',
      );
    }

    if (exists) {
      try {
        // Probe access by listing 1 entry without following links
        directory.listSync(followLinks: false).take(1).toList();
      } catch (_) {
        return FormattingValidationResult.failure(
          'Directory is not accessible: ${directory.path}',
        );
      }
    }

    return const FormattingValidationResult.success();
  }

  /// Validates that a file exists and is readable.
  FormattingValidationResult validateFile(final File file) {
    if (!file.existsSync()) {
      return FormattingValidationResult.failure(
        'File does not exist: ${file.path}',
      );
    }
    try {
      final raf = file.openSync();
      raf.closeSync();
    } catch (_) {
      return FormattingValidationResult.failure(
        'File is not accessible: ${file.path}',
      );
    }
    return const FormattingValidationResult.success();
  }

  // ============================================================================
  // UTILITY OPERATIONS (migrated from UtilityService)
  // ============================================================================

  /// Calculates total number of output artifacts based on album behavior.
  ///
  /// New immutable model semantics:
  /// - "shortcut"  / "reverse-shortcut":
  ///   1 output for the primary + one artifact per album membership.
  /// - "json": one record per primary entity.
  /// - "nothing": only primary entities (those thatoriginally lived in year-based folders).
  /// - "duplicate-copy":
  ///   1 record for each primary and one record per each secondary
  ///
  /// UPDATE (counting rule used by this function):
  /// - We count generated items as follows:
  ///   * "shortcut" / "reverse-shortcut": 1 physical file (primary) + one SHORTCUT per secondary (shortcuts are counted).
  ///   * "json" / "nothing": 1 physical file per primary.
  ///   * "duplicate-copy": 1 physical file per primary + 1 physical file per secondary.
  int calculateOutputFileCount(
    final List<MediaEntity> media,
    final String albumOption,
  ) {
    switch (albumOption) {
      case 'shortcut':
      case 'reverse-shortcut':
        {
          int total = 0;
          for (final MediaEntity e in media) {
            total +=
                1 +
                e.secondaryCount; // 1 physical primary + N shortcuts (counted)
          }
          return total;
        }

      case 'duplicate-copy':
        {
          int total = 0;
          for (final MediaEntity e in media) {
            total +=
                1 + e.secondaryCount; // 1 physical primary + N physical copies
          }
          return total;
        }

      case 'json':
      case 'nothing':
        // 1 physical file per primary entity
        return media.length;

      default:
        throw ArgumentError.value(
          albumOption,
          'albumOption',
          'Unknown album option. Valid options: shortcut, duplicate-copy, reverse-shortcut, json, nothing',
        );
    }
  }

  /// Creates a directory safely (best-effort), returning true if created or already exists.
  Future<bool> safeCreateDirectory(final Directory dir) async {
    final p = dir.path;
    if (p.trim().isEmpty) {
      // Treat empty path as a programmer error; don't attempt to create it.
      return false;
    }
    try {
      await dir.create(recursive: true);
      return true;
    } catch (e) {
      printError('Failed to create directory $p: $e');
      return false;
    }
  }

  /// Exits the program with an optional code, optionally waiting for user input.
  Never exitProgram(
    final int code, {
    final bool showInteractiveMessage = false,
  }) {
    // Allow tests to intercept exit to avoid terminating the test process
    final override = testExitOverride;
    if (override != null) {
      override(code);
      throw _TestExitException(code);
    }

    if (showInteractiveMessage) {
      print(
        '[gpth ${code != 0 ? 'quitted :(' : 'finished :)'} (code $code) - '
        'press enter to close]',
      );
      stdin.readLineSync();
    }
    exit(code);
  }

  // ============================================================================
  // ERROR HANDLING
  // ============================================================================

  /// Prints an error message to stderr with consistent formatting.
  void printError(final Object? message) {
    stderr.writeln('[ERROR] $message');
  }

  /// Prints a warning message to stderr with consistent formatting.
  void printWarning(final Object? message) {
    stderr.writeln('[WARNING] $message');
  }
}

/// Extension for string utility operations.
extension StringUtilityExtensions on String {
  /// Returns the same string if the pattern isn't found; otherwise replaces the last occurrence.
  String replaceLastOcurrence(final String from, final String to) {
    final int lastIndex = lastIndexOf(from);
    if (lastIndex == -1) return this;
    return replaceRange(lastIndex, lastIndex + from.length, to);
  }
}

/// Extension methods for [File] to support utility operations.
extension FileUtilityExtensions on File {
  /// Returns the file name without extension.
  String get nameWithoutExtension {
    final String fullName = uri.pathSegments.last;
    final int lastDot = fullName.lastIndexOf('.');
    return lastDot == -1 ? fullName : fullName.substring(0, lastDot);
  }

  /// Returns the file extension including the leading dot, or empty string if none.
  String get extension {
    final String fullName = uri.pathSegments.last;
    final int lastDot = fullName.lastIndexOf('.');
    return lastDot == -1 ? '' : fullName.substring(lastDot);
  }
}

/// Result of a validation operation.
class FormattingValidationResult {
  const FormattingValidationResult._({required this.isSuccess, this.message});

  /// Creates a successful validation result.
  const FormattingValidationResult.success() : this._(isSuccess: true);

  /// Creates a failed validation result with a message.
  const FormattingValidationResult.failure(final String message)
    : this._(isSuccess: false, message: message);

  /// Whether the validation was successful.
  final bool isSuccess;

  /// Error message if validation failed.
  final String? message;

  /// Whether the validation failed.
  bool get isFailure => !isSuccess;
}

/// Exception thrown by [exitProgram] when test override is active.
class _TestExitException implements Exception {
  const _TestExitException(this.code);
  final int code;

  @override
  String toString() =>
      'Program attempted to exit with code $code. '
      'This indicates a fatal error or completion condition was reached. '
      'In production, this would terminate the application. '
      'Check logs above for the specific cause of termination.';
}
