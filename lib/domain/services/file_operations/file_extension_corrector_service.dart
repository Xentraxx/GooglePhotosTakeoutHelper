import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../../shared/extensions/file_extensions.dart';
import '../core/logging_service.dart';
import '../media/mime_type_service.dart';
import '../metadata/json_metadata_matcher_service.dart';
import '../processing/edited_version_detector_service.dart';

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
  static const EditedVersionDetectorService _extrasService =
      EditedVersionDetectorService();

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
        'Detected AVI file incorrectly named as .mp4: ${p.basename(file.path)}',
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
        'for file ${p.basename(file.path)}',
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

    // Find and rename associated JSON file
    final File? jsonFile = await _findJsonFile(file);
    try {
      // Store original paths for verification
      final String originalFilePath = file.path;
      final String? originalJsonPath = jsonFile?.path;

      // Rename the media file
      final File renamedFile = await file.rename(newFilePath);

      // Verify the rename was successful
      if (!await renamedFile.exists()) {
        logError(
          'Renamed file does not exist after rename operation: $newFilePath',
        );
        return false;
      }

      // Verify the original file was actually removed
      if (await File(originalFilePath).exists()) {
        logError(
          'Original file still exists after rename operation. This indicates a failed rename: $originalFilePath',
        );
        // Try to clean up by deleting the original file if the new file exists
        try {
          await File(originalFilePath).delete();
          logWarning(
            'Manually deleted original file after failed rename: $originalFilePath',
          );
        } catch (deleteError) {
          logError(
            'Failed to delete original file after rename failure: $deleteError',
          );
          return false;
        }
      }

      // Rename the JSON file if it exists
      if (jsonFile != null && jsonFile.existsSync()) {
        final String jsonNewPath = '$newFilePath.json';
        try {
          final File renamedJsonFile = await jsonFile.rename(jsonNewPath);

          // Verify JSON rename was successful
          if (!await renamedJsonFile.exists()) {
            logWarning(
              'Renamed JSON file does not exist after rename operation: $jsonNewPath',
            );
          }

          // Verify original JSON file was removed
          if (originalJsonPath != null &&
              await File(originalJsonPath).exists()) {
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
            }
          }
        } catch (jsonRenameError) {
          logWarning(
            'Failed to rename JSON file ${jsonFile.path}: $jsonRenameError',
          );
          // Don't fail the entire operation if JSON rename fails
        }
      }

      logInfo(
        'Fixed extension: ${p.basename(originalFilePath)} -> ${p.basename(newFilePath)}',
      );
      return true;
    } catch (e) {
      logError('Failed to rename file ${file.path}: $e');
      return false;
    }
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
          'Found JSON file with tryHard methods: ${p.basename(jsonFile.path)}',
        );
      }
    }

    return jsonFile;
  }

  /// Returns the preferred file extension for a given MIME type
  String? _getPreferredExtension(final String mimeType) =>
      _mimeTypeService.getPreferredExtension(mimeType);
}
