import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:coordinate_converter/coordinate_converter.dart';
import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import '../extras.dart' as extras;
import '../utils.dart';

/// Finds corresponding json file with info from media file and gets 'photoTakenTime' from it
Future<DateTime?> jsonDateTimeExtractor(
  final File file, {
  final bool tryhard = false,
}) async {
  final File? jsonFile = await jsonForFile(file, tryhard: tryhard);
  if (jsonFile == null) return null;
  try {
    final dynamic data = jsonDecode(await jsonFile.readAsString());
    final int epoch = int.parse(data['photoTakenTime']['timestamp'].toString());
    return DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
  } on FormatException catch (_) {
    // this is when json is bad
    return null;
  } on FileSystemException catch (_) {
    // this happens for issue #143
    // "Failed to decode data using encoding 'utf-8'"
    // maybe this will self-fix when dart itself support more encodings
    return null;
  } on NoSuchMethodError catch (_) {
    // this is when tags like photoTakenTime aren't there
    return null;
  }
}

/// Attempts to find the corresponding JSON file for a media file
///
/// Tries multiple strategies to locate JSON files, including handling
/// filename truncation, bracket swapping, and extra format removal.
/// Strategies are ordered from least to most aggressive (issue #29).
///
/// [file] Media file to find JSON for
/// [tryhard] If true, uses more aggressive matching strategies
/// Returns the JSON file if found, null otherwise
Future<File?> jsonForFile(
  final File file, {
  required final bool tryhard,
}) async {
  final Directory dir = Directory(p.dirname(file.path));
  final String name = p.basename(file.path);

  // Basic strategies (always applied) - ordered from most reliable to least reliable
  // Each strategy addresses specific, well-documented scenarios where JSON files
  // might not match their corresponding media files due to Google Photos processing
  final basicStrategies = <String Function(String s)>[
    // Strategy 1: No modification (100% reliable)
    // Try exact filename match first - this handles the majority of cases
    // where Google Photos preserved original filenames
    (final String s) => s,

    // Strategy 2: Filename shortening (high reliability)
    // Handles filesystem filename length limits (51 chars on some systems)
    // Google Photos sometimes truncates long filenames during export
    _shortenName,

    // Strategy 3: Bracket number swapping (high reliability)
    // Addresses known Google Photos pattern: "image(11).jpg" vs "image.jpg(11).json"
    // This is a documented behavior where numbering position differs between file types
    _bracketSwap,

    // Strategy 4: Extension fixing reverse lookup (high reliability, issue #32)
    // Handles files renamed by extension fixing: "file.jpg.heic" → "file.heic"
    // MUST run before _noExtension to avoid false matches
    // Addresses specific scenario where extension fixing breaks JSON pairing
    _removeExtensionFixingSuffix,

    // Strategy 5: Remove file extension (medium reliability)
    // Handles cases where Google added extensions to originally extension-less files
    // More aggressive than above strategies but still common enough to be in basic set
    _noExtension,

    // Strategy 6: Remove complete extra formats (medium-high reliability)
    // Removes known "edited" suffixes like "-edited", "-bearbeitet", "-modifié"
    // Uses predefined safe list, so relatively reliable but more aggressive
    _removeExtraComplete,
  ];
  // Aggressive strategies (only with tryhard=true) - ordered from least to most aggressive
  // These strategies have higher false positive rates but can resolve edge cases
  // They're gated behind tryhard flag to prevent unintended matches in normal operation
  final aggressiveStrategies = <String Function(String s)>[
    // Strategy 7: Remove partial extra formats (medium reliability)
    // Handles filename truncation that cuts off "edited" suffixes mid-word
    // Example: "photo-edited.jpg" truncated to "photo-edit.jpg"
    // Addresses issue #29 but has potential for false positives
    _removeExtraPartial,

    // Strategy 8: Extension restoration after partial removal (medium-low reliability)
    // Combines partial suffix removal with extension reconstruction
    // Handles cases where both suffix AND extension were truncated
    // More complex logic = higher chance of false matches
    _removeExtraPartialWithExtensionRestore,

    // Strategy 9: Edge case pattern removal (low reliability, heuristic-based)
    // Last resort pattern matching using heuristics rather than exact rules
    // Can catch unusual truncation patterns but prone to false positives
    _removeExtraEdgeCase,

    // Strategy 10: Remove digit patterns (very low reliability, most aggressive)
    // Removes any "(digit)" patterns - broadest possible matching
    // Example: "image(2).png" → "image.png"
    // High risk of false matches, only use as absolute last resort
    _removeDigit,
  ];
  // Combine strategies based on tryhard setting
  // Basic strategies are always safe to run and handle 90%+ of cases
  // Aggressive strategies are opt-in due to higher false positive risk
  final allStrategies = [
    ...basicStrategies,
    if (tryhard) ...aggressiveStrategies,
  ];

  // Try each strategy in order of decreasing reliability
  // Stop at first match to avoid false positives from more aggressive strategies
  for (final String Function(String s) method in allStrategies) {
    final String processedName = method(name);

    // For each processed filename, try multiple JSON file patterns
    // Google Photos uses different JSON naming conventions:

    // Pattern 1: supplemental-metadata.json (most common for newer exports)
    // Contains comprehensive metadata including timestamps, location, etc.
    final File supplementalJsonFile = File(
      p.join(dir.path, '$processedName.supplemental-metadata.json'),
    );
    if (await supplementalJsonFile.exists()) {
      return supplementalJsonFile;
    }

    // Pattern 2: standard .json (older exports, simpler metadata)
    // Usually contains basic info like creation time and title
    final File jsonFile = File(p.join(dir.path, '$processedName.json'));
    if (await jsonFile.exists()) {
      return jsonFile;
    }

    // Handle numbered files - special case for Google Photos numbering system
    // Google Photos creates numbered files like "IMG_2367(1).jpg" when duplicates exist
    // But JSON files follow pattern: "IMG_2367.HEIC.supplemental-metadata(1).json"
    // This handles the mismatch between numbering positions
    final RegExp numberedFilePattern = RegExp(r'^(.+)\((\d+)\)$');
    final numberedMatch = numberedFilePattern.firstMatch(processedName);

    if (numberedMatch != null) {
      final baseNameWithoutNumber = numberedMatch.group(1)!;
      final number = numberedMatch.group(2)!;

      // Pattern 3: numbered supplemental-metadata (handles duplicate file numbering)
      // Example: IMG_2367(1).HEIC → IMG_2367.HEIC.supplemental-metadata(1).json
      final File numberedSupplementalJsonFile = File(
        p.join(
          dir.path,
          '$baseNameWithoutNumber.supplemental-metadata($number).json',
        ),
      );
      if (await numberedSupplementalJsonFile.exists()) {
        return numberedSupplementalJsonFile;
      }

      // Pattern 4: numbered standard JSON (older export numbering)
      // Example: IMG_2367(1).HEIC → IMG_2367(1).json
      final File numberedJsonFile = File(
        p.join(dir.path, '$baseNameWithoutNumber($number).json'),
      );
      if (await numberedJsonFile.exists()) {
        return numberedJsonFile;
      }
    }

    // Pattern 5: Case-insensitive fallback (handles extension case mismatches)
    // Sometimes file extensions have different cases between media and JSON files
    // Example: "photo.JPG" vs "photo.jpg.json" - this resolves such mismatches
    final caseInsensitiveJsonFile = await _findJsonFileIgnoringCase(
      dir,
      processedName,
    );
    if (caseInsensitiveJsonFile != null) {
      return caseInsensitiveJsonFile;
    }
  }

  // No JSON file found after trying all strategies
  // This is normal for many files - not all media files have JSON metadata
  return null;
}

