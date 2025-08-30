import 'dart:io';
import 'package:gpth/gpth-lib.dart';

/// Strongly-typed album metadata for a media entity.
/// Kept minimal on purpose, but extensible (e.g., cover, description, id...).
class AlbumInfo {
  const AlbumInfo({
    required this.name,
    Set<String>? sourceDirectories,
  }) : sourceDirectories = sourceDirectories ?? const {};

  /// Album display/name key (already sanitized by the discovery layer)
  final String name;

  /// Directories in the Takeout where this entity had a physical file for this album.
  /// Useful for diagnostics and for reconstructing albums reliably.
  final Set<String> sourceDirectories;

  /// Returns a new AlbumInfo with `dir` added to the sourceDirectories set.
  AlbumInfo addSourceDir(final String dir) {
    if (dir.isEmpty) return this;
    final next = Set<String>.from(sourceDirectories)..add(dir);
    return AlbumInfo(name: name, sourceDirectories: next);
  }

  /// Merges two AlbumInfo objects with the same album name.
  AlbumInfo merge(final AlbumInfo other) {
    if (other.name != name) return this;
    if (other.sourceDirectories.isEmpty) return this;
    final next = Set<String>.from(sourceDirectories)..addAll(other.sourceDirectories);
    return AlbumInfo(name: name, sourceDirectories: next);
  }

  @override
  String toString() => 'AlbumInfo(name: $name, dirs: ${sourceDirectories.length})';
}

/// Immutable domain entity representing a media file (photo or video)
///
/// This is the core domain model for media files, designed to be immutable
/// and thread-safe. All modifications return new instances rather than
/// mutating existing state.
class MediaEntity {
  /// Creates a new media entity
  const MediaEntity({
    required this.files,
    this.dateTaken,
    this.dateAccuracy,
    this.dateTimeExtractionMethod,
    this.partnershared = false,
    Map<String, AlbumInfo>? belongToAlbums,
  }) : belongToAlbums = belongToAlbums ?? const {};

  /// Creates a media entity with a single file
  factory MediaEntity.single({
    required final File file,
    final DateTime? dateTaken,
    final DateAccuracy? dateAccuracy,
    final DateTimeExtractionMethod? dateTimeExtractionMethod,
    final bool partnershared = false,
    Map<String, AlbumInfo>? belongToAlbums,
  }) =>
      MediaEntity(
        files: MediaFilesCollection.single(file),
        dateTaken: dateTaken,
        dateAccuracy: dateAccuracy,
        dateTimeExtractionMethod: dateTimeExtractionMethod,
        partnershared: partnershared,
        belongToAlbums: belongToAlbums,
      );

  /// Creates a media entity from a legacy map structure
  factory MediaEntity.fromMap({
    required final Map<String?, File> files,
    final DateTime? dateTaken,
    final int? dateTakenAccuracy,
    final DateTimeExtractionMethod? dateTimeExtractionMethod,
    final bool partnershared = false,
    Map<String, AlbumInfo>? belongToAlbums,
  }) =>
      MediaEntity(
        files: MediaFilesCollection.fromMap(files),
        dateTaken: dateTaken,
        dateAccuracy:
            dateTakenAccuracy != null ? DateAccuracy.fromInt(dateTakenAccuracy) : null,
        dateTimeExtractionMethod: dateTimeExtractionMethod,
        partnershared: partnershared,
        belongToAlbums: belongToAlbums,
      );

  /// Collection of files associated with this media (primary and secondaries).
  final MediaFilesCollection files;

  /// Map of album name → AlbumInfo, listing all albums where this entity belongs.
  /// This does NOT replace `files`; both are maintained. `belongToAlbums` is the
  /// canonical place to carry album membership metadata forward.
  final Map<String, AlbumInfo> belongToAlbums;

  /// Date when the media was taken/created
  final DateTime? dateTaken;

  /// Accuracy of the date extraction
  final DateAccuracy? dateAccuracy;

  /// Method used to extract the date/time
  final DateTimeExtractionMethod? dateTimeExtractionMethod;

  /// Whether this media was shared by a partner (from Google Photos partner sharing)
  final bool partnershared;

  /// Gets the primary file for this media
  File get primaryFile => files.firstFile;

  /// Gets the legacy accuracy value for backward compatibility
  int? get dateTakenAccuracy => dateAccuracy?.value;

  /// Whether this media has reliable date information
  bool get hasReliableDate => dateAccuracy?.isReliable ?? false;

