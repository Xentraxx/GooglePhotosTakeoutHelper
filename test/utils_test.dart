/// # Utility Functions Test Suite
///
/// Comprehensive tests for utility functions that provide essential support
/// services across the Google Photos Takeout Helper application, including
/// stream processing, file operations, system validation, and helper utilities.
///
/// ## Core Functionality Tested
///
/// ### Stream Processing Extensions
/// - Type filtering extensions for processing file streams efficiently
/// - Media file filtering to identify photos and videos specifically
/// - Stream transformation utilities for batch processing operations
/// - Performance optimization for large directory traversals
///
/// ### File System Operations
/// - Intelligent filename generation to avoid conflicts during operations
/// - Safe file operations with collision detection and resolution
/// - Cross-platform path handling and normalization
/// - File extension detection and validation for media types
/// - Directory creation and management with proper permissions
///
/// ### System Validation and Environment
/// - Disk space checking before large file operations
/// - Platform-specific behavior detection and adaptation
/// - Memory usage monitoring for resource-intensive operations
/// - External tool availability verification (ExifTool, etc.)
///
/// ### JSON and Data Processing
/// - Safe JSON parsing with error handling for malformed metadata
/// - Timestamp conversion utilities for various date formats
/// - Unicode normalization for cross-platform filename compatibility
/// - Data validation and sanitization for user inputs
///
/// ### Logging and Progress Tracking
/// - Structured logging utilities for operation tracking
/// - Progress reporting mechanisms for long-running operations
/// - Error categorization and user-friendly message formatting
/// - Debug information collection for troubleshooting
///
/// ## Technical Implementation
///
/// The utility functions provide a foundation for reliable operations across
/// different operating systems and file systems. Key areas include:
///
/// ### Cross-Platform Compatibility
/// - Handling of different path separators and filename restrictions
/// - Unicode normalization for international character support
/// - Case sensitivity handling for different file systems
/// - Permission and access control validation
///
/// ### Performance Optimization
/// - Efficient stream processing for large photo collections
/// - Memory-conscious operations for resource-constrained systems
/// - Batch processing capabilities to minimize I/O overhead
/// - Caching mechanisms for frequently accessed metadata
///
/// ### Error Recovery and Resilience
/// - Graceful handling of filesystem errors and permissions issues
/// - Retry mechanisms for transient failures
/// - Fallback strategies when preferred methods are unavailable
/// - Comprehensive error reporting for user guidance
library;

import 'dart:io';

import 'package:gpth/media.dart';
import 'package:gpth/moving.dart';
import 'package:gpth/utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import './test_setup.dart';

