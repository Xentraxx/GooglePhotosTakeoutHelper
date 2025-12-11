// ignore_for_file: unintended_html_in_doc_comment

import 'dart:collection';
import 'dart:io';
import 'package:gpth/gpth_lib_exports.dart';

/// Modern domain model representing a collection of media entities (slim version).
/// This class is now a pure container; the heavy logic for steps 3–6
/// lives inside each step's `execute`.
class MediaEntityCollection with LoggerMixin {
  MediaEntityCollection([final List<MediaEntity>? initial])
    : _media = initial?.toList(growable: true) ?? <MediaEntity>[];

  final List<MediaEntity> _media;

  /// Read-only snapshot
  List<MediaEntity> get media => List.unmodifiable(_media);

  /// Number of media items in the collection
  int get length => _media.length;

  /// Whether the collection is empty
  bool get isEmpty => _media.isEmpty;

  bool get isNotEmpty => _media.isNotEmpty;

  /// Iterable view
  Iterable<MediaEntity> get entities => _media;

  /// Indexer (read)
  MediaEntity operator [](final int index) => _media[index];

  /// Indexer (write/replace one)
  void operator []=(final int index, final MediaEntity entity) {
    _media[index] = entity;
  }

  /// Append one
  void add(final MediaEntity entity) => _media.add(entity);

  /// Append many
  void addAll(final Iterable<MediaEntity> entities) => _media.addAll(entities);

  /// Remove one (by identity/equality)
  bool remove(final MediaEntity entity) => _media.remove(entity);

  /// Clear all
  void clear() => _media.clear();

  /// Replace at index
  void replaceAt(final int index, final MediaEntity entity) {
    _media[index] = entity;
  }

  /// Replace entire content in one shot
  void replaceAll(final List<MediaEntity> newList) {
    _media
      ..clear()
      ..addAll(newList);
  }

  /// Return a modifiable copy of the internal list
  List<MediaEntity> asList() => List<MediaEntity>.from(_media);

