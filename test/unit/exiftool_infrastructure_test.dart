/// # ExifTool Infrastructure Service Test Suite
///
/// Tests for the refactored ExifTool infrastructure service that provides
/// clean interface for EXIF metadata operations following clean architecture.
library;

import 'dart:convert';
import 'dart:io';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('ExifTool Infrastructure Service', () {
    late TestFixture fixture;
    late ExifToolService? exiftool;
    late File testImage;
    setUpAll(() async {
      // Initialize ExifTool service
      exiftool = await ExifToolService.find();
    });

    tearDownAll(() async {
      await exiftool?.dispose();
    });
    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp(); // Create test image if exiftool is available
      if (exiftool != null) {
        // Create a valid JPEG file for testing using base64 from test_setup.dart
        final jpegBytes = base64Decode(greenImgBase64.replaceAll('\n', ''));
        testImage = fixture.createFile('test.jpg', jpegBytes);

        // Ensure file is actually created and accessible
        await Future.delayed(const Duration(milliseconds: 50));
        expect(
          await testImage.exists(),
          isTrue,
          reason: 'Test image should exist after creation',
        );
      }
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    group('Service Initialization', () {
      test('ExifTool service can be found and initialized', () {
        // This test validates that ExifTool is available on the system
        // Skip if not available since it's an external dependency
        if (exiftool == null) {
          print('Skipping ExifTool tests - ExifTool not found on system');
          return;
        }

        expect(exiftool, isNotNull);
        expect(exiftool, isA<ExifToolService>());
      });
    });
    group('EXIF Data Operations', () {
      test('readExifData handles files gracefully', () async {
        if (exiftool == null) return; // Skip if exiftool not available

        // Verify file exists before reading
        expect(await testImage.exists(), isTrue);

        // Should handle the test image without throwing
        final result = await exiftool!.readExifData(testImage);
        expect(result, isA<Map<String, dynamic>>());
      });

      test('writeExifData handles basic metadata', () async {
        if (exiftool == null) return; // Skip if exiftool not available

        // Verify file exists before writing
        expect(await testImage.exists(), isTrue);

        final testData = {'Artist': 'Test Artist', 'Software': 'Test Software'};

        // Should handle writing basic metadata without throwing
        await expectLater(
          exiftool!.writeExifDataSingle(testImage, testData),
          completes,
        );

        // Verify file still exists after writing
        expect(await testImage.exists(), isTrue);
      });

      test('executeCommand works with basic ExifTool commands', () async {
        if (exiftool == null) return; // Skip if exiftool not available

        // Test basic version command
        final output = await exiftool!.executeExifToolCommand(['-ver']);

        expect(output, isNotEmpty);
        expect(output.trim(), matches(r'^\d+\.\d+'));
      });
    });
    group('Error Handling', () {
      test('handles non-existent files gracefully', () async {
        if (exiftool == null) return; // Skip if exiftool not available

        final nonExistentFile = File('${fixture.basePath}/nonexistent.jpg');

        // Should handle non-existent files by returning empty map or throwing predictably
        try {
          final result = await exiftool!.readExifData(nonExistentFile);
          expect(result, isA<Map<String, dynamic>>());
        } catch (e) {
          expect(e, isA<Exception>());
          expect(e.toString(), contains('File not found'));
        }
      });

      test('handles invalid file formats gracefully', () async {
        if (exiftool == null) return; // Skip if exiftool not available

        final textFile = fixture.createFile(
          'test.txt',
          'Hello world'.codeUnits,
        );

        // Wait for file to be fully written
        await Future.delayed(const Duration(milliseconds: 50));
        expect(await textFile.exists(), isTrue);

        // Should handle invalid formats without crashing
        try {
          final result = await exiftool!.readExifData(textFile);
          expect(result, isA<Map<String, dynamic>>());
        } catch (e) {
          expect(e, isA<Exception>());
          expect(e.toString(), contains('File not found'));
        }
      });
    });

    group('Resource Management', () {
      test('dispose cleans up resources properly', () async {
        if (exiftool == null) return; // Skip if exiftool not available

        // Create a separate service instance for testing disposal
        final testService = await ExifToolService.find();
        if (testService != null) {
          await testService.startPersistentProcess();

          // Should dispose without throwing
          expect(testService.dispose, returnsNormally);
        }
      });
    });
  });
}
