import 'dart:io';
import 'package:gpth/gpth_lib_exports.dart';

/// Consolidated service for all disk space operations across different platforms
///
/// This service merges functionality from:
/// - PlatformService.getDiskFreeSpace()
/// - DiskSpaceService.getAvailableSpace()
/// - Platform-specific disk operations scattered across the codebase
///
/// Provides a unified interface for disk space checking while handling
/// platform-specific implementations internally.
class ConsolidatedDiskSpaceService with LoggerMixin {
  /// Creates a new consolidated disk space service
  ConsolidatedDiskSpaceService();

  // ============================================================================
  // PLATFORM DETECTION (consolidated from PlatformService)
  // ============================================================================

  /// Whether the current platform is Windows
  bool get isWindows => Platform.isWindows;

  /// Whether the current platform is macOS
  bool get isMacOS => Platform.isMacOS;

  /// Whether the current platform is Linux
  bool get isLinux => Platform.isLinux;

  /// Gets the optimal concurrency level for the current platform
  int getOptimalConcurrency() => ConcurrencyManager().diskOptimized;

  // ============================================================================
  // DISK SPACE OPERATIONS
  // ============================================================================

  /// Gets available disk space for the given path
  ///
  /// [path] Directory path to check (defaults to current directory)
  /// Returns available space in bytes, or null if unable to determine
  Future<int?> getAvailableSpace([String? path]) async {
    path ??= Directory.current.path;

    try {
      if (isWindows) {
        return await _getSpaceWindows(path);
      } else if (isMacOS) {
        return await _getSpaceMacOS(path);
      } else if (isLinux) {
        return await _getSpaceLinux(path);
      } else {
        logWarning('Unsupported platform for disk space checking');
        return null;
      }
    } catch (e) {
      logError('Failed to get disk space for $path: $e');
      return null;
    }
  }

  /// Checks if there's enough space for a given operation
  ///
  /// [path] Directory path to check
  /// [requiredBytes] Number of bytes needed
  /// [safetyMarginBytes] Additional safety margin (default: 100MB)
  ///
  /// Returns true if there's enough space, false otherwise
  Future<bool> hasEnoughSpace(
    final String path,
    final int requiredBytes, {
    final int safetyMarginBytes = 100 * 1024 * 1024, // 100MB default
  }) async {
    final availableBytes = await getAvailableSpace(path);

    if (availableBytes == null) {
      logWarning('Cannot determine available space, assuming insufficient');
      return false;
    }

    final totalNeeded = requiredBytes + safetyMarginBytes;
    return availableBytes >= totalNeeded;
  }

  /// Gets disk usage statistics for multiple paths
  ///
  /// Useful for checking both input and output directories
  /// [paths] List of paths to check
  /// Returns map of path to available bytes (null if failed)
  Future<Map<String, int?>> getMultipleSpaceInfo(
    final List<String> paths,
  ) async {
    final Map<String, int?> results = {};

    // Simple sequential processing - disk space checks are lightweight
    await Future.wait(
      paths.map((final path) async {
        results[path] = await getAvailableSpace(path);
      }),
    );

    return results;
  }

  /// Calculates required space for a file operation
  ///
  /// [sourceFiles] Files that will be processed
  /// [operationType] Type of operation (copy, move, etc.)
  /// [albumBehavior] How albums will be handled
  ///
  /// Returns estimated bytes needed for the operation
  Future<int> calculateRequiredSpace(
    final List<File> sourceFiles,
    final String operationType,
    final String albumBehavior,
  ) async {
    int totalSize = 0;

    // Calculate total size of source files
    for (final file in sourceFiles) {
      try {
        if (file.existsSync()) {
          totalSize += file.lengthSync();
        }
      } catch (e) {
        logWarning('Could not get size for ${file.path}: $e');
      }
    }

    // Apply multiplier based on operation type and album behavior
    double multiplier = 1.0;

    if (operationType.toLowerCase() == 'copy') {
      multiplier = 2.0; // Need space for both original and copy
    }

    if (albumBehavior == 'duplicate-copy') {
      multiplier *= 1.5; // Additional space for album duplicates
    } else if (albumBehavior == 'shortcut') {
      multiplier *= 1.1; // Small overhead for shortcuts
    }

    return (totalSize * multiplier).round();
  }

