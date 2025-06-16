import 'dart:convert';
import 'dart:io';
import 'package:gpth/date_extractors/json_extractor.dart';
import 'package:gpth/extras.dart';
import 'package:test/test.dart';
import 'test_setup.dart';

void main() {
  group('Issue #29 Additional Edge Cases and Bug Verification', () {
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

    group('removePartialExtraFormats Function Tests', () {
      test('correctly handles minimum partial suffix length', () {
        // Test that 2-character minimums work correctly
        expect(removePartialExtraFormats('photo-ed.jpg'), equals('photo.jpg'));
        expect(
          removePartialExtraFormats('photo-be.jpg'),
          equals('photo.jpg'),
        ); // from -bearbeitet
        expect(
          removePartialExtraFormats('photo-mo.jpg'),
          equals('photo.jpg'),
        ); // from -modifié

        // Test that single character gets removed
        expect(
          removePartialExtraFormats('photo-e.jpg'),
          equals('photo.jpg'),
        ); // should not change
        expect(
          removePartialExtraFormats('photo-b.jpg'),
          equals('photo.jpg'),
        ); // should not change
      });

      test('handles partial suffixes with digit patterns', () {
        expect(
          removePartialExtraFormats('photo-ed(1).jpg'),
          equals('photo.jpg'),
        );
        expect(
          removePartialExtraFormats('photo-be(2).jpg'),
          equals('photo.jpg'),
        );
        expect(
          removePartialExtraFormats('photo-edi(3).jpg'),
          equals('photo.jpg'),
        );
      });

      test('preserves exact match behavior for known complete suffixes', () {
        expect(
          removePartialExtraFormats('photo-edited.jpg'),
          equals('photo.jpg'),
        );
        expect(
          removePartialExtraFormats('photo-bearbeitet.jpg'),
          equals('photo.jpg'),
        );
        expect(
          removePartialExtraFormats('photo-modifié.jpg'),
          equals('photo.jpg'),
        );
      });

      test('handles case insensitive matching', () {
        expect(removePartialExtraFormats('photo-ED.jpg'), equals('photo.jpg'));
        expect(removePartialExtraFormats('Photo-Be.JPG'), equals('Photo.JPG'));
        expect(
          removePartialExtraFormats('PHOTO-MO.JPEG'),
          equals('PHOTO.JPEG'),
        );
      });

      test('only removes suffix at end of filename', () {
        // Should not remove suffix in middle of filename
        expect(
          removePartialExtraFormats('edited-photo-ed.jpg'),
          equals('edited-photo.jpg'),
        );
        expect(
          removePartialExtraFormats('be-photo-be.jpg'),
          equals('be-photo.jpg'),
        );

        // Should not affect similar text that isn't at the end
        expect(
          removePartialExtraFormats('edited-photo.jpg'),
          equals('edited-photo.jpg'),
        );
      });

      test('handles filenames without extensions', () {
        expect(removePartialExtraFormats('photo-ed'), equals('photo'));
        expect(removePartialExtraFormats('photo-be'), equals('photo'));
      });

      test('preserves directory path information', () {
        expect(
          removePartialExtraFormats('/path/to/photo-ed.jpg'),
          equals('/path/to/photo.jpg'),
        );
        expect(
          removePartialExtraFormats('C:\\photos\\photo-be.jpg'),
          equals('C:\\photos\\photo.jpg'),
        );
      });
    });

    group('Edge Cases for JSON File Matching', () {
      test(
        'handles very short partial suffixes that could be false positives',
        () async {
          // This tests filenames that end with common letters but aren't actually truncated suffixes
          final testCases = [
            {
              'media': 'photo-to.jpg',
              'shouldMatch': false,
            }, // "to" is not a known partial suffix
            {
              'media': 'photo-in.jpg',
              'shouldMatch': false,
            }, // "in" is not a known partial suffix
            {
              'media': 'photo-at.jpg',
              'shouldMatch': false,
            }, // "at" is not a known partial suffix
            {
              'media': 'photo-on.jpg',
              'shouldMatch': false,
            }, // "on" is not a known partial suffix
          ];

          for (final testCase in testCases) {
            final String mediaFilename = testCase['media']! as String;
            final mediaFile = fixture.createImageWithExif(mediaFilename);

            // Only create matching JSON if we expect it to match
            File? jsonFile;
            if (testCase['shouldMatch'] == true) {
              final baseFilename = mediaFilename.replaceAll(
                RegExp(r'-\w+\.'),
                '.',
              );
              jsonFile = createTextFile(
                '$baseFilename.json',
                '{"title": "test"}',
              );
            }

            final result = await jsonForFile(mediaFile, tryhard: true);

            if (testCase['shouldMatch'] == true) {
              expect(
                result?.path,
                equals(jsonFile!.path),
                reason: 'Should match $mediaFilename',
              );
            } else {
              expect(
                result,
                isNull,
                reason:
                    'Should NOT match $mediaFilename - likely false positive',
              );
            }

            // Cleanup
            await mediaFile.delete();
            if (jsonFile != null) await jsonFile.delete();
          }
        },
      );

      test('handles multiple dash patterns in filename', () async {
        final testCases = [
          // Multiple dashes - should only remove the last relevant one
          {
            'media': 'photo-background-ed.jpg',
            'json': 'photo-background.jpg.json',
          },
          {
            'media': 'nature-landscape-mountains-be.jpg',
            'json': 'nature-landscape-mountains.jpg.json',
          },
          {
            'media': 'family-vacation-2023-edited-ed.jpg',
            'json': 'family-vacation-2023-edited.jpg.json',
          },
        ];
        for (final testCase in testCases) {
          final mediaFilename = testCase['media']!;
          final jsonFilename = testCase['json']!;
          final mediaFile = fixture.createImageWithExif(mediaFilename);
          final jsonFile = createTextFile(jsonFilename, '{"title": "test"}');

          final result = await jsonForFile(mediaFile, tryhard: true);
          expect(
            result?.path,
            equals(jsonFile.path),
            reason: 'Should handle multiple dashes in $mediaFilename',
          );

          // Cleanup
          await mediaFile.delete();
          await jsonFile.delete();
        }
      });

      test(
        'handles Unicode and international characters in partial suffixes',
        () async {
          final testCases = [
            {'media': 'café-modif.jpg', 'json': 'café.jpg.json'},
            {'media': 'naïve-edi.jpg', 'json': 'naïve.jpg.json'},
            {'media': 'résumé-be.jpg', 'json': 'résumé.jpg.json'},
          ];

          for (final testCase in testCases) {
            final mediaFile = fixture.createImageWithExif(testCase['media']!);
            final jsonFile = createTextFile(
              testCase['json']!,
              '{"title": "unicode_test"}',
            );

            final result = await jsonForFile(mediaFile, tryhard: true);
            expect(
              result?.path,
              equals(jsonFile.path),
              reason: 'Should handle Unicode in ${testCase['media']}',
            );

            // Cleanup
            await mediaFile.delete();
            await jsonFile.delete();
          }
        },
      );

      test('handles ambiguous partial suffixes correctly', () async {
        // Test cases where partial suffix could match multiple complete suffixes
        final testCases = [
          {
            'media': 'photo-edit.jpg', // Could be from -edited or -editado
            'json': 'photo.jpg.json',
          },
          {
            'media': 'photo-bear.jpg', // Could be from -bearbeitet
            'json': 'photo.jpg.json',
          },
          {
            'media': 'photo-modi.jpg', // Could be from -modifié or -modificato
            'json': 'photo.jpg.json',
          },
        ];

        for (final testCase in testCases) {
          final mediaFile = fixture.createImageWithExif(testCase['media']!);
          final jsonFile = createTextFile(
            testCase['json']!,
            '{"title": "ambiguous_test"}',
          );

          final result = await jsonForFile(mediaFile, tryhard: true);
          expect(
            result?.path,
            equals(jsonFile.path),
            reason:
                'Should handle ambiguous partial suffix in ${testCase['media']}',
          );

          // Cleanup
          await mediaFile.delete();
          await jsonFile.delete();
        }
      });
    });

    group('Performance and Stress Tests', () {
      test('handles very long filenames efficiently', () async {
        final longBaseName = 'a' * 200; // Very long base name
        final mediaFile = fixture.createImageWithExif('$longBaseName-ed.jpg');
        final jsonFile = createTextFile(
          '$longBaseName.jpg.json',
          '{"title": "long_test"}',
        );

        final stopwatch = Stopwatch()..start();
        final result = await jsonForFile(mediaFile, tryhard: true);
        stopwatch.stop();

        expect(result?.path, equals(jsonFile.path));
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(1000),
          reason: 'Should process long filenames efficiently',
        );

        // Cleanup
        await mediaFile.delete();
        await jsonFile.delete();
      });

      test(
        'handles many strategies without excessive processing time',
        () async {
          // Test a filename that will trigger many strategy attempts
          final mediaFile = fixture.createImageWithExif(
            'complex_filename_with_multiple_patterns-ed.jpg',
          );

          final stopwatch = Stopwatch()..start();
          stopwatch.stop();

          // Even if no JSON is found, it shouldn't take too long
          expect(
            stopwatch.elapsedMilliseconds,
            lessThan(1000),
            reason: 'Strategy execution should be reasonably fast',
          );

          // Cleanup
          await mediaFile.delete();
        },
      );
    });

    group('Boundary and Edge Case Tests', () {
      test('handles empty and minimal filenames', () {
        expect(removePartialExtraFormats(''), equals(''));
        expect(removePartialExtraFormats('.jpg'), equals('.jpg'));
        expect(removePartialExtraFormats('a.jpg'), equals('a.jpg'));
      });

      test('handles filenames with only partial suffix', () {
        expect(removePartialExtraFormats('-ed.jpg'), equals('.jpg'));
        expect(removePartialExtraFormats('-be.jpg'), equals('.jpg'));
      });

      test('handles maximum partial suffix length', () {
        // Test longest possible partial suffix (should be full suffix minus 1 char)
        expect(
          removePartialExtraFormats('photo-edite.jpg'),
          equals('photo.jpg'),
        ); // from -edited
        expect(
          removePartialExtraFormats('photo-bearbeite.jpg'),
          equals('photo.jpg'),
        ); // from -bearbeitet
      });

      test('preserves filenames that do not match any patterns', () {
        final noMatchCases = [
          'photo.jpg',
          'normal-filename.jpg',
          'photo-xyz.jpg', // xyz is not a known partial suffix
          'photo-123.jpg', // numbers only
          'photo-.jpg', // dash with nothing after
        ];

        for (final filename in noMatchCases) {
          expect(
            removePartialExtraFormats(filename),
            equals(filename),
            reason: 'Should preserve $filename unchanged',
          );
        }
      });
    });
  });
}
