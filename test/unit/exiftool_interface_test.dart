/// # ExifTool Interface Test Suite - Refactored
///
/// Tests for the ExifTool interface that delegates to the infrastructure service
/// following clean architecture principles. This tests the interface layer
/// that wraps the ExifToolService.
library;

import 'dart:io';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

void main() {
  late ExifToolService? exiftool;

  setUpAll(() async {
    exiftool = await ExifToolService.find();
    if (exiftool != null) {
      await exiftool!.startPersistentProcess();
    }
  });

  tearDownAll(() async {
    if (exiftool != null) {
      await exiftool!.dispose();
    }
  });

  group('ExifTool Service Tests', () {
    test('ExifTool service can be found', () {
      expect(exiftool, isNotNull);
    });

    test('ExifTool service can read EXIF data', () async {
      if (exiftool == null) {
        fail('ExifTool not found');
      }

      // Create a test file with EXIF data
      final testFile = File('test/test_files/test_image.jpg');
      if (!await testFile.exists()) {
        return;
      }

      final exifData = await exiftool!.readExifData(testFile);
      expect(exifData, isNotEmpty);
      expect(exifData['DateTimeOriginal'], isNotNull);
    });
  });
}
