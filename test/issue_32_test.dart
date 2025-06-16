import 'dart:convert';
import 'dart:io';
import 'package:gpth/date_extractors/json_extractor.dart';
import 'package:gpth/utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'test_setup.dart';

void main() {
  group('Issue #32 - Extension fixing and JSON matching', () {
    late TestFixture fixture;

    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    /// Helper method to create a text file
    File createTextFile(final String name, final String content) =>
        fixture.createFile(name, utf8.encode(content));

    /// Helper method to create HEIC file with proper header
    File createHEICFile(final String name) {
      // HEIF/HEIC file signature
      final heicHeader = [
        0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, // ftbox
        0x68, 0x65, 0x69, 0x63, 0x00, 0x00, 0x00, 0x00, // heic type
        0x68, 0x65, 0x69, 0x63, 0x6D, 0x69, 0x66, 0x31, // compatibility brands
        0x6D, 0x69, 0x61, 0x66, 0x4D, 0x41, 0x31, 0x42, // more brands
      ];
      return fixture.createFile(name, heicHeader);
    }

    group('JSON matching after extension fixing', () {
      test('should find JSON for file renamed by extension fixing', () async {
        // Create original HEIC file with wrong extension (.jpg)
        final originalFile = createHEICFile('IMG_2367(1).jpg');

        // Create corresponding JSON file with original name pattern
        final jsonFile = createTextFile(
          'IMG_2367.HEIC.supplemental-metadata(1).json',
          '{"photoTakenTime": {"timestamp": "1599078832", "formatted": "Sep 2, 2020, 2:47:12 PM UTC"}}',
        );

        // Simulate extension fixing: HEIC file with .jpg extension gets renamed to .heic
        final fixedFile = File(
          p.join(p.dirname(originalFile.path), 'IMG_2367(1).jpg.heic'),
        );
        await originalFile.rename(fixedFile.path);

        // Test JSON matching - should find the JSON despite the extension change
        final result = await jsonForFile(fixedFile, tryhard: true);
        expect(result, isNotNull);
        expect(result!.path, equals(jsonFile.path));
      });

      test('should handle numbered files with extension mismatch', () async {
        // Create HEIC file with JPEG extension
        final originalFile = createHEICFile('IMG_2367(1).jpeg');

        // Create corresponding JSON files
        final jsonFile1 = createTextFile(
          'IMG_2367.HEIC.supplemental-metadata(1).json',
          '{"photoTakenTime": {"timestamp": "1599078832"}}',
        );

        // Simulate extension fixing
        final fixedFile = File(
          p.join(p.dirname(originalFile.path), 'IMG_2367(1).jpeg.heic'),
        );
        await originalFile.rename(fixedFile.path);

        // Test JSON matching
        final result = await jsonForFile(fixedFile, tryhard: true);
        expect(result, isNotNull);
        expect(result!.path, equals(jsonFile1.path));
      });

      test(
        'should handle multiple extension changes in same directory',
        () async {
          // Create multiple files with extension mismatches
          final file1 = createHEICFile('IMG_2367.jpg');
          final file2 = createHEICFile('IMG_2367(1).jpg');

          // Create corresponding JSON files
          final json1 = createTextFile(
            'IMG_2367.HEIC.supplemental-metadata.json',
            '{"photoTakenTime": {"timestamp": "1599078832"}}',
          );
          final json2 = createTextFile(
            'IMG_2367.HEIC.supplemental-metadata(1).json',
            '{"photoTakenTime": {"timestamp": "1599078833"}}',
          );

          // Simulate extension fixing for both files
          final fixed1 = File(
            p.join(p.dirname(file1.path), 'IMG_2367.jpg.heic'),
          );
          final fixed2 = File(
            p.join(p.dirname(file2.path), 'IMG_2367(1).jpg.heic'),
          );

          await file1.rename(fixed1.path);
          await file2.rename(fixed2.path);

          // Test JSON matching for both files
          final result1 = await jsonForFile(fixed1, tryhard: true);
          final result2 = await jsonForFile(fixed2, tryhard: true);

          expect(result1, isNotNull);
          expect(result2, isNotNull);
          expect(result1!.path, equals(json1.path));
          expect(result2!.path, equals(json2.path));
        },
      );

      test('should handle files with added .jpg extension to HEIC', () async {
        // This tests the specific scenario from issue #32
        final heicFile = createHEICFile('IMG_2367(1).HEIC');

        // Create JSON file that would be present
        final jsonFile = createTextFile(
          'IMG_2367.HEIC.supplemental-metadata(1).json',
          '{"photoTakenTime": {"timestamp": "1599078832"}}',
        );

        // Simulate what extension fixing does: adds .jpg to HEIC file
        final renamedFile = File(
          p.join(p.dirname(heicFile.path), 'IMG_2367(1).HEIC.jpg'),
        );
        await heicFile.rename(renamedFile.path);

        // This should find the JSON file despite the extension change
        final result = await jsonForFile(renamedFile, tryhard: true);
        expect(result, isNotNull);
        expect(result!.path, equals(jsonFile.path));
      });

      test('should work with standard .json files too', () async {
        final heicFile = createHEICFile('photo.heic');

        // Create standard JSON file
        final jsonFile = createTextFile(
          'photo.HEIC.json',
          '{"photoTakenTime": {"timestamp": "1599078832"}}',
        );

        // Simulate extension fixing
        final renamedFile = File(
          p.join(p.dirname(heicFile.path), 'photo.heic.jpg'),
        );
        await heicFile.rename(renamedFile.path);

        final result = await jsonForFile(renamedFile, tryhard: true);
        expect(result, isNotNull);
        expect(result!.path, equals(jsonFile.path));
      });
    });

    group('Extension fixing integration tests', () {
      test(
        'extension fixing should update JSON file names correctly',
        () async {
          final testDir = fixture.createDirectory('extension_test');

          // Create HEIC file with wrong .jpg extension
          final wrongFile = createHEICFile('test_image.jpg');
          await wrongFile.rename(
            p.join(testDir.path, p.basename(wrongFile.path)),
          );

          // Create corresponding JSON file
          final jsonFile = createTextFile(
            'test_image.jpg.json',
            '{"title": "test"}',
          );
          await jsonFile.rename(
            p.join(testDir.path, p.basename(jsonFile.path)),
          );

          // Run extension fixing
          final fixedCount = await fixIncorrectExtensions(testDir, false);
          expect(fixedCount, equals(1));

          // Check that both file and JSON were renamed correctly
          final expectedFile = File(
            p.join(testDir.path, 'test_image.jpg.heic'),
          );
          final expectedJson = File(
            p.join(testDir.path, 'test_image.jpg.heic.json'),
          );

          expect(expectedFile.existsSync(), isTrue);
          expect(expectedJson.existsSync(), isTrue);
        },
      );

      test('should handle supplemental-metadata JSON files', () async {
        final testDir = fixture.createDirectory('metadata_test');

        // Create HEIC file with wrong extension
        final wrongFile = createHEICFile('IMG_1234.jpeg');
        await wrongFile.rename(
          p.join(testDir.path, p.basename(wrongFile.path)),
        );

        // Create supplemental-metadata JSON file
        final jsonFile = createTextFile(
          'IMG_1234.jpeg.supplemental-metadata.json',
          '{"photoTakenTime": {"timestamp": "1599078832"}}',
        );
        await jsonFile.rename(p.join(testDir.path, p.basename(jsonFile.path)));

        // Run extension fixing
        final fixedCount = await fixIncorrectExtensions(testDir, false);
        expect(fixedCount, equals(1));

        // Check that both file and supplemental-metadata JSON were renamed
        final expectedFile = File(p.join(testDir.path, 'IMG_1234.jpeg.heic'));
        final expectedJson = File(
          p.join(testDir.path, 'IMG_1234.jpeg.heic.supplemental-metadata.json'),
        );

        expect(expectedFile.existsSync(), isTrue);
        expect(expectedJson.existsSync(), isTrue);
      });
    });

    group('Edge cases for issue #32', () {
      test(
        'should handle files where original JSON has different case',
        () async {
          final heicFile = createHEICFile('Photo.jpg');

          // JSON file with different case in extension
          final jsonFile = createTextFile(
            'Photo.HEIC.json',
            '{"photoTakenTime": {"timestamp": "1599078832"}}',
          );

          // Simulate extension fixing
          final renamedFile = File(
            p.join(p.dirname(heicFile.path), 'Photo.jpg.heic'),
          );
          await heicFile.rename(renamedFile.path);

          final result = await jsonForFile(renamedFile, tryhard: true);
          expect(result, isNotNull);
          expect(result!.path, equals(jsonFile.path));
        },
      );

      test('should not match unrelated JSON files', () async {
        final heicFile = createHEICFile('IMG_9999.jpg');

        // Create unrelated JSON file
        createTextFile(
          'IMG_8888.HEIC.json',
          '{"photoTakenTime": {"timestamp": "1599078832"}}',
        );

        // Simulate extension fixing
        final renamedFile = File(
          p.join(p.dirname(heicFile.path), 'IMG_9999.jpg.heic'),
        );
        await heicFile.rename(renamedFile.path);

        final result = await jsonForFile(renamedFile, tryhard: true);
        expect(result, isNull);
      });

      test('should handle complex filename patterns', () async {
        final heicFile = createHEICFile(
          'VeryLongFileNameThatMightGetTruncated_IMG_1234(1).jpeg',
        );

        // JSON with original pattern
        final jsonFile = createTextFile(
          'VeryLongFileNameThatMightGetTruncated_IMG_1234.HEIC.supplemental-metadata(1).json',
          '{"photoTakenTime": {"timestamp": "1599078832"}}',
        );

        // Simulate extension fixing
        final renamedFile = File(
          p.join(
            p.dirname(heicFile.path),
            'VeryLongFileNameThatMightGetTruncated_IMG_1234(1).jpeg.heic',
          ),
        );
        await heicFile.rename(renamedFile.path);

        final result = await jsonForFile(renamedFile, tryhard: true);
        expect(result, isNotNull);
        expect(result!.path, equals(jsonFile.path));
      });
    });
  });
}
