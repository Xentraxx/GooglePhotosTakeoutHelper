import 'dart:io';

import '../../infrastructure/exiftool_service.dart';
import '../entities/media_entity.dart';
import '../services/core/logging_service.dart';
import '../services/core/service_container.dart';
import '../services/metadata/date_extraction/json_date_extractor.dart';
import '../services/metadata/exif_writer_service.dart';
import '../value_objects/date_time_extraction_method.dart';
import 'performance_config_model.dart';

/// Modern domain model representing a collection of media entities
///
/// This replaces MediaCollection to use the new immutable MediaEntity
/// throughout the processing pipeline, providing better type safety and performance.
class MediaEntityCollection with LoggerMixin {
  MediaEntityCollection([final List<MediaEntity>? initialMedia])
    : _media = initialMedia ?? [];

  final List<MediaEntity> _media;

  /// Read-only access to the media list
  List<MediaEntity> get media => List.unmodifiable(_media);

  /// Number of media items in the collection
  int get length => _media.length;

  /// Whether the collection is empty
  bool get isEmpty => _media.isEmpty;
  bool get isNotEmpty => _media.isNotEmpty;

  /// Add a single media entity to the collection
  void add(final MediaEntity mediaEntity) {
    _media.add(mediaEntity);
  }

  /// Add multiple media entities to the collection
  void addAll(final Iterable<MediaEntity> mediaEntities) {
    _media.addAll(mediaEntities);
  }

  /// Remove a media entity from the collection
  bool remove(final MediaEntity mediaEntity) => _media.remove(mediaEntity);

  /// Clear all media from the collection
  void clear() {
    _media.clear();
  }

  /// Extract dates from all media entities using configured date extractors
  ///
  /// This method applies date extraction algorithms to media entities that don't
  /// have dates, providing extraction method statistics.
  Future<Map<DateTimeExtractionMethod, int>> extractDates(
    final List<Future<DateTime?> Function(MediaEntity)> extractors, {
    final void Function(int current, int total)? onProgress,
  }) async {
    final extractionStats = <DateTimeExtractionMethod, int>{};

    // Map extractor index to extraction method for proper tracking
    final extractorMethods = [
      DateTimeExtractionMethod.json, // JSON extractor (first priority)
      DateTimeExtractionMethod.exif, // EXIF extractor (second priority)
      DateTimeExtractionMethod.guess, // Filename guess extractor (if enabled)
      DateTimeExtractionMethod.jsonTryHard, // JSON tryhard extractor
      DateTimeExtractionMethod.folderYear, // Folder year extractor (fallback)
    ];

    for (int i = 0; i < _media.length; i++) {
      final mediaFile = _media[i];
      DateTimeExtractionMethod? extractionMethod;

      // Skip if media already has a date
      if (mediaFile.dateTaken != null) {
        extractionMethod =
            mediaFile.dateTimeExtractionMethod ?? DateTimeExtractionMethod.none;
        logDebug(
          'File already has date: ${mediaFile.primaryFile.path} (${extractionMethod.name})',
        );
      } else {
        // Try each extractor in sequence until one succeeds
        bool dateFound = false;
        for (
          int extractorIndex = 0;
          extractorIndex < extractors.length;
          extractorIndex++
        ) {
          final extractor = extractors[extractorIndex];
          final extractedDate = await extractor(mediaFile);

          if (extractedDate != null) {
            // Determine the correct extraction method based on extractor index
            extractionMethod = extractorIndex < extractorMethods.length
                ? extractorMethods[extractorIndex]
                : DateTimeExtractionMethod.guess;

            _media[i] = mediaFile.withDate(
              dateTaken: extractedDate,
              dateTimeExtractionMethod: extractionMethod,
            );

            logInfo(
              'Date extracted for ${mediaFile.primaryFile.path}: $extractedDate (method: ${extractionMethod.name})',
            );
            dateFound = true;
            break;
          }
        }

        if (!dateFound) {
          extractionMethod = DateTimeExtractionMethod.none;
          _media[i] = mediaFile.withDate(
            dateTimeExtractionMethod: DateTimeExtractionMethod.none,
          );
          logInfo('No date found for ${mediaFile.primaryFile.path}');
        }
      }

      extractionStats[extractionMethod!] =
          (extractionStats[extractionMethod] ?? 0) + 1;

      onProgress?.call(i + 1, _media.length);
    }

    return extractionStats;
  }

