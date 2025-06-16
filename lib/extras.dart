import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'media.dart';

const List<String> extraFormats = <String>[
  // EN/US - thanks @DalenW
  '-edited',
  '-effects',
  '-smile',
  '-mix',
  // PL
  '-edytowane',
  // DE - thanks @cintx
  '-bearbeitet',
  // NL - thanks @jaapp
  '-bewerkt', // JA - thanks @fossamagna
  '-編集済み',
  // ZH - Chinese
  '-编辑',
  // IT - thanks @rgstori
  '-modificato',
  // FR - for @palijn's problems <3
  '-modifié', // ES - @Sappstal report
  '-ha editado',
  '-editado',
  // CA - @Sappstal report
  '-editat',
  // Add more "edited" flags in more languages if you want.
  // They need to be lowercase.
];

/// Removes media files that match "extra" format patterns (edited versions)
///
/// Filters out files with names ending in language-specific "edited" suffixes
/// like "-edited", "-bearbeitet", "-modifié", etc. Uses Unicode normalization
/// to handle accented characters correctly on macOS.
///
/// [media] List of Media objects to filter
/// Returns count of removed items
int removeExtras(final List<Media> media) {
  final List<Media> copy = media.toList();
  int count = 0;
  for (final Media m in copy) {
    final String name = p
        .withoutExtension(p.basename(m.firstFile.path))
        .toLowerCase();
    for (final String extra in extraFormats) {
      // MacOS uses NFD that doesn't work with our accents 🙃🙃
      // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/247
      if (unorm.nfc(name).endsWith(extra)) {
        media.remove(m);
        count++;
        break;
      }
    }
  }
  return count;
}

/// Checks if a filename matches "extra" format patterns (edited versions)
///
/// Returns true if the filename (without extension) ends with any language-specific
/// "edited" suffix like "-edited", "-bearbeitet", "-modifié", etc.
/// Uses Unicode normalization to handle accented characters correctly on macOS.
///
/// [filename] Filename to check (can include path and extension)
/// Returns true if the file appears to be an edited version
bool isExtra(final String filename) {
  final String name = p.withoutExtension(p.basename(filename)).toLowerCase();
  for (final String extra in extraFormats) {
    // MacOS uses NFD that doesn't work with our accents 🙃🙃
    // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/247
    if (unorm.nfc(name).endsWith(extra)) {
      return true;
    }
  }
  return false;
}

/// Removes partial extra format suffixes from filenames
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
  final String ext = p.extension(filename);
  final String nameWithoutExt = p.basenameWithoutExtension(filename);
  final String dirname = p.dirname(filename);
  for (final String suffix in extraFormats) {
    for (int i = 1; i <= suffix.length; i++) {
      final String partialSuffix = suffix.substring(0, i);

      // Skip very short suffixes that are likely to cause false positives
      if (partialSuffix.length < 2 ||
          (partialSuffix.length == 1 && partialSuffix == '-')) {
        continue;
      }

      final RegExp regExp = RegExp(
        RegExp.escape(partialSuffix) + r'(?:\(\d+\))?$',
        caseSensitive: false,
      );

      if (regExp.hasMatch(nameWithoutExt)) {
        final String cleanedName = nameWithoutExt.replaceAll(regExp, '');
        // Preserve directory path and original path separator style
        if (dirname == '.') {
          return '$cleanedName$ext';
        } else {
          // Preserve the original path separator style from the input
          final String separator = filename.contains('/') ? '/' : p.separator;
          return '$dirname$separator$cleanedName$ext';
        }
      }
    }
  }
  return filename;
}

/// Strategy 1: Removes complete extra format suffixes using regex patterns
///
/// Uses regex to match complete suffixes with optional digit patterns.
/// Example: "photo-edited(1).jpg" -> "photo.jpg"
///
/// [filename] Original filename
/// Returns filename with complete extra patterns removed, or null if no match
String? removeCompleteExtraFormats(final String filename) {
  // MacOS uses NFD that doesn't work with our accents 🙃🙃
  // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/247
  final String normalizedFilename = unorm.nfc(filename);

  // Include all characters, also with accents
  final Iterable<RegExpMatch> matches = RegExp(
    r'(?<extra>-[A-Za-zÀ-ÖØ-öø-ÿ]+(\(\d\))?)\.\w+$',
  ).allMatches(normalizedFilename);

  if (matches.length == 1) {
    return normalizedFilename.replaceAll(
      matches.first.namedGroup('extra')!,
      '',
    );
  }

  return null;
}

/// Strategy 3: Restores file extensions that may have been truncated
///
/// When filename truncation affects the extension, this function attempts
/// to restore common photo/video extensions based on partial matches.
/// Example: "truncated_name.jp" -> "truncated_name.jpg"
///
/// [filename] Filename with potentially truncated extension
/// [originalExt] Original extension before processing (unused, kept for compatibility)
/// Returns filename with restored extension, or original filename if no restoration needed
String restoreFileExtension(final String filename, final String originalExt) {
  final String currentExt = p.extension(filename);

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
  ];

  for (final String ext in commonExtensions) {
    if (ext.toLowerCase().startsWith(currentExt.toLowerCase()) &&
        ext.length <= 4) {
      // Reasonable extension length
      final String nameWithoutExt = p.basenameWithoutExtension(filename);
      final String dirname = p.dirname(filename);
      return dirname == '.'
          ? '$nameWithoutExt$ext'
          : p.join(dirname, '$nameWithoutExt$ext');
    }
  }
  return filename;
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
  final String originalExt = p.extension(normalizedFilename);

  final RegExpMatch? lastDashMatch = RegExp(
    r'-[a-zA-ZÀ-ÖØ-öø-ÿ\s]*(\(\d+\))?$',
  ).firstMatch(p.basenameWithoutExtension(normalizedFilename));

  if (lastDashMatch == null) return null;

  final String beforeDash = p
      .basenameWithoutExtension(normalizedFilename)
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
      final String dirname = p.dirname(normalizedFilename);
      return dirname == '.'
          ? '$beforeDash$originalExt'
          : p.join(dirname, '$beforeDash$originalExt');
    }
  }

  return null;
}
