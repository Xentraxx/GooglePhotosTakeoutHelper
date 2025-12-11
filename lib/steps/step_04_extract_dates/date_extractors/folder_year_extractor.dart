import 'dart:io';
import 'package:path/path.dart' as path;

/// Extracts year from parent folder names like "Photos from 2002", "Photos from 2005"
///
/// This extractor looks at the parent folder name to find year patterns when other
/// extraction methods fail. It's particularly useful for Google Photos Takeout
/// exports where files are organized in year-based folders but lack metadata.
///
/// Supported patterns:
/// - "Photos from YYYY" (standard Google Photos pattern)
/// - "YYYY Photos"
/// - "Pictures YYYY"
/// - "YYYY-MM" or "YYYY_MM" (year-month folders)
/// - Standalone "YYYY" folder names
///
/// The extractor assigns January 1st of the detected year as the date,
/// providing a reasonable fallback for chronological organization.
Future<DateTime?> folderYearExtractor(final File file) async {
  try {
    // Get the parent directory path
    final parentDir = path.dirname(file.path);
    final folderName = path.basename(parentDir);

    // Try different year extraction patterns
    final year = _extractYearFromFolderName(folderName);

    if (year != null && _isValidYear(year)) {
      // Return January 1st of the detected year
      return DateTime(year);
    }

    return null;
  } catch (e) {
    // Return null if any error occurs during path processing
    return null;
  }
}

/// Extracts year from various folder name patterns
int? _extractYearFromFolderName(final String folderName) {
  // Pattern 1: "Photos from YYYY" (Google Photos standard)
  final photosFromPattern = RegExp(
    r'Photos\s+from\s+(\d{4})',
    caseSensitive: false,
  );
  var match = photosFromPattern.firstMatch(folderName);
  if (match != null) {
    return int.tryParse(match.group(1)!);
  }

  // Pattern 2: "YYYY Photos" or "Pictures YYYY"
  final yearPhotosPattern = RegExp(
    r'(?:^|\s)(\d{4})\s+(?:Photos|Pictures)',
    caseSensitive: false,
  );
  match = yearPhotosPattern.firstMatch(folderName);
  if (match != null) {
    return int.tryParse(match.group(1)!);
  }

  // Pattern 3: "Photos YYYY" or "Pictures YYYY"
  final photosYearPattern = RegExp(
    r'(?:Photos|Pictures)\s+(\d{4})',
    caseSensitive: false,
  );
  match = photosYearPattern.firstMatch(folderName);
  if (match != null) {
    return int.tryParse(match.group(1)!);
  }

  // Pattern 4: "YYYY-MM" or "YYYY_MM" (year-month folders)
  final yearMonthPattern = RegExp(r'^(\d{4})[-_]\d{2}$');
  match = yearMonthPattern.firstMatch(folderName);
  if (match != null) {
    return int.tryParse(match.group(1)!);
  }

  // Pattern 5: Standalone "YYYY" (4-digit year as folder name)
  final standaloneYearPattern = RegExp(r'^\d{4}$');
  if (standaloneYearPattern.hasMatch(folderName)) {
    return int.tryParse(folderName);
  }

  // Pattern 6: "Album YYYY" or any word followed by year
  final albumYearPattern = RegExp(r'\b(\d{4})\b');
  final matches = albumYearPattern.allMatches(folderName);
  for (final match in matches) {
    final year = int.tryParse(match.group(1)!);
    if (year != null && _isValidYear(year)) {
      return year;
    }
  }

  return null;
}

/// Validates if the extracted year is reasonable for photos
///
/// Photos should be between 1900 (early photography) and current year + 1
/// (allowing for timezone differences)
bool _isValidYear(final int year) {
  final currentYear = DateTime.now().year;
  return year >= 1900 && year <= currentYear + 1;
}
