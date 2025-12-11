import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:gpth/gpth_lib_exports.dart';

/// Service for detecting and managing album relationships between media files
///
/// This service handles the complex logic of merging media files that appear
/// in both year-based folders and album folders, maintaining all file associations
/// while choosing the best metadata.
class AlbumRelationshipService with LoggerMixin {
  /// Creates a new album relationship service
  AlbumRelationshipService({
    this.maxConcurrent = 0, // 0 → auto (CPU cores)
    this.enableFastHash = false,
    this.fastHashBytesPerEdge = 2 * 1024 * 1024, // 2MiB from head (fast mode)
  });

  /// Maximum number of concurrent file operations (0 → number of processors)
  final int maxConcurrent;

  /// Enable fast hashing mode (reads only the first [fastHashBytesPerEdge] bytes)
  /// WARNING: This is a heuristic and increases collision risk; keep it false
  /// if you need strict deduplication guarantees.
  final bool enableFastHash;

  /// Bytes to read from file start in fast hash mode
  final int fastHashBytesPerEdge;

  /// Simple in-memory cache for file hashes within the same execution
  // ignore: unintended_html_in_doc_comment
  /// Key format: '<path>|<size>|<mtime_ms>' → md5 hex
  final Map<String, String> _hashCache = <String, String>{};

  /// Finds and merges album relationships in a list of media entities
  ///
  /// This processes media files that appear in multiple locations (year folders
  /// and album folders) and merges them into single entities with all file
  /// associations preserved.
  ///
  /// Returns a new list with merged entities, where duplicates have been
  /// combined and the best metadata has been preserved.
  Future<List<MediaEntity>> detectAndMergeAlbums(
    final List<MediaEntity> mediaList,
  ) async {
    if (mediaList.isEmpty) {
      return [];
    }

    logInfo('Starting album detection for ${mediaList.length} media files');

    // Group identical media by content (optimized: pre-group by file size)
    final identicalGroups = await _groupIdenticalMediaOptimized(mediaList);

    final List<MediaEntity> mergedResults = [];
    int mergedCount = 0;

    // Process each group of identical media
    for (final group in identicalGroups.values) {
      if (group.length <= 1) {
        // No duplicates to merge
        mergedResults.addAll(group);
      } else {
        // Merge the group into a single entity
        final merged = _mergeMediaGroup(group);
        mergedResults.add(merged);
        mergedCount += group.length - 1; // Count how many were merged
      }
    }

    logInfo('Album detection complete: merged $mergedCount duplicate files');
    logInfo('Final result: ${mergedResults.length} unique media files');

    return mergedResults;
  }

  /// Optimized grouping strategy:
  /// 1) Pre-group by file size (cheap): unique sizes are not duplicates → no hash
  /// 2) For size groups with >1 items, compute md5 in streaming with limited concurrency
  // ignore: unintended_html_in_doc_comment
  /// 3) Build content groups keyed by '<size>_<md5>'
  Future<Map<String, List<MediaEntity>>> _groupIdenticalMediaOptimized(
    final List<MediaEntity> mediaList,
  ) async {
    // Decide concurrency
    final int concurrency = (maxConcurrent != 0)
        ? maxConcurrent
        : (Platform.numberOfProcessors > 0 ? Platform.numberOfProcessors : 4);
    logInfo('Album detection: using concurrency = $concurrency');

    // 1) Collect file sizes (concurrently with a semaphore)
    final Map<int, List<MediaEntity>> sizeBuckets = <int, List<MediaEntity>>{};
    final _Semaphore semSizes = _Semaphore(concurrency);

    await Future.wait(
      mediaList.map((final entity) async {
        await semSizes.acquire();
        try {
          final File file = entity.primaryFile.asFile();
          final int size = await file.length();
          sizeBuckets.putIfAbsent(size, () => <MediaEntity>[]).add(entity);
        } catch (e) {
          logWarning(
            'Skipping file during size pass due to error: ${entity.primaryFile.path} - $e',
          );
          // Use a dedicated bucket for unprocessable files keyed by unique path length 0
          sizeBuckets.putIfAbsent(-1, () => <MediaEntity>[]).add(entity);
        } finally {
          semSizes.release();
        }
      }),
    );

    // 2) For buckets with count == 1 → unique group per item (no hash needed)
    //    For buckets with count > 1 → compute md5 and group by '<size>_<md5>'
    final Map<String, List<MediaEntity>> groups = <String, List<MediaEntity>>{};
    final List<Future<void>> hashingTasks = <Future<void>>[];
    final _Semaphore semHash = _Semaphore(concurrency);

    sizeBuckets.forEach((final int size, final List<MediaEntity> bucket) {
      if (size <= 0) {
        // Unprocessable files (errors): group by unique path to avoid merging
        for (final entity in bucket) {
          final key = 'unprocessable_${entity.primaryFile.path}';
          groups.putIfAbsent(key, () => <MediaEntity>[]).add(entity);
        }
        return;
      }

      if (bucket.length == 1) {
        // Unique size → cannot be duplicate; keep as its own group
        final entity = bucket.first;
        final key = 'unique_${size}_${entity.primaryFile.path}';
        groups.putIfAbsent(key, () => <MediaEntity>[]).add(entity);
        return;
      }

      // Multiple files with the same size → potentially duplicates
      // Schedule hashing tasks with limited concurrency
      for (final entity in bucket) {
        hashingTasks.add(() async {
          await semHash.acquire();
          try {
            final File file = entity.primaryFile.asFile();
            final String md5hex = await _md5ForFileWithCache(
              file,
              expectedSize: size,
            );
            final String contentKey = '${size}_$md5hex';
            groups.putIfAbsent(contentKey, () => <MediaEntity>[]).add(entity);
          } catch (e) {
            logWarning(
              'Hashing error, keeping as unique: ${entity.primaryFile.path} - $e',
            );
            final key = 'hash_error_${size}_${entity.primaryFile.path}';
            groups.putIfAbsent(key, () => <MediaEntity>[]).add(entity);
          } finally {
            semHash.release();
          }
        }());
      }
    });

    await Future.wait(hashingTasks);

    return groups;
  }