  /// Write EXIF data to media files
  ///
  /// Updates EXIF metadata for media entities that have date/time information
  /// and coordinate data, tracking success statistics.
  Future<Map<String, int>> writeExifData({
    final void Function(int current, int total)? onProgress,
    final PerformanceConfig? performanceConfig,
  }) async {
    final config = performanceConfig ?? PerformanceConfig.balanced;

    // Check if ExifTool is available before proceeding
    final exifTool = ServiceContainer.instance.exifTool;
    if (exifTool == null) {
      logWarning('ExifTool not available, skipping EXIF data writing');
      return {'coordinatesWritten': 0, 'dateTimesWritten': 0};
    }

    logInfo('[Step 5/8] Starting EXIF data writing for ${_media.length} files');

    if (config.enableParallelProcessing && _media.length > 10) {
      return _writeExifDataParallel(onProgress, config, exifTool);
    } else {
      return _writeExifDataSequential(onProgress, exifTool);
    }
  }

  /// Sequential EXIF writing (original implementation)
  Future<Map<String, int>> _writeExifDataSequential(
    final void Function(int current, int total)? onProgress,
    final ExifToolService exifTool,
  ) async {
    var coordinatesWritten = 0;
    var dateTimesWritten = 0;

    for (int i = 0; i < _media.length; i++) {
      final mediaEntity = _media[i];
      final exifWriter = ExifWriterService(exifTool);

      // Write GPS coordinates to EXIF if available
      try {
        final coordinates = await jsonCoordinatesExtractor(
          mediaEntity.files.firstFile,
        );
        if (coordinates != null) {
          final success = await exifWriter.writeGpsToExif(
            coordinates,
            mediaEntity.files.firstFile,
            ServiceContainer.instance.globalConfig,
          );
          if (success) {
            coordinatesWritten++;
          }
        }
      } catch (e) {
        logWarning(
          'Failed to extract/write GPS coordinates for ${mediaEntity.files.firstFile.path}: $e',
        );
      }

      // Write date/time to EXIF if available and not already from EXIF
      if (mediaEntity.dateTaken != null &&
          mediaEntity.dateTimeExtractionMethod !=
              DateTimeExtractionMethod.exif &&
          mediaEntity.dateTimeExtractionMethod !=
              DateTimeExtractionMethod.none) {
        try {
          final success = await exifWriter.writeDateTimeToExif(
            mediaEntity.dateTaken!,
            mediaEntity.files.firstFile,
            ServiceContainer.instance.globalConfig,
          );
          if (success) {
            dateTimesWritten++;
          }
        } catch (e) {
          logWarning(
            'Failed to write DateTime to EXIF for ${mediaEntity.files.firstFile.path}: $e',
          );
        }
      }

      onProgress?.call(i + 1, _media.length);
    }

    // Log final statistics similar to canonical implementation
    if (coordinatesWritten > 0) {
      logInfo(
        '$coordinatesWritten files got their coordinates set in EXIF data (from json)',
      );
    }
    if (dateTimesWritten > 0) {
      logInfo('$dateTimesWritten got their DateTime set in EXIF data');
    }

    return {
      'coordinatesWritten': coordinatesWritten,
      'dateTimesWritten': dateTimesWritten,
    };
  }

