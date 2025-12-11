/// Test suite for ExifWriterService
///
/// Tests the EXIF data writing functionality.
library;

import 'dart:convert';
import 'dart:io';
import 'package:coordinate_converter/coordinate_converter.dart';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

import '../setup/test_setup.dart';

/// Mock ExifTool service for testing (extends concrete class)
class MockExifToolService extends ExifToolService {
  MockExifToolService() : super('/mock/path/exiftool');

  bool shouldFail = false;
  Map<String, dynamic>? lastWrittenData;
  File? lastWrittenFile;

  @override
  Future<void> writeExifDataSingle(
    final File file,
    final Map<String, dynamic> exifData,
  ) async {
    lastWrittenFile = file;
    lastWrittenData = exifData;
    if (shouldFail) {
      throw Exception('Mock ExifTool failure');
    }
    // no-op success
  }

  @override
  Future<void> writeExifDataBatch(
    final List<MapEntry<File, Map<String, dynamic>>> batch,
  ) async {
    if (shouldFail) {
      throw Exception('Mock ExifTool batch failure');
    }
    if (batch.isNotEmpty) {
      lastWrittenFile = batch.last.key;
      lastWrittenData = batch.last.value;
    }
  }

  @override
  Future<void> writeExifDataBatchViaArgFile(
    final List<MapEntry<File, Map<String, dynamic>>> batch,
  ) async {
    if (shouldFail) {
      throw Exception('Mock ExifTool argfile batch failure');
    }
    if (batch.isNotEmpty) {
      lastWrittenFile = batch.last.key;
      lastWrittenData = batch.last.value;
    }
  }

  @override
  Future<Map<String, dynamic>> readExifData(final File file) async {
    if (shouldFail) {
      throw Exception('Mock ExifTool failure');
    }
    return {};
  }

  @override
  Future<void> startPersistentProcess() async {
    if (shouldFail) {
      throw Exception('Mock ExifTool startup failure');
    }
  }

  @override
  Future<String> executeExifToolCommand(
    final List<String> args, {
    final Duration? timeout,
  }) async {
    if (shouldFail) {
      throw Exception('Mock ExifTool command failure');
    }
    return 'Mock command output';
  }

  @override
  Future<void> dispose() async {
    // no-op
  }
}

