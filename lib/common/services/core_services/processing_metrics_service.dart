/// Service for calculating processing metrics and file counts
///
/// Extracted from utils.dart to provide focused functionality for
/// calculating expected outputs and processing statistics.
library;
import 'package:gpth/gpth-lib.dart';


/// Service for calculating processing metrics
class ProcessingMetricsService {
  /// Creates a new processing metrics service
  const ProcessingMetricsService();

  /// Calculates total number of output files based on album behavior
  ///
  /// [collection] Collection of media entities
  /// [albumOption] Album handling option ('shortcut', 'duplicate-copy', etc.)
  /// Returns expected number of output files
  int calculateOutputFileCount(
    final MediaEntityCollection collection,
    final String albumOption,
  ) {
    switch (albumOption) {
      case 'shortcut':
      case 'duplicate-copy':
      case 'reverse-shortcut':
        return collection.media.fold(
          0,
          (final int prev, final MediaEntity e) => prev + e.files.length,
        );
      case 'json':
        return collection.media.length;
      case 'nothing':
        return collection.media
            .where(
              (final MediaEntity e) =>
                  e.files.files.values.any((final f) => f.path.isNotEmpty),
            )
            .length;
      default:
        throw ArgumentError.value(
          albumOption,
          'albumOption',
          'Unknown album option. Valid options are: shortcut, duplicate-copy, reverse-shortcut, json, nothing',
        );
    }
  }

  /// Calculates processing statistics
  ///
  /// Returns a map with various metrics about the media collection
  Map<String, dynamic> calculateStatistics(
    final MediaEntityCollection collection,
  ) {
    final stats = <String, dynamic>{};
    stats['totalMedia'] = collection.media.length;
    stats['mediaWithDates'] = collection.media
        .where((final m) => m.dateTaken != null)
        .length;
    stats['mediaWithAlbums'] = collection.media
        .where((final m) => m.hasAlbumAssociations)
        .length;
    stats['totalFiles'] = collection.media.fold(
      0,
      (final int sum, final m) => sum + m.files.length,
    );

    // Calculate by album options
    for (final option in ['shortcut', 'duplicate-copy', 'json', 'nothing']) {
      stats['outputCount_$option'] = calculateOutputFileCount(
        collection,
        option,
      );
    }

    return stats;
  }
}
