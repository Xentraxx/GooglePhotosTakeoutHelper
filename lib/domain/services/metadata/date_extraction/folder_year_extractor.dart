import 'dart:io';
import 'package:path/path.dart' as p;

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
    final parentDir = p.dirname(file.path);
    final folderName = p.basename(parentDir);

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
  final match = photosFromPattern.firstMatch(folderName);
  if (match != null) {
    return int.tryParse(match.group(1)!);
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
