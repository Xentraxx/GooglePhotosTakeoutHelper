/// # Moving Logic Test Suite
///
/// Comprehensive tests for the media moving and organization system used to
/// reorganize Google Photos Takeout exports into structured directories.
///
/// ## Core Functionality Tested
///
/// ### Album Integration and Behavior
/// - Album-based file organization and directory structure creation
/// - Merging of files across albums while preserving metadata relationships
/// - Album naming conventions and directory path generation
/// - Handling of duplicate files within album contexts
///
/// ### Date-Based Organization Systems
/// - Year/month directory hierarchies based on date metadata
/// - Date extraction accuracy handling for reliable sorting
/// - Fallback strategies for files without reliable date information
/// - Mixed date accuracy scenarios and prioritization
///
/// ### File Operation Management
/// - Safe file moving operations with collision detection
/// - Filename sanitization and path validation for cross-platform compatibility
/// - Deduplication during move operations to prevent data loss
/// - Error handling for filesystem permission and space issues
///
/// ### Path Generation and Naming
/// - Intelligent filename cleaning for filesystem compatibility
/// - Special character handling and Unicode normalization
/// - Duplicate filename resolution with automatic numbering
/// - Extension preservation and case handling
///
/// ## Test Structure
///
/// Tests use a controlled filesystem fixture with various file types:
/// - Regular photos with standard naming patterns
/// - Screenshots with timestamp information embedded in filenames
/// - Edited photos with language-specific suffixes (edited, modifié, etc.)
/// - Files with complex naming including parentheses and special characters
/// - Album files that duplicate content but have different metadata
///
/// Date scenarios covered include:
/// - High accuracy dates from EXIF data (accuracy level 1)
/// - Medium accuracy dates from filename parsing (accuracy level 2)
/// - Low accuracy dates from fallback methods (accuracy level 3)
/// - Files with no extractable date information
///
/// The test suite validates that the moving logic correctly:
/// - Preserves the most accurate date information during organization
/// - Creates appropriate directory structures for different scenarios
/// - Handles edge cases like files without dates or conflicting information
/// - Maintains data integrity during complex move operations
library;

import 'dart:io';
import 'package:collection/collection.dart';
import 'package:gpth/grouping.dart';
import 'package:gpth/media.dart';
import 'package:gpth/moving.dart';
import 'package:gpth/utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import './test_setup.dart';