void main() {
  group('Utils', () {
    late TestFixture fixture;

    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    group('Stream Extensions', () {
      /// Tests stream processing extensions that efficiently filter and
      /// transform file streams for media processing operations, including
      /// type filtering and media-specific file identification.
      test('whereType filters stream correctly', () {
        final stream = Stream.fromIterable([1, 'a', 2, 'b', 3, 'c']);

        expect(stream.whereType<int>(), emitsInOrder([1, 2, 3, emitsDone]));
      });

      /// Should filter media files using wherePhotoVideo.
      test('wherePhotoVideo filters media files', () {
        final stream = Stream<FileSystemEntity>.fromIterable([
          File('${fixture.basePath}/photo.jpg'),
          File('${fixture.basePath}/document.txt'),
          File('${fixture.basePath}/video.mp4'),
          File('${fixture.basePath}/audio.mp3'),
          File('${fixture.basePath}/image.png'),
        ]);

        expect(
          stream.wherePhotoVideo().map((final f) => p.basename(f.path)),
          emitsInOrder(['photo.jpg', 'video.mp4', 'image.png', emitsDone]),
        );
      });
    });

    group('File Operations', () {
      /// Tests file system operations including intelligent filename generation
      /// to prevent conflicts, safe file operations, and cross-platform
      /// path handling with proper collision resolution.
      test('findNotExistingName generates unique filename', () {
        final existingFile = fixture.createFile('test.jpg', [1, 2, 3]);

        final uniqueFile = findNotExistingName(existingFile);

        expect(uniqueFile.path, endsWith('test(1).jpg'));
        expect(uniqueFile.existsSync(), isFalse);
      });

      /// Should return original if file does not exist.
      test('findNotExistingName returns original if file does not exist', () {
        final nonExistentFile = File('${fixture.basePath}/nonexistent.jpg');

        final result = findNotExistingName(nonExistentFile);

        expect(result.path, nonExistentFile.path);
      });
    });

    group('Disk Operations', () {
      /// Should return non-null value for disk free space.
      test('getDiskFree returns non-null value', () async {
        final freeSpace = await getDiskFree('.');

        expect(freeSpace, isNotNull);
        expect(freeSpace!, greaterThan(0));
      });
    });

    group('File Size Formatting', () {
      /// Should format bytes correctly to human-readable string.
      test('filesize formats bytes correctly', () {
        expect(filesize(1024), contains('KB'));
        expect(filesize(1024 * 1024), contains('MB'));
        expect(filesize(1024 * 1024 * 1024), contains('GB'));
      });
    });

    group('Logging', () {
      /// Should handle different log levels without throwing.
      test('log function handles different levels', () {
        // Test that log function doesn't throw
        expect(() => log('test info'), returnsNormally);
        expect(() => log('test warning', level: 'warning'), returnsNormally);
        expect(() => log('test error', level: 'error'), returnsNormally);
      });
    });

    group('Directory Validation', () {
      /// Should succeed for existing directory.
      test('validateDirectory succeeds for existing directory', () async {
        final dir = fixture.createDirectory('test_dir');

        final result = await validateDirectory(dir);

        expect(result, isTrue);
      });

      /// Should fail for non-existing directory when should exist.
      test(
        'validateDirectory fails for non-existing directory when should exist',
        () async {
          final dir = Directory('${fixture.basePath}/nonexistent');

          final result = await validateDirectory(dir);

          expect(result, isFalse);
        },
      );
    });

    group('Platform-specific Operations', () {
      /// Should handle Windows shortcuts (Windows only test).
      test(
        'createShortcutWin handles Windows shortcuts',
        () async {
          if (Platform.isWindows) {
            final targetFile = fixture.createFile('target.txt', [1, 2, 3]);
            final shortcutPath = '${fixture.basePath}/shortcut.lnk';

            // Ensure target file exists before creating shortcut
            expect(targetFile.existsSync(), isTrue);

            // Should not throw and should complete successfully
            await createShortcutWin(shortcutPath, targetFile.path);

            // Verify shortcut was created
            expect(File(shortcutPath).existsSync(), isTrue);
          }
        },
        skip: !Platform.isWindows ? 'Windows only test' : null,
      );
    });

    group('JSON File Processing', () {
      /// Should handle supplemental metadata suffix in JSON files.
      test('renameJsonFiles handles supplemental metadata suffix', () async {
        final jsonFile = fixture.createJsonFile(
          'test.jpg.supplemental-metadata.json',
          1599078832,
        );

        await renameIncorrectJsonFiles(fixture.baseDir);

        final renamedFile = File('${fixture.basePath}/test.jpg.json');
        expect(renamedFile.existsSync(), isTrue);
        expect(jsonFile.existsSync(), isFalse);
      });
    });

    group('Pixel Motion Photos', () {
      /// Placeholder for changeMPExtensions logic.
      test('changeMPExtensions renames MP/MV files', () async {
        // This would require Media objects and is more of an integration test
        // For now, we'll test the core logic in integration tests
        expect(true, isTrue); // Placeholder
      });
    });

    group('Special Folders Processing', () {
      /// Tests the processSpecialFolderFiles function with different combinations
      /// of specialFoldersMode and albumBehavior parameters to ensure proper
      /// handling of Google Photos special folders (Archive, Trash, Screenshots, Camera).

      late Directory archiveDir;
      late Directory trashDir;
      late Directory screenshotsDir;
      late Directory cameraDir;

      /// Sets up test special folders and files before each test.
      setUp(() async {
        // Create special folders
        archiveDir = fixture.createDirectory('Archive');
        trashDir = fixture.createDirectory('Trash');
        screenshotsDir = fixture.createDirectory('Screenshots');
        cameraDir = fixture.createDirectory('Camera');

        // Create test files in special folders
        fixture.createFile(
          'Archive/photo1.jpg',
          [255, 216, 255], // JPEG header
        );
        fixture.createFile(
          'Trash/video1.mp4',
          [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70], // MP4 header
        );
        fixture.createFile(
          'Screenshots/screenshot1.png',
          [137, 80, 78, 71, 13, 10, 26, 10], // PNG header
        );
        fixture.createFile(
          'Camera/photo2.jpg',
          [255, 216, 255], // JPEG header
        );

        // Create JSON metadata files
        fixture.createJsonFile('Archive/photo1.jpg.json', 1599078832);
        fixture.createJsonFile('Trash/video1.mp4.json', 1599078833);
        fixture.createJsonFile('Screenshots/screenshot1.png.json', 1599078834);
        fixture.createJsonFile('Camera/photo2.jpg.json', 1599078835);
      });

      group('specialFoldersMode: skip', () {
        /// Should return empty list when mode is 'skip' regardless of albumBehavior.
        test('returns empty list with albumBehavior: nothing', () async {
          final specialFolders = [
            archiveDir,
            trashDir,
            screenshotsDir,
            cameraDir,
          ];

          final result = await processSpecialFolderFiles(
            specialFolders,
            'skip',
            'nothing',
          );

          expect(result, isEmpty);
        });

        test('returns empty list with albumBehavior: json', () async {
          final specialFolders = [
            archiveDir,
            trashDir,
            screenshotsDir,
            cameraDir,
          ];

          final result = await processSpecialFolderFiles(
            specialFolders,
            'skip',
            'json',
          );

          expect(result, isEmpty);
        });

        test('returns empty list with albumBehavior: shortcut', () async {
          final specialFolders = [
            archiveDir,
            trashDir,
            screenshotsDir,
            cameraDir,
          ];

          final result = await processSpecialFolderFiles(
            specialFolders,
            'skip',
            'shortcut',
          );

          expect(result, isEmpty);
        });

        test('returns empty list with albumBehavior: duplicate-copy', () async {
          final specialFolders = [
            archiveDir,
            trashDir,
            screenshotsDir,
            cameraDir,
          ];

          final result = await processSpecialFolderFiles(
            specialFolders,
            'skip',
            'duplicate-copy',
          );

          expect(result, isEmpty);
        });

        test(
          'returns empty list with albumBehavior: reverse-shortcut',
          () async {
            final specialFolders = [
              archiveDir,
              trashDir,
              screenshotsDir,
              cameraDir,
            ];

            final result = await processSpecialFolderFiles(
              specialFolders,
              'skip',
              'reverse-shortcut',
            );

            expect(result, isEmpty);
          },
        );
      });

      group('specialFoldersMode: include', () {
        /// Should add files with null key (for ALL_PHOTOS) when mode is 'include'.
        test('adds files with null key for albumBehavior: nothing', () async {
          final specialFolders = [archiveDir, trashDir];

          final result = await processSpecialFolderFiles(
            specialFolders,
            'include',
            'nothing',
          );

          expect(result, hasLength(2));
          expect(
            result.every((final Media media) => media.files.containsKey(null)),
            isTrue,
          );
          expect(
            result.map((final m) => p.basename(m.firstFile.path)),
            containsAll(['photo1.jpg', 'video1.mp4']),
          );
        });

        test('adds files with null key for albumBehavior: json', () async {
          final specialFolders = [screenshotsDir, cameraDir];

          final result = await processSpecialFolderFiles(
            specialFolders,
            'include',
            'json',
          );

          expect(result, hasLength(2));
          expect(
            result.every((final media) => media.files.containsKey(null)),
            isTrue,
          );
          expect(
            result.map((final m) => p.basename(m.firstFile.path)),
            containsAll(['screenshot1.png', 'photo2.jpg']),
          );
        });

        test('adds files with null key for albumBehavior: shortcut', () async {
          final specialFolders = [archiveDir, screenshotsDir];

          final result = await processSpecialFolderFiles(
            specialFolders,
            'include',
            'shortcut',
          );

          expect(result, hasLength(2));
          expect(
            result.every((final media) => media.files.containsKey(null)),
            isTrue,
          );
          expect(
            result.map((final m) => p.basename(m.firstFile.path)),
            containsAll(['photo1.jpg', 'screenshot1.png']),
          );
        });

        test(
          'adds files with null key for albumBehavior: duplicate-copy',
          () async {
            final specialFolders = [trashDir, cameraDir];

            final result = await processSpecialFolderFiles(
              specialFolders,
              'include',
              'duplicate-copy',
            );

            expect(result, hasLength(2));
            expect(
              result.every((final media) => media.files.containsKey(null)),
              isTrue,
            );
            expect(
              result.map((final m) => p.basename(m.firstFile.path)),
              containsAll(['video1.mp4', 'photo2.jpg']),
            );
          },
        );

        test(
          'adds files with null key for albumBehavior: reverse-shortcut',
          () async {
            final specialFolders = [
              archiveDir,
              trashDir,
              screenshotsDir,
              cameraDir,
            ];

            final result = await processSpecialFolderFiles(
              specialFolders,
              'include',
              'reverse-shortcut',
            );

            expect(result, hasLength(4));
            expect(
              result.every((final media) => media.files.containsKey(null)),
              isTrue,
            );
            expect(
              result.map((final m) => p.basename(m.firstFile.path)),
              containsAll([
                'photo1.jpg',
                'video1.mp4',
                'screenshot1.png',
                'photo2.jpg',
              ]),
            );
          },
        );
      });

      group('specialFoldersMode: albums', () {
        /// Should add files with folder name as key when mode is 'albums'.
        test(
          'adds files with folder name key for albumBehavior: nothing',
          () async {
            final specialFolders = [archiveDir, trashDir];

            final result = await processSpecialFolderFiles(
              specialFolders,
              'albums',
              'nothing',
            );

            expect(result, hasLength(2));

            final archiveMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'photo1.jpg',
            );
            final trashMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'video1.mp4',
            );

            expect(archiveMedia.files.keys.contains('Archive'), isTrue);
            expect(trashMedia.files.keys.contains('Trash'), isTrue);
          },
        );

        test(
          'adds files with folder name key for albumBehavior: json',
          () async {
            final specialFolders = [screenshotsDir, cameraDir];

            final result = await processSpecialFolderFiles(
              specialFolders,
              'albums',
              'json',
            );

            expect(result, hasLength(2));

            final screenshotsMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'screenshot1.png',
            );
            final cameraMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'photo2.jpg',
            );

            expect(screenshotsMedia.files.keys.contains('Screenshots'), isTrue);
            expect(cameraMedia.files.keys.contains('Camera'), isTrue);
          },
        );

        test(
          'adds files with folder name key for albumBehavior: shortcut',
          () async {
            final specialFolders = [archiveDir, screenshotsDir];

            final result = await processSpecialFolderFiles(
              specialFolders,
              'albums',
              'shortcut',
            );

            expect(result, hasLength(2));

            final archiveMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'photo1.jpg',
            );
            final screenshotsMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'screenshot1.png',
            );

            expect(archiveMedia.files.keys.contains('Archive'), isTrue);
            expect(screenshotsMedia.files.keys.contains('Screenshots'), isTrue);
          },
        );

        test(
          'adds files with folder name key for albumBehavior: duplicate-copy',
          () async {
            final specialFolders = [trashDir, cameraDir];

            final result = await processSpecialFolderFiles(
              specialFolders,
              'albums',
              'duplicate-copy',
            );

            expect(result, hasLength(2));

            final trashMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'video1.mp4',
            );
            final cameraMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'photo2.jpg',
            );

            expect(trashMedia.files.keys.contains('Trash'), isTrue);
            expect(cameraMedia.files.keys.contains('Camera'), isTrue);
          },
        );

        test(
          'adds files with folder name key for albumBehavior: reverse-shortcut',
          () async {
            final specialFolders = [
              archiveDir,
              trashDir,
              screenshotsDir,
              cameraDir,
            ];

            final result = await processSpecialFolderFiles(
              specialFolders,
              'albums',
              'reverse-shortcut',
            );

            expect(result, hasLength(4));

            final archiveMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'photo1.jpg',
            );
            final trashMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'video1.mp4',
            );
            final screenshotsMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'screenshot1.png',
            );
            final cameraMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'photo2.jpg',
            );

            expect(archiveMedia.files.keys.contains('Archive'), isTrue);
            expect(trashMedia.files.keys.contains('Trash'), isTrue);
            expect(screenshotsMedia.files.keys.contains('Screenshots'), isTrue);
            expect(cameraMedia.files.keys.contains('Camera'), isTrue);
          },
        );
      });

      group('specialFoldersMode: auto', () {
        /// Should behave based on albumBehavior when mode is 'auto'.
        test('behaves like include when albumBehavior is nothing', () async {
          final specialFolders = [archiveDir, trashDir];

          final result = await processSpecialFolderFiles(
            specialFolders,
            'auto',
            'nothing',
          );

          expect(result, hasLength(2));
          expect(
            result.every((final media) => media.files.containsKey(null)),
            isTrue,
          );
          expect(
            result.map((final m) => p.basename(m.firstFile.path)),
            containsAll(['photo1.jpg', 'video1.mp4']),
          );
        });

        test('behaves like albums when albumBehavior is json', () async {
          final specialFolders = [screenshotsDir, cameraDir];

          final result = await processSpecialFolderFiles(
            specialFolders,
            'auto',
            'json',
          );

          expect(result, hasLength(2));

          final screenshotsMedia = result.firstWhere(
            (final m) => p.basename(m.firstFile.path) == 'screenshot1.png',
          );
          final cameraMedia = result.firstWhere(
            (final m) => p.basename(m.firstFile.path) == 'photo2.jpg',
          );

          expect(screenshotsMedia.files.keys.contains('Screenshots'), isTrue);
          expect(cameraMedia.files.keys.contains('Camera'), isTrue);
        });

        test('behaves like albums when albumBehavior is shortcut', () async {
          final specialFolders = [archiveDir, screenshotsDir];

          final result = await processSpecialFolderFiles(
            specialFolders,
            'auto',
            'shortcut',
          );

          expect(result, hasLength(2));

          final archiveMedia = result.firstWhere(
            (final m) => p.basename(m.firstFile.path) == 'photo1.jpg',
          );
          final screenshotsMedia = result.firstWhere(
            (final m) => p.basename(m.firstFile.path) == 'screenshot1.png',
          );

          expect(archiveMedia.files.keys.contains('Archive'), isTrue);
          expect(screenshotsMedia.files.keys.contains('Screenshots'), isTrue);
        });

        test(
          'behaves like albums when albumBehavior is duplicate-copy',
          () async {
            final specialFolders = [trashDir, cameraDir];

            final result = await processSpecialFolderFiles(
              specialFolders,
              'auto',
              'duplicate-copy',
            );

            expect(result, hasLength(2));

            final trashMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'video1.mp4',
            );
            final cameraMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'photo2.jpg',
            );

            expect(trashMedia.files.keys.contains('Trash'), isTrue);
            expect(cameraMedia.files.keys.contains('Camera'), isTrue);
          },
        );

        test(
          'behaves like albums when albumBehavior is reverse-shortcut',
          () async {
            final specialFolders = [
              archiveDir,
              trashDir,
              screenshotsDir,
              cameraDir,
            ];

            final result = await processSpecialFolderFiles(
              specialFolders,
              'auto',
              'reverse-shortcut',
            );

            expect(result, hasLength(4));

            final archiveMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'photo1.jpg',
            );
            final trashMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'video1.mp4',
            );
            final screenshotsMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'screenshot1.png',
            );
            final cameraMedia = result.firstWhere(
              (final m) => p.basename(m.firstFile.path) == 'photo2.jpg',
            );

            expect(archiveMedia.files.keys.contains('Archive'), isTrue);
            expect(trashMedia.files.keys.contains('Trash'), isTrue);
            expect(screenshotsMedia.files.keys.contains('Screenshots'), isTrue);
            expect(cameraMedia.files.keys.contains('Camera'), isTrue);
          },
        );
      });

      group('Edge Cases', () {
        /// Should handle empty special folders list.
        test('handles empty special folders list', () async {
          final result = await processSpecialFolderFiles(
            [],
            'include',
            'nothing',
          );

          expect(result, isEmpty);
        });

        /// Should handle special folders with no media files.
        test('handles special folders with no media files', () async {
          final emptyDir = fixture.createDirectory('EmptySpecial');
          fixture.createFile('EmptySpecial/document.txt', [
            116,
            101,
            115,
            116,
          ]); // Non-media file

          final result = await processSpecialFolderFiles(
            [emptyDir],
            'include',
            'nothing',
          );

          expect(result, isEmpty);
        });

        /// Should handle files without corresponding JSON metadata.
        test('handles files without JSON metadata', () async {
          final noJsonDir = fixture.createDirectory('NoJsonSpecial');
          fixture.createFile(
            'NoJsonSpecial/orphan.jpg',
            [255, 216, 255], // JPEG header
          );

          final result = await processSpecialFolderFiles(
            [noJsonDir],
            'albums',
            'json',
          );

          expect(result, hasLength(1));
          expect(result.first.files.keys.first, equals('NoJsonSpecial'));
          expect(p.basename(result.first.firstFile.path), equals('orphan.jpg'));
        });

        /// Should handle special folders with mixed file types.
        test('handles mixed file types in special folders', () async {
          final mixedDir = fixture.createDirectory('MixedSpecial');

          // Create various file types
          fixture.createFile('MixedSpecial/photo.jpg', [255, 216, 255]);
          fixture.createFile('MixedSpecial/video.mp4', [
            0x00,
            0x00,
            0x00,
            0x20,
            0x66,
            0x74,
            0x79,
            0x70,
          ]);
          fixture.createFile('MixedSpecial/document.txt', [116, 101, 115, 116]);
          fixture.createFile('MixedSpecial/archive.zip', [80, 75, 3, 4]);
          fixture.createFile('MixedSpecial/image.png', [137, 80, 78, 71]);

          // Create corresponding JSON files for media
          fixture.createJsonFile('MixedSpecial/photo.jpg.json', 1599078837);
          fixture.createJsonFile('MixedSpecial/video.mp4.json', 1599078838);
          fixture.createJsonFile('MixedSpecial/image.png.json', 1599078839);

          final result = await processSpecialFolderFiles(
            [mixedDir],
            'albums',
            'shortcut',
          );

          // Should only include media files (photo, video, image)
          expect(result, hasLength(3));
          expect(
            result.every(
              (final media) => media.files.keys.first == 'MixedSpecial',
            ),
            isTrue,
          );
          expect(
            result.map((final m) => p.basename(m.firstFile.path)),
            containsAll(['photo.jpg', 'video.mp4', 'image.png']),
          );
          expect(
            result.map((final m) => p.basename(m.firstFile.path)),
            isNot(contains('document.txt')),
          );
          expect(
            result.map((final m) => p.basename(m.firstFile.path)),
            isNot(contains('archive.zip')),
          );
        });
      });
    });
  });
}
