import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:gpth/gpth-lib.dart';

/// Service for detecting and fixing incorrect file extensions
///
/// This service analyzes file headers to determine the actual MIME type
/// and renames files when their extensions don't match their content.
/// Common issues include:
/// - Google Photos compressing HEIC to JPEG but keeping original extension
/// - Files incorrectly renamed from AVI to .mp4 during export
/// - Web-downloaded images with generic or incorrect extensions
class FileExtensionCorrectorService with LoggerMixin {
  /// Creates a new file extension corrector service
  FileExtensionCorrectorService() : _mimeTypeService = const MimeTypeService();
  final MimeTypeService _mimeTypeService;
  static const EditedVersionDetectorService _extrasService = EditedVersionDetectorService();

  /// Fixes incorrectly named files by renaming them to match their actual MIME type
  ///
  /// [directory] Directory to scan recursively for media files
  /// [skipJpegFiles] If true, skips files that are actually JPEG (for conservative mode)
  ///
  /// Returns the number of files that were successfully renamed
  Future<int> fixIncorrectExtensions(
    final Directory directory, {
    final bool skipJpegFiles = false,
  }) async {
    int fixedCount = 0;

    await for (final FileSystemEntity file
        in directory.list(recursive: true).wherePhotoVideo()) {
      try {
        final result = await _processFile(File(file.path), skipJpegFiles);
        if (result) {
          fixedCount++;
        }
      } catch (e) {
        logError('Failed to process file ${file.path}: $e');
      }
    }

    return fixedCount;
  }

  /// Processes a single file to check if extension fixing is needed
  Future<bool> _processFile(final File file, final bool skipJpegFiles) async {
    // Read file header to determine actual MIME type
    final List<int> headerBytes = await file.openRead(0, 128).first;
    final String? actualMimeType = lookupMimeType(
      file.path,
      headerBytes: headerBytes,
    );

    // Skip if we can't determine the actual type
    if (actualMimeType == null) {
      return false;
    }

    // Skip JPEG files if in conservative mode
    if (skipJpegFiles && actualMimeType == 'image/jpeg') {
      return false;
    }

    final String? extensionMimeType = lookupMimeType(
      file.path,
    ); // Skip TIFF-based files (like RAW formats) as MIME detection often
    // misidentifies these formats, and renaming could break camera software compatibility
    if (actualMimeType == 'image/tiff') {
      return false;
    }

    // Check if extension matches content
    if (actualMimeType == extensionMimeType) {
      return false; // Extension is correct
    } // Log special cases
    if (extensionMimeType == 'video/mp4' &&
        actualMimeType == 'video/x-msvideo') {
      logDebug(
        'Detected AVI file incorrectly named as .mp4: ${path.basename(file.path)}',
      );
    }

    return _renameFileWithCorrectExtension(file, actualMimeType);
  }

  /// Renames a file to use the correct extension based on its MIME type
  Future<bool> _renameFileWithCorrectExtension(
    final File file,
    final String mimeType,
  ) async {
    final String? newExtension = _getPreferredExtension(mimeType);

    if (newExtension == null) {
      logWarning(
        'Could not determine correct extension for MIME type $mimeType '
        'for file ${path.basename(file.path)}',
      );
      return false;
    }

    final String newFilePath = '${file.path}.$newExtension';
    final File newFile = File(newFilePath);

    // Check if target file already exists
    if (await newFile.exists()) {
      logWarning(
        'Skipped fixing extension because target file already exists: $newFilePath',
      );
      return false;
    } // Skip extra files (edited versions)
    if (_extrasService.isExtra(file.path)) {
      return false;
    }

    // Find associated JSON file before any renaming
    final File? jsonFile = await _findJsonFile(file);

    // Perform atomic rename operation
    return _performAtomicRename(file, newFilePath, jsonFile);
  }

  /// Finds the JSON metadata file associated with a media file
  Future<File?> _findJsonFile(final File file) async {
    // Try quick lookup first
    File? jsonFile = await JsonMetadataMatcherService.findJsonForFile(
      file,
      tryhard: false,
    );

    if (jsonFile == null) {
      // Try harder lookup if quick one failed
      jsonFile = await JsonMetadataMatcherService.findJsonForFile(
        file,
        tryhard: true,
      );
      if (jsonFile == null) {
        logWarning('Unable to find matching JSON for file: ${file.path}');
      } else {
        logDebug(
          'Found JSON file with tryHard methods: ${path.basename(jsonFile.path)}',
        );
      }
    }

    return jsonFile;
  }

