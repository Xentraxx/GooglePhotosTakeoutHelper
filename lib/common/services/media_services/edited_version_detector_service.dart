import 'package:path/path.dart' as path;
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'package:gpth/gpth-lib.dart';

/// Service for handling "extra" format files (edited versions)
///
/// This service provides functionality to identify and remove edited versions
/// of photos and videos, such as files ending with "-edited", "-bearbeitet", etc.
class EditedVersionDetectorService {
  /// Creates a new edited version detector service
  const EditedVersionDetectorService();

  /// Checks if a filename matches "extra" format patterns (edited versions)
  ///
  /// Returns true if the filename (without extension) ends with any language-specific
  /// "edited" suffix like "-edited", "-bearbeitet", "-modifié", etc.
  /// Uses Unicode normalization to handle accented characters correctly on macOS.
  ///
  /// [filename] Filename to check (can include path and extension)
  /// Returns true if the file appears to be an edited version
  bool isExtra(final String filename) {
    final String name = path.withoutExtension(path.basename(filename)).toLowerCase();
    for (final String extra in extraFormats) {
      // MacOS uses NFD that doesn't work with our accents 🙃🙃
      // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/247
      if (unorm.nfc(name).endsWith(extra)) {
        return true;
      }
    }
    return false;
  }

  /// Removes media files that match "extra" format patterns (edited versions)
  ///
  /// Filters out files with names ending in language-specific "edited" suffixes
  /// like "-edited", "-bearbeitet", "-modifié", etc. Uses Unicode normalization
  /// to handle accented characters correctly on macOS.
  ///
  /// [collection] MediaEntityCollection to filter
  /// Returns new collection with extras removed and count of removed items
  ({MediaEntityCollection collection, int removedCount}) removeExtras(
    final MediaEntityCollection collection,
  ) {
    final List<MediaEntity> filteredEntities = [];
    int removedCount = 0;

    for (final MediaEntity entity in collection.media) {
      final String name = path.withoutExtension(path.basename(entity.files.firstFile.path))
          .toLowerCase();
      final String normalizedName = unorm.nfc(name);

      bool isExtra = false;
      for (final String extra in extraFormats) {
        if (normalizedName.endsWith(extra)) {
          isExtra = true;
          break;
        }
      }

      if (isExtra) {
        removedCount++;
      } else {
        filteredEntities.add(entity);
      }
    }

    return (
      collection: MediaEntityCollection(filteredEntities),
      removedCount: removedCount,
    );
  }

  /// Removes "extra" format suffixes from filenames
  ///
  /// Uses multiple strategies to identify and remove edited format suffixes:
  /// 1. Direct suffix matching
  /// 2. Partial suffix matching for truncated names
  /// 3. Cross-extension pattern matching
  /// 4. Edge case pattern matching
  ///
  /// [filename] Original filename
  /// Returns filename with extra formats removed, or original if no match
  // ignore: prefer_expression_function_bodies
  String removeExtraFormats(final String filename) {
    // Try each strategy in order of specificity
    final String? completeResult = removeCompleteExtraFormats(filename);
    if (completeResult != null) return completeResult;

    final String partialResult = removePartialExtraFormats(filename);
    if (partialResult != filename) return partialResult;

    final String? crossExtResult = removeCrossExtensionExtraFormats(filename);
    if (crossExtResult != null) return crossExtResult;

    final String? edgeCaseResult = removeEdgeCaseExtraFormats(filename);
    if (edgeCaseResult != null) return edgeCaseResult;

    return filename;
  }

  /// Strategy 1: Direct matching against complete extra format list
  ///
  /// Most conservative strategy that only removes suffixes that exactly
  /// match known patterns from the extraFormats list.
  ///
  /// [filename] Original filename
  /// Returns filename with complete extra formats removed, or null if no match
  String? removeCompleteExtraFormats(final String filename) {
    // MacOS uses NFD that doesn't work with our accents 🙃🙃
    final String normalizedFilename = unorm.nfc(filename);
    final String originalExt = path.extension(normalizedFilename);
    final String nameWithoutExt = path.basenameWithoutExtension(
      normalizedFilename,
    );

    for (final String suffix in extraFormats) {
      if (nameWithoutExt.toLowerCase().endsWith(suffix)) {
        final String cleanName = nameWithoutExt.substring(
          0,
          nameWithoutExt.length - suffix.length,
        );
        final String dirname = path.dirname(normalizedFilename);
        return dirname == '.'
            ? '$cleanName$originalExt'
            : path.join(dirname, '$cleanName$originalExt');
      }
    }
    return null;
  }