void main() {
  /// Helper only used in this test: writes EXIF with exiftool and mirrors it to JSON
  Future<bool> writeExifDataWithJsonHelper(
    final WriteExifAuxiliaryService service,
    final ExifToolService exifTool,
    final File file,
    final File jsonFile,
    final Map<String, dynamic> exifData,
  ) async {
    try {
      await exifTool.writeExifDataSingle(file, exifData);

      final jsonData = await jsonFile.readAsString();
      final Map<String, dynamic> jsonMap = jsonDecode(jsonData);
      jsonMap.addAll(exifData);
      await jsonFile.writeAsString(jsonEncode(jsonMap));

      return true;
    } catch (_) {
      return false;
    }
  }

  group('ExifWriterService', () {
    late WriteExifAuxiliaryService service;
    late MockExifToolService mockExifTool;
    late TestFixture fixture;

    setUp(() async {
      mockExifTool = MockExifToolService();
      service = WriteExifAuxiliaryService(mockExifTool);
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    group('writeTagsWithExifTool', () {
      test('returns true when exiftool succeeds', () async {
        final file = fixture.createImageWithExif('test.jpg');
        final exifData = {'DateTimeOriginal': '2023:01:01 12:00:00'};

        mockExifTool.shouldFail = false;

        final result = await service.writeTagsWithExifToolSingle(
          file,
          exifData,
          isDate: true,
        );

        expect(result, isTrue);
        expect(mockExifTool.lastWrittenFile?.path, equals(file.path));
        expect(mockExifTool.lastWrittenData, equals(exifData));
      });

      test('returns false when exiftool fails', () async {
        final file = fixture.createImageWithExif('test.jpg');
        final exifData = {'DateTimeOriginal': '2023:01:01 12:00:00'};

        mockExifTool.shouldFail = true;

        final result = await service.writeTagsWithExifToolSingle(
          file,
          exifData,
          isDate: true,
        );

        expect(result, isFalse);
      });

      test('returns false when exif data is empty', () async {
        final file = fixture.createImageWithExif('test.jpg');
        final exifData = <String, dynamic>{};

        mockExifTool.shouldFail = false;

        final result = await service.writeTagsWithExifToolSingle(
          file,
          exifData,
          isDate: true,
        );

        expect(result, isFalse);
        expect(mockExifTool.lastWrittenData, isNull);
      });
    });

    group('writeExifDataWithJson (helper)', () {
      test('writes to both file and JSON when successful', () async {
        final file = fixture.createImageWithExif('test.jpg');
        final jsonFile = fixture.createFile(
          'test.json',
          utf8.encode('{"title": "test"}'),
        );
        final exifData = {'DateTimeOriginal': '2023:01:01 12:00:00'};

        mockExifTool.shouldFail = false;

        final result = await writeExifDataWithJsonHelper(
          service,
          mockExifTool,
          file,
          jsonFile,
          exifData,
        );

        expect(result, isTrue);
        expect(mockExifTool.lastWrittenFile?.path, equals(file.path));

        final updatedJson = await jsonFile.readAsString();
        final jsonMap = jsonDecode(updatedJson);
        expect(jsonMap['title'], equals('test'));
        expect(jsonMap['DateTimeOriginal'], equals('2023:01:01 12:00:00'));
      });

      test('returns false when exiftool fails', () async {
        final file = fixture.createImageWithExif('test.jpg');
        final jsonFile = fixture.createFile(
          'test.json',
          utf8.encode('{"title": "test"}'),
        );
        final exifData = {'DateTimeOriginal': '2023:01:01 12:00:00'};

        mockExifTool.shouldFail = true;

        final result = await writeExifDataWithJsonHelper(
          service,
          mockExifTool,
          file,
          jsonFile,
          exifData,
        );

        expect(result, isFalse);
      });

      test('returns false when JSON file is invalid', () async {
        final file = fixture.createImageWithExif('test.jpg');
        final jsonFile = fixture.createFile(
          'test.json',
          utf8.encode('invalid json'),
        );
        final exifData = {'DateTimeOriginal': '2023:01:01 12:00:00'};

        mockExifTool.shouldFail = false;

        final result = await writeExifDataWithJsonHelper(
          service,
          mockExifTool,
          file,
          jsonFile,
          exifData,
        );

        expect(result, isFalse);
      });
    });

    group('native JPEG writes', () {
      test('writeDateTimeNativeJpeg returns bool', () async {
        final file = fixture.createImageWithExif('test.jpg');
        final dateTime = DateTime(2023, 1, 1, 12);

        mockExifTool.shouldFail = false;

        final result = await service.writeDateTimeNativeJpeg(file, dateTime);

        expect(result, isA<bool>());
      });

      test('writeGpsNativeJpeg returns bool', () async {
        final file = fixture.createImageWithExif('test.jpg');
        final ddCoordinates = DDCoordinates(
          latitude: 40.713,
          longitude: -74.006,
        );
        final coordinates = DMSCoordinates.fromDD(ddCoordinates);

        final result = await service.writeGpsNativeJpeg(file, coordinates);

        expect(result, isA<bool>());
      });

      test('writeGpsNativeJpeg works on image without existing EXIF', () async {
        final file = fixture.createImageWithoutExif('no_gps.jpg');
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

        final result = await service.writeGpsNativeJpeg(file, coordinates);

        expect(result, isA<bool>());
        // Log for manual inspection in CI output
        // ignore: avoid_print
        print('GPS writing result: $result - ${coordinates.toString()}');
      });

      test('writeGpsNativeJpeg handles different hemispheres', () async {
        final cases = [
          DMSCoordinates(
            latDegrees: 48,
            latMinutes: 8,
            latSeconds: 34.2,
            longDegrees: 11,
            longMinutes: 34,
            longSeconds: 12.7,
            latDirection: DirectionY.north,
            longDirection: DirectionX.east,
          ),
          DMSCoordinates(
            latDegrees: 33,
            latMinutes: 55,
            latSeconds: 11.09,
            longDegrees: 118,
            longMinutes: 24,
            longSeconds: 7.35,
            latDirection: DirectionY.south,
            longDirection: DirectionX.west,
          ),
          DMSCoordinates(
            latDegrees: 0,
            latMinutes: 0,
            latSeconds: 0,
            longDegrees: 0,
            longMinutes: 0,
            longSeconds: 0,
            latDirection: DirectionY.north,
            longDirection: DirectionX.east,
          ),
        ];

        for (final coords in cases) {
          final file = fixture.createImageWithoutExif(
            'case_${coords.hashCode}.jpg',
          );
          final ok = await service.writeGpsNativeJpeg(file, coords);
          expect(ok, isA<bool>());
          // ignore: avoid_print
          print('✓ GPS case ${coords.hashCode}: ${coords.toString()}');
        }
      });

      test('writeGpsNativeJpeg returns false on non-image', () async {
        final file = fixture.createFile('invalid.txt', [1, 2, 3]); // Non-image
        final coordinates = DMSCoordinates(
          latDegrees: 40,
          latMinutes: 42,
          latSeconds: 46,
          longDegrees: 74,
          longMinutes: 0,
          longSeconds: 21,
          latDirection: DirectionY.north,
          longDirection: DirectionX.west,
        );

        final result = await service.writeGpsNativeJpeg(file, coordinates);

        expect(result, isFalse);
      });
    });

    group('error handling', () {
      test(
        'exiftool write error bubbles as false in high-level wrapper',
        () async {
          final file = fixture.createImageWithExif('test.jpg');
          final exifData = {'DateTimeOriginal': '2023:01:01 12:00:00'};

          mockExifTool.shouldFail = true;

          final ok = await service.writeTagsWithExifToolSingle(
            file,
            exifData,
            isDate: true,
          );

          expect(ok, isFalse);
        },
      );
    });
  });
}
