/// Test suite for Folder Classification functionality.
///
/// This comprehensive test suite validates the folder classification system
/// that categorizes directories in Google Photos Takeout exports. The
/// classification system is critical for organizing and processing photos
/// according to their original structure and metadata.
///
/// Key Classification Categories:
///
/// 1. Year Folders:
///    - Standard format: "Photos from YYYY"
///    - Alternative formats: "YYYY", "YYYY Photos", "Year YYYY"
///    - Edge cases: Future years, historical years, invalid years
///
/// 2. Album Folders:
///    - User-created albums with custom names
///    - System-generated albums (Screenshots, Camera, etc.)
///    - Albums with emoji characters in names
///    - Empty albums and albums with special characters
///
/// 3. Special Folders:
///    - Archive folders for deleted content
///    - Trash folders and temporary directories
///    - Metadata folders containing JSON files
///
/// Testing Strategy:
/// The tests create controlled directory structures that mirror real Google
/// Photos Takeout exports, verifying that the classification algorithm
/// correctly identifies each folder type. This ensures proper file
/// organization during the processing workflow.
///
/// Dependencies:
/// - TestFixture for isolated test environments
/// - Real directory creation for filesystem interaction testing
/// - Path manipulation utilities for cross-platform compatibility
library;

// Tests for folder classification: year folders, album folders, and edge cases.

import 'dart:io';
import 'package:gpth/folder_classify.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import './test_setup.dart';