/// Handles files renamed by extension fixing process (Strategy 4)
///
/// **WHY THIS EXISTS:** Issue #32 - Extension fixing breaks JSON file pairing
///
/// **THE PROBLEM:** When GPTH fixes incorrect extensions, it renames files like:
/// - "IMG_2367(1).HEIC" (with wrong .jpg extension) → "IMG_2367(1).HEIC.jpg"
/// - But the JSON file remains: "IMG_2367.HEIC.supplemental-metadata(1).json"
/// - Result: JSON file can't be found because filename no longer matches
///
/// **THE SOLUTION:** This function reverses the extension fixing logic to find
/// the original filename pattern that would match existing JSON files.
///
/// **WHY IT RUNS EARLY:** Must execute before _noExtension strategy because:
/// - _noExtension would turn "IMG_2367(1).HEIC.jpg" → "IMG_2367(1).HEIC"
/// - But we need the more specific transformation to "IMG_2367.HEIC(1)"
/// - Order matters: specific patterns before general ones
///
/// **PATTERNS HANDLED:**
/// - Pattern 1: file.jpg.heic → file.heic (wrong ext + correct ext)
/// - Pattern 2: file.heic.jpg → file.heic (correct ext + added ext)
/// - Both patterns handle numbered files: IMG_2367(1).jpg.heic → IMG_2367.HEIC(1)
///
/// [filename] Filename that may have been renamed by extension fixing
/// Returns original filename pattern that would match existing JSON files
String _removeExtensionFixingSuffix(final String filename) {
  // Check if this looks like an extension-fixed file
  // Pattern 1: Wrong extension then correct one: file.jpg.heic (Google Photos scenario)
  // Pattern 2: Original then added: file.heic.jpg (typical fixing scenario)
  final RegExp extensionFixPattern = RegExp(
    r'\.(?:jpg|jpeg|png)\.(heic|heif|tiff|tif|webp|avif|cr2|dng|arw|nef|raf|crw|cr3|nrw)$|'
    r'\.(heic|heif|tiff|tif|webp|avif|cr2|dng|arw|nef|raf|crw|cr3|nrw)\.(?:jpg|jpeg|png)$',
    caseSensitive: false,
  );
  if (extensionFixPattern.hasMatch(filename)) {
    // Handle two patterns:
    // Pattern 1: wrong.ext.correct (e.g., file.jpg.heic) - remove wrong extension
    // Pattern 2: correct.ext.added (e.g., file.heic.jpg) - remove added extension

    String originalFilename;
    String originalExt;

    // Check for Pattern 1: .jpg/.jpeg/.png then .heic/etc (PRESERVE ORIGINAL CASE)
    final RegExp pattern1 = RegExp(
      r'(.+)\.(?:jpg|jpeg|png)\.(heic|heif|tiff|tif|webp|avif|cr2|dng|arw|nef|raf|crw|cr3|nrw)$',
      caseSensitive: false,
    );
    final match1 = pattern1.firstMatch(filename);
    if (match1 != null) {
      // Pattern 1: file.jpg.heic -> file.heic (remove wrong extension, preserve case)
      originalFilename = '${match1.group(1)!}.${match1.group(2)!}';
      originalExt = match1.group(2)!;
    } else {
      // Pattern 2: file.heic.jpg -> file.heic (remove added extension, preserve case)
      final RegExp pattern2 = RegExp(
        r'(.+\.(heic|heif|tiff|tif|webp|avif|cr2|dng|arw|nef|raf|crw|cr3|nrw))\.(?:jpg|jpeg|png)$',
        caseSensitive: false,
      );
      final match2 = pattern2.firstMatch(filename);
      if (match2 != null) {
        originalFilename = match2.group(1)!;
        originalExt = match2.group(2)!;
      } else {
        return filename;
      }
    }

    // CRITICAL: Handle numbered file transformation for JSON matching
    // Extension fixing changes: "IMG_2367(1).jpg.heic" but JSON is: "IMG_2367.HEIC.supplemental-metadata(1).json"
    // We need to transform: "IMG_2367(1).heic" → "IMG_2367.HEIC(1)" to match JSON pattern
    //
    // WHY THIS TRANSFORMATION:
    // - Google Photos JSON: "IMG_2367.HEIC.supplemental-metadata(1).json"
    // - Media file after fixing: "IMG_2367(1).heic"
    // - Transform to: "IMG_2367.HEIC(1)" to match the JSON's base pattern
    final RegExp numberedPattern = RegExp(r'^(.+)\((\d+)\)\.([^.]+)$');
    final numberedMatch = numberedPattern.firstMatch(originalFilename);

    if (numberedMatch != null) {
      // Numbered file: rearrange number position to match JSON pattern
      final baseName = numberedMatch.group(1)!;
      final number = numberedMatch.group(2)!;
      final originalExtPart = numberedMatch.group(3)!;
      // Transform: "IMG_2367(1).heic" → "IMG_2367.HEIC(1)"
      final result = '$baseName.${originalExtPart.toUpperCase()}($number)';

      return result;
    }

    // Non-numbered files: just ensure uppercase extension for consistency
    // Google Photos JSON files typically use uppercase extensions
    final result = originalFilename.replaceAll(
      RegExp('\\.$originalExt\$', caseSensitive: false),
      '.${originalExt.toUpperCase()}',
    );
    return result;
  }

  return filename;
}

