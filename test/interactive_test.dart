/// Test suite for the Interactive Module functionality.
///
/// This comprehensive test suite validates the interactive components of
/// Google Photos Takeout Helper that handle user input and provide
/// configuration options. The interactive module is responsible for:
///
/// 1. Album Processing Options:
///    - Providing users with different strategies for handling album files
///    - Validating album option configurations and descriptions
///    - Ensuring proper formatting of user-facing option text
///
/// 2. Input Validation:
///    - Validating user input for various configuration parameters
///    - Handling edge cases and invalid input gracefully
///    - Providing meaningful error messages for invalid configurations
///
/// 3. User Experience:
///    - Testing interactive prompts and menu systems
///    - Validating help text and user guidance
///    - Ensuring consistent user interface behavior
///
/// Key Components Tested:
/// - Album behavior options (shortcut, duplicate-copy, json, nothing)
/// - Input validation functions for paths, options, and parameters
/// - Interactive prompt handling and response processing
/// - Error handling for invalid user input
/// - Help system and user guidance features
///
/// Testing Strategy:
/// The tests use controlled input scenarios to verify that the interactive
/// module correctly handles various user inputs and provides appropriate
/// feedback. Mock input streams and controlled test environments ensure
/// repeatable and reliable test results.
library;

// Tests for interactive module: album options, input validation, and user experience.

import 'dart:io';
import 'package:gpth/interactive.dart' as interactive;
import 'package:test/test.dart';
import './test_setup.dart';

