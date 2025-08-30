import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:gpth/gpth-lib.dart';


/// Service for detecting duplicate media files based on content hash and size
///
/// This service provides efficient duplicate detection by first grouping files
/// by size (fast comparison), then calculating content hashes only for files
/// with matching sizes. Uses parallel processing with adaptive concurrency limits to
/// balance performance with system resource usage and automatically adjusts
/// batch sizes based on system performance.
class DuplicateDetectionService with LoggerMixin {
  /// Creates a new instance of DuplicateDetectionService
  DuplicateDetectionService({final MediaHashService? hashService})
    : _hashService = hashService ?? MediaHashService();

  final MediaHashService _hashService;

  /// Performance monitoring for adaptive optimization
  final List<double> _recentPerformanceMetrics = [];
  static const int _maxPerformanceHistory = 10;

  /// Base concurrency multiplier based on CPU cores
  static int get baseConcurrency => ConcurrencyManager().cpuCoreCount;

  /// Adaptive concurrency based on recent performance
  int get adaptiveConcurrency => ConcurrencyManager().getAdaptiveConcurrency(
    _recentPerformanceMetrics,
    baseLevel: ConcurrencyManager().conservative,
  );

  /// Maximum number of concurrent operations to prevent overwhelming the system
  static int get maxConcurrency =>
      ConcurrencyManager().concurrencyFor(ConcurrencyOperation.duplicate);

  /// Records performance metric for adaptive optimization
  void _recordPerformance(final int filesProcessed, final Duration elapsed) {
    final filesPerSecond =
        filesProcessed / elapsed.inSeconds.clamp(1, double.infinity);
    _recentPerformanceMetrics.add(filesPerSecond);

    // Keep only recent metrics
    if (_recentPerformanceMetrics.length > _maxPerformanceHistory) {
      _recentPerformanceMetrics.removeAt(0);
    }

    logInfo('Performance: ${filesPerSecond.toStringAsFixed(1)} files/sec, adaptive concurrency: $adaptiveConcurrency');
  }