/// Removes file extension from filename (Strategy 5)
///
/// **WHY THIS EXISTS:** Google Photos sometimes adds extensions to originally extension-less files
///
/// **THE PROBLEM:** Some files originally had no extension, but Google Photos export adds one
/// - Original file: "screenshot" (no extension)
/// - Google export: "screenshot.png"
/// - JSON file: "screenshot.json"
/// - Without this strategy: no match found
///
/// **THE SOLUTION:** Try matching without any extension
/// Transform "screenshot.png" → "screenshot" to find "screenshot.json"
///
/// **WHY IT RUNS AFTER EXTENSION FIXING:** More general transformation that could
/// interfere with specific extension fixing patterns if run too early
///
/// [filename] Original filename that might have an added extension
/// Returns filename without extension
String _noExtension(final String filename) =>
    p.basenameWithoutExtension(File(filename).path);

/// Removes digit patterns like "(1)" from filenames (Strategy 10 - Most Aggressive)
///
/// **WHY THIS EXISTS:** Last resort for unusual numbering patterns
///
/// **THE PROBLEM:** Some files have digit patterns that don't follow standard conventions
/// - Media file: "image(2).png"
/// - JSON file: "image.png.json" (no numbering)
///
/// **THE SOLUTION:** Remove any digit patterns completely
/// Transform "image(2).png" → "image.png" to find "image.png.json"
///
/// **WHY IT RUNS LAST:** Highest risk of false positives
/// - Could incorrectly match unrelated files with similar names
/// - Only use when all other strategies fail
/// - Broadest possible pattern matching
///
/// **RISK EXAMPLE:** "family_photo(2).jpg" might incorrectly match "family_photo.jpg.json"
/// when they're actually different photos
///
/// [filename] Original filename that might have digit patterns
/// Returns filename with digit patterns removed
String _removeDigit(final String filename) =>
    filename.replaceAll(RegExp(r'\(\d\)\.'), '.');

