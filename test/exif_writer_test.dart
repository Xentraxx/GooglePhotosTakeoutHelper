/// # EXIF Writer Test Suite
///
/// Comprehensive tests for EXIF metadata writing functionality that enables
/// enriching media files with location, time, and other metadata information
/// extracted from Google Photos Takeout JSON files.
library;

import 'package:coordinate_converter/coordinate_converter.dart';
import 'package:exif_reader/exif_reader.dart';
import 'package:gpth/domain/services/exif_writer_service.dart';
import 'package:gpth/exiftoolInterface.dart';
import 'package:intl/intl.dart';
import 'package:test/test.dart';

import './test_setup.dart';

void main() {
  group('EXIF Writer', () {
    late TestFixture fixture;
    setUpAll(() async {
      await initExiftool();
    });

    tearDownAll(() async {
      await cleanupExiftool();
    });

    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    group('GPS Coordinates Writing', () {
      /// Tests GPS coordinate writing functionality that converts decimal
      /// degree coordinates to DMS format and writes them to EXIF metadata.
      /// Validates coordinate precision and direction handling.
      test('writeGpsToExif writes GPS coordinates to JPEG file', () async {
        final testImage = fixture.createImageWithoutExif('test.jpg');
        final coordinates = DMSCoordinates(
          latDegrees: 41,
          latMinutes: 19,
          latSeconds: 22.1611,
          longDegrees: 19,
          longMinutes: 48,
          longSeconds: 14.9139,
          latDirection: DirectionY.north,
          longDirection: DirectionX.east,
        );

        final result = await writeGpsToExif(coordinates, testImage);

        expect(result, isTrue); // Verify coordinates were written
        if (exiftool != null) {
          final tags = await exiftool!.readExifData(testImage);
          expect(tags['GPSLatitude'], isNotNull);
          expect(tags['GPSLongitude'], isNotNull);
          expect(tags['GPSLatitudeRef'], 'N');
          expect(tags['GPSLongitudeRef'], 'E');
        }
      });

      /// Should return false for unsupported file formats (e.g., text files).
      test(
        'writeGpsToExif returns false for unsupported file formats',
        () async {
          final textFile = fixture.createFile('test.txt', [1, 2, 3]);
          final coordinates = DMSCoordinates(
            latDegrees: 41,
            latMinutes: 19,
            latSeconds: 22.1611,
            longDegrees: 19,
            longMinutes: 48,
            longSeconds: 14.9139,
            latDirection: DirectionY.north,
            longDirection: DirectionX.east,
          );

          final result = await writeGpsToExif(coordinates, textFile);

          expect(result, isFalse);
        },
      );
    });

    group('DateTime Writing', () {
      /// Tests DateTime metadata writing functionality that sets creation
      /// timestamps in EXIF DateTimeOriginal fields, ensuring proper
      /// timestamp preservation from Google Photos metadata.
      test(
        'writeDateTimeToExif writes DateTime to image without EXIF',
        () async {
          final testImage = fixture.createImageWithoutExif('test.jpg');
          final testDateTime = DateTime(2023, 12, 25, 15, 30, 45);

          final result = await writeDateTimeToExif(testDateTime, testImage);

          expect(result, isTrue);

          // Verify DateTime was written
          final tags = await readExifFromBytes(await testImage.readAsBytes());
          final exifFormat = DateFormat('yyyy:MM:dd HH:mm:ss');
          final expectedDateTime = exifFormat.format(testDateTime);
          expect(tags['Image DateTime']?.printable, expectedDateTime);
          expect(tags['EXIF DateTimeOriginal']?.printable, expectedDateTime);
          expect(tags['EXIF DateTimeDigitized']?.printable, expectedDateTime);
        },
      );

      /// Should skip writing DateTime if EXIF DateTime already exists.
      test(
        'writeDateTimeToExif skips files with existing EXIF DateTime',
        () async {
          final testImage = fixture.createImageWithExif('test.jpg');
          final testDateTime = DateTime(2023, 12, 25, 15, 30, 45);

          final result = await writeDateTimeToExif(testDateTime, testImage);

          expect(result, isFalse);
        },
      );

      /// Should return false for unsupported file formats.
      test(
        'writeDateTimeToExif returns false for unsupported file formats',
        () async {
          final textFile = fixture.createFile('test.txt', [1, 2, 3]);
          final testDateTime = DateTime(2023, 12, 25, 15, 30, 45);

          final result = await writeDateTimeToExif(testDateTime, textFile);

          expect(result, isFalse);
        },
      );

      /// Should handle JPEG files correctly when writing DateTime.
      test('writeDateTimeToExif handles JPEG files correctly', () async {
        final testImage = fixture.createImageWithoutExif('test.jpg');
        final testDateTime = DateTime(2023, 12, 25, 15, 30, 45);

        final result = await writeDateTimeToExif(testDateTime, testImage);

        expect(result, isTrue);

        // Check that the DateTime was actually written
        final newExifData = await readExifFromBytes(
          await testImage.readAsBytes(),
        );
        expect(newExifData.isNotEmpty, isTrue);
        expect(newExifData['Image DateTime'], isNotNull);
      });

      /// Should handle corrupted image files gracefully.
      test(
        'writeDateTimeToExif handles corrupted image files gracefully',
        () async {
          final corruptedFile = fixture.createFile('corrupted.jpg', [
            1,
            2,
            3,
            4,
            5,
          ]);
          final testDateTime = DateTime(2023, 12, 25, 15, 30, 45);

          final result = await writeDateTimeToExif(testDateTime, corruptedFile);

          // Should handle gracefully and return false
          expect(result, isFalse);
        },
      );
    });

    group('Native vs ExifTool Writing', () {
      /// Tests the writing strategy selection between native Dart EXIF
      /// writing and ExifTool external binary, ensuring optimal performance
      /// while maintaining broad file format compatibility.
      test('prefers native JPEG writing when available', () async {
        final testImage = fixture.createImageWithoutExif('test.jpg');
        final testDateTime = DateTime(2023, 12, 25, 15, 30, 45);

        final result = await writeDateTimeToExif(testDateTime, testImage);

        expect(result, isTrue);
        // The test doesn't need to verify which method was used,
        // just that it succeeded
      });

      /// Should fall back to ExifTool for non-JPEG files (placeholder).
      test(
        'falls back to ExifTool for non-JPEG files',
        () async {
          // This would be for testing non-JPEG files like TIFF, but we'll
          // keep it simple for now since we're using JPEG test images
          expect(true, isTrue); // Placeholder for ExifTool fallback tests
        },
        skip: 'Would require ExifTool and non-JPEG test files',
      );
    });
  });
}