  /// Groups media entities by file size and hash for duplicate detection with caching
  ///
  /// Uses a three-phase approach for maximum efficiency:
  /// 1. Group by file size (fast comparison using existing file metadata)
  /// 2. For size-matching groups, calculate and compare content hashes (with caching)
  /// 3. Use batch processing with optimal concurrency to maximize throughput
  ///
  /// Returns a map where:
  /// - Key: Either "XXXbytes" for unique file sizes, or hash string for potential duplicates
  /// - Value: List of MediaEntity objects sharing that size/hash
  ///
  /// Single-item groups indicate unique files, multi-item groups are duplicates
  Future<Map<String, List<MediaEntity>>> groupIdentical(
    final List<MediaEntity> mediaList,
  ) async {
    if (mediaList.isEmpty) return <String, List<MediaEntity>>{};

    final Map<String, List<MediaEntity>> output = <String, List<MediaEntity>>{};
    final stopwatch = Stopwatch()..start();

    logInfo('Starting duplicate detection for ${mediaList.length} files...');

    // Step 1: Calculate all sizes in parallel with optimal batching
    final sizeResults = <({MediaEntity media, int size})>[];
    final batchSize = (adaptiveConcurrency * 1.5).round(); // Use adaptive concurrency

    logDebug('Starting $batchSize threads (duplicate size batching concurrency)');

    for (int i = 0; i < mediaList.length; i += batchSize) {
      final batch = mediaList.skip(i).take(batchSize);
      final futures = batch.map((final media) async {
        try {
          final size = await _hashService.calculateFileSize(media.primaryFile);
          return (media: media, size: size);
        } catch (e) {
          logError('Failed to get size for ${media.primaryFile.path}: $e');
          return null;
        }
      });

      final batchResults = await Future.wait(futures);
      sizeResults.addAll(batchResults.whereType<({MediaEntity media, int size})>());

      // Progress reporting
      if (mediaList.length > 1000) {
        final processed = math.min(i + batchSize, mediaList.length);
        final progress = (processed / mediaList.length * 100).clamp(0, 100);
        logInfo('Size calculation progress: ${progress.toStringAsFixed(1)}%');
      }
    }

    // Group by size
    final sizeGroups = <int, List<MediaEntity>>{};
    for (final entry in sizeResults) {
      sizeGroups.putIfAbsent(entry.size, () => <MediaEntity>[]).add(entry.media);
    }

    logInfo('Grouped ${mediaList.length} files into ${sizeGroups.length} size groups');

    // Step 2: Calculate hashes in parallel for groups with multiple files
    int hashCalculationsNeeded = 0;
    int uniqueSizeFiles = 0;

    for (final MapEntry<int, List<MediaEntity>> sameSize in sizeGroups.entries) {
      if (sameSize.value.length <= 1) {
        output['${sameSize.key}bytes'] = sameSize.value;
        uniqueSizeFiles++;
      } else {
        hashCalculationsNeeded += sameSize.value.length;

        // Calculate hashes in optimized parallel batches
        final hashResults = <({MediaEntity media, String hash})>[];
        final mediaWithSameSize = sameSize.value;

        // Use adaptive batch size for hash calculation
        final hashBatchSize = adaptiveConcurrency;

        logDebug('Starting $hashBatchSize threads (duplicate hash batching concurrency)');

        for (int i = 0; i < mediaWithSameSize.length; i += hashBatchSize) {
          final batch = mediaWithSameSize.skip(i).take(hashBatchSize);
          final futures = batch.map((final media) async {
            try {
              final hash = await _hashService.calculateFileHash(media.primaryFile);
              return (media: media, hash: hash);
            } catch (e) {
              logError('Failed to calculate hash for ${media.primaryFile.path}: $e');
              return null;
            }
          });

          final batchResults = await Future.wait(futures);
          hashResults.addAll(batchResults.whereType<({MediaEntity media, String hash})>());

          // Progress reporting for large groups
          if (mediaWithSameSize.length > 100) {
            final processed = math.min(i + hashBatchSize, mediaWithSameSize.length);
            final progress = (processed / mediaWithSameSize.length * 100).clamp(0, 100);
            logInfo('Hash calculation progress for ${sameSize.key}bytes group: ${progress.toStringAsFixed(1)}%');
          }
        }

        // Group by hash
        final hashGroups = <String, List<MediaEntity>>{};
        for (final entry in hashResults) {
          hashGroups.putIfAbsent(entry.hash, () => <MediaEntity>[]).add(entry.media);
        }
        output.addAll(hashGroups);
      }
    }
    stopwatch.stop();

    // Record performance metrics for adaptive optimization
    _recordPerformance(mediaList.length, stopwatch.elapsed);

    // Log performance statistics
    final cacheStats = _hashService.getCacheStats();
    logInfo('Duplicate detection completed in ${stopwatch.elapsed.inMilliseconds}ms');
    logInfo('Files with unique sizes: $uniqueSizeFiles');
    logInfo('Files requiring hash calculation: $hashCalculationsNeeded');
    logInfo('Cache statistics: $cacheStats');

    // Count and log duplicate groups found
    final duplicateGroups = output.values.where((final group) => group.length > 1);
    final totalDuplicates = duplicateGroups.fold<int>(0, (final sum, final group) => sum + group.length - 1);

    if (duplicateGroups.isNotEmpty) {
      logInfo('Found ${duplicateGroups.length} duplicate groups with $totalDuplicates duplicate files');
    }

    return output;
  }

  /// Removes duplicate media from list of media entities with enhanced logging
  ///
  /// This method is designed for early-stage processing before album merging.
  /// It preserves duplicated files that have different album associations,
  /// ensuring no album relationships are lost during deduplication.
  ///
  /// [mediaList] List of media entities to deduplicate
  /// [progressCallback] Optional callback for progress updates (processed, total)
  /// Returns list with duplicates removed, keeping the highest quality version
  Future<List<MediaEntity>> removeDuplicates(
    final List<MediaEntity> mediaList, {
    final void Function(int processed, int total)? progressCallback,
  }) async {
    if (mediaList.length <= 1) return mediaList;

    logInfo('Starting duplicate removal for ${mediaList.length} media entities...');

    final grouped = await groupIdentical(mediaList);
    final result = <MediaEntity>[];
    int processed = 0;
    int duplicatesRemoved = 0;

    for (final group in grouped.values) {
      if (group.length == 1) {
        // No duplicates, keep the single file
        result.add(group.first);
      } else {
        // Multiple files with same content, keep the best one
        final best = _selectBestMedia(group);
        result.add(best);

        // Log which duplicates are being removed
        final duplicatesToRemove = group.where((final media) => media != best).toList();
        duplicatesRemoved += duplicatesToRemove.length;

        if (duplicatesToRemove.isNotEmpty) {
          final keptFile = best.primaryFile.path;
          logDebug('Found ${group.length} identical files, keeping: $keptFile');
          for (final duplicate in duplicatesToRemove) {
            logDebug('  Removing duplicate: ${duplicate.primaryFile.path}');
          }
        }
      }

      processed++;
      progressCallback?.call(processed, grouped.length);
    }

    logInfo('Duplicate removal completed: removed $duplicatesRemoved files, kept ${result.length}');

    // Log cache performance
    final cacheStats = _hashService.getCacheStats();
    logInfo('Final cache statistics: $cacheStats');

    return result;
  }

