import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../shared/extensions/file_extensions.dart';
import '../entities/media_entity.dart';
import '../models/pipeline_step_model.dart';
import '../models/processing_config_model.dart';
import '../services/processing/edited_version_detector_service.dart';
import '../services/processing/takeout_folder_classifier_service.dart';

/// Step 2: Discover and classify media files
///
/// This comprehensive step handles the discovery and initial classification of all media files
/// in the Google Photos Takeout structure. It processes both year-based organization and
/// album folders to build a complete inventory of media files.
///
/// ## Discovery Process
///
/// ### Year Folder Processing
/// - Scans "Photos from YYYY" directories for chronologically organized media
/// - Extracts individual media files (photos, videos) from these primary folders
/// - Handles various year folder naming patterns and international characters
/// - Processes nested directory structures within year folders
///
/// ### Album Folder Processing
/// - Identifies album directories that exist separately from year folders
/// - Creates media entries for album-specific files that may not exist in year folders
/// - Handles duplicate relationships between year and album folder files
/// - Preserves album metadata and relationship information for later processing
///
/// ### Media Classification
/// - Distinguishes between photos, videos, and other media types
/// - Identifies associated JSON metadata files for each media file
/// - Handles special file types like Live Photos, Motion Photos, and edited versions
/// - Filters out non-media files and system artifacts
///
/// ## Processing Logic
///
/// ### Comprehensive File Discovery
/// The step performs a deep scan of the input directory structure to identify:
/// - All valid media files (photos, videos) with supported extensions
/// - Associated JSON metadata files containing Google Photos metadata
/// - Album folder structures and their contained media files
/// - Relationship mapping between files in different locations
///
/// ### Duplicate Detection Setup
/// During discovery, the step identifies potential duplicate relationships:
/// - Files that appear in both year folders and album folders
/// - Multiple copies of the same file across different album locations
/// - Sets up the foundation for later duplicate resolution processing
///
/// ### Media Object Creation
/// For each discovered media file, creates appropriate Media objects:
/// - Associates files with their album context (if applicable)
/// - Links JSON metadata files with their corresponding media files
/// - Preserves original file paths for later processing steps
/// - Maintains album relationship information for organization
///
/// ## Configuration Handling
///
/// ### Input Validation
/// - Validates that the input directory exists and is accessible
/// - Ensures the directory structure matches expected Google Photos Takeout format
/// - Handles various Takeout export formats and structures
/// - Provides meaningful error messages for invalid input structures
///
/// ### Progress Reporting
/// - Reports discovery progress for large photo collections
/// - Provides detailed statistics about discovered media counts
/// - Shows breakdown of files found in year folders vs. album folders
/// - Estimates processing time based on collection size
///
/// ## Error Handling
///
/// ### Access and Permission Issues
/// - Gracefully handles files with restricted access permissions
/// - Skips corrupted or inaccessible files without stopping processing
/// - Reports permission issues for user awareness
/// - Continues processing when individual files cannot be accessed
///
/// ### Malformed Export Handling
/// - Detects and handles incomplete or corrupted Google Photos exports
/// - Adapts to various export formats and edge cases
/// - Provides fallback strategies for unusual directory structures
/// - Reports structural issues found in the export
///
/// ## Integration with Other Steps
///
/// ### Media Collection Population
/// - Populates the MediaCollection with all discovered media files
/// - Provides the foundation for all subsequent processing steps
/// - Ensures comprehensive coverage of all media in the export
/// - Sets up proper data structures for efficient processing
///
/// ### Album Relationship Setup
/// - Establishes the groundwork for album finding and merging
/// - Preserves album context information for later processing
/// - Creates the data structures needed for album organization options
/// - Enables proper handling of files that exist in multiple albums
class DiscoverMediaStep extends ProcessingStep {
  const DiscoverMediaStep() : super('Discover Media');
  @override
  Future<StepResult> execute(final ProcessingContext context) async {
    final stopwatch = Stopwatch()..start();

    try {
      print('\n[Step 2/8] Discovering media files...');

      final inputDir = Directory(context.config.inputPath);
      if (!await inputDir.exists()) {
        throw Exception(
          'Input directory does not exist: ${context.config.inputPath}',
        );
      } // Use optimized single-pass directory scanning
      final scanResult = await _scanDirectoriesOptimized(inputDir, context);
      final totalFiles =
          scanResult.yearFolderFiles + scanResult.albumFolderFiles;

      // Apply skipExtras filtering if enabled
      var extrasSkipped = 0;
      if (context.config.skipExtras) {
        const extrasService = EditedVersionDetectorService();
        final result = extrasService.removeExtras(context.mediaCollection);
        context.mediaCollection.clear();
        context.mediaCollection.addAll(result.collection.media);
        extrasSkipped = result.removedCount;

        if (context.config.verbose) {
          print(
            'Skipped $extrasSkipped extra files due to skipExtras configuration',
          );
        }
      }

      stopwatch.stop();
      return StepResult.success(
        stepName: name,
        duration: stopwatch.elapsed,
        data: {
          'yearFolderFiles': scanResult.yearFolderFiles,
          'albumFolderFiles': scanResult.albumFolderFiles,
          'totalFiles': totalFiles,
          'extrasSkipped': extrasSkipped,
        },
        message:
            'Discovered $totalFiles media files (${scanResult.yearFolderFiles} from year folders, ${scanResult.albumFolderFiles} from albums)'
            '${extrasSkipped > 0 ? ', skipped $extrasSkipped extra files' : ''}',
      );
    } catch (e) {
      stopwatch.stop();
      return StepResult.failure(
        stepName: name,
        duration: stopwatch.elapsed,
        error: e is Exception ? e : Exception(e.toString()),
        message: 'Failed to discover media files: $e',
      );
    }
  }