  /// Computes md5 of a file using a streaming approach and caches the result
  /// The cache key includes path, size and last modification time.
  Future<String> _md5ForFileWithCache(
    final File file, {
    required final int expectedSize,
  }) async {
    final FileStat st = await file.stat();
    final String cacheKey =
        '${file.path}|${st.size}|${st.modified.millisecondsSinceEpoch}';

    final String? cached = _hashCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final String digestHex = enableFastHash
        ? await _md5Fast(file, readBytes: fastHashBytesPerEdge)
        : await _md5Streaming(file);

    _hashCache[cacheKey] = digestHex;
    return digestHex;
  }

  /// Full-file streaming md5 (no memory blow-ups, no full readAsBytes)
  Future<String> _md5Streaming(final File file) async {
    try {
      final Digest digest = await md5.bind(file.openRead()).first;
      return digest.toString();
    } catch (e) {
      // Re-throw to let caller handle grouping fallback
      rethrow;
    }
  }

  /// Fast md5 heuristic: read only the first [readBytes] bytes
  /// WARNING: Higher collision risk; only use if you accept a heuristic.
  Future<String> _md5Fast(
    final File file, {
    required final int readBytes,
  }) async {
    try {
      final Digest digest = await md5
          .bind(file.openRead(0, readBytes > 0 ? readBytes : null))
          .first;
      return digest.toString();
    } catch (e) {
      // If fast mode fails, fallback to full streaming
      return _md5Streaming(file);
    }
  }

  /// Merges a group of identical media entities into a single entity
  ///
  /// Combines all file associations and preserves the best metadata
  /// from all entities in the group. The merging process:
  /// 1. Starts with the first entity as the base
  /// 2. Iteratively merges each additional entity
  /// 3. Combines file associations from all entities
  /// 4. Preserves all album relationships
  MediaEntity _mergeMediaGroup(final List<MediaEntity> group) {
    if (group.isEmpty) {
      throw ArgumentError('Cannot merge empty group');
    }
    if (group.length == 1) {
      return group.first;
    }
    // Start with the first entity and merge others into it
    MediaEntity result = group.first;
    for (int i = 1; i < group.length; i++) {
      result = result.mergeWith(group[i]);
    }

    return result;
  }

  /// Finds media entities that exist in albums
  List<MediaEntity> findAlbumMedia(final List<MediaEntity> mediaList) =>
      mediaList.where((final entity) => entity.hasAlbumAssociations).toList();

  /// Finds media entities that only exist in year-based organization
  List<MediaEntity> findYearOnlyMedia(final List<MediaEntity> mediaList) =>
      mediaList
          .where(
            (final entity) =>
                !entity.hasAlbumAssociations && entity.hasYearBasedFiles,
          )
          .toList();

  /// Gets statistics about album associations
  AlbumStatistics getAlbumStatistics(final List<MediaEntity> mediaList) {
    final albumMedia = findAlbumMedia(mediaList);
    final yearOnlyMedia = findYearOnlyMedia(mediaList);

    // Count unique albums
    final allAlbums = <String>{};
    for (final entity in albumMedia) {
      allAlbums.addAll(entity.albumNames);
    }

    // Count files with multiple album associations
    final multiAlbumFiles = albumMedia
        .where((final entity) => entity.albumNames.length > 1)
        .length;

    return AlbumStatistics(
      totalFiles: mediaList.length,
      albumFiles: albumMedia.length,
      yearOnlyFiles: yearOnlyMedia.length,
      uniqueAlbums: allAlbums.length,
      multiAlbumFiles: multiAlbumFiles,
      albumNames: allAlbums,
    );
  }
}

/// Simple semaphore for limiting concurrency without extra dependencies
class _Semaphore {
  _Semaphore(this._max);

  final int _max;
  int _current = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_current < _max) {
      _current++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      next.complete();
    } else {
      _current--;
      if (_current < 0) _current = 0;
    }
  }
}

/// Statistics about album detection and organization
class AlbumStatistics {
  const AlbumStatistics({
    required this.totalFiles,
    required this.albumFiles,
    required this.yearOnlyFiles,
    required this.uniqueAlbums,
    required this.multiAlbumFiles,
    required this.albumNames,
  });

  final int totalFiles;
  final int albumFiles;
  final int yearOnlyFiles;
  final int uniqueAlbums;
  final int multiAlbumFiles;
  final Set<String> albumNames;

  @override
  String toString() =>
      'AlbumStatistics('
      'total: $totalFiles, '
      'in albums: $albumFiles, '
      'year-only: $yearOnlyFiles, '
      'albums: $uniqueAlbums, '
      'multi-album files: $multiAlbumFiles'
      ')';
}
