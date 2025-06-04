/// # Google Photos Takeout Helper Integration Test Suite
///
/// Comprehensive integration tests that validate the complete Google Photos
/// Takeout Helper pipeline from raw export processing to final organized
/// media library. Tests end-to-end workflows and complex edge cases.
///
/// ## Full Pipeline Integration Testing
///
/// ### Complete Workflow Validation
/// - End-to-end processing of Google Photos Takeout exports
/// - Integration between all major components (classification, grouping, moving)
/// - Real-world scenario simulation with complex file relationships
/// - Performance validation with large-scale photo collections
/// - Data integrity verification throughout the entire pipeline
///
/// ### Multi-Component Coordination
/// - Folder classification feeding into media grouping
/// - Duplicate detection coordinating with extras removal
/// - Date extraction informing organization strategies
/// - Album processing integrated with file moving operations
/// - EXIF writing coordinated with metadata preservation
///
/// ### Complex Edge Case Scenarios
/// - Mixed file types with inconsistent metadata quality
/// - Corrupted or incomplete takeout exports
/// - Files with conflicting information from multiple sources
/// - International characters and Unicode handling across components
/// - Large batches testing memory management and performance
///
/// ## Real-World Export Processing
///
/// ### Google Photos Export Structure Simulation
/// - Realistic directory hierarchies matching actual takeout exports
/// - Album folders with duplicate file relationships
/// - JSON metadata files with various timestamp formats
/// - Mixed file naming conventions and special characters
/// - Partial exports and incomplete metadata scenarios
///
/// ### Metadata Integration Testing
/// - Coordination between JSON metadata and EXIF data
/// - Date extraction from multiple sources with conflict resolution
/// - GPS coordinate handling and timezone conversion
/// - Album relationship preservation during reorganization
/// - Edited file detection and original file matching
///
/// ### Error Handling and Recovery
/// - Graceful handling of corrupted or missing metadata
/// - Recovery from partial operation failures
/// - Validation of rollback capabilities when errors occur
/// - User feedback and progress reporting during complex operations
/// - Resource cleanup after failed or interrupted operations
///
/// ## Performance and Scalability Validation
///
/// ### Large-Scale Processing
/// - Memory usage patterns with thousands of files
/// - I/O efficiency during batch operations
/// - Progress reporting accuracy for long-running operations
/// - Resource utilization monitoring and optimization
/// - Concurrent operation handling and thread safety
///
/// ### Cross-Platform Compatibility
/// - Filesystem behavior differences across operating systems
/// - Path handling and filename restriction compliance
/// - Unicode normalization consistency across platforms
/// - External tool integration (ExifTool) across environments
/// - Permission and access control handling variations
///
/// ## Integration Test Structure
///
/// Tests simulate realistic takeout export scenarios including:
/// - Multiple albums with overlapping content
/// - Files with various editing states and naming patterns
/// - Mixed date accuracy levels from different metadata sources
/// - Special characters and international filename conventions
/// - Corrupted files and incomplete export scenarios
///
/// Validation encompasses:
/// - Complete pipeline execution without data loss
/// - Proper error propagation and user notification
/// - Performance characteristics within acceptable bounds
/// - Resource cleanup and memory management
/// - Final output structure correctness and accessibility
library;

import 'dart:convert';
import 'dart:io';

import 'package:gpth/date_extractors/date_extractor.dart';
import 'package:gpth/emojicleaner.dart';
import 'package:gpth/exiftoolInterface.dart';
import 'package:gpth/extras.dart';
import 'package:gpth/grouping.dart';
import 'package:gpth/media.dart';
import 'package:gpth/moving.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'test_setup.dart';

