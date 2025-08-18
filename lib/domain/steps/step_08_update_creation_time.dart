import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:console_bars/console_bars.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../models/pipeline_step_model.dart';

/// Step 8: Update creation times (Windows only)
///
/// This Windows-specific final step synchronizes file creation timestamps with their
/// modification times to ensure proper chronological sorting in Windows Explorer and
/// other file managers that rely on creation time for organization.
///
/// ## Purpose and Rationale
///
/// ### Windows File System Behavior
/// - **Creation vs Modification Time**: Windows tracks both creation and modification timestamps
/// - **File Manager Sorting**: Windows Explorer often sorts by creation time by default
/// - **Photo Viewer Behavior**: Many photo viewers use creation time for chronological display
/// - **Backup Software**: Some backup tools rely on creation time for change detection
///
/// ### Google Photos Export Issues
/// - **Incorrect Creation Times**: Exported files often have creation time = export time
/// - **Chronological Confusion**: Photos appear in wrong order due to export timestamps
/// - **Date Mismatch**: Creation time doesn't match actual photo date
/// - **User Experience**: Confusing timeline when browsing organized photos
///
/// ## Processing Logic
///
/// ### Timestamp Synchronization
/// 1. **Source Timestamp**: Uses the file's current last modification time
/// 2. **Target Timestamp**: Sets creation time to match modification time
/// 3. **Preservation**: Maintains all other file attributes and metadata
/// 4. **Verification**: Confirms timestamp update was successful
///
/// ### Platform Detection
/// - **Windows Only**: Operation is only performed on Windows systems
/// - **Graceful Skipping**: Silently skips on non-Windows platforms
/// - **Cross-Platform Compatibility**: Uses Dart's Platform detection for safety
///
/// ## Configuration and Control
///
/// ### User Options
/// - **Enable/Disable**: Controlled by `updateCreationTime` configuration flag
/// - **Verbose Logging**: Provides detailed progress when verbose mode enabled
/// - **Error Reporting**: Reports any files that couldn't be updated
/// - **Statistics**: Tracks number of files successfully updated
///
/// ### Safety Features
/// - **Non-Destructive**: Only modifies timestamps, never file content
/// - **Error Recovery**: Continues processing if individual files fail
/// - **Permission Respect**: Skips files that can't be modified due to permissions
///
/// ### Step Sequencing
/// - **Final Step**: Runs as the last step after all file operations complete
/// - **Post-Processing**: Applied after files are in their final locations
/// - **Non-Critical**: Failure doesn't affect core functionality
/// - **Optional**: Can be safely skipped without affecting main workflow
///
/// ### Prerequisites
/// - **Completed File Organization**: Files must be in final output locations
/// - **Windows Platform**: Only runs on Windows operating systems
/// - **Configuration Flag**: Must be explicitly enabled by user
/// - **File Accessibility**: Files must be writable for timestamp modification
///
/// ## Benefits and Use Cases
///
/// ### User Experience Improvements
/// - **Chronological Browsing**: Photos appear in correct order in Windows Explorer
/// - **Date-Based Organization**: File managers can properly sort by creation date
/// - **Photo Viewer Compatibility**: Improves experience with Windows photo applications
/// - **Backup Software**: Ensures backup tools see correct file dates
///
/// ### Professional Workflows
/// - **Digital Asset Management**: Supports professional photo management workflows
/// - **Archive Organization**: Improves long-term photo archive organization
/// - **Client Delivery**: Ensures photos are properly timestamped for client delivery
/// - **System Integration**: Better integration with Windows-based photo workflows
///
/// ## Technical Considerations
///
/// ### File System Impact
/// - **Minimal Overhead**: Very low impact on file system performance
/// - **Journal Updates**: May trigger file system journal updates
/// - **Index Updates**: May cause Windows Search index updates
/// - **Backup Impact**: May affect incremental backup change detection
///
/// ### Security and Permissions
/// - **User Permissions**: Respects current user's file permissions
/// - **Administrator Rights**: May require elevated permissions for some files
/// - **Security Descriptors**: Preserves file security information
/// - **Audit Trails**: May generate file system audit events
class UpdateCreationTimeStep extends ProcessingStep {
  const UpdateCreationTimeStep() : super('Update Creation Time');

  @override
  Future<StepResult> execute(final ProcessingContext context) async {
    final stopwatch = Stopwatch()..start();

    try {
      if (!Platform.isWindows || !context.config.updateCreationTime) {
        final reason = !Platform.isWindows
            ? 'not supported on this platform'
            : 'disabled in configuration';
        print('\n[Step 8/8] Skipping creation time update ($reason).');

        stopwatch.stop();
        return StepResult.success(
          stepName: name,
          duration: stopwatch.elapsed,
          data: {'updatedCount': 0, 'skipped': true},
          message: 'Creation time update skipped',
        );
      }
      if (context.config.verbose) {
        print('\n[Step 8/8] Updating creation times...');
      }

      int updatedCount = 0;

      // 1. Traverse the output directory and update creation times
      final outputDir = Directory(context.config.outputPath);
      if (!await outputDir.exists()) {
        if (context.config.verbose) {
          print(
            'Output directory does not exist, skipping creation time update',
          );
        }

        stopwatch.stop();
        return StepResult.success(
          stepName: name,
          duration: stopwatch.elapsed,
          data: {'updatedCount': 0, 'skipped': true},
          message: 'Creation time update skipped - output directory not found',
        );
      } // 2. For each file, set creation time = last modified time
      // 3. Use Windows APIs/PowerShell for the operation
      updatedCount = await _updateCreationTimeRecursively(outputDir);

      if (context.config.verbose) {
        print('Creation time update completed. Updated $updatedCount files.');
      }

      stopwatch.stop();
      return StepResult.success(
        stepName: name,
        duration: stopwatch.elapsed,
        data: {'updatedCount': updatedCount, 'skipped': false},
        message: 'Updated creation times for $updatedCount files',
      );
    } catch (e) {
      stopwatch.stop();
      return StepResult.failure(
        stepName: name,
        duration: stopwatch.elapsed,
        error: e is Exception ? e : Exception(e.toString()),
        message: 'Failed to update creation times: $e',
      );
    }
  }