  /// Strategy 2: Partial matching for truncated extra formats
  ///
  /// Handles cases where filename truncation (e.g., due to filesystem limits)
  /// results in partial suffix matches. For example, "-ed" will be removed
  /// if it matches the beginning of a known extra format like "-edited".
  ///
  /// This addresses issue #29 where truncated filenames prevent proper JSON
  /// file matching for date extraction.
  ///
  /// [filename] Original filename that may contain partial suffixes
  /// Returns filename with partial suffixes removed, or original if no removal needed
  String removePartialExtraFormats(final String filename) {
    final String ext = path.extension(filename);
    final String nameWithoutExt = path.basenameWithoutExtension(filename);

    for (final String suffix in extraFormats) {
      for (int i = 2; i <= suffix.length; i++) {
        final String partialSuffix = suffix.substring(0, i);
        final RegExp regExp = RegExp(
          RegExp.escape(partialSuffix) + r'(?:\(\d+\))?$',
          caseSensitive: false,
        );

        if (regExp.hasMatch(nameWithoutExt)) {
          final String cleanedName = nameWithoutExt.replaceAll(regExp, '');
          return cleanedName + ext;
        }
      }
    }

    return filename;
  }

  /// Strategy 3: Cross-extension pattern matching
  ///
  /// Handles cases where file extensions were changed but editing
  /// suffixes remain in the base name.
  ///
  /// [filename] Original filename
  /// Returns filename with cross-extension patterns removed, or null if no match
  String? removeCrossExtensionExtraFormats(final String filename) {
    // Check for patterns like "photo-edited.mp4" -> "photo.jpg"
    final String normalizedFilename = unorm.nfc(filename);
    final String nameWithoutExt = path.basenameWithoutExtension(
      normalizedFilename,
    );
    final String ext = path.extension(normalizedFilename);

    // Look for cross-extension patterns where editing suffixes exist
    // but the extension might have changed
    for (final String suffix in extraFormats) {
      if (nameWithoutExt.toLowerCase().endsWith(suffix)) {
        final String baseName = nameWithoutExt.substring(
          0,
          nameWithoutExt.length - suffix.length,
        );

        // For video extensions, try common photo extensions
        if (['.mp4', '.mov', '.avi'].contains(ext.toLowerCase())) {
          final String dirname = path.dirname(normalizedFilename);
          return dirname == '.'
              ? '$baseName.jpg'
              : path.join(dirname, '$baseName.jpg');
        }
      }
    }

    return null;
  }

  /// Strategy 4: Last resort pattern matching for edge cases
  ///
  /// Handles edge cases where other strategies might miss truncated patterns.
  /// Looks for any pattern ending with dash and partial text that could be
  /// a truncated "edited" suffix.
  ///
  /// [filename] Original filename
  /// Returns filename with edge case patterns removed, or null if no match
  String? removeEdgeCaseExtraFormats(final String filename) {
    // MacOS uses NFD that doesn't work with our accents 🙃🙃
    final String normalizedFilename = unorm.nfc(filename);
    final String originalExt = path.extension(normalizedFilename);

    final RegExpMatch? lastDashMatch = RegExp(
      r'-[a-zA-ZÀ-ÖØ-öø-ÿ\s]*(\(\d+\))?$',
    ).firstMatch(path.basenameWithoutExtension(normalizedFilename));

    if (lastDashMatch == null) return null;

    final String beforeDash = path.basenameWithoutExtension(normalizedFilename)
        .substring(0, lastDashMatch.start);
    final String afterDash = lastDashMatch.group(0)!;

    // Check if the text after dash could be a truncated "edited" suffix
    for (final String suffix in extraFormats) {
      // Remove the leading dash for comparison
      final String suffixWithoutDash = suffix.substring(1);
      final String afterDashClean = afterDash
          .replaceAll(RegExp(r'\(\d+\)'), '')
          .substring(1);

      // If what comes after dash could be start of any extra format
      if (suffixWithoutDash.toLowerCase().startsWith(
            afterDashClean.toLowerCase(),
          ) &&
          afterDashClean.length >= 2) {
        // At least 2 chars to avoid false positives
        final String dirname = path.dirname(normalizedFilename);
        return dirname == '.'
            ? '$beforeDash$originalExt'
            : path.join(dirname, '$beforeDash$originalExt');
      }
    }

    return null;
  }

  /// Restores file extensions that may have been truncated
  ///
  /// When filename truncation affects the extension, this function attempts
  /// to restore common photo/video extensions based on partial matches.
  /// Example: "truncated_name.jp" -> "truncated_name.jpg"
  ///
  /// [filename] Filename with potentially truncated extension
  /// [originalExt] Original extension before processing (unused, kept for compatibility)
  /// Returns filename with restored extension, or original filename if no restoration needed
  String restoreFileExtension(final String filename, final String originalExt) {
    final String currentExt = path.extension(filename);

    // Only attempt restoration if the current extension looks truncated
    if (currentExt.length > 4 || currentExt.length < 2) {
      return filename;
    }

    // Common photo/video extensions that might get truncated
    const List<String> commonExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.mp4',
      '.mov',
      '.avi',
      '.heic',
      '.tiff',
      '.mp',
    ];

    for (final String ext in commonExtensions) {
      if (ext.toLowerCase().startsWith(currentExt.toLowerCase()) &&
          ext.length <= 4) {
        // Reasonable extension length
        final String nameWithoutExt = path.basenameWithoutExtension(filename);
        final String dirname = path.dirname(filename);
        return dirname == '.'
            ? '$nameWithoutExt$ext'
            : path.join(dirname, '$nameWithoutExt$ext');
      }
    }
    return filename;
  }
}
