import 'dart:io';
import 'package:proper_filesize/proper_filesize.dart';
import 'package:gpth/gpth-lib.dart';


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

  /// Formats byte count into human-readable file size string
  ///
  /// Consolidates functionality from:
  /// - UtilityService.formatFileSize()
  /// - FileSystemService.formatFileSize()
  /// - InteractiveConfigurationService._formatBytes()
  ///
  /// [bytes] Number of bytes to format
  /// Returns formatted string like "1.5 MB"
  String formatFileSize(final int bytes) {
    if (bytes < 0) return '0 B';
    if (bytes == 0) return '0 B';

    return FileSize.fromBytes(bytes).toString(
      unit: Unit.auto(size: bytes, baseType: BaseType.metric),
      decimals: 2,
    );
  }

  /// Formats duration to human-readable string
  ///
  /// [duration] Duration object to format
  /// Returns formatted string like "1m 30s" or "45s"
  String formatDuration(final Duration duration) {
    final seconds = duration.inSeconds;

    if (seconds < 60) {
      return '${seconds}s';
    }

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

  /// Formats a number with thousand separators
  ///
  /// [number] Number to format
  /// Returns formatted string like "1,234,567"
  String formatNumber(final int number) => number.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (final Match match) => '${match[1]},',
  );

  // ============================================================================
  // FILE OPERATIONS
  // ============================================================================

  /// Creates a unique file name by appending (1), (2), etc. until non-existing
  ///
  /// Consolidates functionality from:
  /// - FileSystemService.findUniqueFileName()
  /// - FileOperationService.findUniqueFileName()
  ///
  /// [initialFile] The desired file path
  /// Returns a File object with a unique path that doesn't exist
  File findUniqueFileName(final File initialFile) {
    if (!initialFile.existsSync()) {
      return initialFile;
    }

    final String directory = initialFile.parent.path;
    final String nameWithoutExtension = initialFile.nameWithoutExtension;
    final String extension = initialFile.extension;

    int counter = 1;
    File candidateFile;

    do {
      final String newName = '$nameWithoutExtension($counter)$extension';
      candidateFile = File('$directory${Platform.pathSeparator}$newName');
      counter++;
    } while (candidateFile.existsSync());

    return candidateFile;
  }

  // ============================================================================
  // VALIDATION OPERATIONS
  // ============================================================================

  /// Validates that a directory exists and is accessible
  ///
  /// [directory] Directory to validate
  /// [shouldExist] Whether the directory should exist (default: true)
  /// Returns validation result with success/failure and message
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

    // Check if directory is accessible (try to list contents)
    if (exists) {
      try {
        directory.listSync(followLinks: false).take(1).toList();
      } catch (e) {
        return FormattingValidationResult.failure(
          'Directory is not accessible: ${directory.path}',
        );
      }
    }

    return const FormattingValidationResult.success();
  }

  /// Validates that a file exists and is readable
  ///
  /// [file] File to validate
  /// Returns validation result with success/failure and message
  FormattingValidationResult validateFile(final File file) {
    if (!file.existsSync()) {
      return FormattingValidationResult.failure('File does not exist: ${file.path}');
    }

    try {
      // Try to read the first byte to check accessibility
      final randomAccess = file.openSync();
      randomAccess.closeSync();
    } catch (e) {
      return FormattingValidationResult.failure('File is not accessible: ${file.path}');
    }

    return const FormattingValidationResult.success();
  }
  // ============================================================================
  // UTILITY OPERATIONS (migrated from UtilityService)
  // ============================================================================

  /// Calculates total number of output files based on album behavior
  ///
  /// [media] List of media entities
  /// [albumOption] Album handling option ('shortcut', 'duplicate-copy', etc.)
  /// Returns expected number of output files
  int calculateOutputFileCount(
    final List<MediaEntity> media,
    final String albumOption,
  ) {
    if (<String>[
      'shortcut',
      'duplicate-copy',
      'reverse-shortcut',
    ].contains(albumOption)) {
      return media.fold(
        0,
        (final int prev, final MediaEntity e) => prev + e.files.files.length,
      );
    } else if (albumOption == 'json') {
      return media.length;
    } else if (albumOption == 'nothing') {
      return media
          .where((final MediaEntity e) => e.files.hasYearBasedFiles)
          .length;
    } else {
      throw ArgumentError.value(albumOption, 'albumOption');
    }
  }

  /// Safely creates directory with error handling
  Future<bool> safeCreateDirectory(final Directory dir) async {
    final path = dir.path;
    // Guard against empty or whitespace-only paths which can behave
    // inconsistently across platforms (macOS throws, Windows may resolve to cwd)
    if (path.trim().isEmpty) {
      // Treat empty path as programmer error; return false consistently without noisy logging
      return false;
    }
    try {
      await dir.create(recursive: true);
      return true;
    } catch (e) {
      printError('Failed to create directory $path: $e');
      return false;
    }
  }

  /// Exits the program with optional code, showing interactive message if needed
  ///
  /// [code] Exit code (default: 1)
  /// [showInteractiveMessage] Whether to show press-enter prompt
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

  /// Prints error message to stderr with consistent formatting
  ///
  /// [message] Error message to print
  void printError(final Object? message) {
    stderr.writeln('[ERROR] $message');
  }

  /// Prints warning message to stderr with consistent formatting
  ///
  /// [message] Warning message to print
  void printWarning(final Object? message) {
    stderr.writeln('[WARNING] $message');
  }
}

/// Extension for string utility operations
extension StringUtilityExtensions on String {
  /// Returns same string if pattern not found, otherwise replaces last occurrence
  String replaceLastOcurrence(final String from, final String to) {
    final int lastIndex = lastIndexOf(from);
    if (lastIndex == -1) return this;
    return replaceRange(lastIndex, lastIndex + from.length, to);
  }
}

/// Extension methods for File class to support utility operations
extension FileUtilityExtensions on File {
  /// Gets the file name without extension
  String get nameWithoutExtension {
    final String fullName = uri.pathSegments.last;
    final int lastDot = fullName.lastIndexOf('.');
    return lastDot == -1 ? fullName : fullName.substring(0, lastDot);
  }

  /// Gets the file extension including the dot
  String get extension {
    final String fullName = uri.pathSegments.last;
    final int lastDot = fullName.lastIndexOf('.');
    return lastDot == -1 ? '' : fullName.substring(lastDot);
  }
}

/// Result of a validation operation
class FormattingValidationResult {
  const FormattingValidationResult._({required this.isSuccess, this.message});

  /// Creates a successful validation result
  const FormattingValidationResult.success() : this._(isSuccess: true);

  /// Creates a failed validation result with message
  const FormattingValidationResult.failure(final String message)
    : this._(isSuccess: false, message: message);

  /// Whether the validation was successful
  final bool isSuccess;

  /// Error message if validation failed
  final String? message;

  /// Whether the validation failed
  bool get isFailure => !isSuccess;
}

/// Exception thrown by exitProgram when test override is active
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