  @override
  bool shouldSkip(final ProcessingContext context) =>
      !Platform.isWindows || !context.config.updateCreationTime;

  /// Updates creation times recursively for all files in the directory
  ///
  /// Returns the number of files processed
  Future<int> _updateCreationTimeRecursively(final Directory directory) async {
    // Collect all files first to show progress
    final List<File> allFiles = [];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        allFiles.add(entity);
      }
    }

    if (allFiles.isEmpty) {
      print('No files found to update creation times');
      return 0;
    }

    // Initialize progress bar - always visible
    final progressBar = FillingBar(
      desc: 'Updating creation times',
      total: allFiles.length,
      width: 50,
    );

    int successCount = 0;
    int errorCount = 0;

    // Process files with progress reporting
    for (int i = 0; i < allFiles.length; i++) {
      final File file = allFiles[i];

      try {
        if (await _updateFileCreationTimeWin32(file)) {
          successCount++;
        } else {
          errorCount++;
        }
      } catch (e) {
        errorCount++;
        if (errorCount <= 10) {
          // Only show first 10 errors to avoid spam
          print('Failed to update creation time for ${file.path}: $e');
        }
      }

      // Update progress bar
      progressBar.update(i + 1);
      if (i + 1 == allFiles.length) {
        print(''); // Add a newline after progress bar completion
      }

      // Early exit if too many errors (prevents infinite retry scenarios)
      if (errorCount > 100) {
        print(''); // Ensure we're on a new line after progress bar
        print(
          '⚠️  Too many errors ($errorCount), stopping creation time updates',
        );
        break;
      }
    }

    if (errorCount > 0) {
      print('⚠️  Failed to update creation time for $errorCount files');
    }

    return successCount;
  }

  /// Updates creation time for a single file using Win32 API
  ///
  /// Returns true if successful, false otherwise
  Future<bool> _updateFileCreationTimeWin32(final File file) async {
    if (!Platform.isWindows) return false;

    return _updateFileCreationTimeSync(file.path);
  }

  /// Synchronous Win32 creation time update
  bool _updateFileCreationTimeSync(final String filePath) {
    try {
      return using((final Arena arena) {
        // Convert path to wide string for Win32 API
        final Pointer<Utf16> pathPtr = filePath.toNativeUtf16(allocator: arena);

        // Open file handle with write access to attributes
        final int fileHandle = CreateFile(
          pathPtr,
          FILE_WRITE_ATTRIBUTES,
          FILE_SHARE_READ | FILE_SHARE_WRITE,
          nullptr,
          OPEN_EXISTING,
          FILE_ATTRIBUTE_NORMAL,
          NULL,
        );

        if (fileHandle == INVALID_HANDLE_VALUE) {
          return false; // Could not open file
        }

        try {
          // Get current file times
          final Pointer<FILETIME> creationTime = arena<FILETIME>();
          final Pointer<FILETIME> accessTime = arena<FILETIME>();
          final Pointer<FILETIME> writeTime = arena<FILETIME>();

          // Use the Kernel32 API functions from win32 package
          final kernel32 = DynamicLibrary.open('kernel32.dll');
          final getFileTimeFunction = kernel32
              .lookupFunction<
                Int32 Function(
                  IntPtr,
                  Pointer<FILETIME>,
                  Pointer<FILETIME>,
                  Pointer<FILETIME>,
                ),
                int Function(
                  int,
                  Pointer<FILETIME>,
                  Pointer<FILETIME>,
                  Pointer<FILETIME>,
                )
              >('GetFileTime');

          final setFileTimeFunction = kernel32
              .lookupFunction<
                Int32 Function(
                  IntPtr,
                  Pointer<FILETIME>,
                  Pointer<FILETIME>,
                  Pointer<FILETIME>,
                ),
                int Function(
                  int,
                  Pointer<FILETIME>,
                  Pointer<FILETIME>,
                  Pointer<FILETIME>,
                )
              >('SetFileTime');

          final bool getTimesSuccess =
              getFileTimeFunction(
                fileHandle,
                creationTime,
                accessTime,
                writeTime,
              ) !=
              FALSE;

          if (!getTimesSuccess) {
            return false;
          }

          // Set creation time to match write time (last modified time)
          final bool setTimeSuccess =
              setFileTimeFunction(
                fileHandle,
                writeTime, // Set creation time to write time
                accessTime, // Keep access time unchanged
                writeTime, // Keep write time unchanged
              ) !=
              FALSE;

          return setTimeSuccess;
        } finally {
          // Always close the file handle
          CloseHandle(fileHandle);
        }
      });
    } catch (e) {
      // Catch any FFI-related exceptions
      return false;
    }
  }
}