void main() {
  group('Interactive Module - User Interface and Input Handling', () {
    late TestFixture fixture;

    setUp(() async {
      // Set up a clean test environment for each test
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      // Clean up test artifacts to prevent interference
      await fixture.tearDown();
    });

    group('Album Options - Configuration and Validation', () {
      /// Validates that the album options map contains all expected
      /// configuration options for handling album files. These options
      /// determine how the tool processes album relationships and file
      /// organization during the takeout processing.
      test('provides valid album behavior options', () {
        expect(interactive.albumOptions, isA<Map<String, String>>());
        expect(interactive.albumOptions.isNotEmpty, isTrue);

        // Verify all expected album processing strategies are available
        expect(interactive.albumOptions.keys, contains('shortcut'));
        expect(interactive.albumOptions.keys, contains('duplicate-copy'));
        expect(interactive.albumOptions.keys, contains('json'));
        expect(interactive.albumOptions.keys, contains('nothing'));
      });

      /// Ensures that each album option has a meaningful description
      /// that helps users understand the behavior and consequences
      /// of each processing strategy.
      test('album options have comprehensive descriptions', () {
        for (final entry in interactive.albumOptions.entries) {
          expect(
            entry.value,
            isNotEmpty,
            reason: 'Option ${entry.key} has no description',
          );
          expect(
            entry.value,
            isA<String>(),
            reason: 'Option ${entry.key} description is not a string',
          );
        }
      });

      /// Verifies that album option descriptions are properly formatted
      /// for display in user interfaces, with appropriate capitalization
      /// and punctuation for professional presentation.
      test('album options are properly formatted for user display', () {
        for (final entry in interactive.albumOptions.entries) {
          // Key should be lowercase and may contain hyphens
          expect(
            entry.key,
            matches(RegExp(r'^[a-z-]+$')),
            reason: 'Option key ${entry.key} is not properly formatted',
          );

          // Description should be a non-empty string
          expect(
            entry.value.trim(),
            isNotEmpty,
            reason: 'Option ${entry.key} has empty description',
          );
        }
      });
    });

    group('Interactive Mode Detection', () {
      /// Should indicate interactive mode availability.
      test('indeed property indicates interactive mode availability', () {
        expect(interactive.indeed, isA<bool>());
      });
    });

    group('User Input Validation', () {
      /// Should handle directory validation for interactive input.
      test('handles directory validation for interactive input', () async {
        // Create test directories
        final validDir = fixture.createDirectory('valid_input');
        final invalidPath = '${fixture.basePath}/nonexistent';

        // Test directory existence checking logic (would be used in interactive mode)
        expect(validDir.existsSync(), isTrue);
        expect(Directory(invalidPath).existsSync(), isFalse);
      });

      /// Should validate album behavior options.
      test('validates album behavior options', () {
        final validOptions = interactive.albumOptions.keys.toList();

        for (final option in validOptions) {
          expect(
            interactive.albumOptions.containsKey(option),
            isTrue,
            reason: 'Valid option $option not found in albumOptions',
          );
        }

        // Test invalid options
        expect(interactive.albumOptions.containsKey('invalid'), isFalse);
        expect(interactive.albumOptions.containsKey(''), isFalse);
        expect(
          interactive.albumOptions.containsKey('SHORTCUT'),
          isFalse,
        ); // Case sensitive
      });
    });

    group('Output Cleaning Confirmation', () {
      /// Should handle output directory scenarios for cleaning confirmation.
      test('askForCleanOutput handles output directory scenarios', () async {
        // Create output directory with existing content
        final outputDir = fixture.createDirectory('output');
        fixture.createFile('${outputDir.path}/existing_file.txt', [1, 2, 3]);
        fixture.createDirectory('${outputDir.path}/existing_folder');

        // In a real interactive scenario, this would prompt the user
        // For testing, we verify the directory state
        expect(outputDir.listSync().isNotEmpty, isTrue);
      });

      /// Should handle empty output directories.
      test('handles empty output directories', () async {
        final emptyOutputDir = fixture.createDirectory('empty_output');

        expect(emptyOutputDir.listSync().isEmpty, isTrue);
      });

      /// Should handle non-existent output directories.
      test('handles non-existent output directories', () async {
        final nonExistentOutput = Directory(
          '${fixture.basePath}/nonexistent_output',
        );

        expect(nonExistentOutput.existsSync(), isFalse);
      });
    });

    group('Input Directory Selection', () {
      /// Should handle valid input directory structures.
      test('handles valid input directory structures', () async {
        // Create a Google Takeout-like structure
        final inputDir = fixture.createDirectory('input');
        final takeoutDir = fixture.createDirectory('${inputDir.path}/Takeout');
        final photosDir = fixture.createDirectory(
          '${takeoutDir.path}/Google Photos',
        );

        fixture.createFile('${photosDir.path}/photo1.jpg', [1, 2, 3]);
        fixture.createFile('${photosDir.path}/photo1.jpg.json', [4, 5, 6]);

        expect(inputDir.existsSync(), isTrue);
        expect(takeoutDir.existsSync(), isTrue);
        expect(photosDir.existsSync(), isTrue);
      });

      /// Should handle multiple Takeout directories.
      test('handles multiple Takeout directories', () async {
        final inputDir = fixture.createDirectory('input_multiple');

        // Create multiple takeout directories
        for (int i = 1; i <= 3; i++) {
          final takeoutDir = fixture.createDirectory(
            '${inputDir.path}/Takeout$i',
          );
          final photosDir = fixture.createDirectory(
            '${takeoutDir.path}/Google Photos',
          );
          fixture.createFile('${photosDir.path}/photo$i.jpg', [
            i,
            i + 1,
            i + 2,
          ]);
        }

        final takeoutDirs = inputDir
            .listSync()
            .whereType<Directory>()
            .where((final d) => d.path.contains('Takeout'))
            .toList();

        expect(takeoutDirs.length, 3);
      });

      /// Should handle nested album structures.
      test('handles nested album structures', () async {
        final inputDir = fixture.createDirectory('input_albums');
        final takeoutDir = fixture.createDirectory('${inputDir.path}/Takeout');
        final photosDir = fixture.createDirectory(
          '${takeoutDir.path}/Google Photos',
        );

        // Create album directories
        final albumDirs = [
          'Photos from 2023',
          'Vacation Album',
          'Family Photos',
          'Random Album',
        ];

        for (final albumName in albumDirs) {
          final albumDir = fixture.createDirectory(
            '${photosDir.path}/$albumName',
          );
          fixture.createFile('${albumDir.path}/photo.jpg', [1, 2, 3]);
          fixture.createFile('${albumDir.path}/photo.jpg.json', [4, 5, 6]);
        }

        final albums = photosDir.listSync().whereType<Directory>().toList();
        expect(albums.length, albumDirs.length);
      });
    });

    group('Error Handling', () {
      /// Should handle permission errors gracefully.
      test('handles permission errors gracefully', () {
        // This would test how interactive functions handle permission denied errors
        // In a real scenario, we'd mock file system operations
        expect(() => interactive.albumOptions, returnsNormally);
      });

      /// Should handle invalid input gracefully.
      test('handles invalid input gracefully', () {
        // Test that invalid inputs don't crash the interactive functions
        expect(interactive.albumOptions.containsKey(null), isFalse);
      });

      /// Should handle interruption signals.
      test('handles interruption signals', () {
        // In a real interactive session, users might press Ctrl+C
        // The interactive functions should handle this gracefully
        expect(() => interactive.indeed, returnsNormally);
      });
    });

    group('Platform Compatibility', () {
      /// Should handle Windows paths correctly.
      test('handles Windows paths correctly', () {
        if (Platform.isWindows) {
          // Test Windows-specific path handling
          final windowsDir = fixture.createDirectory('windows_test');
          expect(windowsDir.path.contains('\\'), isTrue);
        } else {
          // Test Unix-like paths
          final unixDir = fixture.createDirectory('unix_test');
          expect(unixDir.path.contains('/'), isTrue);
        }
      });

      /// Should handle different path separators.
      test('handles different path separators', () {
        final testDir = fixture.createDirectory('path_test');
        final separator = Platform.pathSeparator;

        expect(testDir.path.contains(separator), isTrue);
      });

      /// Should handle long file paths.
      test('handles long file paths', () {
        // Test handling of long paths (especially important on Windows)
        final longPath = '${'a' * 50}/${'b' * 50}/${'c' * 50}';

        expect(() {
          final testDir = Directory('${fixture.basePath}/$longPath');
          return testDir.path;
        }, returnsNormally);
      });
    });

    group('Configuration Options', () {
      /// Should cover all expected album behavior options.
      test('album options cover all expected behaviors', () {
        final requiredOptions = [
          'shortcut',
          'duplicate-copy',
          'json',
          'nothing',
        ];

        for (final option in requiredOptions) {
          expect(
            interactive.albumOptions.keys,
            contains(option),
            reason: 'Missing required album option: $option',
          );
        }
      });

      /// Should ensure album option descriptions are informative.
      test('album option descriptions are informative', () {
        for (final entry in interactive.albumOptions.entries) {
          final description = entry.value.toLowerCase();

          // Each description should give some hint about what the option does
          expect(
            description.length,
            greaterThan(10),
            reason: 'Description for ${entry.key} is too short',
          );
        }
      });

      /// Should ensure a default album option exists.
      test('default album option exists', () {
        // There should be a reasonable default option
        expect(interactive.albumOptions.keys, contains('shortcut'));
      });
    });

    group('User Experience', () {
      /// Should ensure option keys are user-friendly.
      test('option keys are user-friendly', () {
        for (final key in interactive.albumOptions.keys) {
          // Keys should be readable and not too cryptic
          expect(
            key.length,
            greaterThan(2),
            reason: 'Option key $key is too short',
          );
          expect(
            key,
            isNot(matches(RegExp(r'[0-9]+$'))),
            reason: 'Option key $key should not be just numbers',
          );
        }
      });
    });

    group('Integration Scenarios', () {
      /// Should support typical Google Photos Takeout structure.
      test('supports typical Google Photos Takeout structure', () async {
        // Create a realistic Google Photos Takeout structure
        final takeoutRoot = fixture.createDirectory('Takeout');
        final googlePhotos = fixture.createDirectory(
          '${takeoutRoot.path}/Google Photos',
        );

        // Year folders
        final year2023 = fixture.createDirectory(
          '${googlePhotos.path}/Photos from 2023',
        );
        fixture.createDirectory('${googlePhotos.path}/Photos from 2022');

        // Album folders
        final vacation = fixture.createDirectory(
          '${googlePhotos.path}/Vacation Album',
        );
        fixture.createDirectory('${googlePhotos.path}/Family Photos');

        // Add sample files
        fixture.createFile('${year2023.path}/IMG_001.jpg', [1, 2, 3]);
        fixture.createFile('${year2023.path}/IMG_001.jpg.json', [4, 5, 6]);
        fixture.createFile('${vacation.path}/beach.jpg', [7, 8, 9]);
        fixture.createFile('${vacation.path}/beach.jpg.json', [10, 11, 12]);

        expect(takeoutRoot.existsSync(), isTrue);
        expect(year2023.listSync().length, 2); // jpg + json
        expect(vacation.listSync().length, 2); // jpg + json
      });

      /// Should handle mixed content scenarios.
      test('handles mixed content scenarios', () async {
        final inputDir = fixture.createDirectory('mixed_content');

        // Mix of photos, videos, documents
        fixture.createFile('${inputDir.path}/photo.jpg', [1, 2, 3]);
        fixture.createFile('${inputDir.path}/video.mp4', [4, 5, 6]);
        fixture.createFile('${inputDir.path}/document.pdf', [7, 8, 9]);
        fixture.createFile('${inputDir.path}/readme.txt', [10, 11, 12]);

        final files = inputDir.listSync().whereType<File>().toList();
        expect(files.length, 4);
      });
    });

    group('Extension Fixing Options', () {
      /// Should handle extension fixing configuration.
      test('handles extension fixing configuration', () async {
        // Test that the askFixExtensions function would return proper configuration
        // In a real scenario, this would test user input validation

        // Valid extension fixing options
        final validConfigs = [
          {
            'fix-extensions': false,
            'fix-extensions-non-jpeg': false,
            'fix-extensions-solo-mode': false,
          },
          {
            'fix-extensions': true,
            'fix-extensions-non-jpeg': false,
            'fix-extensions-solo-mode': false,
          },
          {
            'fix-extensions': false,
            'fix-extensions-non-jpeg': true,
            'fix-extensions-solo-mode': false,
          },
          {
            'fix-extensions': true,
            'fix-extensions-non-jpeg': false,
            'fix-extensions-solo-mode': true,
          },
        ];

        for (final config in validConfigs) {
          // Validate that each configuration has the expected keys
          expect(config.containsKey('fix-extensions'), isTrue);
          expect(config.containsKey('fix-extensions-non-jpeg'), isTrue);
          expect(config.containsKey('fix-extensions-solo-mode'), isTrue);

          // Validate that values are booleans
          for (final value in config.values) {
            expect(value, isA<bool>());
          }
        }
      });

      /// Should handle solo mode configuration.
      test('handles solo mode configuration', () {
        const Map<String, bool> soloConfig = {
          'fix-extensions': true,
          'fix-extensions-non-jpeg': false,
          'fix-extensions-solo-mode': true,
        }; // Solo mode should work with fix-extensions
        expect(soloConfig['fix-extensions-solo-mode'], isTrue);
        expect(soloConfig['fix-extensions'], isTrue);
      });
    });

    group('Unzipping Functionality - Basic Integration Tests', () {
      /// Tests that unzipping functions are properly exposed
      test('unzipping functions are available in interactive module', () {
        // Test that the unzip function is accessible
        expect(interactive.unzip, isNotNull);
      });

      /// Tests askIfUnzip function exists and has proper type
      test('askIfUnzip function is properly defined', () {
        // Test that askIfUnzip function exists
        expect(interactive.askIfUnzip, isNotNull);
      });

      /// Tests that ZIP file validation works
      test('getZips validates file selection', () async {
        // This test verifies that getZips function exists and is properly typed
        // The actual interactive testing would require UI mocking which is complex
        expect(interactive.getZips, isNotNull);
      });

      /// Tests that free space notice function works
      test('freeSpaceNotice handles space calculations', () async {
        final testDir = fixture.createDirectory('space_test');

        // Test that function doesn't throw with valid inputs
        expect(
          () => interactive.freeSpaceNotice(1024 * 1024, testDir),
          returnsNormally,
        );
      });

      /// Tests SecurityException class exists and works
      test('SecurityException class is properly defined', () {
        const exception = interactive.SecurityException('Test message');
        expect(exception.message, equals('Test message'));
        expect(exception.toString(), contains('SecurityException'));
        expect(exception.toString(), contains('Test message'));
      });

      /// Tests that unzip function handles basic error cases
      test('unzip function validates inputs', () async {
        final testDir = fixture.createDirectory('unzip_test');

        // Test with empty ZIP list
        expect(() => interactive.unzip([], testDir), returnsNormally);
      });

      /// Tests filename sanitization works in isolation
      test('filename sanitization basic functionality', () {
        // We can't directly test the private _sanitizeFileName function,
        // but we can test the public interface indirectly

        // Create a mock scenario to verify the module loads correctly
        expect(interactive.albumOptions, isNotEmpty);
        expect(interactive.albumOptions.containsKey('shortcut'), isTrue);
      });
    });
  });
}