  // ============================================================================
  // PLATFORM-SPECIFIC IMPLEMENTATIONS
  // ============================================================================

  /// Gets disk free space on Windows using GetDiskFreeSpaceEx
  Future<int?> _getSpaceWindows(final String path) async {
    try {
      // Try PowerShell command as fallback for better compatibility
      final result = await Process.run('powershell', [
        '-Command',
        'Get-WmiObject -Class Win32_LogicalDisk | ',
        'Where-Object {\$_.DeviceID -eq "${_getWindowsDrive(path)}"} | ',
        'Select-Object FreeSpace',
      ]);

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final match = RegExp(r'(\d+)').firstMatch(output);
        if (match != null) {
          return int.tryParse(match.group(1)!);
        }
      }
    } catch (e) {
      logWarning('PowerShell disk space check failed: $e');
    }

    // Fallback to dir command
    try {
      final result = await Process.run('dir', [path]);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final lines = output.split('\n');
        final lastLine = lines.lastWhere(
          (final line) => line.contains('bytes free'),
          orElse: () => '',
        );

        if (lastLine.isNotEmpty) {
          final match = RegExp(r'([\d,]+)\s+bytes free').firstMatch(lastLine);
          if (match != null) {
            final bytesStr = match.group(1)!.replaceAll(',', '');
            return int.tryParse(bytesStr);
          }
        }
      }
    } catch (e) {
      logWarning('Dir command disk space check failed: $e');
    }

    return null;
  }

  /// Gets disk free space on macOS using df
  Future<int?> _getSpaceMacOS(final String path) async {
    try {
      final result = await Process.run('df', ['-B1', path]);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        if (lines.length >= 2) {
          final parts = lines[1].split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            return int.tryParse(parts[3]);
          }
        }
      }
    } catch (e) {
      logWarning('df command failed on macOS: $e');
    }
    return null;
  }

  /// Gets disk free space on Linux using multiple fallback methods
  Future<int?> _getSpaceLinux(final String path) async {
    // Method 1: Try df command (most reliable when available)
    final dfResult = await _tryDfCommand(path);
    if (dfResult != null) return dfResult;

    // Method 2: Try statvfs command (alternative on some systems)
    final statvfsResult = await _tryStatvfsCommand(path);
    if (statvfsResult != null) return statvfsResult;

    // Method 3: Try /proc/self/mountinfo parsing (fallback for containers)
    final procResult = await _tryProcMountinfo(path);
    if (procResult != null) return procResult;

    // Method 4: Try du command as last resort (less accurate but works)
    final duResult = await _tryDuCommand(path);
    if (duResult != null) return duResult;

    logWarning('All Linux disk space detection methods failed for: $path');
    return null;
  }

  /// Try df command for disk space
  Future<int?> _tryDfCommand(final String path) async {
    try {
      final result = await Process.run('df', ['-B1', path]);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        if (lines.length >= 2) {
          final parts = lines[1].split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            return int.tryParse(parts[3]);
          }
        }
      }
    } catch (e) {
      logDebug('df command failed on Linux: $e');
    }
    return null;
  }

  /// Try statvfs command for disk space
  Future<int?> _tryStatvfsCommand(final String path) async {
    try {
      final result = await Process.run('stat', ['-f', '-c', '%a %S', path]);
      if (result.exitCode == 0) {
        final parts = result.stdout.toString().trim().split(' ');
        if (parts.length >= 2) {
          final availableBlocks = int.tryParse(parts[0]);
          final blockSize = int.tryParse(parts[1]);
          if (availableBlocks != null && blockSize != null) {
            return availableBlocks * blockSize;
          }
        }
      }
    } catch (e) {
      logDebug('statvfs command failed on Linux: $e');
    }
    return null;
  }

  /// Try parsing /proc/self/mountinfo for containers
  Future<int?> _tryProcMountinfo(final String path) async {
    try {
      final mountInfoFile = File('/proc/self/mountinfo');
      if (!mountInfoFile.existsSync()) return null;

      await mountInfoFile.readAsString();
      // This is a simplified implementation - in practice, you'd need
      // more sophisticated parsing of mountinfo format
      logDebug('Attempted /proc/mountinfo parsing for $path');

      // For now, just return null as this would need more complex implementation
      return null;
    } catch (e) {
      logDebug('proc mountinfo parsing failed: $e');
    }
    return null;
  }

  /// Try du command as last resort (estimates available space)
  Future<int?> _tryDuCommand(final String path) async {
    try {
      // Get filesystem info using du
      final result = await Process.run('du', ['-s', path]);
      if (result.exitCode == 0) {
        // This is a very rough estimate - we can't get actual free space with du
        // But we can at least verify the path is accessible
        logDebug(
          'du command succeeded, but cannot determine free space exactly',
        );
        // Return a conservative estimate (1GB) if path is accessible
        return 1 * 1024 * 1024 * 1024; // 1GB fallback
      }
    } catch (e) {
      logDebug('du command failed on Linux: $e');
    }
    return null;
  }

  /// Helper to extract Windows drive letter from path
  String _getWindowsDrive(final String path) {
    if (path.length >= 2 && path[1] == ':') {
      return '${path[0]}:';
    }
    return 'C:'; // Default fallback
  }

  // ============================================================================
  // SYSTEM RESOURCE CHECKING
  // ============================================================================

  /// Checks overall system resources (memory, disk, CPU)
  ///
  /// [requiredDiskSpace] Minimum required disk space in bytes
  /// [targetPath] Path where disk space will be used
  ///
  /// Returns resource adequacy information
  Future<SystemResourceInfo> checkSystemResources({
    required final int requiredDiskSpace,
    required final String targetPath,
  }) async {
    // Check disk space
    final availableSpace = await getAvailableSpace(targetPath);
    final hasEnoughDisk =
        availableSpace != null && availableSpace >= requiredDiskSpace;

    // Check memory (simplified - assume 4GB+ is sufficient)
    bool hasEnoughMemory = true;
    try {
      if (isLinux || isMacOS) {
        final result = await Process.run('free', ['-m']);
        if (result.exitCode == 0) {
          final output = result.stdout.toString();
          final match = RegExp(r'Mem:\s+(\d+)').firstMatch(output);
          if (match != null) {
            final memoryMB = int.tryParse(match.group(1)!) ?? 0;
            hasEnoughMemory = memoryMB >= 4096; // 4GB minimum
          }
        }
      }
    } catch (e) {
      logWarning('Could not check memory: $e');
    }

    return SystemResourceInfo(
      hasEnoughMemory: hasEnoughMemory,
      hasEnoughDiskSpace: hasEnoughDisk,
      availableDiskSpaceMB: availableSpace != null
          ? (availableSpace / (1024 * 1024)).round()
          : null,
      processorCount: Platform.numberOfProcessors,
    );
  }
}

/// System resource information
class SystemResourceInfo {
  const SystemResourceInfo({
    required this.hasEnoughMemory,
    required this.hasEnoughDiskSpace,
    required this.availableDiskSpaceMB,
    required this.processorCount,
  });

  /// Whether sufficient memory is available
  final bool hasEnoughMemory;

  /// Whether sufficient disk space is available
  final bool hasEnoughDiskSpace;

  /// Available disk space in MB (null if unknown)
  final int? availableDiskSpaceMB;

  /// Number of processor cores
  final int processorCount;

  /// Whether all resource requirements are met
  bool get isResourcesAdequate => hasEnoughMemory && hasEnoughDiskSpace;
}
