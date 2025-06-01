/// This file contains utils for determining type of a folder
/// Whether it's a legendary "year folder", album, trash, etc
/// NOTE: Those functions are only used on input folders and should never be used in tests to verify output!
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'utils.dart';

/// Determines if a directory is a Google Photos year folder
///
/// Checks if the folder name contains a valid year pattern "Photos from YYYY (extra)"
/// [dir] Directory to check
/// Returns true if it's a year folder
bool isYearFolder(final Directory dir) =>
    RegExp(r'^Photos from (20|19|18)\d{2}$').hasMatch(p.basename(dir.path));

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
    // Exclude year folders and from being considered albums
    if (isYearFolder(dir)) {
      return false;
    }

    // Only consider it an Album if it contains media files
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
/// Note: ALL_PHOTOS is not included as it's an output folder created by GPTH,
/// not a Google Photos input folder.
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