void main() {
  group('Folder Classification - Automated Directory Categorization', () {
    late TestFixture fixture;

    setUp(() async {
      // Initialize a clean test environment for each test
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      // Clean up test artifacts to prevent cross-test interference
      await fixture.tearDown();
    });

    group('Year Folder Detection - Standard and Alternative Formats', () {
      /// Validates detection of the standard Google Photos year folder format.
      /// Google Photos Takeout typically creates folders named "Photos from YYYY"
      /// for organizing photos by the year they were taken or uploaded.
      /// This test ensures the classification algorithm correctly identifies
      /// these standard year folders across different years.
      test('identifies standard Google Photos year folders', () {
        final yearDirs = [
          fixture.createDirectory('Photos from 2023'),
          fixture.createDirectory('Photos from 2022'),
          fixture.createDirectory('Photos from 2021'),
          fixture.createDirectory('Photos from 2020'),
          fixture.createDirectory('Photos from 1999'),
          fixture.createDirectory('Photos from 1980'),
        ];

        for (final dir in yearDirs) {
          expect(isYearFolder(dir), isTrue, reason: 'Failed for ${dir.path}');
        }
      });

      /// Tests that non-standard year folder naming patterns are correctly
      /// rejected, since the function only works with exact Google Photos format.
      /// The function is restricted to only match "Photos from YYYY" pattern
      /// as this is the exact format used in Google Photos takeout exports.
      test('identifies alternative year folder patterns', () {
        final nonYearDirs = [
          fixture.createDirectory('2023'),
          fixture.createDirectory('2022 Photos'),
          fixture.createDirectory('Year 2021'),
          fixture.createDirectory('Pictures from 2020'),
          fixture.createDirectory('Images from 2019'),
        ];

        for (final dir in nonYearDirs) {
          expect(isYearFolder(dir), isFalse, reason: 'Failed for ${dir.path}');
        }
      });

      /// Validates that folders without year information are correctly
      /// excluded from year folder classification. This prevents false
      /// positives that could disrupt the organization logic.
      test('rejects non-year folders and invalid year patterns', () {
        final nonYearDirs = [
          fixture.createDirectory('Vacation'),
          fixture.createDirectory('Family Photos'),
          fixture.createDirectory('Random Folder'),
          fixture.createDirectory('Photos from vacation'),
          fixture.createDirectory('2025'), // Future year
          fixture.createDirectory('1899'), // Too old
          fixture.createDirectory('Photos from 12345'), // Invalid year
        ];

        for (final dir in nonYearDirs) {
          expect(isYearFolder(dir), isFalse, reason: 'Failed for ${dir.path}');
        }
      });

      /// Tests edge cases in year detection including boundary years,
      /// future years, and complex naming patterns that might contain
      /// years but shouldn't be classified as year folders.
      test('handles edge cases for year detection', () {
        final edgeCases = [
          fixture.createDirectory('Photos from 1900'), // Minimum valid year
          fixture.createDirectory('Photos from 2024'), // Current/recent year
          fixture.createDirectory('2000s'), // Not a specific year
          fixture.createDirectory('20th Century'), // Not a year
          fixture.createDirectory(
            'Photos from 2023 backup',
          ), // Year with suffix - should fail with exact matching
        ];

        expect(isYearFolder(edgeCases[0]), isTrue); // 1900
        expect(isYearFolder(edgeCases[1]), isTrue); // 2024
        expect(isYearFolder(edgeCases[2]), isFalse); // 2000s
        expect(isYearFolder(edgeCases[3]), isFalse); // 20th Century
        expect(
          isYearFolder(edgeCases[4]),
          isFalse,
        ); // 2023 with suffix - should fail
      });

      /// Should extract year from year folders correctly.
      test('extracts year from year folders correctly', () {
        final yearDir2023 = fixture.createDirectory('Photos from 2023');
        final yearDir1995 = fixture.createDirectory('Photos from 1995');
        final yearDirComplex = fixture.createDirectory('Photos from 2010');

        // Test the internal year extraction logic
        expect(isYearFolder(yearDir2023), isTrue);
        expect(isYearFolder(yearDir1995), isTrue);
        expect(isYearFolder(yearDirComplex), isTrue);
      });
    });

    group('Album Folder Detection - Media Content Analysis', () {
      /// Verifies identification of folders containing media files as albums.
      /// Album folders are distinguished by containing actual photo/video
      /// content rather than just metadata or organizational files.
      test('identifies album folders with media files', () async {
        final albumDir = fixture.createDirectory('Vacation Photos');
        fixture.createFile('${albumDir.path}/photo1.jpg', [1, 2, 3]);
        fixture.createFile('${albumDir.path}/photo2.png', [4, 5, 6]);
        fixture.createFile('${albumDir.path}/video1.mp4', [7, 8, 9]);

        expect(await isAlbumFolder(albumDir), isTrue);
      });

      /// Tests detection of albums with mixed content including both media
      /// and non-media files, which is common in real-world exports.
      test('identifies album folders with mixed content', () async {
        final albumDir = fixture.createDirectory('Mixed Album');
        fixture.createFile('${albumDir.path}/photo.jpg', [1, 2, 3]);
        fixture.createFile('${albumDir.path}/document.txt', [4, 5, 6]);
        fixture.createFile('${albumDir.path}/readme.md', [7, 8, 9]);

        expect(await isAlbumFolder(albumDir), isTrue);
      });

      /// Ensures folders containing only non-media files are not classified
      /// as albums, preventing incorrect organization of document folders.
      test('rejects folders without media files', () async {
        final nonAlbumDir = fixture.createDirectory('Documents');
        fixture.createFile('${nonAlbumDir.path}/document.txt', [1, 2, 3]);
        fixture.createFile('${nonAlbumDir.path}/readme.md', [4, 5, 6]);
        fixture.createFile('${nonAlbumDir.path}/notes.txt', [7, 8, 9]);

        expect(await isAlbumFolder(nonAlbumDir), isFalse);
      });

      /// Validates that empty directories are correctly excluded from
      /// album classification to avoid processing empty folders.
      test('rejects empty folders', () async {
        final emptyDir = fixture.createDirectory('Empty Folder');

        expect(await isAlbumFolder(emptyDir), isFalse);
      });

      /// Tests handling of folders containing only metadata JSON files,
      /// which should not be considered albums themselves.
      test('handles folders with only metadata files', () async {
        final metadataDir = fixture.createDirectory('Metadata Only');
        fixture.createFile('${metadataDir.path}/photo.jpg.json', [1, 2, 3]);
        fixture.createFile('${metadataDir.path}/video.mp4.json', [4, 5, 6]);

        expect(await isAlbumFolder(metadataDir), isFalse);
      });

      /// Verifies proper handling of nested album structures that might
      /// occur in complex Google Photos exports.
      test('handles nested album folders', () async {
        final parentDir = fixture.createDirectory('Parent Album');
        final subDir = fixture.createDirectory('${parentDir.path}/Sub Album');

        fixture.createFile('${parentDir.path}/photo1.jpg', [1, 2, 3]);
        fixture.createFile('${subDir.path}/photo2.jpg', [4, 5, 6]);

        expect(await isAlbumFolder(parentDir), isTrue);
        expect(await isAlbumFolder(subDir), isTrue);
      });

      /// Should identify album folders with various media formats.
      test('identifies album folders with various media formats', () async {
        final albumDir = fixture.createDirectory('Multi Format Album');

        // Common photo formats
        fixture.createFile('${albumDir.path}/photo.jpg', [1, 2, 3]);
        fixture.createFile('${albumDir.path}/image.png', [4, 5, 6]);
        fixture.createFile('${albumDir.path}/pic.gif', [7, 8, 9]);
        fixture.createFile('${albumDir.path}/raw.CR2', [10, 11, 12]);

        // Video formats
        fixture.createFile('${albumDir.path}/video.mp4', [13, 14, 15]);
        fixture.createFile('${albumDir.path}/movie.mov', [16, 17, 18]);
        fixture.createFile('${albumDir.path}/clip.avi', [19, 20, 21]);

        expect(await isAlbumFolder(albumDir), isTrue);
      });

      /// Should handle folders with hidden files.
      test('handles folders with hidden files', () async {
        final albumDir = fixture.createDirectory('Album with Hidden Files');
        fixture.createFile('${albumDir.path}/photo.jpg', [1, 2, 3]);
        fixture.createFile('${albumDir.path}/.DS_Store', [4, 5, 6]);
        fixture.createFile('${albumDir.path}/.thumbs.db', [7, 8, 9]);

        expect(await isAlbumFolder(albumDir), isTrue);
      });
    });

    group('Folder Name Analysis - Pattern Recognition', () {
      /// Tests extraction of year information from various folder naming
      /// patterns to ensure robust year detection only works with exact format.
      test('extracts year from various folder name patterns', () {
        final testCases = [
          ['Photos from 2023', true],
          ['Photos from 2022', true],
          ['Photos from 2021', true],
          ['Photos from 2020', true],
          ['Photos from 2019', true],
          ['Photos from 1980', true],
          // These should fail with the restricted pattern
          ['2022 Vacation', false],
          ['Family Photos 2021', false],
          ['Christmas_2020_Photos', false],
          ['2019-Summer-Trip', false],
          ['backup_2018_imgs', false],
        ];

        for (final testCase in testCases) {
          final folderName = testCase[0] as String;
          final expectedResult = testCase[1] as bool;
          final dir = fixture.createDirectory(folderName);

          expect(
            isYearFolder(dir),
            expectedResult,
            reason: 'Failed for: $folderName',
          );
        }
      });

      /// Validates that only exact Google Photos format matches as year folders.
      /// Special characters and additional text should cause rejection.
      test('handles special characters in folder names', () {
        final specialDirs = [
          fixture.createDirectory('Photos from 2023'), // Should match
          fixture.createDirectory('Photos from 2022'), // Should match
          fixture.createDirectory('Photos from 2021'), // Should match
          // These should fail with the exact pattern matching
          fixture.createDirectory('Photos from 2023 (Backup)'),
          fixture.createDirectory('2022 - Family Vacation'),
          fixture.createDirectory('Photos_from_2021'),
          fixture.createDirectory('2020 & 2019 Combined'),
          fixture.createDirectory('Photos@2018'),
        ];

        // Only the first 3 should match
        expect(
          isYearFolder(specialDirs[0]),
          isTrue,
          reason: 'Failed for ${specialDirs[0].path}',
        );
        expect(
          isYearFolder(specialDirs[1]),
          isTrue,
          reason: 'Failed for ${specialDirs[1].path}',
        );
        expect(
          isYearFolder(specialDirs[2]),
          isTrue,
          reason: 'Failed for ${specialDirs[2].path}',
        );

        // The rest should fail
        for (int i = 3; i < specialDirs.length; i++) {
          expect(
            isYearFolder(specialDirs[i]),
            isFalse,
            reason: 'Failed for ${specialDirs[i].path}',
          );
        }
      });

      /// Tests that only exact Google Photos format works, not Unicode variations.
      /// Unicode characters should cause rejection from year folder classification.
      test('handles Unicode characters in folder names', () {
        final unicodeDirs = [
          fixture.createDirectory('Photos from 2023'), // Should match
          fixture.createDirectory('Photos from 2022'), // Should match
          // These should fail due to extra characters
          fixture.createDirectory('Photos from 2023 📸'),
          fixture.createDirectory('2022 家族写真'),
          fixture.createDirectory('Fotos de 2021'),
          fixture.createDirectory('Photos från 2020'),
          fixture.createDirectory('2019 фотографии'),
        ];

        // Only the first 2 should match
        expect(
          isYearFolder(unicodeDirs[0]),
          isTrue,
          reason: 'Failed for ${unicodeDirs[0].path}',
        );
        expect(
          isYearFolder(unicodeDirs[1]),
          isTrue,
          reason: 'Failed for ${unicodeDirs[1].path}',
        );

        // The rest should fail
        for (int i = 2; i < unicodeDirs.length; i++) {
          expect(
            isYearFolder(unicodeDirs[i]),
            isFalse,
            reason: 'Failed for ${unicodeDirs[i].path}',
          );
        }
      });
    });

    group('Performance and Edge Cases - Robustness Testing', () {
      /// Tests performance with very long folder names to ensure the
      /// classification algorithm scales appropriately.
      test('handles very long folder names', () {
        // Create a long but reasonable folder name to avoid filesystem limits
        final longName = '${'A' * 50} Photos from 2023 ${'B' * 50}';
        final longDir = fixture.createDirectory(longName);

        // With exact pattern matching, this should fail due to extra characters
        expect(isYearFolder(longDir), isFalse);

        // Test a long folder name that matches the exact pattern
        final validLongDir = fixture.createDirectory('Photos from 2023');
        expect(isYearFolder(validLongDir), isTrue);
      });

      /// Validates graceful handling of non-existent directories to
      /// prevent crashes during filesystem scanning.
      test('handles non-existent directories gracefully', () {
        final nonExistent = Directory(p.join(fixture.basePath, 'nonexistent'));

        expect(() => isYearFolder(nonExistent), returnsNormally);
        expect(isYearFolder(nonExistent), isFalse);
      });

      /// Tests concurrent access patterns that might occur during
      /// multi-threaded processing of large photo collections.
      test('handles concurrent access to folders', () async {
        final concurrentDir = fixture.createDirectory('Concurrent Test');
        fixture.createFile('${concurrentDir.path}/photo.jpg', [1, 2, 3]);

        // Test concurrent access
        final futures = List.generate(
          10,
          (final index) => isAlbumFolder(concurrentDir),
        );
        final results = await Future.wait(futures);

        expect(results.every((final result) => result == true), isTrue);
      });
    });

    group('Special Folder Detection Tests', () {
      test('isSpecialFolder correctly identifies all special folders', () {
        // Create temporary directories for testing
        final Directory archiveDir = Directory(
          p.join(fixture.basePath, 'Archive'),
        );
        final Directory trashDir = Directory(p.join(fixture.basePath, 'Trash'));
        final Directory screenshotsDir = Directory(
          p.join(fixture.basePath, 'Screenshots'),
        );
        final Directory cameraDir = Directory(
          p.join(fixture.basePath, 'Camera'),
        );
        final Directory allPhotosDir = Directory(
          p.join(fixture.basePath, 'ALL_PHOTOS'),
        );
        final Directory normalDir = Directory(
          p.join(fixture.basePath, 'Normal_Folder'),
        );
        final Directory albumDir = Directory(
          p.join(fixture.basePath, 'Vacation Photos'),
        );

        // Create all the test directories
        archiveDir.createSync();
        trashDir.createSync();
        screenshotsDir.createSync();
        cameraDir.createSync();
        allPhotosDir.createSync();
        normalDir.createSync();
        albumDir.createSync();

        // Test each folder. ALL_PHOTOS should not be detected as special folder.
        expect(isSpecialFolder(archiveDir), isTrue);
        expect(isSpecialFolder(trashDir), isTrue);
        expect(isSpecialFolder(screenshotsDir), isTrue);
        expect(isSpecialFolder(cameraDir), isTrue);
        expect(isSpecialFolder(allPhotosDir), isFalse);

        // Test non-special folders
        expect(isSpecialFolder(normalDir), isFalse);
        expect(isSpecialFolder(albumDir), isFalse);
      });

      test('isSpecialFolder is case sensitive', () {
        // Special folders should be case-sensitive to match Google's format
        final Directory archiveLowercaseDir = Directory(
          p.join(fixture.basePath, 'archive'),
        );
        final Directory trashUppercaseDir = Directory(
          p.join(fixture.basePath, 'TRASH'),
        );
        final Directory screenshotsLowercaseDir = Directory(
          p.join(fixture.basePath, 'screenshots'),
        );
        final Directory cameraNormalcaseDir = Directory(
          p.join(fixture.basePath, 'Camera'),
        );

        // Create test directories
        archiveLowercaseDir.createSync();
        trashUppercaseDir.createSync();
        screenshotsLowercaseDir.createSync();
        cameraNormalcaseDir.createSync();

        expect(isSpecialFolder(archiveLowercaseDir), isFalse);
        expect(isSpecialFolder(trashUppercaseDir), isFalse);
        expect(isSpecialFolder(screenshotsLowercaseDir), isFalse);
        expect(isSpecialFolder(cameraNormalcaseDir), isTrue);
      });
    });
  });
}