  /// Parallel EXIF writing for improved performance
  Future<Map<String, int>> _writeExifDataParallel(
    final void Function(int current, int total)? onProgress,
    final PerformanceConfig config,
    final ExifToolService exifTool,
  ) async {
    logInfo('[Step 5/8] Using parallel EXIF writing for improved performance');

    var coordinatesWritten = 0;
    var dateTimesWritten = 0;
    var completed = 0;

    // Calculate optimal concurrency
    final maxConcurrency =
        config.maxConcurrentOperations ??
        (Platform.numberOfProcessors * 2).clamp(2, 8);

    // Process files in parallel batches using existing ExifWriterService
    for (int i = 0; i < _media.length; i += maxConcurrency) {
      final batch = _media.skip(i).take(maxConcurrency);

      final futures = batch.map((final mediaEntity) async {
        final exifWriter = ExifWriterService(exifTool);
        var gpsWritten = false;
        var dateTimeWritten = false;

        // Write GPS coordinates to EXIF if available
        try {
          final coordinates = await jsonCoordinatesExtractor(
            mediaEntity.files.firstFile,
          );
          if (coordinates != null) {
            final success = await exifWriter.writeGpsToExif(
              coordinates,
              mediaEntity.files.firstFile,
              ServiceContainer.instance.globalConfig,
            );
            if (success) {
              gpsWritten = true;
            }
          }
        } catch (e) {
          logWarning(
            'Failed to extract/write GPS coordinates for ${mediaEntity.files.firstFile.path}: $e',
          );
        }

        // Write date/time to EXIF if available and not already from EXIF
        if (mediaEntity.dateTaken != null &&
            mediaEntity.dateTimeExtractionMethod !=
                DateTimeExtractionMethod.exif &&
            mediaEntity.dateTimeExtractionMethod !=
                DateTimeExtractionMethod.none) {
          try {
            final success = await exifWriter.writeDateTimeToExif(
              mediaEntity.dateTaken!,
              mediaEntity.files.firstFile,
              ServiceContainer.instance.globalConfig,
            );
            if (success) {
              dateTimeWritten = true;
            }
          } catch (e) {
            logWarning(
              'Failed to write DateTime to EXIF for ${mediaEntity.files.firstFile.path}: $e',
            );
          }
        }

        return {'gps': gpsWritten, 'dateTime': dateTimeWritten};
      });

      // Wait for all futures in this batch to complete
      final results = await Future.wait(futures);

      // Update counters
      for (final result in results) {
        if (result['gps'] == true) coordinatesWritten++;
        if (result['dateTime'] == true) dateTimesWritten++;
        completed++;
      }

      // Report progress
      onProgress?.call(completed, _media.length);
    }

    // Log final statistics
    if (coordinatesWritten > 0) {
      logInfo(
        '$coordinatesWritten files got their coordinates set in EXIF data (from json)',
      );
    }
    if (dateTimesWritten > 0) {
      logInfo('$dateTimesWritten got their DateTime set in EXIF data');
    }

    return {
      'coordinatesWritten': coordinatesWritten,
      'dateTimesWritten': dateTimesWritten,
    };
  }

  /// Remove duplicate media entities from the collection
  ///
  /// Uses content-based duplicate detection to identify and remove duplicate files,
  /// keeping the best version of each duplicate group.
  Future<int> removeDuplicates({
    final void Function(int current, int total)? onProgress,
  }) async {
    if (_media.isEmpty) return 0;

    final duplicateService =
        ServiceContainer.instance.duplicateDetectionService;
    int removedCount = 0;

    // Group media by album association first to preserve cross-album duplicates
    final albumGroups = <String?, List<MediaEntity>>{};
    for (final media in _media) {
      // Get the album key (null for year folder files, album name for album files)
      final albumKey = media.files.getAlbumKey();
      albumGroups.putIfAbsent(albumKey, () => []).add(media);
    }

    // Process each album group separately to avoid removing cross-album duplicates
    final entitiesToRemove = <MediaEntity>[];
    int processed = 0;
    final totalGroups = albumGroups.length;

    for (final albumGroup in albumGroups.values) {
      if (albumGroup.length <= 1) {
        processed++;
        onProgress?.call(processed, totalGroups);
        continue;
      }

      // Find duplicates within this album group only
      final hashGroups = await duplicateService.groupIdentical(albumGroup);

      for (final group in hashGroups.values) {
        if (group.length <= 1) {
          continue; // No duplicates in this group
        } // Sort by best date extraction quality, then file name length
        group.sort((final MediaEntity a, final MediaEntity b) {
          // Prefer files with dates from better extraction methods
          final aAccuracy = a.dateAccuracy?.value ?? 999;
          final bAccuracy = b.dateAccuracy?.value ?? 999;
          if (aAccuracy != bAccuracy) {
            return aAccuracy.compareTo(bAccuracy);
          }

          // If equal accuracy, prefer shorter file names (typically original names)
          final aNameLength = a.files.firstFile.path.length;
          final bNameLength = b.files.firstFile.path.length;
          return aNameLength.compareTo(bNameLength);
        });

        // Add all duplicates except the first (best) one to removal list
        final duplicatesToRemove = group.sublist(1);

        // Log which duplicates are being removed
        if (duplicatesToRemove.isNotEmpty) {
          final keptFile = group.first.primaryFile.path;
          logInfo('Found ${group.length} identical files, keeping: $keptFile');
          for (final duplicate in duplicatesToRemove) {
            logInfo('  Removing duplicate: ${duplicate.primaryFile.path}');
          }
        }

        entitiesToRemove.addAll(duplicatesToRemove);
        removedCount += duplicatesToRemove.length;
      }

      processed++;
      onProgress?.call(processed, totalGroups);
    }

    // Remove all duplicates in a single operation to prevent race conditions
    // ignore: prefer_foreach
    for (final entityToRemove in entitiesToRemove) {
      _media.remove(entityToRemove);
    }

    return removedCount;
  }