/// Removes "extra" format suffixes safely using predefined list
///
/// Only removes suffixes from the known safe list in extraFormats.
/// This is the safe, conservative approach that only matches known formats.
/// Handles Unicode normalization for cross-platform compatibility.
///
/// [filename] Original filename
/// Returns filename with extra formats removed
String _removeExtraComplete(final String filename) {
  // MacOS uses NFD that doesn't work with our accents 🙃🙃
  // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/pull/247
  final String normalizedFilename = unorm.nfc(filename);
  final String ext = p.extension(normalizedFilename);
  final String nameWithoutExt = p.basenameWithoutExtension(normalizedFilename);

  for (final String extra in extras.extraFormats) {
    // Check for exact suffix match with optional digit pattern
    final RegExp exactPattern = RegExp(
      RegExp.escape(extra) + r'(\(\d+\))?$',
      caseSensitive: false,
    );

    if (exactPattern.hasMatch(nameWithoutExt)) {
      final String cleanedName = nameWithoutExt.replaceAll(exactPattern, '');
      return cleanedName + ext;
    }
  }
  return normalizedFilename;
}

/// Removes partial extra format suffixes for truncated cases
///
/// Handles cases where filename truncation results in partial suffix matches.
/// Only removes partial matches of known extra formats from extraFormats list.
///
/// [filename] Original filename
/// Returns filename with partial suffixes removed
String _removeExtraPartial(final String filename) =>
    extras.removePartialExtraFormats(filename);

/// Removes partial extra formats and restores truncated extensions
///
/// Combines partial suffix removal with extension restoration for cases
/// where both the suffix and extension were truncated due to filename limits.
///
/// [filename] Original filename
/// Returns filename with partial suffixes removed and extension restored
String _removeExtraPartialWithExtensionRestore(final String filename) {
  final String originalExt = p.extension(filename);
  final String cleanedFilename = extras.removePartialExtraFormats(filename);

  if (cleanedFilename != filename) {
    log(
      '$filename was renamed to $cleanedFilename by the removePartialExtraFormats function.',
    );

    // Try to restore truncated extension
    final String restoredFilename = extras.restoreFileExtension(
      cleanedFilename,
      originalExt,
    );

    if (restoredFilename != cleanedFilename) {
      log(
        'Extension restored from ${p.extension(cleanedFilename)} to ${p.extension(restoredFilename)} for file: $restoredFilename',
      );
      return restoredFilename;
    }

    return cleanedFilename;
  }

  return filename;
}

/// Removes edge case extra format patterns as last resort
///
/// Handles edge cases where other strategies might miss truncated patterns.
/// Uses heuristic-based pattern matching for missed truncated suffixes.
///
/// [filename] Original filename
/// Returns filename with edge case patterns removed
String _removeExtraEdgeCase(final String filename) {
  final String? result = extras.removeEdgeCaseExtraFormats(filename);
  if (result != null) {
    log(
      'Truncated suffix detected and removed by edge case handling: $filename -> $result',
    );
    return result;
  }
  return filename;
}

