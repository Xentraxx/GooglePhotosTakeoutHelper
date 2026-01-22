import 'dart:io';

import 'package:gpth/gpth_lib_exports.dart';
import 'package:path/path.dart' as path;

/// Service for classifying directories in Google Photos Takeout exports
///
/// This service determines whether directories are year folders, album folders,
/// or other types based on their structure and contents.
class TakeoutFolderClassifierService {
  /// Creates a new takeout folder classifier service
  const TakeoutFolderClassifierService();

  /// Determines if a directory is a Google Photos year folder
  ///
  /// Checks if the folder name matches the pattern "Photos from YYYY" where YYYY is a year from 1800 to 2099.
  /// This is a strict match and does not cover all possible year folder naming conventions.
  ///
  /// [dir] Directory to check
  /// Returns true if it's a year folder
  bool isYearFolder(final Directory dir) => RegExp(
    r'^(Photos from|Fotos del|Fotos von) (20|19|18)\d{2}$',
  ).hasMatch(path.basename(dir.path));

  /// Determines if a directory is an album folder
  ///
  /// An album folder is one that contains at least one media file
  /// (photo or video). Uses the wherePhotoVideo extension to check
  /// for supported media formats.
  ///
  /// [dir] Directory to check
  /// Returns true if it's an album folder
  Future<bool> isAlbumFolder(final Directory dir) async {
    try {
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
}

// Legacy exports for backward compatibility - will be removed in next major version
bool isYearFolder(final Directory dir) =>
    const TakeoutFolderClassifierService().isYearFolder(dir);

Future<bool> isAlbumFolder(final Directory dir) async =>
    const TakeoutFolderClassifierService().isAlbumFolder(dir);
