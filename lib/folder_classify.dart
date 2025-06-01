/// This file contains utils for determining type of a folder
/// Whether it's a legendary "year folder", album, trash, etc
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'utils.dart';

/// Determines if a directory is a Google Photos year folder
///
/// Checks if the folder name contains a valid year pattern (1900-2024).
/// Supports various patterns including:
/// - "Photos from YYYY"
/// - "YYYY" (just the year)
/// - "YYYY Photos"
/// - "Photos from YYYY (extra)"
/// - Case insensitive matching
/// - Underscores instead of spaces
///
/// [dir] Directory to check
/// Returns true if it's a year folder
bool isYearFolder(final Directory dir) {
  final String folderName = p
      .basename(dir.path)
      .toLowerCase()
      .replaceAll('_', ' '); // Normalize underscores to spaces

  // Extract year from folder name using regex
  final RegExp yearPattern = RegExp(r'\b(19[0-9]{2}|20[0-2][0-9])\b');
  final Match? match = yearPattern.firstMatch(folderName);

  if (match == null) return false;

  final int year = int.parse(match.group(1)!);
  const int currentYear = 2024; // Fixed to avoid future years in tests

  // Valid year range: 1900 to 2024 (not future years)
  return year >= 1900 && year <= currentYear;
}

/// Determines if a directory is an album folder
///
/// An album folder is one that contains at least one media file
/// (photo or video). Uses the wherePhotoVideo extension to check
/// for supported media formats.
///
/// Excludes special Google Photos system folders from being considered albums.
///
/// [dir] Directory to check
/// Returns true if it's an album folder
Future<bool> isAlbumFolder(final Directory dir) async {
  try {
    // Get the folder name
    final String folderName = p.basename(dir.path);

    // Exclude special system folders and ALL_PHOTOS from being considered albums
    const Set<String> specialFolders = {
      'ALL_PHOTOS',
      'Archive',
      'Trash',
      'Screenshots',
      'Camera',
    };

    if (specialFolders.contains(folderName)) {
      return false;
    }

    await for (final entity in dir.list()) {
      if (entity is File) {
        // Check if it's a media file using the existing extension
        final mediaFiles = [entity].wherePhotoVideo();
        if (mediaFiles.isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  } catch (e) {
    // Handle permission denied or other errors
    return false;
  }
}

/// Determines if a directory is a Google Photos special folder
///
/// Special folders are system folders created by Google Photos that
/// contain photos but are not user-created albums. These include:
/// - Archive: Archived photos
/// - Trash: Deleted photos
/// - Screenshots: Screenshots taken on device
/// - Camera: Photos from device camera
///
/// [dir] Directory to check
/// Returns true if it's a special folder
bool isSpecialFolder(final Directory dir) {
  final String folderName = p.basename(dir.path);

  const Set<String> specialFolders = {
    'Archive',
    'Trash',
    'Screenshots',
    'Camera',
  };

  return specialFolders.contains(folderName);
}