// this resolves years of bugs and head-scratches 😆
/// Shortens filenames to handle filesystem limits (Strategy 2)
///
/// **WHY THIS EXISTS:** Some filesystems have filename length limits
///
/// **THE PROBLEM:** Google Photos exports can have very long descriptive filenames
/// that exceed filesystem limits (51 characters including .json extension)
/// Example: "very_long_descriptive_filename_from_google_photos.jpg"
///
/// **THE SOLUTION:** Truncate filename to fit within limits while preserving
/// the ability to find corresponding JSON files
///
/// **WHY IT RUNS EARLY:** High reliability - filesystem limits are predictable
/// and this transformation has low false positive risk
///
/// [filename] Original filename that might be too long
/// Returns shortened filename if needed, original otherwise
// f.e: https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/8#issuecomment-736539592
String _shortenName(final String filename) => '$filename.json'.length > 51
    ? filename.substring(0, 51 - '.json'.length)
    : filename;

/// Handles bracket number swapping in filenames (Strategy 3)
///
/// **WHY THIS EXISTS:** Google Photos has inconsistent numbering patterns
///
/// **THE PROBLEM:** Duplicate files get numbered differently between media and JSON:
/// - Media file: "image(11).jpg"
/// - JSON file: "image.jpg(11).json"
/// The bracket position differs between file types
///
/// **THE SOLUTION:** Swap bracket position to match JSON naming pattern
/// Transform "image(11).jpg" → "image.jpg(11)" to find the JSON
///
/// **WHY IT RUNS EARLY:** Known, documented Google Photos behavior with high reliability
/// Limited scope reduces false positive risk
///
/// [filename] Original filename that might have brackets
/// Returns filename with brackets repositioned to match JSON pattern
// thanks @casualsailo and @denouche for bringing attention!
// https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/188
// and https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/175
String _bracketSwap(final String filename) {
  // this is with the dot - more probable that it's just before the extension
  final RegExpMatch? match = RegExp(
    r'\(\d+\)\.',
  ).allMatches(filename).lastOrNull;
  if (match == null) return filename;
  final String bracket = match.group(0)!.replaceAll('.', ''); // remove dot
  // remove only last to avoid errors with filenames like:
  // 'image(3).(2)(3).jpg' <- "(3)." repeats twice
  final String withoutBracket = filename.replaceLast(bracket, '');
  return '$withoutBracket$bracket';
}

/// This is to get coordinates from the json file. Expects media file and finds json.
Future<DMSCoordinates?> jsonCoordinatesExtractor(
  final File file, {
  final bool tryhard = false,
}) async {
  final File? jsonFile = await jsonForFile(file, tryhard: tryhard);
  if (jsonFile == null) return null;
  try {
    final Map<String, dynamic> data = jsonDecode(await jsonFile.readAsString());
    final double lat = data['geoData']['latitude'] as double;
    final double long = data['geoData']['longitude'] as double;
    //var alt = double.tryParse(data['geoData']['altitude']); //Info: Altitude is not used.
    if (lat == 0.0 || long == 0.0) {
      return null;
    } else {
      final DDCoordinates ddcoords = DDCoordinates(
        latitude: lat,
        longitude: long,
      );
      final DMSCoordinates dmscoords = DMSCoordinates.fromDD(ddcoords);
      return dmscoords;
    }
  } on FormatException catch (_) {
    // this is when json is bad
    return null;
  } on FileSystemException catch (_) {
    // this happens for issue #143
    // "Failed to decode data using encoding 'utf-8'"
    // maybe this will self-fix when dart itself support more encodings
    return null;
  } on NoSuchMethodError catch (_) {
    // this is when tags like photoTakenTime aren't there
    return null;
  }
}

/// Attempts to find a JSON file with case-insensitive matching
///
/// This handles cases where the file extension case doesn't match exactly.
/// For example, finding 'photo.HEIC.json' when looking for 'photo.heic.json'
///
/// [dir] Directory to search in
/// [baseName] Base name to search for (without .json/.supplemental-metadata.json)
/// Returns the JSON file if found, null otherwise
Future<File?> _findJsonFileIgnoringCase(
  final Directory dir,
  final String baseName,
) async {
  try {
    await for (final entity in dir.list()) {
      if (entity is File) {
        final fileName = p.basename(entity.path);

        // Check for supplemental-metadata.json with case-insensitive matching
        final supplementalPattern = '$baseName.supplemental-metadata.json';
        if (fileName.toLowerCase() == supplementalPattern.toLowerCase()) {
          return entity;
        }

        // Check for standard .json with case-insensitive matching
        final jsonPattern = '$baseName.json';
        if (fileName.toLowerCase() == jsonPattern.toLowerCase()) {
          return entity;
        }
      }
    }
  } catch (e) {
    // Handle directory access errors gracefully
    return null;
  }
  return null;
}
