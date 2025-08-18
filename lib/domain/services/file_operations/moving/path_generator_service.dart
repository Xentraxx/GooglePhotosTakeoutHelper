import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../models/processing_config_model.dart';
import 'moving_context_model.dart';

/// Service responsible for generating file and directory paths
///
/// This service handles all path generation logic for the moving operations,
/// including date-based folder structures and album-specific paths.
class PathGeneratorService {
  /// Generates the target directory for a file based on album and date information
  ///
  /// [albumKey] The album name (null for ALL_PHOTOS)
  /// [dateTaken] The date the photo was taken
  /// [context] The moving context with configuration
  /// Returns the target directory path
  Directory generateTargetDirectory(
    final String? albumKey,
    final DateTime? dateTaken,
    final MovingContext context,
  ) {
    final String folderName = albumKey?.trim() ?? 'ALL_PHOTOS';
    // Only apply date division to ALL_PHOTOS, not to Albums
    final String dateFolder = albumKey == null
        ? _generateDateFolder(dateTaken, context.dateDivision)
        : '';

    return Directory(
      p.join(context.outputDirectory.path, folderName, dateFolder),
    );
  }

  /// Generates the date-based folder structure
  String _generateDateFolder(
    final DateTime? date,
    final DateDivisionLevel divideToDates,
  ) {
    if (divideToDates == DateDivisionLevel.none) {
      return '';
    }

    if (date == null) {
      return 'date-unknown';
    }

    switch (divideToDates) {
      case DateDivisionLevel.day:
        return p.join(
          '${date.year}',
          date.month.toString().padLeft(2, '0'),
          date.day.toString().padLeft(2, '0'),
        );
      case DateDivisionLevel.month:
        return p.join('${date.year}', date.month.toString().padLeft(2, '0'));
      case DateDivisionLevel.year:
        return '${date.year}';
      case DateDivisionLevel.none:
        return '';
    }
  }

  /// Generates the albums-info.json file path
  String generateAlbumsInfoJsonPath(final Directory outputDirectory) =>
      p.join(outputDirectory.path, 'albums-info.json');

  /// Generates ALL_PHOTOS directory path
  Directory generateAllPhotosDirectory(final Directory outputDirectory) =>
      Directory(p.join(outputDirectory.path, 'ALL_PHOTOS'));

  /// Sanitizes a filename to ensure cross-platform compatibility
  String sanitizeFileName(final String fileName) => fileName
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Gets the target file path for a specific file in a directory
  String generateTargetFilePath(
    final File sourceFile,
    final Directory targetDirectory,
  ) {
    final sanitizedName = sanitizeFileName(p.basename(sourceFile.path));
    return p.join(targetDirectory.path, sanitizedName);
  }
}