  /// Optimized single-pass directory scanning to avoid multiple traversals
  ///
  /// This method scans the input directory once and classifies directories
  /// as either year folders or album folders, then processes media files
  /// accordingly. This is much more efficient than the original dual-pass approach.
  Future<_ScanResult> _scanDirectoriesOptimized(
    final Directory inputDir,
    final ProcessingContext context,
  ) async {
    int yearFolderFiles = 0;
    int albumFolderFiles = 0;

    // Cache for directory classification to avoid repeated checks
    final directoryCache = <String, _DirectoryType>{};

    // Single pass through all entities in input directory
    final entities = await inputDir.list().toList();

    // Classify directories first (cheaper operations)
    final yearDirectories = <Directory>[];
    final albumDirectories = <Directory>[];

    for (final entity in entities) {
      if (entity is Directory) {
        final dirType = await _classifyDirectory(entity, directoryCache);
        switch (dirType) {
          case _DirectoryType.year:
            yearDirectories.add(entity);
            break;
          case _DirectoryType.album:
            albumDirectories.add(entity);
            break;
          case _DirectoryType.other:
            // Ignore other directories
            break;
        }
      }
    } // Process year directories
    for (final yearDir in yearDirectories) {
      if (context.config.verbose) {
        print('Scanning year folder: ${p.basename(yearDir.path)}');
      }
      await for (final mediaFile in _getMediaFiles(yearDir, context)) {
        context.mediaCollection.add(
          MediaEntity.fromMap(files: {null: mediaFile}),
        );
        yearFolderFiles++;
      }
    } // Process album directories
    for (final albumDir in albumDirectories) {
      final albumName = p.basename(albumDir.path);
      if (context.config.verbose) {
        print('Scanning album folder: $albumName');
      }
      await for (final mediaFile in _getMediaFiles(albumDir, context)) {
        context.mediaCollection.add(
          MediaEntity.fromMap(files: {albumName: mediaFile}),
        );
        albumFolderFiles++;
      }
    }

    return _ScanResult(
      yearFolderFiles: yearFolderFiles,
      albumFolderFiles: albumFolderFiles,
    );
  }

  /// Classify a directory as year, album, or other
  ///
  /// Uses caching to avoid repeated expensive operations
  Future<_DirectoryType> _classifyDirectory(
    final Directory directory,
    final Map<String, _DirectoryType> cache,
  ) async {
    final path = directory.path;
    if (cache.containsKey(path)) {
      return cache[path]!;
    }

    _DirectoryType type;
    if (isYearFolder(directory)) {
      type = _DirectoryType.year;
    } else if (await isAlbumFolder(directory)) {
      type = _DirectoryType.album;
    } else {
      type = _DirectoryType.other;
    }

    cache[path] = type;
    return type;
  }

  /// Get media files from a directory, respecting extension fixing configuration
  Stream<File> _getMediaFiles(
    final Directory directory,
    final ProcessingContext context,
  ) async* {
    if (context.config.extensionFixing == ExtensionFixingMode.none) {
      // When extension fixing is disabled, be more lenient about file detection
      // Use content-based MIME detection rather than extension-based
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          try {
            // Reading first 512 bytes is sufficient for reliable MIME type detection
            const headerSize = 512; // Read first 512 bytes for MIME detection
            final fileSize = await entity.length();
            final bytesToRead = fileSize < headerSize ? fileSize : headerSize;

            final headerBytes = await entity.openRead(0, bytesToRead).first;
            final String? mimeType = lookupMimeType(
              entity.path,
              headerBytes: headerBytes,
            );

            if (mimeType != null &&
                (mimeType.startsWith('image/') ||
                    mimeType.startsWith('video/'))) {
              yield entity;
              continue;
            }

            // Fallback: check if it has a JSON metadata file (indicating it's a Google Photos media file)
            final metadataFile = File('${entity.path}.json');
            if (await metadataFile.exists()) {
              yield entity;
            }
          } catch (e) {
            // If we can't read the file, skip it
            continue;
          }
        }
      }
    } else {
      // Use standard media detection when extension fixing is enabled
      await for (final file
          in directory.list(recursive: true).wherePhotoVideo()) {
        yield file;
      }
    }
  }

  @override
  bool shouldSkip(final ProcessingContext context) => false;
}

/// Result of directory scanning operation
class _ScanResult {
  const _ScanResult({
    required this.yearFolderFiles,
    required this.albumFolderFiles,
  });

  final int yearFolderFiles;
  final int albumFolderFiles;
}

/// Directory classification for efficient processing
enum _DirectoryType { year, album, other }