  /// Whether this media is associated with albums (from files or from belongToAlbums)
  bool get hasAlbumAssociations =>
      files.hasAlbumFiles || belongToAlbums.isNotEmpty;

  /// Gets all album names this media is associated with (union of both sources)
  Set<String> get albumNames {
    final fromFiles = files.albumNames; // depends on your MediaFilesCollection
    if (belongToAlbums.isEmpty) return fromFiles;
    return {...fromFiles, ...belongToAlbums.keys};
  }

  /// Creates a new media entity with additional file association
  /// `albumName` can be null (e.g., year folder/main source). If provided, we also
  /// update belongToAlbums with the parent directory of this file as a source dir.
  MediaEntity withFile(final String? albumName, final File file) {
    final newFiles = files.withFile(albumName, file);

    Map<String, AlbumInfo> nextAlbums = belongToAlbums;
    if (albumName != null) {
      final parentDir = file.parent.path;
      final existing = belongToAlbums[albumName];
      final updated = (existing == null)
          ? AlbumInfo(name: albumName, sourceDirectories: {parentDir})
          : existing.addSourceDir(parentDir);
      nextAlbums = Map<String, AlbumInfo>.from(belongToAlbums)
        ..[albumName] = updated;
    }

    return MediaEntity(
      files: newFiles,
      dateTaken: dateTaken,
      dateAccuracy: dateAccuracy,
      dateTimeExtractionMethod: dateTimeExtractionMethod,
      partnershared: partnershared,
      belongToAlbums: nextAlbums,
    );
  }

  /// Creates a new media entity with multiple additional files
  /// For each (albumName, file) we also update belongToAlbums accordingly.
  MediaEntity withFiles(final Map<String?, File> additionalFiles) {
    final newFiles = files.withFiles(additionalFiles);

    if (additionalFiles.isEmpty) {
      return MediaEntity(
        files: newFiles,
        dateTaken: dateTaken,
        dateAccuracy: dateAccuracy,
        dateTimeExtractionMethod: dateTimeExtractionMethod,
        partnershared: partnershared,
        belongToAlbums: belongToAlbums,
      );
    }

    final next = Map<String, AlbumInfo>.from(belongToAlbums);
    additionalFiles.forEach((final String? albumName, final File file) {
      if (albumName == null) return; // main/year file, no album
      final parentDir = file.parent.path;
      final existing = next[albumName];
      final updated = (existing == null)
          ? AlbumInfo(name: albumName, sourceDirectories: {parentDir})
          : existing.addSourceDir(parentDir);
      next[albumName] = updated;
    });

    return MediaEntity(
      files: newFiles,
      dateTaken: dateTaken,
      dateAccuracy: dateAccuracy,
      dateTimeExtractionMethod: dateTimeExtractionMethod,
      partnershared: partnershared,
      belongToAlbums: next,
    );
  }

  /// Creates a new media entity with updated date information
  MediaEntity withDate({
    final DateTime? dateTaken,
    final DateAccuracy? dateAccuracy,
    final DateTimeExtractionMethod? dateTimeExtractionMethod,
  }) =>
      MediaEntity(
        files: files,
        dateTaken: dateTaken ?? this.dateTaken,
        dateAccuracy: dateAccuracy ?? this.dateAccuracy,
        dateTimeExtractionMethod:
            dateTimeExtractionMethod ?? this.dateTimeExtractionMethod,
        partnershared: partnershared,
        belongToAlbums: belongToAlbums,
      );

  /// Returns a new entity without a specific album association in the files collection.
  /// Does not erase belongToAlbums on purpose (it is metadata; a separate decision can clear it).
  MediaEntity withoutAlbum(final String? albumName) => MediaEntity(
        files: files.withoutAlbum(albumName),
        dateTaken: dateTaken,
        dateAccuracy: dateAccuracy,
        dateTimeExtractionMethod: dateTimeExtractionMethod,
        partnershared: partnershared,
        belongToAlbums: belongToAlbums,
      );

