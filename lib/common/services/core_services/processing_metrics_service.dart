import 'package:gpth/gpth_lib_exports.dart';

/// Service for calculating processing metrics
class ProcessingMetricsService {
  /// Creates a new processing metrics service
  const ProcessingMetricsService();

  /// Calculates total number of output artifacts based on album behavior.
  ///
  /// New immutable model semantics:
  /// - "shortcut"  / "reverse-shortcut":
  ///   1 output for the primary + one artifact per album membership.
  /// - "json": one record per primary entity.
  /// - "nothing": only primary entities (those thatoriginally lived in year-based folders).
  /// - "duplicate-copy":
  ///   1 record for each primary and one record per each secondary
  ///
  /// UPDATE (counting rule used by this function):
  /// - We count generated items as follows:
  ///   * "shortcut" / "reverse-shortcut": 1 physical file (primary) + one SHORTCUT per secondary (shortcuts are counted).
  ///   * "json" / "nothing": 1 physical file per primary.
  ///   * "duplicate-copy": 1 physical file per primary + 1 physical file per secondary.
  int calculateOutputFileCount(
    final MediaEntityCollection collection,
    final String albumOption,
  ) {
    switch (albumOption) {
      case 'shortcut':
      case 'reverse-shortcut':
        {
          int total = 0;
          for (final MediaEntity e in collection.media) {
            total +=
                1 +
                e.secondaryCount; // 1 physical primary + N shortcuts (counted)
          }
          return total;
        }

      case 'duplicate-copy':
        {
          int total = 0;
          for (final MediaEntity e in collection.media) {
            total +=
                1 + e.secondaryCount; // 1 physical primary + N physical copies
          }
          return total;
        }

      case 'json':
      case 'nothing':
        // 1 physical file per primary entity
        return collection.media.length;

      default:
        throw ArgumentError.value(
          albumOption,
          'albumOption',
          'Unknown album option. Valid options: shortcut, duplicate-copy, reverse-shortcut, json, nothing',
        );
    }
  }

  /// Calculates basic statistics for the current collection.
  ///
  /// totalFiles = primary (1) + count of secondary files for each entity (physical inputs).
  Map<String, dynamic> calculateStatistics(
    final MediaEntityCollection collection,
  ) {
    final stats = <String, dynamic>{};

    // Totals
    stats['totalMedia'] = collection.media.length;

    // Media with a date assigned
    int mediaWithDates = 0;
    for (final m in collection.media) {
      if (m.dateTaken != null) mediaWithDates++;
    }
    stats['mediaWithDates'] = mediaWithDates;

    // Media with any album association
    int mediaWithAlbums = 0;
    for (final m in collection.media) {
      if (m.hasAlbumAssociations) mediaWithAlbums++;
    }
    stats['mediaWithAlbums'] = mediaWithAlbums;

    // Physical input files tracked by the model (primary + secondaries)
    int totalFiles = 0;
    for (final m in collection.media) {
      totalFiles += 1 + m.secondaryFiles.length;
    }
    stats['totalFiles'] = totalFiles;

    // Output counts by album options
    for (final option in const [
      'shortcut',
      'duplicate-copy',
      'reverse-shortcut',
      'json',
      'nothing',
    ]) {
      stats['outputCount_$option'] = calculateOutputFileCount(
        collection,
        option,
      );
    }

    return stats;
  }
}