  // Backward compat helpers (used by some steps)
  void addOrReplaceAt(final int index, final MediaEntity entity) {
    if (index >= 0 && index < _media.length) {
      _media[index] = entity;
    } else if (index == _media.length) {
      _media.add(entity);
    } else {
      throw RangeError.index(index, _media, 'index', null, _media.length);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Backward-compat façade: legacy methods that now delegate to each Step's execute
  // These methods build a ProcessingContext internally.
  // Defaults:
  //   - config: ServiceContainer.instance.globalConfig (must be ProcessingConfig)
  //   - inputDirectory: Directory.current
  //   - outputDirectory: Directory.current
  // Pass explicit parameters in tests if you need different paths/config.
  // ───────────────────────────────────────────────────────────────────────────

  /// Legacy API: writes EXIF data (GPS + Date/Time) for all items.
  /// Delegates to WriteExifStep.execute(context).
  ///
  /// Returns:
  /// { 'coordinatesWritten': <int>, 'dateTimesWritten': <int> }
  Future<Map<String, int>> writeExifData({
    final ProcessingConfig? config,
    final Directory? inputDirectory,
    final Directory? outputDirectory,
  }) async {
    final StepResult res = await _runStep(
      step: const WriteExifStep(),
      config: config,
      inputDirectory: inputDirectory,
      outputDirectory: outputDirectory,
    );

    final data = _asMap(res.data);
    return <String, int>{
      'coordinatesWritten': _asInt(data['coordinatesWritten']),
      'dateTimesWritten': _asInt(data['dateTimesWritten']),
    };
  }

  /// Legacy API: removes duplicates across the collection.
  /// Delegates to RemoveDuplicatesStep.execute(context).
  ///
  /// Returns the number of removed duplicates when available, otherwise 0.
  Future<int> mergeMediaEntities({
    final ProcessingConfig? config,
    final Directory? inputDirectory,
    final Directory? outputDirectory,
  }) async {
    final StepResult res = await _runStep(
      step: const MergeMediaEntitiesStep(),
      config: config,
      inputDirectory: inputDirectory,
      outputDirectory: outputDirectory,
    );

    final data = _asMap(res.data);
    if (data.isEmpty) return 0;

    if (data.containsKey('removed')) return _asInt(data['removed']);
    if (data.containsKey('duplicatesRemoved')) {
      return _asInt(data['duplicatesRemoved']);
    }
    if (data.containsKey('removedCount')) return _asInt(data['removedCount']);
    if (data.containsKey('duplicateFilesRemoved')) {
      return _asInt(data['duplicateFilesRemoved']);
    }
    return 0;
  }

  /// Legacy API: extracts/normalizes dates for media items.
  /// Delegates to ExtractDatesStep.execute(context).
  ///
  /// Returns a normalized map of counters when present, otherwise an empty map.
  /// Keys usually include: 'filesProcessed', 'validDates', 'invalidDates', etc.
  Future<Map<String, int>> extractDates({
    final ProcessingConfig? config,
    final Directory? inputDirectory,
    final Directory? outputDirectory,
  }) async {
    final StepResult res = await _runStep(
      step: const ExtractDatesStep(),
      config: config,
      inputDirectory: inputDirectory,
      outputDirectory: outputDirectory,
    );

    final data = _asMap(res.data);
    final normalized = <String, int>{};
    for (final entry in data.entries) {
      final v = entry.value;
      if (v is int) {
        normalized[entry.key] = v;
      } else if (v is num) {
        normalized[entry.key] = v.toInt();
      } else {
        final parsed = int.tryParse('$v');
        if (parsed != null) normalized[entry.key] = parsed;
      }
    }
    return normalized;
  }

  /// Legacy API: finds and merges albums, replacing the collection when applicable.
  /// Delegates to FindAlbumsStep.execute(context).
  ///
  /// Returns the number of merged groups when available, and replaces internal list if the step provides it.
  Future<int> findAlbums({
    final ProcessingConfig? config,
    final Directory? inputDirectory,
    final Directory? outputDirectory,
  }) async {
    final StepResult res = await _runStep(
      step: const FindAlbumsStep(),
      config: config,
      inputDirectory: inputDirectory,
      outputDirectory: outputDirectory,
    );

    final data = _asMap(res.data);
    final mergedList = _tryExtractMediaList(data);
    if (mergedList != null) {
      replaceAll(mergedList);
    }

    if (data.containsKey('mergedCount')) return _asInt(data['mergedCount']);
    if (data.containsKey('albumsMerged')) return _asInt(data['albumsMerged']);
    if (data.containsKey('groupsMerged')) return _asInt(data['groupsMerged']);
    return 0;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Statistics (restored): provides collection-level processing statistics
  // ───────────────────────────────────────────────────────────────────────────

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

      // Count media with album associations (metadata)
      if (mediaEntity.albumsMap.isNotEmpty) {
        mediaWithAlbums++;
      }

      // Count total files: primary + secondaries
      totalFiles += 1 + mediaEntity.secondaryFiles.length;

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

  // ───────────────────────────────────────────────────────────────────────────
  // Internal helpers to build context, run a step, and normalize outputs
  // ───────────────────────────────────────────────────────────────────────────

  Future<StepResult> _runStep({
    required final ProcessingStep step,
    final ProcessingConfig? config,
    final Directory? inputDirectory,
    final Directory? outputDirectory,
  }) async {
    final ProcessingConfig cfg = _resolveConfig(config);
    final Directory inDir = inputDirectory ?? Directory.current;
    final Directory outDir = outputDirectory ?? Directory.current;

    final ctx = ProcessingContext(
      config: cfg,
      mediaCollection: this,
      inputDirectory: inDir,
      outputDirectory: outDir,
    );

    return step.execute(ctx);
  }

  /// Resolves a ProcessingConfig, casting ServiceContainer.instance.globalConfig
  /// and throwing a clear error if it is missing or of a wrong type.
  ProcessingConfig _resolveConfig(final ProcessingConfig? provided) {
    if (provided != null) return provided;

    final dynamic global = ServiceContainer.instance.globalConfig;
    if (global is ProcessingConfig) return global;

    throw StateError(
      'Global config is not initialized or has the wrong type. '
      'Initialize ServiceContainer.instance.globalConfig as ProcessingConfig in setUp(), '
      'or pass `config:` explicitly to the method.',
    );
  }

  Map<String, dynamic> _asMap(final Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return Map<String, dynamic>.from(
        data.map((final k, final v) => MapEntry('$k', v)),
      );
    }
    return const <String, dynamic>{};
  }

  int _asInt(final Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  List<MediaEntity>? _tryExtractMediaList(final Map<String, dynamic> data) {
    Object? list;
    if (data.containsKey('merged')) list = data['merged'];
    list ??= data['collection'];
    list ??= data['entities'];

    if (list is List<MediaEntity>) return list;
    if (list is List) {
      final out = <MediaEntity>[];
      for (final e in list) {
        if (e is MediaEntity) out.add(e);
      }
      if (out.isNotEmpty) return out;
    }
    return null;
  }

  // Remove a set of entities in a single pass O(N + R)
  void removeAll(final Iterable<MediaEntity> items) {
    // Convert to Set for O(1) membership checks
    final Set<MediaEntity> s = HashSet<MediaEntity>.identity()..addAll(items);
    // IMPORTANT: operate over the internal mutable list
    _media.removeWhere(s.contains);
  }

  // Apply kept0 → kept replacements in one linear scan O(N)
  void applyReplacements(final Map<MediaEntity, MediaEntity> mapping) {
    for (int i = 0; i < _media.length; i++) {
      final MediaEntity current = _media[i];
      final MediaEntity? repl = mapping[current];
      if (repl != null) {
        _media[i] = repl;
      }
    }
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