  /// Returns a new entity with an explicit album membership update (metadata only).
  /// Does not add a physical file; use withFile/withFiles for that.
  MediaEntity withAlbumInfo(final String albumName, {final String? sourceDir}) {
    if (albumName.isEmpty) return this;
    final existing = belongToAlbums[albumName];
    final updated = (existing == null)
        ? AlbumInfo(
            name: albumName,
            sourceDirectories: sourceDir != null && sourceDir.isNotEmpty
                ? {sourceDir}
                : const {},
          )
        : (sourceDir != null && sourceDir.isNotEmpty
            ? existing.addSourceDir(sourceDir)
            : existing);
    final next = Map<String, AlbumInfo>.from(belongToAlbums)
      ..[albumName] = updated;
    return MediaEntity(
      files: files,
      dateTaken: dateTaken,
      dateAccuracy: dateAccuracy,
      dateTimeExtractionMethod: dateTimeExtractionMethod,
      partnershared: partnershared,
      belongToAlbums: next,
    );
  }

  /// Merges this media entity with another, taking the better date accuracy,
  /// union of physical files and a deep merge of `belongToAlbums`.
  MediaEntity mergeWith(final MediaEntity other) {
    // 1) Combine all files via MediaFilesCollection
    final combinedFiles = files.withFiles(other.files.files);

    // 2) Combine album metadata
    final Map<String, AlbumInfo> mergedAlbums = <String, AlbumInfo>{};
    // Start with "this"
    for (final entry in belongToAlbums.entries) {
      mergedAlbums[entry.key] = entry.value;
    }
    // Merge "other"
    for (final entry in other.belongToAlbums.entries) {
      final String album = entry.key;
      final AlbumInfo incoming = entry.value;
      final AlbumInfo? existing = mergedAlbums[album];
      mergedAlbums[album] =
          existing == null ? incoming : existing.merge(incoming);
    }

    // 3) Pick the best date info (the same policy you already had)
    final DateTime? bestDate;
    final DateAccuracy? bestAccuracy;
    final DateTimeExtractionMethod? bestMethod;

    if (dateAccuracy == null && other.dateAccuracy == null) {
      bestDate = dateTaken ?? other.dateTaken;
      bestAccuracy = null;
      bestMethod = dateTimeExtractionMethod ?? other.dateTimeExtractionMethod;
    } else if (dateAccuracy == null) {
      bestDate = other.dateTaken;
      bestAccuracy = other.dateAccuracy;
      bestMethod = other.dateTimeExtractionMethod;
    } else if (other.dateAccuracy == null) {
      bestDate = dateTaken;
      bestAccuracy = dateAccuracy;
      bestMethod = dateTimeExtractionMethod;
    } else {
      if (dateAccuracy!.isBetterThan(other.dateAccuracy!)) {
        bestDate = dateTaken;
        bestAccuracy = dateAccuracy;
        bestMethod = dateTimeExtractionMethod;
      } else {
        bestDate = other.dateTaken;
        bestAccuracy = other.dateAccuracy;
        bestMethod = other.dateTimeExtractionMethod;
      }
    }

    return MediaEntity(
      files: combinedFiles,
      dateTaken: bestDate,
      dateAccuracy: bestAccuracy,
      dateTimeExtractionMethod: bestMethod,
      partnershared: partnershared || other.partnershared,
      belongToAlbums: mergedAlbums,
    );
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) return true;
    return other is MediaEntity &&
        other.files == files &&
        other.dateTaken == dateTaken &&
        other.dateAccuracy == dateAccuracy &&
        other.dateTimeExtractionMethod == dateTimeExtractionMethod &&
        other.partnershared == partnershared &&
        // compare album keys (values can be large; keep equality light-weight)
        _sameAlbumKeys(other.belongToAlbums.keys, belongToAlbums.keys);
  }

  @override
  int get hashCode => Object.hash(
        files,
        dateTaken,
        dateAccuracy,
        dateTimeExtractionMethod,
        partnershared,
        // hash album keys only (stable enough for sets/maps usage)
        Object.hashAllUnordered(belongToAlbums.keys),
      );

  @override
  String toString() {
    final dateInfo = dateTaken != null ? ', dateTaken: $dateTaken' : '';
    final accuracyInfo =
        dateAccuracy != null ? ' (${dateAccuracy!.description})' : '';
    final partnerInfo = partnershared ? ', partnershared: true' : '';
    final albumsCount =
        albumNames.length; // union of files + belongToAlbums
    return 'MediaEntity(${primaryFile.path}$dateInfo$accuracyInfo, albums: $albumsCount$partnerInfo)';
  }

  static bool _sameAlbumKeys(
    final Iterable<String> a,
    final Iterable<String> b,
  ) {
    if (identical(a, b)) return true;
    final sa = a.toSet();
    final sb = b.toSet();
    if (sa.length != sb.length) return false;
    return sa.containsAll(sb);
  }
}