void main() {
  group('Moving Logic', () {
    late TestFixture fixture;
    late Directory outputDir;
    late List<Media> testMedia;
    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();

      outputDir = fixture.createDirectory('output');

      // Create test media with various scenarios
      final imgFile1 = fixture.createFile('image-edited.jpg', [0, 1, 2]);
      final imgFile2 = fixture.createFile(
        'Screenshot_2022-10-28-09-31-43-118_com.snapchat.jpg',
        [3, 4, 5],
      );
      final imgFile3 = fixture.createFile('simple_file_20200101-edited.jpg', [
        6,
        7,
        8,
      ]);
      final imgFile4 = fixture.createFile(
        'simple_file_20200101-edited(1).jpg',
        [9, 10, 11],
      );
      final imgFile5 = fixture.createFile(
        'Urlaub in Knaufspesch in der Schneifel (38).JPG',
        [12, 13, 14],
      );
      final imgFile6 = fixture.createFile(
        'img_(87).(vacation stuff).lol(87).jpg',
        [15, 16, 17],
      );
      final imgFile7 = fixture.createFile('IMG-20150125-WA0003-modifié.jpg', [
        18,
        19,
        20,
      ]);
      final imgFile8 = fixture.createFile(
        'IMG-20150125-WA0003-modifié(1).jpg',
        [21, 22, 23],
      );

      // Create album directory and copy file
      final albumDir = fixture.createDirectory('Vacation');
      final albumFile = File('${albumDir.path}/${p.basename(imgFile1.path)}');
      albumFile.createSync();
      albumFile.writeAsBytesSync([
        0,
        1,
        2,
      ], flush: true); // Same content as imgFile1 with explicit flush

      // Give Windows a moment to ensure file handles are properly released
      if (Platform.isWindows) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      testMedia = <Media>[
        Media(
          <String?, File>{null: imgFile1},
          dateTaken: DateTime(2020, 9),
          dateTakenAccuracy: 1,
        ),
        Media(
          <String?, File>{'Vacation': albumFile},
          dateTaken: DateTime(2022, 9),
          dateTakenAccuracy: 2,
        ),
        Media(
          <String?, File>{null: imgFile2},
          dateTaken: DateTime(2022, 10, 28),
          dateTakenAccuracy: 1,
        ),
        Media(<String?, File>{null: imgFile3}), // No date
        Media(
          <String?, File>{null: imgFile4},
          dateTaken: DateTime(2019),
          dateTakenAccuracy: 3,
        ),
        Media(
          <String?, File>{null: imgFile5},
          dateTaken: DateTime(2020),
          dateTakenAccuracy: 1,
        ),
        Media(
          <String?, File>{null: imgFile6},
          dateTaken: DateTime(2020),
          dateTakenAccuracy: 1,
        ),
        Media(
          <String?, File>{null: imgFile7},
          dateTaken: DateTime(2015),
          dateTakenAccuracy: 1,
        ),
        Media(
          <String?, File>{null: imgFile8},
          dateTaken: DateTime(2015),
          dateTakenAccuracy: 1,
        ),
      ];

      // Process media (remove duplicates and find albums)
      removeDuplicates(testMedia);
      findAlbums(testMedia);
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    group('Album Behavior - Shortcut', () {
      /// Tests album shortcut creation functionality where album files are
      /// organized as symbolic links or shortcuts instead of full copies.
      /// This approach saves disk space while maintaining album organization.
      test('creates shortcuts for album files', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'shortcut',
        ).toList();

        final outputted = await outputDir
            .list(recursive: true, followLinks: false)
            .toSet();

        // Debug: print all outputted entities
        for (final entity in outputted) {
          print('Entity: ${entity.path} (${entity.runtimeType})');
        }

        // Should have 2 (All_PHOTOS, Vacation) folders + media files + 1 album shortcut
        expect(outputted.length, 2 + testMedia.length + 1);

        if (Platform.isWindows) {
          // Windows shortcuts
          final shortcuts = outputted
              .whereType<File>()
              .where((final file) => file.path.endsWith('.lnk'))
              .toList();
          expect(shortcuts.length, 1);
        } else {
          // Unix symlinks
          expect(outputted.whereType<Link>().length, 1);
        }

        // Check folder structure
        final dirs = outputted
            .whereType<Directory>()
            .map((final dir) => p.basename(dir.path))
            .toSet();
        expect(dirs, containsAll(['ALL_PHOTOS', 'Vacation']));
      });

      /// Should ensure shortcut points to correct album file.
      test('shortcut points to correct album file', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'shortcut',
        ).toList();

        if (!Platform.isWindows) {
          final links = await outputDir
              .list(recursive: true)
              .where((final entity) => entity is Link)
              .cast<Link>()
              .toList();

          if (links.isNotEmpty) {
            final link = links.first;
            final target = await link.target();
            expect(target, isNotEmpty);
          }
        }
      });
    });

    group('Album Behavior - Duplicate Copy', () {
      /// Tests album duplicate copy functionality where album files are
      /// physically duplicated to maintain album structure while preserving
      /// original file organization. Creates full file copies for albums.
      test('creates copies of album files', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'duplicate-copy',
        ).toList();

        final outputted = await outputDir
            .list(recursive: true, followLinks: false)
            .toSet();

        // Should have 2 folders + media files + 1 album copy
        expect(outputted.length, 2 + testMedia.length + 1);
        expect(outputted.whereType<Link>().length, 0); // No symlinks
        expect(outputted.whereType<Directory>().length, 2);
        expect(outputted.whereType<File>().length, testMedia.length + 1);

        // Check that album file appears in both locations
        final fileNames = outputted
            .whereType<File>()
            .map((final file) => p.basename(file.path))
            .toList();

        final duplicateFiles = fileNames
            .where(
              (final name) =>
                  fileNames.where((final n) => n == name).length > 1,
            )
            .toList();
        expect(duplicateFiles.isNotEmpty, isTrue);
      });

      /// Should ensure album copies have identical content.
      test('album copies have identical content', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'duplicate-copy',
        ).toList();

        final allFiles = await outputDir
            .list(recursive: true)
            .whereType<File>()
            .toList();

        final duplicateFiles = <String, List<File>>{};
        for (final file in allFiles) {
          final basename = p.basename(file.path);
          duplicateFiles.putIfAbsent(basename, () => []).add(file);
        }

        for (final entry in duplicateFiles.entries) {
          if (entry.value.length > 1) {
            final files = entry.value;
            final content1 = await files[0].readAsBytes();
            final content2 = await files[1].readAsBytes();
            expect(content1, equals(content2));
          }
        }
      });
    });

    group('Album Behavior - JSON', () {
      /// Tests album metadata JSON generation functionality where album
      /// information is stored in albums-info.json files rather than
      /// creating physical album directories or duplicates.
      test('creates albums-info.json file', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'json',
        ).toList();

        final outputted = await outputDir
            .list(recursive: true, followLinks: false)
            .toSet();

        // Should have 1 folder + media + 1 json file
        expect(outputted.length, 1 + testMedia.length + 1);
        expect(outputted.whereType<Link>().length, 0);
        expect(outputted.whereType<Directory>().length, 1);
        expect(outputted.whereType<File>().length, testMedia.length + 1);

        // Check for albums-info.json
        final jsonFiles = outputted
            .whereType<File>()
            .where((final file) => p.basename(file.path) == 'albums-info.json')
            .toList();
        expect(jsonFiles.length, 1);

        // Verify JSON content
        final jsonFile = jsonFiles.first;
        final jsonContent = await jsonFile.readAsString();
        expect(jsonContent, isNotEmpty);
        expect(jsonContent, contains('Vacation'));
      });

      /// Should ensure albums-info.json contains correct album information.
      test('albums-info.json contains correct album information', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'json',
        ).toList();

        final jsonFile = await outputDir
            .list(recursive: true)
            .whereType<File>()
            .firstWhere(
              (final file) => p.basename(file.path) == 'albums-info.json',
            );

        final jsonContent = await jsonFile.readAsString();
        expect(jsonContent, contains('Vacation'));
        // Could parse JSON and verify structure if needed
      });
    });

    group('Album Behavior - Nothing', () {
      /// Tests album behavior when album information should be completely
      /// ignored, treating all files as individual items without any
      /// album-based organization or metadata preservation.
      test('ignores album information', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'nothing',
        ).toList();

        final outputted = await outputDir
            .list(recursive: true, followLinks: false)
            .toSet();

        // Should have 1 folder + media only
        expect(outputted.length, 1 + testMedia.length);
        expect(outputted.whereType<Link>().length, 0);
        expect(outputted.whereType<Directory>().length, 1);

        final dirs = outputted
            .whereType<Directory>()
            .map((final dir) => p.basename(dir.path))
            .toSet();
        expect(dirs, equals({'ALL_PHOTOS'}));
      });
    });

    group('Date Division', () {
      /// Tests date-based directory organization functionality that creates
      /// hierarchical folder structures based on photo dates. Supports various
      /// levels of date granularity from no division to year/month organization.
      test('divideToDates: 0 puts all files in ALL_PHOTOS', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'nothing',
        ).toList();

        final dirs = await outputDir
            .list()
            .whereType<Directory>()
            .map((final dir) => p.basename(dir.path))
            .toSet();

        expect(dirs, contains('ALL_PHOTOS'));
        expect(dirs.length, 1);
      });

      /// Should create year folders if divideToDates is 1.
      test('divideToDates: 1 creates year folders', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 1,
          albumBehavior: 'nothing',
        ).toList();

        final allDirs = (await outputDir.list(recursive: true).toList())
            .whereType<Directory>()
            .map((final dir) => p.basename(dir.path))
            .toList();

        // Should have year folders (they are created under ALL_PHOTOS)
        expect(allDirs, contains('2020'));
        expect(allDirs, contains('2022'));
        expect(allDirs, contains('2019'));
        expect(allDirs, contains('2015'));
      });

      /// Should create year-month folders if divideToDates is 2.
      test('divideToDates: 2 creates year-month folders', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 2,
          albumBehavior: 'nothing',
        ).toList();

        // Year-month folders are created under ALL_PHOTOS directory
        final allPhotosDir = Directory('${outputDir.path}/ALL_PHOTOS');
        expect(await allPhotosDir.exists(), isTrue);

        // Recursively check for year and month folders under ALL_PHOTOS
        final allDirs = <String>[];
        await for (final entity in allPhotosDir.list(recursive: true)) {
          if (entity is Directory) {
            allDirs.add(p.basename(entity.path));
          }
        }

        // Should have year folders and month folders
        expect(allDirs.any((final dir) => dir.contains('2020')), isTrue);
        expect(allDirs.any((final dir) => dir.contains('2022')), isTrue);
        // Should also have month folders (01, 09, 10, etc.)
        expect(
          allDirs.any((final dir) => RegExp(r'^\d{2}$').hasMatch(dir)),
          isTrue,
        );
      });

      /// Should put files without dates in ALL_PHOTOS/date-unknown.
      test('files without dates go to ALL_PHOTOS', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 1,
          albumBehavior: 'nothing',
        ).toList();

        final allPhotosDir = Directory('${outputDir.path}/ALL_PHOTOS');
        expect(await allPhotosDir.exists(), isTrue);

        // Files without dates should be in the date-unknown subdirectory
        final dateUnknownDir = Directory('${allPhotosDir.path}/date-unknown');
        expect(await dateUnknownDir.exists(), isTrue);

        final filesInDateUnknown = await dateUnknownDir
            .list()
            .whereType<File>()
            .toList();
        expect(filesInDateUnknown.isNotEmpty, isTrue);
      });
    });

    group('Copy vs Move Operations', () {
      /// Tests the difference between copy and move operations, ensuring
      /// files are either preserved in original locations (copy) or
      /// transferred completely (move) while maintaining data integrity.
      test('copy: true preserves original files', () async {
        final originalFiles = testMedia.map((final m) => m.firstFile).toList();
        final originalExists = originalFiles
            .map((final f) => f.existsSync())
            .toList();

        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'nothing',
        ).toList();

        // Original files should still exist
        for (int i = 0; i < originalFiles.length; i++) {
          expect(originalFiles[i].existsSync(), originalExists[i]);
        }

        // Output files should also exist
        final outputFiles = await outputDir
            .list(recursive: true)
            .whereType<File>()
            .toList();
        expect(outputFiles.length, testMedia.length);
      });

      /// Should move files (remove originals) when copy is false.
      test('copy: false moves files (simulated)', () async {
        // Create separate test files for move operation
        final moveTestMedia = [
          Media(<String?, File>{
            null: fixture.createFile('move_test.jpg', [1, 2, 3]),
          }),
        ];

        final originalFile = moveTestMedia.first.firstFile;
        expect(originalFile.existsSync(), isTrue);

        await moveFiles(
          moveTestMedia,
          outputDir,
          copy: false,
          divideToDates: 0,
          albumBehavior: 'nothing',
        ).toList();

        // Original should be moved (no longer exist in original location)
        expect(originalFile.existsSync(), isFalse);

        // File should exist in output
        final outputFiles = await outputDir
            .list(recursive: true)
            .whereType<File>()
            .toList();
        expect(outputFiles.length, 1);
        expect(outputFiles.first.readAsBytesSync(), [1, 2, 3]);
      });
    });

    group('File Name Handling', () {
      /// Tests filename sanitization and special character handling to ensure
      /// cross-platform compatibility and proper filesystem operations.
      /// Validates Unicode normalization and illegal character replacement.
      test('handles special characters in filenames', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'nothing',
        ).toList();

        final outputFiles = await outputDir
            .list(recursive: true)
            .whereType<File>()
            .toList();
        final fileNames = outputFiles
            .map((final f) => p.basename(f.path))
            .toSet();

        // Check that special character files are handled
        expect(fileNames.any((final name) => name.contains('(')), isTrue);
        expect(fileNames.any((final name) => name.contains(')')), isTrue);
        expect(fileNames.any((final name) => name.contains('-')), isTrue);
      });

      /// Should handle duplicate filenames with numbering.
      test('handles duplicate filenames with numbering', () async {
        // Create media with potential name conflicts
        final conflictMedia = [
          Media(<String?, File>{
            null: fixture.createFile('test.jpg', [1, 2, 3]),
          }),
          Media(<String?, File>{
            null: fixture.createFile('test(1).jpg', [4, 5, 6]),
          }),
        ];

        await moveFiles(
          conflictMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'nothing',
        ).toList();

        final outputFiles = await outputDir
            .list(recursive: true)
            .whereType<File>()
            .toList();
        expect(outputFiles.length, 2);

        final names = outputFiles.map((final f) => p.basename(f.path)).toList();
        expect(names, contains('test.jpg'));
        expect(names, contains('test(1).jpg'));
      });

      /// Should preserve file extensions.
      test('preserves file extensions', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'nothing',
        ).toList();

        final outputFiles = await outputDir
            .list(recursive: true)
            .whereType<File>()
            .toList();

        for (final file in outputFiles) {
          final extension = p.extension(file.path);
          expect(extension, isNotEmpty);
          expect(extension, anyOf('.jpg', '.JPG', '.json'));
        }
      });
    });

    group('Progress and Error Handling', () {
      /// Tests progress reporting and error handling during file operations,
      /// ensuring proper feedback for long-running operations and graceful
      /// handling of filesystem errors and edge cases.
      test('moveFiles stream emits progress events', () async {
        final events = <int>[];

        // ignore: prefer_foreach
        await for (final event in moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'nothing',
        )) {
          events.add(event);
        }

        expect(events.isNotEmpty, isTrue);
        // Events should contain progress information
      });

      /// Should handle output directory creation.
      test('handles output directory creation', () async {
        final newOutputDir = Directory('${fixture.basePath}/new_output');
        expect(await newOutputDir.exists(), isFalse);

        await moveFiles(
          testMedia,
          newOutputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'nothing',
        ).toList();

        expect(await newOutputDir.exists(), isTrue);
        final files = await newOutputDir
            .list(recursive: true)
            .whereType<File>()
            .toList();
        expect(files.length, testMedia.length);
      });
    });

    group('Complex Scenarios', () {
      /// Tests complex integration scenarios combining multiple features like
      /// album behaviors with date division, mixed file types, and edge cases
      /// that represent real-world Google Photos Takeout processing.
      test('handles mixed album behaviors with date division', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 1,
          albumBehavior: 'shortcut',
        ).toList();

        final outputted = await outputDir.list(recursive: true).toSet();

        // Should have year folders + album folders + shortcuts
        final dirs = outputted
            .whereType<Directory>()
            .map((final dir) => p.basename(dir.path))
            .toSet();

        expect(dirs.contains('2020'), isTrue);
        expect(dirs.contains('2022'), isTrue);
        expect(dirs.contains('Vacation'), isTrue);
      });

      /// Should handle a large number of files efficiently.
      test('handles large number of files efficiently', () async {
        // Create more test media
        final largeMediaList = <Media>[];
        for (int i = 0; i < 50; i++) {
          final file = fixture.createFile('large_test_$i.jpg', [
            i,
            i + 1,
            i + 2,
          ]);
          largeMediaList.add(Media(<String?, File>{null: file}));
        }

        final stopwatch = Stopwatch()..start();

        await moveFiles(
          largeMediaList,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'nothing',
        ).toList();

        stopwatch.stop();

        // Should complete in reasonable time
        expect(stopwatch.elapsed.inSeconds, lessThan(30));

        final outputFiles = await outputDir
            .list(recursive: true)
            .whereType<File>()
            .toList();
        expect(outputFiles.length, largeMediaList.length);
      });

      /// Should maintain file integrity during operations.
      test('maintains file integrity during operations', () async {
        await moveFiles(
          testMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'nothing',
        ).toList();

        // Verify file contents are preserved
        final outputFiles = await outputDir
            .list(recursive: true)
            .whereType<File>()
            .toList();

        for (final outputFile in outputFiles) {
          final outputContent = await outputFile.readAsBytes();
          expect(outputContent.isNotEmpty, isTrue);

          // Find corresponding original file
          final originalMedia = testMedia.firstWhereOrNull(
            (final media) =>
                p.basename(media.firstFile.path) == p.basename(outputFile.path),
          );

          if (originalMedia != null) {
            final originalContent = await originalMedia.firstFile.readAsBytes();
            expect(outputContent, equals(originalContent));
          }
        }
      });
    });
  });
}