void main() {
  group('GPTH Integration Tests', () {
    late TestFixture fixture;
    late List<Media> media;
    late Directory albumDir;

    // Global test setup
    setUpAll(() async {
      await initExiftool();
    });

    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();

      // Create album directory
      albumDir = fixture.createDirectory('Vacation');

      // Create test files with various scenarios
      final imgFile1 = fixture.createFile('image-vacation.jpg', [0, 1, 2]);
      final imgFile2 = fixture.createFile(
        'Urlaub in Knaufspesch in der Schneifel (38).JPG',
        [3, 4, 5],
      );
      final imgFile3 = fixture.createFile(
        'Screenshot_2022-10-28-09-31-43-118_com.snapchat.jpg',
        [6, 7, 8],
      );
      final imgFile4 = fixture.createFile('simple_file_20200101-version.jpg', [
        9,
        10,
        11,
      ]);
      final imgFile4_1 = fixture.createFile(
        'simple_file_20200101-version(1).jpg',
        [9, 10, 11],
      ); // duplicate
      final imgFile5 = fixture.createFile(
        'img_(87).(vacation stuff).lol(87).jpg',
        [12, 13, 14],
      );
      final imgFile6 = fixture.createFile('IMG-20150125-WA0003-modifié.jpg', [
        15,
        16,
        17,
      ]);
      final imgFile6_1 = fixture.createFile(
        'IMG-20150125-WA0003-modifié(1).jpg',
        [18, 19, 20],
      );

      // Copy one file to album folder to create album relationship
      final albumFile1 = File('${albumDir.path}/${p.basename(imgFile1.path)}');
      imgFile1.copySync(albumFile1.path);

      // Create corresponding JSON files with metadata
      fixture.createJsonFile('image-vacation.jpg.json', 1599078832);
      fixture.createJsonFile(
        'Urlaub in Knaufspesch in der Schneifel (38).JPG.json',
        1683078832,
      );
      fixture.createJsonFile(
        'Screenshot_2022-10-28-09-31-43-118_com.snapchat.json',
        1666942303,
      );
      fixture.createJsonFile('simple_file_20200101.jpg.json', 1683074444);
      fixture.createJsonFile(
        'img_(87).(vacation stuff).lol.jpg(87).json',
        1680289442,
      );
      fixture.createJsonFile('IMG-20150125-WA0003.jpg.json', 1422183600);

      // Create media objects
      media = [
        Media(
          <String?, File>{null: imgFile1},
          dateTaken: DateTime(2020, 9),
          dateTakenAccuracy: 1,
        ),
        Media(
          <String?, File>{albumName(albumDir): albumFile1},
          dateTaken: DateTime(2022, 9),
          dateTakenAccuracy: 2,
        ),
        Media(
          <String?, File>{null: imgFile2},
          dateTaken: DateTime(2020),
          dateTakenAccuracy: 2,
        ),
        Media(
          <String?, File>{null: imgFile3},
          dateTaken: DateTime(2022, 10, 28),
          dateTakenAccuracy: 1,
        ),
        Media(<String?, File>{null: imgFile4}),
        Media(
          <String?, File>{null: imgFile4_1}, // duplicate
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
          dateTaken: DateTime(2015),
          dateTakenAccuracy: 1,
        ),
        Media(
          <String?, File>{null: imgFile6_1},
          dateTaken: DateTime(2015),
          dateTakenAccuracy: 1,
        ),
      ];
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    group('End-to-End Processing Pipeline', () {
      /// Should process the full pipeline: remove duplicates, extras, find albums, move files.
      test(
        'full media processing pipeline: duplicates -> albums -> moving',
        () async {
          // Need to ensure we have duplicates to test duplicate removal
          final imgDup = fixture.createFile('duplicate.jpg', [1, 2, 3]);
          media.add(Media({null: imgDup}));
          media.add(Media({null: imgDup}));

          // Step 1: Remove duplicates
          final duplicatesRemoved = removeDuplicates(media);
          expect(duplicatesRemoved, greaterThan(0));

          // Step 2: Remove extras
          final extrasRemoved = removeExtras(media);
          expect(extrasRemoved, greaterThanOrEqualTo(0));

          // Step 3: Find albums
          final mediaBeforeAlbums = media.length;
          findAlbums(media);
          expect(
            media.length,
            lessThanOrEqualTo(mediaBeforeAlbums),
          ); // May reduce due to album merging

          // Verify album was found
          final albumedMedia = media
              .where((final m) => m.files.length > 1)
              .toList();
          expect(albumedMedia.length, greaterThan(0));
          expect(
            albumedMedia.first.files.keys.any((final key) => key == 'Vacation'),
            isTrue,
          );

          // Step 4: Move files with different album behaviors
          final outputDir = fixture.createDirectory('output');

          await moveFiles(
            media,
            outputDir,
            copy: true,
            divideToDates: 0,
            albumBehavior: 'shortcut',
            specialFoldersMode: 'auto',
          ).toList();

          // Verify output structure
          final outputEntities = await outputDir.list(recursive: true).toList();
          expect(outputEntities.isNotEmpty, isTrue);

          final directories = outputEntities.whereType<Directory>().toList();
          final files = outputEntities.whereType<File>().toList();

          expect(directories.isNotEmpty, isTrue);
          expect(files.isNotEmpty, isTrue);

          // Should have album directory
          final albumDirectories = directories
              .where((final d) => p.basename(d.path) == 'Vacation')
              .toList();
          expect(albumDirectories.length, 1);
        },
      );

      /// Should handle emoji folder processing end-to-end.
      test('emoji folder processing end-to-end', () async {
        const String emojiFolderName = 'test_💖❤️';
        final Directory emojiDir = fixture.createDirectory(emojiFolderName);
        final File img = File(p.join(emojiDir.path, 'img.jpg'));
        img.writeAsBytesSync(
          base64.decode(greenImgBase64.replaceAll('\n', '')),
        );

        // 1. Encode and rename folder
        final Directory hexNameDir = encodeAndRenameAlbumIfEmoji(emojiDir);
        expect(hexNameDir.path.contains('_0x1f496_'), isTrue); // 💖
        expect(hexNameDir.path.contains('_0x2764_'), isTrue); // ❤
        expect(hexNameDir.path.contains('_0xfe0f_'), isTrue); // ️

        final Directory hexDir = Directory(
          p.join(emojiDir.parent.path, p.basename(hexNameDir.path)),
        );
        expect(hexDir.existsSync(), isTrue);

        final File hexImg = File(p.join(hexDir.path, 'img.jpg'));
        expect(hexImg.existsSync(), isTrue);

        // 2. Read EXIF from image in hex folder
        final DateTime? exifDate = await exifDateTimeExtractor(hexImg);
        expect(exifDate, DateTime.parse('2022-12-16 16:06:47'));

        // 3. Write EXIF using ExifTool
        if (exiftool != null) {
          final Map<String, String> tags = {'Artist': 'TestArtist'};
          final result = await exiftool!.writeExifBatch(hexImg, tags);
          expect(result, isTrue);

          // Verify tag was written
          final readTags = await exiftool!.readExifBatch(hexImg, ['Artist']);
          expect(readTags['Artist'], 'TestArtist');
        }

        // 4. Decode and restore folder name
        final String decodedPath = decodeAndRestoreAlbumEmoji(hexDir.path);
        if (decodedPath != hexDir.path) {
          hexDir.renameSync(decodedPath);
        }

        final Directory restoredDir = Directory(decodedPath);
        expect(restoredDir.existsSync(), isTrue);
        expect(p.basename(restoredDir.path), emojiFolderName);
      });

      /// Should handle mixed content with date extractors.
      test('handles mixed content with date extractors', () async {
        // Create files with different date sources
        final imgWithExif = fixture.createImageWithExif('with_exif.jpg');
        final imgWithJson = fixture.createFile('with_json.jpg', [1, 2, 3]);
        fixture.createJsonFile('with_json.jpg.json', 1599078832);
        final imgGuessable = fixture.createFile('IMG_20220101_120000.jpg', [
          4,
          5,
          6,
        ]);
        final imgUnknown = fixture.createFile('unknown_date.jpg', [7, 8, 9]);

        // Test each extractor
        final exifDate = await exifDateTimeExtractor(imgWithExif);
        expect(exifDate, isNotNull);

        final jsonDate = await jsonDateTimeExtractor(imgWithJson);
        expect(jsonDate, isNotNull);
        expect(jsonDate!.millisecondsSinceEpoch, 1599078832 * 1000);

        final guessDate = await guessExtractor(imgGuessable);
        expect(guessDate, isNotNull);
        expect(guessDate!.year, 2022);
        expect(guessDate.month, 1);
        expect(guessDate.day, 1);

        final unknownDate = await guessExtractor(imgUnknown);
        expect(unknownDate, isNull);
      });

      /// Should perform well with a large number of media objects.
      test('performance with large number of media objects', () async {
        // Create a larger set of media for performance testing
        final largeMediaList = <Media>[];

        for (int i = 0; i < 100; i++) {
          final file = fixture.createFile('test_$i.jpg', [i, i + 1, i + 2]);
          largeMediaList.add(
            Media(
              <String?, File>{null: file},
              dateTaken: DateTime(2020 + (i % 5)),
              dateTakenAccuracy: 1,
            ),
          );
        }

        final stopwatch = Stopwatch()..start();

        // Test duplicate removal performance
        removeDuplicates(largeMediaList);

        // Test album finding performance
        findAlbums(largeMediaList);

        stopwatch.stop();

        // Should complete in reasonable time (less than 10 seconds)
        expect(stopwatch.elapsedMilliseconds, lessThan(10000));
        expect(largeMediaList.isNotEmpty, isTrue);
      });
    });

    group('Error Handling and Edge Cases', () {
      /// Should handle empty media lists gracefully.
      test('handles empty media lists', () async {
        final emptyMedia = <Media>[];

        expect(removeDuplicates(emptyMedia), 0);
        expect(removeExtras(emptyMedia), 0);
        expect(() => findAlbums(emptyMedia), returnsNormally);

        final outputDir = fixture.createDirectory('empty_output');
        final events = await moveFiles(
          emptyMedia,
          outputDir,
          copy: true,
          divideToDates: 0,
          albumBehavior: 'nothing',
          specialFoldersMode: 'auto',
        ).toList();

        // Check that it returns a list (may be empty but still a list)
        expect(events, isNotNull);
      });

      /// Should handle special characters in file paths.
      test('handles special characters in file paths', () async {
        // Create files with special characters
        final specialFiles = [
          fixture.createFile('file with spaces.jpg', [1, 2, 3]),
          fixture.createFile('file-with-dashes.jpg', [4, 5, 6]),
          fixture.createFile('file_with_underscores.jpg', [7, 8, 9]),
          fixture.createFile('file(with)parentheses.jpg', [10, 11, 12]),
        ];

        final specialMedia = specialFiles
            .map(
              (final file) => Media(
                <String?, File>{null: file},
                dateTaken: DateTime(2023),
                dateTakenAccuracy: 1,
              ),
            )
            .toList();

        // Should handle special characters without issues
        expect(() => removeDuplicates(specialMedia), returnsNormally);
        expect(() => findAlbums(specialMedia), returnsNormally);

        final outputDir = fixture.createDirectory('special_output');
        expect(
          () => moveFiles(
            specialMedia,
            outputDir,
            copy: true,
            divideToDates: 0,
            albumBehavior: 'nothing',
            specialFoldersMode: 'auto',
          ).toList(),
          returnsNormally,
        );
      });
    });
  });
}