  /// Selects the best media entity from a group of duplicates
  ///
  /// Priority order:
  /// 1. Media with most accurate date information
  /// 2. Media with more album associations
  /// 3. Media with shorter file path (likely original location)
  MediaEntity _selectBestMedia(final List<MediaEntity> duplicates) {
    if (duplicates.length == 1) {
      return duplicates.first;
    }
    // Sort by quality criteria
    final sorted = duplicates.toList()
      ..sort((final a, final b) {
        // 1. Prefer media with more accurate date
        final aHasDate = a.dateTaken != null && a.dateAccuracy != null;
        final bHasDate = b.dateTaken != null && b.dateAccuracy != null;

        if (aHasDate && bHasDate) {
          final dateComparison = a.dateTakenAccuracy!.compareTo(b.dateTakenAccuracy!);
          if (dateComparison != 0) return dateComparison;
        } else if (aHasDate && !bHasDate) {
          return -1; // a is better
        } else if (!aHasDate && bHasDate) {
          return 1; // b is better
        }

        // 2. Prefer media with more album associations
        final albumComparison = b.files.files.length.compareTo(a.files.files.length);
        if (albumComparison != 0) return albumComparison;

        // 3. Prefer media with shorter path (likely more original)
        final pathA = a.primaryFile.path;
        final pathB = b.primaryFile.path;
        return pathA.length.compareTo(pathB.length);
      });

    return sorted.first;
  }

  /// Finds exact duplicates based on file content
  ///
  /// Returns a list of duplicate groups, where each group contains
  /// media entities with identical file content.
  Future<List<List<MediaEntity>>> findDuplicateGroups(
    final List<MediaEntity> mediaList,
  ) async {
    final grouped = await groupIdentical(mediaList);
    return grouped.values.where((final group) => group.length > 1).toList();
  }

  /// Checks if two media entities are duplicates based on content
  Future<bool> areDuplicates(
    final MediaEntity media1,
    final MediaEntity media2,
  ) async {
    // Quick size check first
    final size1 = await _hashService.calculateFileSize(media1.primaryFile);
    final size2 = await _hashService.calculateFileSize(media2.primaryFile);

    if (size1 != size2) return false;

    // If sizes match, compare hashes
    final hash1 = await _hashService.calculateFileHash(media1.primaryFile);
    final hash2 = await _hashService.calculateFileHash(media2.primaryFile);

    return hash1 == hash2;
  }

  /// Statistics about duplicate detection results
  DuplicateStats calculateStats(
    final Map<String, List<MediaEntity>> groupedResults,
  ) {
    int totalFiles = 0;
    int uniqueFiles = 0;
    int duplicateGroups = 0;
    int duplicateFiles = 0;
    int spaceWastedBytes = 0;

    for (final group in groupedResults.values) {
      totalFiles += group.length;

      if (group.length == 1) {
        uniqueFiles++;
      } else {
        duplicateGroups++;
        duplicateFiles += group.length;

        // Calculate wasted space (all but one file in each group)
        for (int i = 1; i < group.length; i++) {
          // Note: This is an approximation - we'd need to actually calculate sizes
          // For now, we'll use the file size from the first file as estimate
          try {
            final size = group.first.primaryFile.lengthSync();
            spaceWastedBytes += size;
          } catch (e) {
            // Ignore files that can't be read
          }
        }
      }
    }

    return DuplicateStats(
      totalFiles: totalFiles,
      uniqueFiles: uniqueFiles,
      duplicateGroups: duplicateGroups,
      duplicateFiles: duplicateFiles,
      spaceWastedBytes: spaceWastedBytes,
    );
  }

  // ───────────────────────── Additional performance APIs (non-breaking) ─────────────────────────

