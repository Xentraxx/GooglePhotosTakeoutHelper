import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';
import 'package:gpth/gpth-lib.dart';

/// Service for creating Windows symbolic links using Win32 API
///
/// This service creates symbolic links on Windows using the native Win32 API,
/// providing better compatibility with cloud services and file type detection
/// compared to .lnk shortcut files.
class WindowsSymlinkService with LoggerMixin {
  /// Creates a new instance of WindowsSymlinkService
  WindowsSymlinkService();

  /// Creates a Windows symbolic link using native Win32 API
  ///
  /// [symlinkPath] Path where the symbolic link will be created
  /// [targetPath] Path to the target file/folder
  /// Throws Exception if symlink creation fails
  Future<void> createSymlink(
    final String symlinkPath,
    final String targetPath,
  ) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('This service is only supported on Windows');
    }

    // Ensure target path is absolute
    final String absoluteTargetPath = p.isAbsolute(targetPath)
        ? targetPath
        : p.absolute(targetPath);

    // Thread-safe directory creation with retry logic for race conditions
    final Directory parentDir = Directory(p.dirname(symlinkPath));
    await _ensureDirectoryExistsSafe(parentDir);

    // Thread-safe target existence verification with retry
    await _verifyTargetExistsSafe(absoluteTargetPath);

    // Create symlink using Win32 API, fall back to Dart's Link if needed
    try {
      await _createSymlinkNative(symlinkPath, absoluteTargetPath);
    } catch (e) {
      logDebug('Win32 symlink creation failed, falling back to Dart Link: $e');
      // Fall back to Dart's Link implementation
      await _createSymlinkDart(symlinkPath, absoluteTargetPath);
    }
  }

  /// Safely ensures a directory exists, handling race conditions
  ///
  /// [directory] The directory to create
  /// Retries up to 3 times with delays to handle concurrent creation
  Future<void> _ensureDirectoryExistsSafe(final Directory directory) async {
    const int maxRetries = 3;
    const Duration retryDelay = Duration(milliseconds: 50);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        return; // Success
      } catch (e) {
        if (attempt == maxRetries) {
          throw Exception(
            'Failed to create directory after $maxRetries attempts: $e',
          );
        }
        await Future.delayed(retryDelay);
      }
    }
  }

  /// Safely verifies target existence with retry logic
  ///
  /// [targetPath] Path to verify
  /// Retries up to 3 times to handle file system delays
  Future<void> _verifyTargetExistsSafe(final String targetPath) async {
    const int maxRetries = 3;
    const Duration retryDelay = Duration(milliseconds: 50);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (File(targetPath).existsSync() || Directory(targetPath).existsSync()) {
        return; // Target exists
      }

      if (attempt == maxRetries) {
        throw Exception('Target path does not exist: $targetPath');
      }

      // Small delay to handle file system propagation delays
      await Future.delayed(retryDelay);
    }
  }

  /// Creates a Windows symbolic link using native Win32 API
  ///
  /// [symlinkPath] Path where the symbolic link will be created
  /// [targetPath] Path to the target file/folder
  /// Throws Exception if Win32 API calls fail
  Future<void> _createSymlinkNative(
    final String symlinkPath,
    final String targetPath,
  ) async {
    // Run the synchronous symlink operations in a separate isolate to avoid blocking
    await Isolate.run(() => _createSymlinkSync(symlinkPath, targetPath));
  }

  /// Synchronous symlink creation using Win32 API
  ///
  /// [symlinkPath] Path where the symbolic link will be created
  /// [targetPath] Path to the target file/folder
  void _createSymlinkSync(final String symlinkPath, final String targetPath) {
    using((final Arena arena) {
      // Convert paths to native UTF16
      final symlinkPathPtr = symlinkPath.toNativeUtf16(allocator: arena);
      final targetPathPtr = targetPath.toNativeUtf16(allocator: arena);

      // Delete existing symlink if it exists
      final existingAttributes = GetFileAttributes(symlinkPathPtr);
      if (existingAttributes != 0xFFFFFFFF) {
        // INVALID_FILE_ATTRIBUTES
        if ((existingAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
          // It's a reparse point (symlink), delete it
          DeleteFile(symlinkPathPtr);
        }
      }

      // Determine if target is a directory
      final targetAttributes = GetFileAttributes(targetPathPtr);
      final isDirectory =
          targetAttributes != 0xFFFFFFFF && // INVALID_FILE_ATTRIBUTES
          (targetAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;

      // Create symbolic link
      // SYMBOLIC_LINK_FLAG_DIRECTORY = 0x1 for directories, 0x0 for files
      // SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE = 0x2 (Windows 10 Creator Update+)
      final flags = (isDirectory ? 0x1 : 0x0) | 0x2;

      final result = CreateSymbolicLink(symlinkPathPtr, targetPathPtr, flags);

      if (result == 0) {
        final error = GetLastError();
        throw Exception(
          'Failed to create symbolic link: Win32 error 0x${error.toRadixString(16)}. '
          'Note: Creating symlinks may require Developer Mode to be enabled on Windows 10/11.',
        );
      }

      logDebug(
        'Successfully created symbolic link: $symlinkPath -> $targetPath',
      );
    });
  }

  /// Creates a symbolic link using Dart's Link class as fallback
  ///
  /// [symlinkPath] Path where the symbolic link will be created
  /// [targetPath] Path to the target file/folder
  Future<void> _createSymlinkDart(
    final String symlinkPath,
    final String targetPath,
  ) async {
    // Use relative path to prevent breaking when folders are moved
    final String targetRelativePath = p.relative(
      targetPath,
      from: p.dirname(symlinkPath),
    );

    // Delete existing link if it exists
    final existingLink = Link(symlinkPath);
    if (await existingLink.exists()) {
      await existingLink.delete();
    }

    final link = await Link(symlinkPath).create(targetRelativePath);

    logDebug(
      'Successfully created symbolic link using Dart Link: ${link.path} -> $targetRelativePath',
    );
  }
}