  /// Returns the preferred file extension for a given MIME type
  String? _getPreferredExtension(final String mimeType) =>
      _mimeTypeService.getPreferredExtension(mimeType);

  /// Performs atomic rename of both media file and its JSON metadata file
  ///
  /// Either both files are renamed successfully, or both operations are rolled back
  /// to maintain consistency between media files and their metadata.
  Future<bool> _performAtomicRename(
    final File mediaFile,
    final String newMediaPath,
    final File? jsonFile,
  ) async {
    final String originalMediaPath = mediaFile.path;
    final String? originalJsonPath = jsonFile?.path;
    final String? newJsonPath = jsonFile != null ? '$newMediaPath.json' : null;

    // Check if JSON target already exists
    if (newJsonPath != null && await File(newJsonPath).exists()) {
      logWarning(
        'Skipped fixing extension because target JSON file already exists: $newJsonPath',
      );
      return false;
    }

    File? renamedMediaFile;
    File? renamedJsonFile;

    try {
      // Step 1: Rename the media file
      renamedMediaFile = await mediaFile.rename(newMediaPath);

      // Verify media file rename was successful
      if (!await renamedMediaFile.exists()) {
        throw Exception(
          'Media file does not exist after rename: $newMediaPath',
        );
      }

      // Step 2: Rename the JSON file if it exists
      if (jsonFile != null && newJsonPath != null) {
        if (await jsonFile.exists()) {
          renamedJsonFile = await jsonFile.rename(newJsonPath);

          // Verify JSON file rename was successful
          if (!await renamedJsonFile.exists()) {
            throw Exception(
              'JSON file does not exist after rename: $newJsonPath',
            );
          }
        }
      }

      // Step 3: Verify cleanup of original files
      await _verifyOriginalFilesRemoved(originalMediaPath, originalJsonPath);

      logInfo(
        'Fixed extension: ${path.basename(originalMediaPath)} -> ${path.basename(newMediaPath)}',
      );
      return true;
    } catch (e) {
      // Rollback: Attempt to restore original state
      logError('Extension fixing failed, attempting rollback: $e');
      await _rollbackAtomicRename(
        originalMediaPath,
        originalJsonPath,
        renamedMediaFile,
        renamedJsonFile,
      );
      return false;
    }
  }

  /// Attempts to rollback a failed atomic rename operation
  Future<void> _rollbackAtomicRename(
    final String originalMediaPath,
    final String? originalJsonPath,
    final File? renamedMediaFile,
    final File? renamedJsonFile,
  ) async {
    try {
      // Rollback JSON file rename if it was attempted
      if (renamedJsonFile != null && originalJsonPath != null) {
        if (await renamedJsonFile.exists()) {
          await renamedJsonFile.rename(originalJsonPath);
          logInfo('Rolled back JSON file rename: $originalJsonPath');
        }
      }

      // Rollback media file rename
      if (renamedMediaFile != null) {
        if (await renamedMediaFile.exists()) {
          await renamedMediaFile.rename(originalMediaPath);
          logInfo('Rolled back media file rename: $originalMediaPath');
        }
      }
    } catch (rollbackError) {
      logError(
        'Failed to rollback atomic rename operation. Manual cleanup may be required. '
        'Original media: $originalMediaPath, Original JSON: $originalJsonPath. Error: $rollbackError',
      );
    }
  }

  /// Verifies that original files were properly removed after rename
  Future<void> _verifyOriginalFilesRemoved(
    final String originalMediaPath,
    final String? originalJsonPath,
  ) async {
    // Check if original media file still exists
    if (await File(originalMediaPath).exists()) {
      logWarning(
        'Original media file still exists after rename. Attempting manual cleanup: $originalMediaPath',
      );
      try {
        await File(originalMediaPath).delete();
        logInfo('Manually cleaned up original media file: $originalMediaPath');
      } catch (deleteError) {
        throw Exception('Failed to delete original media file: $deleteError');
      }
    }

    // Check if original JSON file still exists
    if (originalJsonPath != null && await File(originalJsonPath).exists()) {
      logWarning(
        'Original JSON file still exists after rename. Attempting manual cleanup: $originalJsonPath',
      );
      try {
        await File(originalJsonPath).delete();
        logInfo(
          'Successfully cleaned up original JSON file: $originalJsonPath',
        );
      } catch (deleteError) {
        logWarning('Failed to delete original JSON file: $deleteError');
        // Don't throw here as this is less critical than media file consistency
      }
    }
  }
}