  /// Fast path duplicate grouping with tri-sample fingerprint prefilter.
  ///
  /// This reduces the number of full file hashes by first grouping by [size],
  /// then by a cheap fingerprint computed from three small slices (head/middle/tail).
  /// Only fingerprint-colliding subgroups get full content hashing.
  ///
  /// For tiny groups (≤3 files) we jump straight to full hashing to avoid overhead.
  Future<Map<String, List<MediaEntity>>> groupIdenticalFast(
    final List<MediaEntity> mediaList, {
    final int sampleSizeBytes = 64 * 1024, // 64 KiB per slice
  }) async {
    if (mediaList.isEmpty) return <String, List<MediaEntity>>{};

    final Map<String, List<MediaEntity>> output = <String, List<MediaEntity>>{};
    final stopwatch = Stopwatch()..start();

    logInfo('Starting FAST duplicate detection for ${mediaList.length} files...');

    // Phase 1: group by size (reuse existing logic but inline to avoid extra maps)
    final sizeResults = <({MediaEntity media, int size})>[];
    final sizeBatch = (adaptiveConcurrency * 1.5).round();

    for (int i = 0; i < mediaList.length; i += sizeBatch) {
      final batch = mediaList.skip(i).take(sizeBatch);
      final futures = batch.map((final media) async {
        try {
          final size = await _hashService.calculateFileSize(media.primaryFile);
          return (media: media, size: size);
        } catch (e) {
          logError('Failed to get size for ${media.primaryFile.path}: $e');
          return null;
        }
      });
      final res = await Future.wait(futures);
      sizeResults.addAll(res.whereType<({MediaEntity media, int size})>());

      if (mediaList.length > 1000) {
        final processed = math.min(i + sizeBatch, mediaList.length);
        final progress = (processed / mediaList.length * 100).clamp(0, 100);
        logInfo('Size calculation progress (FAST): ${progress.toStringAsFixed(1)}%');
      }
    }

    final sizeGroups = <int, List<MediaEntity>>{};
    for (final entry in sizeResults) {
      sizeGroups.putIfAbsent(entry.size, () => <MediaEntity>[]).add(entry.media);
    }

    logInfo('FAST mode: ${sizeGroups.length} size groups');

    // Phase 2: inside each size group, tri-sample fingerprint, then full hash
    int fullHashes = 0;
    int uniqueBySize = 0;

    for (final MapEntry<int, List<MediaEntity>> sameSize in sizeGroups.entries) {
      final List<MediaEntity> group = sameSize.value;
      if (group.length <= 1) {
        output['${sameSize.key}bytes'] = group;
        uniqueBySize++;
        continue;
      }

      if (group.length <= 3) {
        // Small groups: direct full hashing
        final Map<String, List<MediaEntity>> byHash = await _fullHashGroup(group);
        output.addAll(byHash);
        fullHashes += group.length;
        continue;
      }

      // 2a) fingerprint batching (cheap reads)
      final Map<String, List<MediaEntity>> byFp = <String, List<MediaEntity>>{};
      final int fpBatch = math.max(1, adaptiveConcurrency);

      for (int i = 0; i < group.length; i += fpBatch) {
        final batch = group.skip(i).take(fpBatch);
        final futures = batch.map((final media) async {
          try {
            final f = media.primaryFile;
            final String fp = await _triSampleFingerprint(f, sampleSizeBytes);
            final key = '${sameSize.key}|$fp';
            return (media: media, key: key);
          } catch (e) {
            logError('Fingerprint failed for ${media.primaryFile.path}: $e');
            return (media: media, key: 'ERR|${media.primaryFile.path}');
          }
        });
        final res = await Future.wait(futures);
        for (final r in res) {
          (byFp[r.key] ??= <MediaEntity>[]).add(r.media);
        }
      }

      // 2b) only hash subgroups with >1
      for (final List<MediaEntity> fpSub in byFp.values) {
        if (fpSub.length == 1) {
          // unique by fingerprint → treat as unique (keep size marker to avoid hash)
          output['${sameSize.key}bytes|${fpSub.first.primaryFile.path}'] = [fpSub.first];
          continue;
        }
        final Map<String, List<MediaEntity>> byHash = await _fullHashGroup(fpSub);
        output.addAll(byHash);
        fullHashes += fpSub.length;
      }
    }

    stopwatch.stop();
    _recordPerformance(mediaList.length, stopwatch.elapsed);

    final cacheStats = _hashService.getCacheStats();
    logInfo('FAST duplicate detection completed in ${stopwatch.elapsed.inMilliseconds}ms');
    logInfo('FAST mode: files hashed fully: $fullHashes (remainder filtered by fingerprint)');
    logInfo('FAST mode: files with unique sizes: $uniqueBySize');
    logInfo('Cache statistics: $cacheStats');

    final duplicateGroups = output.values.where((final g) => g.length > 1);
    final totalDuplicates = duplicateGroups.fold<int>(0, (s, g) => s + g.length - 1);
    if (duplicateGroups.isNotEmpty) {
      logInfo('FAST mode found ${duplicateGroups.length} duplicate groups with $totalDuplicates duplicate files');
    }

    return output;
  }

