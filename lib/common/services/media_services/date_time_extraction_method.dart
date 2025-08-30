/// Enumeration of methods used to extract date/time information from media files
///
/// Order is important! This represents the preference/accuracy order.
/// Lower enum values indicate higher accuracy and should be preferred
/// when resolving conflicts between multiple date sources.
enum DateTimeExtractionMethod {
  /// Extracted from JSON metadata (most accurate)
  json,

  /// Extracted from EXIF data
  exif,

  /// Guessed from filename
  guess,

  /// Extracted from JSON with tryhard mode
  jsonTryHard,

  /// Extracted from parent folder year pattern
  folderYear,

  /// No date extraction performed
  none,
}

/// Extension to add accuracy scoring and legacy compatibility
extension DateTimeExtractionMethodExtensions on DateTimeExtractionMethod {
  /// Returns the accuracy score for this extraction method
  /// Lower numbers indicate higher accuracy
  int get accuracyScore {
    switch (this) {
      case DateTimeExtractionMethod.json:
        return 1;
      case DateTimeExtractionMethod.exif:
        return 2;
      case DateTimeExtractionMethod.guess:
        return 3;
      case DateTimeExtractionMethod.jsonTryHard:
        return 4;
      case DateTimeExtractionMethod.folderYear:
        return 5;
      case DateTimeExtractionMethod.none:
        return 99;
    }
  }

  /// Whether this extraction method provides reliable date information
  bool get isReliable => this != DateTimeExtractionMethod.none;

  /// Human-readable description of the extraction method
  String get description {
    switch (this) {
      case DateTimeExtractionMethod.json:
        return 'JSON metadata';
      case DateTimeExtractionMethod.exif:
        return 'EXIF data';
      case DateTimeExtractionMethod.guess:
        return 'filename guess';
      case DateTimeExtractionMethod.jsonTryHard:
        return 'JSON tryhard';
      case DateTimeExtractionMethod.folderYear:
        return 'folder year';
      case DateTimeExtractionMethod.none:
        return 'No extraction';
    }
  }
}
