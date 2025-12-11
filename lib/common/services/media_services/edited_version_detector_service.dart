import 'package:gpth/gpth_lib_exports.dart';
import 'package:path/path.dart' as path;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

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
    final String name = path
        .withoutExtension(path.basename(filename))
        .toLowerCase();
    for (final String extra in extraFormats) {
      // macOS may use NFD; normalize to NFC so suffixes with accents match.
      if (unorm.nfc(name).endsWith(extra)) {
        return true;
      }
    }
    return false;
  }

  /// Removes media entities that match "extra" format patterns (edited versions)
  ///
  /// Filters out entities whose **primary file name** ends with an "edited" suffix.
  /// (With the new immutable model we key off `primaryFile` instead of `files.firstFile`.)
  ///
  /// [collection] MediaEntityCollection to filter
  /// Returns a new collection with extras removed and the count of removed items
  ({MediaEntityCollection collection, int removedCount}) removeExtras(
    final MediaEntityCollection collection,
  ) {
    final List<MediaEntity> filteredEntities = [];
    int removedCount = 0;

    for (final MediaEntity entity in collection.media) {
      final String base = path.basename(entity.primaryFile.path);
      final String name = path
          .withoutExtension(base)
          .toLowerCase(); // primary file only
      final String normalizedName = unorm.nfc(name);

      bool isExtraEntity = false;
      for (final String extra in extraFormats) {
        if (normalizedName.endsWith(extra)) {
          isExtraEntity = true;
          break;
        }
      }

      if (isExtraEntity) {
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
  /// Applies multiple strategies:
  /// 1) Direct suffix matching
  /// 2) Partial suffix matching for truncated names
  /// 3) Cross-extension pattern matching
  /// 4) Edge-case pattern matching
  String removeExtraFormats(final String filename) {
    // Strategy 1: complete suffix match
    final String? completeResult = removeCompleteExtraFormats(filename);
    if (completeResult != null) return completeResult;

    // Strategy 2: partial suffix match (returns a basename; keep as-is for backward compat)
    final String partialResult = removePartialExtraFormats(filename);
    if (partialResult != filename) return partialResult;

    // Strategy 3: cross-extension handling
    final String? crossExtResult = removeCrossExtensionExtraFormats(filename);
    if (crossExtResult != null) return crossExtResult;

    // Strategy 4: last-resort edge-case handling
    final String? edgeCaseResult = removeEdgeCaseExtraFormats(filename);
    if (edgeCaseResult != null) return edgeCaseResult;

    return filename;
  }

  /// Strategy 1: Direct matching against complete extra format list
  String? removeCompleteExtraFormats(final String filename) {
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
  String? removeCrossExtensionExtraFormats(final String filename) {
    final String normalizedFilename = unorm.nfc(filename);
    final String nameWithoutExt = path.basenameWithoutExtension(
      normalizedFilename,
    );
    final String ext = path.extension(normalizedFilename);

    for (final String suffix in extraFormats) {
      if (nameWithoutExt.toLowerCase().endsWith(suffix)) {
        final String baseName = nameWithoutExt.substring(
          0,
          nameWithoutExt.length - suffix.length,
        );

        // If the edited version is a video now, try restoring a typical photo extension
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
  String? removeEdgeCaseExtraFormats(final String filename) {
    final String normalizedFilename = unorm.nfc(filename);
    final String originalExt = path.extension(normalizedFilename);

    final RegExpMatch? lastDashMatch = RegExp(
      r'-[a-zA-ZÀ-ÖØ-öø-ÿ\s]*(\(\d+\))?$',
    ).firstMatch(path.basenameWithoutExtension(normalizedFilename));

    if (lastDashMatch == null) return null;

    final String beforeDash = path
        .basenameWithoutExtension(normalizedFilename)
        .substring(0, lastDashMatch.start);
    final String afterDash = lastDashMatch.group(0)!;

    for (final String suffix in extraFormats) {
      final String suffixWithoutDash = suffix.substring(1);
      final String afterDashClean = afterDash
          .replaceAll(RegExp(r'\(\d+\)'), '')
          .substring(1);

      if (suffixWithoutDash.toLowerCase().startsWith(
            afterDashClean.toLowerCase(),
          ) &&
          afterDashClean.length >= 2) {
        final String dirname = path.dirname(normalizedFilename);
        return dirname == '.'
            ? '$beforeDash$originalExt'
            : path.join(dirname, '$beforeDash$originalExt');
      }
    }

    return null;
  }

  /// Restores truncated file extensions (best-effort).
  String restoreFileExtension(final String filename, final String originalExt) {
    final String currentExt = path.extension(filename);

    // Only attempt restoration if the current extension looks truncated
    if (currentExt.length > 4 || currentExt.length < 2) {
      return filename;
    }

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