  /// Find and merge album relationships in the collection
  ///
  /// This method detects media files that appear in multiple locations
  /// (year folders and album folders) and merges them into single entities
  /// with all file associations preserved.
  Future<void> findAlbums({
    final void Function(int processed, int total)? onProgress,
  }) async {
    final albumService = ServiceContainer.instance.albumRelationshipService;

    // Create a copy of the media list to avoid concurrent modification
    final mediaCopy = List<MediaEntity>.from(_media);

    // Get the merged results
    final mergedMedia = await albumService.detectAndMergeAlbums(mediaCopy);

    // Replace the current media list with merged results
    _media.clear();
    _media.addAll(mergedMedia);

    onProgress?.call(_media.length, _media.length);
  }

  /// Get processing statistics for the collection
  ///
  /// Returns comprehensive statistics about the media collection including
  /// file counts, date information, and extraction method distribution.
  ProcessingStatistics getStatistics() {
    var mediaWithDates = 0;
    var mediaWithAlbums = 0;
    var totalFiles = 0;
    final extractionMethodDistribution = <DateTimeExtractionMethod, int>{};

    for (final mediaEntity in _media) {
      // Count media with dates
      if (mediaEntity.dateTaken != null) {
        mediaWithDates++;
      }

      // Count media with album associations
      if (mediaEntity.files.hasAlbumFiles) {
        mediaWithAlbums++;
      }

      // Count total files
      totalFiles += mediaEntity.files.files.length;

      // Track extraction method distribution
      final method =
          mediaEntity.dateTimeExtractionMethod ?? DateTimeExtractionMethod.none;
      extractionMethodDistribution[method] =
          (extractionMethodDistribution[method] ?? 0) + 1;
    }

    return ProcessingStatistics(
      totalMedia: _media.length,
      mediaWithDates: mediaWithDates,
      mediaWithAlbums: mediaWithAlbums,
      totalFiles: totalFiles,
      extractionMethodDistribution: extractionMethodDistribution,
    );
  }

  /// Get media entities as an iterable for processing
  Iterable<MediaEntity> get entities => _media;

  /// Access media entity by index
  MediaEntity operator [](final int index) => _media[index];

  /// Set media entity at index
  void operator []=(final int index, final MediaEntity mediaEntity) {
    _media[index] = mediaEntity;
  }
}

/// Statistics about processed media collection
class ProcessingStatistics {
  const ProcessingStatistics({
    required this.totalMedia,
    required this.mediaWithDates,
    required this.mediaWithAlbums,
    required this.totalFiles,
    required this.extractionMethodDistribution,
  });

  final int totalMedia;
  final int mediaWithDates;
  final int mediaWithAlbums;
  final int totalFiles;
  final Map<DateTimeExtractionMethod, int> extractionMethodDistribution;
}