  /// Optional convenience alias if you prefer this name in callers.
  Future<String> computeSha256(final MediaEntity media) => _hashService.calculateFileHash(media.primaryFile);

  // ─────────────────────────────── helpers ───────────────────────────────

  Future<Map<String, List<MediaEntity>>> _fullHashGroup(final List<MediaEntity> files) async {
    final Map<String, List<MediaEntity>> byHash = <String, List<MediaEntity>>{};
    final int hashBatch = adaptiveConcurrency;

    for (int i = 0; i < files.length; i += hashBatch) {
      final batch = files.skip(i).take(hashBatch);
      final futures = batch.map((final media) async {
        try {
          final h = await _hashService.calculateFileHash(media.primaryFile);
          return (media: media, hash: h);
        } catch (e) {
          logError('Failed to calculate hash for ${media.primaryFile.path}: $e');
          return (media: media, hash: 'ERR|${media.primaryFile.path}');
        }
      });
      final res = await Future.wait(futures);
      for (final r in res) {
        (byHash[r.hash] ??= <MediaEntity>[]).add(r.media);
      }
    }
    return byHash;
  }

  /// Compute a compact fingerprint from three small slices of the file.
  /// This is NOT a cryptographic hash; it is only used to pre-cluster and reduce
  /// the number of full hashes needed. Collisions are acceptable because we will
  /// still verify with full file hashes inside each fingerprint subgroup.
  Future<String> _triSampleFingerprint(final File f, final int sampleSize) async {
    final int size = await _hashService.calculateFileSize(f);
    if (size <= 0) return 'SZ0';

    final RandomAccessFile raf = await f.open();
    try {
      final int headLen = math.min(sampleSize, size);
      final Uint8List head = await _readSlice(raf, 0, headLen);

      final int midStart = math.max(0, (size ~/ 2) - (sampleSize ~/ 2));
      final int midLen = math.min(sampleSize, size - midStart);
      final Uint8List mid = await _readSlice(raf, midStart, midLen);

      final int tailStart = math.max(0, size - sampleSize);
      final int tailLen = math.min(sampleSize, size - tailStart);
      final Uint8List tail = await _readSlice(raf, tailStart, tailLen);

      // FNV-1a 64-bit over concatenated slices (fast, simple)
      final int h1 = _fnv1a64(head);
      final int h2 = _fnv1a64(mid);
      final int h3 = _fnv1a64(tail);

      // Include size to strengthen the key and reduce cross-size collisions
      // Format: size|h1|h2|h3 (hex)
      return '${size}b:${_toHex64(h1)}:${_toHex64(h2)}:${_toHex64(h3)}';
    } finally {
      await raf.close();
    }
  }

  Future<Uint8List> _readSlice(final RandomAccessFile raf, final int start, final int length) async {
    await raf.setPosition(start);
    return await raf.read(length);
  }

  // Lightweight FNV-1a 64-bit (unsigned) for small buffers
  int _fnv1a64(final Uint8List data) {
    const int FNV_OFFSET_BASIS = 0xcbf29ce484222325; // 14695981039346656037
    const int FNV_PRIME = 0x100000001b3;            // 1099511628211
    int hash = FNV_OFFSET_BASIS;
    for (int i = 0; i < data.length; i++) {
      hash ^= data[i];
      hash = (hash * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash;
  }

  String _toHex64(final int v) {
    final s = v.toUnsigned(64).toRadixString(16);
    return s.padLeft(16, '0');
  }
}

/// Statistics about duplicate detection results
class DuplicateStats {
  const DuplicateStats({
    required this.totalFiles,
    required this.uniqueFiles,
    required this.duplicateGroups,
    required this.duplicateFiles,
    required this.spaceWastedBytes,
  });

  /// Total number of files processed
  final int totalFiles;

  /// Number of unique files (no duplicates)
  final int uniqueFiles;

  /// Number of groups containing duplicates
  final int duplicateGroups;

  /// Total number of duplicate files
  final int duplicateFiles;

  /// Estimated wasted space in bytes
  final int spaceWastedBytes;

  /// Percentage of files that are duplicates
  double get duplicatePercentage =>
      totalFiles > 0 ? (duplicateFiles / totalFiles) * 100 : 0;

  /// Human readable summary
  String get summary =>
      'Found $duplicateGroups duplicate groups with $duplicateFiles files. '
      'Space wasted: ${(spaceWastedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
