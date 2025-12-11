import 'dart:convert';
import 'dart:io';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('jsonForFile() Integration Tests - Issue #29 Resolution', () {
    late TestFixture fixture;
    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();
      // Initialize ServiceContainer to provide globalConfig
      await ServiceContainer.instance.initialize();
    });

    tearDown(() async {
      await fixture.tearDown();
      await ServiceContainer.reset();
    });

    /// Helper method to create a text file using the existing createFile method
    File createTextFile(final String name, final String content) =>
        fixture.createFile(name, utf8.encode(content));

    group('Basic Strategy Tests (always applied)', () {
      test('finds JSON with no modification (Strategy 1)', () async {
        // Create test files
        final mediaFile = fixture.createImageWithExif('photo.jpg');
        final jsonFile = createTextFile('photo.jpg.json', '{"title": "photo"}');

        final result = await jsonForFile(mediaFile, tryhard: false);
        expect(result?.path, equals(jsonFile.path));
      });

      test('finds JSON with filename shortening (Strategy 2)', () async {
        // Create a very long filename that would be shortened
        const longName =
            'very_long_filename_that_exceeds_normal_limits_and_causes_truncation';
        final mediaFile = fixture.createImageWithExif('$longName.jpg');

        // JSON file exists with shortened name
        final shortenedName = longName.substring(0, 51 - '.json'.length);
        final jsonFile = createTextFile(
          '$shortenedName.json',
          '{"title": "photo"}',
        );

        final result = await jsonForFile(mediaFile, tryhard: false);
        expect(result?.path, equals(jsonFile.path));
      });

      test('finds JSON with bracket number swapping (Strategy 3)', () async {
        // Media file has bracket at end, JSON has bracket before extension
        final mediaFile = fixture.createImageWithExif('image(11).jpg');
        final jsonFile = createTextFile(
          'image.jpg(11).json',
          '{"title": "image"}',
        );

        final result = await jsonForFile(mediaFile, tryhard: false);
        expect(result?.path, equals(jsonFile.path));
      });

      test('finds JSON with extension removal (Strategy 4)', () async {
        // Media file has extension, JSON file doesn't include it
        final mediaFile = fixture.createImageWithExif('photo.jpg');
        final jsonFile = createTextFile('photo.json', '{"title": "photo"}');

        final result = await jsonForFile(mediaFile, tryhard: false);
        expect(result?.path, equals(jsonFile.path));
      });

      test(
        'finds JSON with complete extra format removal (Strategy 5)',
        () async {
          // Media file has complete "edited" suffix
          final mediaFile = fixture.createImageWithExif('photo-edited.jpg');
          final jsonFile = createTextFile(
            'photo.jpg.json',
            '{"title": "photo"}',
          );

          final result = await jsonForFile(mediaFile, tryhard: false);
          expect(result?.path, equals(jsonFile.path));
        },
      );

      test(
        'handles international complete extra formats in basic mode',
        () async {
          final testCases = [
            {'media': 'foto-bearbeitet.jpg', 'json': 'foto.jpg.json'},
            {'media': 'photo-modifié.png', 'json': 'photo.png.json'},
            {'media': 'imagen-editado.gif', 'json': 'imagen.gif.json'},
            {'media': 'photo-edited(1).jpg', 'json': 'photo.jpg.json'},
            {'media': 'mi salón-ha editado.JPG', 'json': 'mi salón.JPG.json'},
          ];

          for (final testCase in testCases) {
            final mediaFile = fixture.createImageWithExif(testCase['media']!);
            final jsonFile = createTextFile(
              testCase['json']!,
              '{"title": "test"}',
            );

            final result = await jsonForFile(mediaFile, tryhard: false);
            expect(
              result?.path,
              equals(jsonFile.path),
              reason: 'Failed for ${testCase['media']}',
            );

            // Cleanup for next iteration
            await mediaFile.delete();
            await jsonFile.delete();
          }
        },
      );
    });

    group('Aggressive Strategy Tests (tryhard=true only)', () {
      test(
        'finds JSON with partial extra format removal - Issue #29 examples',
        () async {
          final testCases = [
            {
              'media': 'Con Yoli por Málaga en el piso nuevo_001-ha edi.JPG',
              'json': 'Con Yoli por Málaga en el piso nuevo_001.JPG.json',
            },
            {
              'media': 'Museo Marino de Matalascañas con Yoli_001-ha ed.JPG',
              'json': 'Museo Marino de Matalascañas con Yoli_001.JPG.json',
            },
            {'media': 'photo-edi.JPG', 'json': 'photo.JPG.json'},
          ];

          for (final testCase in testCases) {
            final mediaFile = fixture.createImageWithExif(testCase['media']!);
            final jsonFile = createTextFile(
              testCase['json']!,
              '{"title": "photo"}',
            );

            // Should NOT find with tryhard=false (basic strategies only)
            final basicResult = await jsonForFile(mediaFile, tryhard: false);
            expect(
              basicResult,
              isNull,
              reason: 'Basic strategies should not find ${testCase['media']}',
            );

            // Should find with tryhard=true (includes aggressive strategies)
            final tryhardResult = await jsonForFile(mediaFile, tryhard: true);
            expect(
              tryhardResult?.path,
              equals(jsonFile.path),
              reason: 'Tryhard should find ${testCase['media']}',
            );

            // Cleanup for next iteration
            await mediaFile.delete();
            await jsonFile.delete();
          }
        },
      );

      test(
        'finds JSON with extension restoration after partial removal',
        () async {
          // This tests the combined Strategy 6 + 7 approach
          final mediaFile = fixture.createFile(
            'photo-ed.jp',
            utf8.encode('fake image data'),
          );
          final jsonFile = createTextFile(
            'photo.jpg.json',
            '{"title": "photo"}',
          );

          // Should NOT find with tryhard=false
          final basicResult = await jsonForFile(mediaFile, tryhard: false);
          expect(basicResult, isNull);

          // Should find with tryhard=true using combined partial removal + extension restoration
          final tryhardResult = await jsonForFile(mediaFile, tryhard: true);
          expect(tryhardResult?.path, equals(jsonFile.path));
        },
      );

      test('finds JSON with edge case pattern removal', () async {
        // Test edge case patterns that might be missed by other strategies
        final mediaFile = fixture.createImageWithExif('photo-edi.jpg');
        final jsonFile = createTextFile('photo.jpg.json', '{"title": "photo"}');

        // Should NOT find with tryhard=false
        final basicResult = await jsonForFile(mediaFile, tryhard: false);
        expect(basicResult, isNull);

        // Should find with tryhard=true
        final tryhardResult = await jsonForFile(mediaFile, tryhard: true);
        expect(tryhardResult?.path, equals(jsonFile.path));
      });

      test('handles various international partial suffixes', () async {
        final testCases = [
          {'media': 'foto-be.jpg', 'json': 'foto.jpg.json'}, // German partial
          {'media': 'photo-mo.jpg', 'json': 'photo.jpg.json'}, // French partial
          {
            'media': 'imagen-ed.png',
            'json': 'imagen.png.json',
          }, // Spanish partial
          {
            'media': 'video-bear.mp4',
            'json': 'video.mp4.json',
          }, // German partial
        ];

        for (final testCase in testCases) {
          final mediaFile = fixture.createImageWithExif(testCase['media']!);
          final jsonFile = createTextFile(
            testCase['json']!,
            '{"title": "test"}',
          );

          // Should NOT find with basic strategies
          final basicResult = await jsonForFile(mediaFile, tryhard: false);
          expect(
            basicResult,
            isNull,
            reason: 'Basic should not find ${testCase['media']}',
          );

          // Should find with tryhard
          final tryhardResult = await jsonForFile(mediaFile, tryhard: true);
          expect(
            tryhardResult?.path,
            equals(jsonFile.path),
            reason: 'Tryhard should find ${testCase['media']}',
          );

          // Cleanup for next iteration
          await mediaFile.delete();
          await jsonFile.delete();
        }
      });
    });

    group('Strategy Precedence and Order Tests', () {
      test('earlier strategies take precedence over later ones', () async {
        // Create multiple JSON files that could match different strategies
        final mediaFile = fixture.createImageWithExif('photo-edited.jpg');

        // Strategy 1: Exact match (should be found first)
        final exactJsonFile = createTextFile(
          'photo-edited.jpg.json',
          '{"title": "exact"}',
        );

        // Strategy 5: Complete format removal match (should not be reached)
        createTextFile('photo.jpg.json', '{"title": "clean"}');

        final result = await jsonForFile(mediaFile, tryhard: false);

        // Should find the exact match first, not the cleaned version
        expect(result?.path, equals(exactJsonFile.path));
        final content = await result!.readAsString();
        expect(content, contains('"exact"'));
      });

      test('aggressive strategies only apply with tryhard=true', () async {
        final mediaFile = fixture.createImageWithExif('photo-ed.jpg');
        final jsonFile = createTextFile('photo.jpg.json', '{"title": "photo"}');

        // Basic strategies should not find partial matches
        final basicResult = await jsonForFile(mediaFile, tryhard: false);
        expect(basicResult, isNull);

        // Aggressive strategies should find partial matches
        final tryhardResult = await jsonForFile(mediaFile, tryhard: true);
        expect(tryhardResult?.path, equals(jsonFile.path));
      });

      test('handles complex real-world filename patterns', () async {
        final complexCases = [
          {
            'media': 'IMG_20230101_123456_HDR-edited(1).jpg',
            'json': 'IMG_20230101_123456_HDR.jpg.json',
            'tryhard': false, // Should work with basic strategies
          },
          {
            'media': 'PXL_20230615_090000000.PORTRAIT-bearbeitet(2).jpg',
            'json': 'PXL_20230615_090000000.PORTRAIT.jpg.json',
            'tryhard': false, // Should work with basic strategies
          },
          {
            'media': 'WhatsApp Image 2023-12-25 at 14.30.45-modifi.jpeg',
            'json': 'WhatsApp Image 2023-12-25 at 14.30.45.jpeg.json',
            'tryhard': true, // Requires aggressive strategies for partial match
          },
        ];

        for (final testCase in complexCases) {
          final mediaFile = fixture.createImageWithExif(
            testCase['media']! as String,
          );
          final jsonFile = createTextFile(
            testCase['json']! as String,
            '{"title": "test"}',
          );

          final result = await jsonForFile(
            mediaFile,
            tryhard: testCase['tryhard']! as bool,
          );
          expect(
            result?.path,
            equals(jsonFile.path),
            reason:
                'Failed for ${testCase['media']} with tryhard=${testCase['tryhard']}',
          );

          // Cleanup for next iteration
          await mediaFile.delete();
          await jsonFile.delete();
        }
      });
    });

    group('Supplemental Metadata Tests', () {
      test('prefers supplemental-metadata.json over regular .json', () async {
        final mediaFile = fixture.createImageWithExif('photo.jpg');

        // Create both types of JSON files
        createTextFile('photo.jpg.json', '{"title": "regular"}');
        final supplementalJsonFile = createTextFile(
          'photo.jpg.supplemental-metadata.json',
          '{"title": "supplemental"}',
        );

        final result = await jsonForFile(mediaFile, tryhard: false);

        // Should prefer supplemental metadata
        expect(result?.path, equals(supplementalJsonFile.path));
        final content = await result!.readAsString();
        expect(content, contains('"supplemental"'));
      });
      test(
        'finds supplemental metadata with strategy transformations',
        () async {
          final mediaFile = fixture.createImageWithExif('photo-edited.jpg');
          final supplementalJsonFile = createTextFile(
            'photo.jpg.supplemental-metadata.json',
            '{"title": "supplemental"}',
          );

          final result = await jsonForFile(mediaFile, tryhard: false);
          expect(result?.path, equals(supplementalJsonFile.path));
        },
      );

      test(
        'finds supplemental metadata for PXL file with cut off supplemental-metadata',
        () async {
          // Create the media file with the exact filename from the user's request
          final mediaFile = fixture.createImageWithExif(
            'PXL_20230518_103349822.MP',
          );

          // Create the corresponding supplemental metadata JSON file
          final supplementalJsonFile = createTextFile(
            'PXL_20230518_103349822.MP.supplemental-met.json',
            '{"photoTakenTime": {"timestamp": "1684402429"}, "title": "PXL photo"}',
          );

          // Test with tryhard=false (basic strategies only)
          final result = await jsonForFile(mediaFile, tryhard: false);
          expect(
            result,
            isNotNull,
            reason: 'Should find supplemental metadata JSON file',
          );
          expect(result?.path, equals(supplementalJsonFile.path));

          // Verify the content can be read properly
          final content = await result!.readAsString();
          expect(content, contains('"photoTakenTime"'));
          expect(content, contains('"timestamp"'));
        },
      );
    });

    group('Edge Cases and Error Handling', () {
      test('returns null when no JSON file is found', () async {
        final mediaFile = fixture.createImageWithExif('photo.jpg');
        // No JSON file created

        final result = await jsonForFile(mediaFile, tryhard: true);
        expect(result, isNull);
      });

      test('handles empty and malformed filenames gracefully', () async {
        // Test with minimal filename
        final mediaFile = fixture.createImageWithExif('a.jpg');
        final jsonFile = createTextFile('a.jpg.json', '{"title": "a"}');

        final result = await jsonForFile(mediaFile, tryhard: false);
        expect(result?.path, equals(jsonFile.path));
      });

      test('handles Unicode characters in filenames', () async {
        final unicodeCases = [
          {'media': 'café-edited.jpg', 'json': 'café.jpg.json'},
          {'media': 'phöto-bearbeitet.png', 'json': 'phöto.png.json'},
          {'media': '测试-编辑.jpg', 'json': '测试.jpg.json'},
        ];

        for (final testCase in unicodeCases) {
          final mediaFile = fixture.createImageWithExif(testCase['media']!);
          final jsonFile = createTextFile(
            testCase['json']!,
            '{"title": "unicode"}',
          );

          final result = await jsonForFile(mediaFile, tryhard: false);
          expect(
            result?.path,
            equals(jsonFile.path),
            reason: 'Failed for Unicode filename: ${testCase['media']}',
          );

          // Cleanup for next iteration
          await mediaFile.delete();
          await jsonFile.delete();
        }
      });

      test('handles special characters and spaces in filenames', () async {
        final specialCases = [
          'image (with spaces)-edited.jpg',
          'file[with]brackets-bearbeitet.png',
          'photo@#\$%-modifié.gif',
        ];

        for (final mediaFilename in specialCases) {
          final mediaFile = fixture.createImageWithExif(mediaFilename);
          // We won't create JSON files for these, just test they don't crash

          final result = await jsonForFile(mediaFile, tryhard: true);
          expect(result, isNull); // Should handle gracefully and return null

          await mediaFile.delete();
        }
      });

      test('preserves normal filenames without modification', () async {
        final normalFiles = [
          'photo.jpg',
          'image.png',
          'video.mp4',
          'document.pdf',
          'IMG_20230101_123456.jpg',
          'vacation_memories.mp4',
          'family_dinner-2023.png', // This has a dash but not an "edited" suffix
        ];

        for (final filename in normalFiles) {
          final mediaFile = fixture.createImageWithExif(filename);
          final jsonFile = createTextFile(
            '$filename.json',
            '{"title": "normal"}',
          );

          final result = await jsonForFile(mediaFile, tryhard: false);
          expect(
            result?.path,
            equals(jsonFile.path),
            reason: 'Should find JSON for normal filename: $filename',
          );

          // Cleanup for next iteration
          await mediaFile.delete();
          await jsonFile.delete();
        }
      });
    });

    group('Performance and Robustness Tests', () {
      test('handles multiple files efficiently', () async {
        final testFiles = <File>[];
        final jsonFiles = <File>[];

        try {
          // Create multiple test files
          for (int i = 0; i < 10; i++) {
            final mediaFile = fixture.createImageWithExif(
              'photo_$i-edited.jpg',
            );
            final jsonFile = createTextFile(
              'photo_$i.jpg.json',
              '{"title": "photo_$i"}',
            );
            testFiles.add(mediaFile);
            jsonFiles.add(jsonFile);
          }

          final stopwatch = Stopwatch()..start();

          // Process all files
          for (int i = 0; i < testFiles.length; i++) {
            final result = await jsonForFile(testFiles[i], tryhard: false);
            expect(result?.path, equals(jsonFiles[i].path));
          }

          stopwatch.stop();

          // Should complete within reasonable time
          expect(
            stopwatch.elapsedMilliseconds,
            lessThan(1000),
            reason: 'Processing multiple files should be efficient',
          );
        } finally {
          // Cleanup
          for (final file in [...testFiles, ...jsonFiles]) {
            if (await file.exists()) await file.delete();
          }
        }
      });

      test('handles nested directory paths correctly', () async {
        // Create nested directory structure
        final nestedDir = Directory(
          path.join(fixture.baseDir.path, 'nested', 'deep'),
        );
        await nestedDir.create(recursive: true);

        final mediaFile = File(path.join(nestedDir.path, 'photo-edited.jpg'));
        final jsonFile = File(path.join(nestedDir.path, 'photo.jpg.json'));

        await mediaFile.writeAsString('fake image data');
        await jsonFile.writeAsString('{"title": "nested photo"}');

        final result = await jsonForFile(mediaFile, tryhard: false);
        expect(result?.path, equals(jsonFile.path));
      });
    });

    group('Google Photos Realistic Filename Tests', () {
      test(
        'handles real Google Photos timestamp formats with basic strategies',
        () async {
          final realBasicCases = [
            // Standard Google Photos formats with complete suffixes
            {
              'media': 'IMG_20230615_143022-edited.jpg',
              'json': 'IMG_20230615_143022.jpg.json',
            },
            {
              'media': 'PXL_20240301_120000123-effects.jpg',
              'json': 'PXL_20240301_120000123.jpg.json',
            },
            {
              'media':
                  'Screenshot_2023-10-28-09-31-43-118_com.snapchat-edited.png',
              'json':
                  'Screenshot_2023-10-28-09-31-43-118_com.snapchat.png.json',
            },
            {
              'media': 'MVIMG_20230412_190301-smile.jpg',
              'json': 'MVIMG_20230412_190301.jpg.json',
            },
            {
              'media': 'VID_20230825_184523-effects.mp4',
              'json': 'VID_20230825_184523.mp4.json',
            },

            // International formats with complete suffixes
            {
              'media': 'IMG_20230101_000000-bearbeitet.JPG',
              'json': 'IMG_20230101_000000.JPG.json',
            },
            {'media': 'DSC_0123-modifié.jpg', 'json': 'DSC_0123.jpg.json'},
            {
              'media': 'Photo_2023-12-25_14-30-45-編集済み.jpeg',
              'json': 'Photo_2023-12-25_14-30-45.jpeg.json',
            },
            {
              'media': 'IMG-20150125-WA0003-ha editado.jpg',
              'json': 'IMG-20150125-WA0003.jpg.json',
            },

            // With digit patterns
            {
              'media': 'IMG_20230615_143022-edited(1).jpg',
              'json': 'IMG_20230615_143022.jpg.json',
            },
            {
              'media': 'PXL_20240301_120000123-bearbeitet(3).jpg',
              'json': 'PXL_20240301_120000123.jpg.json',
            },
          ];

          for (final testCase in realBasicCases) {
            final mediaFile = fixture.createImageWithExif(testCase['media']!);
            final jsonFile = createTextFile(
              testCase['json']!,
              '{"title": "google_photo", "photoTakenTime": {"timestamp": "1687008000"}}',
            );

            final result = await jsonForFile(mediaFile, tryhard: false);
            expect(
              result?.path,
              equals(jsonFile.path),
              reason: 'Basic strategies should find ${testCase['media']}',
            );

            // Cleanup for next iteration
            await mediaFile.delete();
            await jsonFile.delete();
          }
        },
      );

      test(
        'handles Google Photos truncated filenames with aggressive strategies',
        () async {
          final realTruncatedCases = [
            // Real truncation examples from issue #29
            {
              'media': 'Con Yoli por Málaga en el piso nuevo_001-ha edi.JPG',
              'json': 'Con Yoli por Málaga en el piso nuevo_001.JPG.json',
            },
            {
              'media': 'Museo Marino de Matalascañas con Yoli_001-ha ed.JPG',
              'json': 'Museo Marino de Matalascañas con Yoli_001.JPG.json',
            },
            {
              'media': 'Vacaciones familiares en la playa de Cádiz_005-ed.jpg',
              'json': 'Vacaciones familiares en la playa de Cádiz_005.jpg.json',
            },

            // Long descriptive names that get truncated
            {
              'media': 'Family vacation summer 2023 beach memories-edi.JPG',
              'json': 'Family vacation summer 2023 beach memories.JPG.json',
            },
            {
              'media': 'Wedding celebration with friends and family-bear.jpg',
              'json': 'Wedding celebration with friends and family.jpg.json',
            },
            {
              'media':
                  'Christmas dinner grandmother house tradition-modif.jpeg',
              'json': 'Christmas dinner grandmother house tradition.jpeg.json',
            },

            // International characters with truncation
            {
              'media': 'Noël en famille chez grand-mère décembre-mo.jpg',
              'json': 'Noël en famille chez grand-mère décembre.jpg.json',
            },
            {
              'media': 'Geburtstag feier im garten mit der ganzen-be.JPG',
              'json': 'Geburtstag feier im garten mit der ganzen.JPG.json',
            },
            {
              'media': 'Compleanno festa in giardino con tutta la-modific.jpg',
              'json': 'Compleanno festa in giardino con tutta la.jpg.json',
            },

            // Pixel phone specific patterns
            {
              'media': 'PXL_20230615_090000000.PORTRAIT-Night_Sight-ed.jpg',
              'json': 'PXL_20230615_090000000.PORTRAIT-Night_Sight.jpg.json',
            },
            {
              'media': 'PXL_20240301_120000123.MP-Motion_Photo-bear.jpg',
              'json': 'PXL_20240301_120000123.MP-Motion_Photo.jpg.json',
            },

            // With partial extension truncation
            {
              'media': 'Long filename that gets truncated somewhere-ed.jp',
              'json': 'Long filename that gets truncated somewhere.jpg.json',
            },
            {
              'media': 'Another very long descriptive photo name-modif.pn',
              'json': 'Another very long descriptive photo name.png.json',
            },
          ];

          for (final testCase in realTruncatedCases) {
            final mediaFile = fixture.createImageWithExif(testCase['media']!);
            final jsonFile = createTextFile(
              testCase['json']!,
              '{"title": "truncated_photo", "photoTakenTime": {"timestamp": "1687008000"}}',
            );

            // Should NOT find with basic strategies
            final basicResult = await jsonForFile(mediaFile, tryhard: false);
            expect(
              basicResult,
              isNull,
              reason:
                  'Basic strategies should not find truncated ${testCase['media']}',
            );

            // Should find with aggressive strategies
            final tryhardResult = await jsonForFile(mediaFile, tryhard: true);
            expect(
              tryhardResult?.path,
              equals(jsonFile.path),
              reason:
                  'Aggressive strategies should find truncated ${testCase['media']}',
            );

            // Cleanup for next iteration
            await mediaFile.delete();
            await jsonFile.delete();
          }
        },
      );

      test('handles Google Photos album exports with complex names', () async {
        final albumExportCases = [
          // Album export patterns
          {
            'media': 'Google Photos Export - Family Vacation 2023-edited.zip',
            'json': 'Google Photos Export - Family Vacation 2023.zip.json',
          },
          {
            'media': 'Takeout-20231225-album-Christmas_Memories-bearbeitet.jpg',
            'json': 'Takeout-20231225-album-Christmas_Memories.jpg.json',
          },

          // Shared album patterns
          {
            'media': 'Shared_Album_Wedding_Photos_Sarah_and_John-modifié.jpg',
            'json': 'Shared_Album_Wedding_Photos_Sarah_and_John.jpg.json',
          },
          {
            'media': 'Auto_Backup_Phone_Gallery_2023_Summer-edited(2).JPG',
            'json': 'Auto_Backup_Phone_Gallery_2023_Summer.JPG.json',
          },

          // Location-based names
          {
            'media': 'Location_New_York_Central_Park_Picnic_2023-ed.jpg',
            'json': 'Location_New_York_Central_Park_Picnic_2023.jpg.json',
          },
          {
            'media': 'GPS_Tagged_Photo_Latitude_40.7829_Longitude-bear.png',
            'json': 'GPS_Tagged_Photo_Latitude_40.7829_Longitude.png.json',
          },
        ];

        for (final testCase in albumExportCases) {
          final mediaFile = fixture.createImageWithExif(testCase['media']!);
          final jsonFile = createTextFile(
            testCase['json']!,
            '{"title": "album_photo", "photoTakenTime": {"timestamp": "1687008000"}, "geoData": {"latitude": 40.7829, "longitude": -73.9654}}',
          );

          final result = await jsonForFile(mediaFile, tryhard: true);
          expect(
            result?.path,
            equals(jsonFile.path),
            reason: 'Should find album export ${testCase['media']}',
          );

          // Cleanup for next iteration
          await mediaFile.delete();
          await jsonFile.delete();
        }
      });

      test('handles Google Photos burst and motion photos', () async {
        final burstMotionCases = [
          // Burst photo patterns
          {
            'media': 'BURST_20230615_143022_001-edited.jpg',
            'json': 'BURST_20230615_143022_001.jpg.json',
          },
          {
            'media': 'BURST_20230615_143022_COVER-effects.jpg',
            'json': 'BURST_20230615_143022_COVER.jpg.json',
          },
          {
            'media': 'BURST_TOP_SHOT_20230615_143022-bearbeitet.jpg',
            'json': 'BURST_TOP_SHOT_20230615_143022.jpg.json',
          },

          // Motion photo patterns
          {
            'media': 'MVIMG_20230412_190301-edited.jpg',
            'json': 'MVIMG_20230412_190301.jpg.json',
          },
          {
            'media': 'MOTION_PHOTO_20230825_184523-effects.jpg',
            'json': 'MOTION_PHOTO_20230825_184523.jpg.json',
          },

          // Live photo patterns (iOS imported to Google Photos)
          {
            'media': 'LIVE_PHOTO_20230301_120000-modifié.HEIC',
            'json': 'LIVE_PHOTO_20230301_120000.HEIC.json',
          },
          {
            'media': 'IMG_0123_LIVE-edited.jpg',
            'json': 'IMG_0123_LIVE.jpg.json',
          },

          // Truncated burst patterns
          {
            'media': 'BURST_TOP_SHOT_very_long_description_here-ed.jpg',
            'json': 'BURST_TOP_SHOT_very_long_description_here.jpg.json',
          },
          {
            'media': 'MOTION_PHOTO_family_gathering_summer_2023-bear.JPG',
            'json': 'MOTION_PHOTO_family_gathering_summer_2023.JPG.json',
          },
        ];

        for (final testCase in burstMotionCases) {
          final mediaFile = fixture.createImageWithExif(testCase['media']!);
          final jsonFile = createTextFile(
            testCase['json']!,
            '{"title": "burst_motion_photo", "photoTakenTime": {"timestamp": "1687008000"}, "motionPhotoVideo": {"status": "SUCCESS"}}',
          );

          final result = await jsonForFile(mediaFile, tryhard: true);
          expect(
            result?.path,
            equals(jsonFile.path),
            reason: 'Should find burst/motion ${testCase['media']}',
          );

          // Cleanup for next iteration
          await mediaFile.delete();
          await jsonFile.delete();
        }
      });

      test('handles Google Photos screenshot and WhatsApp patterns', () async {
        final screenshotWhatsAppCases = [
          // Android screenshot patterns
          {
            'media': 'Screenshot_20231225_143022-edited.png',
            'json': 'Screenshot_20231225_143022.png.json',
          },
          {
            'media':
                'Screenshot_2023-12-25-14-30-22-118_com.android.camera-effects.png',
            'json':
                'Screenshot_2023-12-25-14-30-22-118_com.android.camera.png.json',
          },
          {
            'media': 'Screenshot_20231225_143022_Google_Photos-bearbeitet.png',
            'json': 'Screenshot_20231225_143022_Google_Photos.png.json',
          },

          // WhatsApp patterns
          {
            'media': 'IMG-20231225-WA0001-edited.jpg',
            'json': 'IMG-20231225-WA0001.jpg.json',
          },
          {
            'media': 'VID-20231225-WA0001-effects.mp4',
            'json': 'VID-20231225-WA0001.mp4.json',
          },
          {
            'media': 'WhatsApp Image 2023-12-25 at 14.30.45-modifié.jpeg',
            'json': 'WhatsApp Image 2023-12-25 at 14.30.45.jpeg.json',
          },
          {
            'media': 'WhatsApp Video 2023-12-25 at 14.30.45-bearbeitet.mp4',
            'json': 'WhatsApp Video 2023-12-25 at 14.30.45.mp4.json',
          },

          // Truncated WhatsApp patterns
          {
            'media': 'WhatsApp Image 2023-12-25 at 14.30.45 very long-ed.jpeg',
            'json': 'WhatsApp Image 2023-12-25 at 14.30.45 very long.jpeg.json',
          },
          {
            'media': 'IMG-20231225-WA0001-group-chat-family-ed.jpg',
            'json': 'IMG-20231225-WA0001-group-chat-family.jpg.json',
          },

          // Screen recording patterns
          {
            'media': 'Screen_Recording_20231225_143022-edited.mp4',
            'json': 'Screen_Recording_20231225_143022.mp4.json',
          },
          {
            'media': 'Screencast_20231225_143022-effects.mp4',
            'json': 'Screencast_20231225_143022.mp4.json',
          },
        ];

        for (final testCase in screenshotWhatsAppCases) {
          final mediaFile = fixture.createImageWithExif(testCase['media']!);
          final jsonFile = createTextFile(
            testCase['json']!,
            '{"title": "screenshot_whatsapp", "photoTakenTime": {"timestamp": "1703509822"}, "description": "Shared via WhatsApp"}',
          );

          final result = await jsonForFile(mediaFile, tryhard: true);
          expect(
            result?.path,
            equals(jsonFile.path),
            reason: 'Should find screenshot/WhatsApp ${testCase['media']}',
          );

          // Cleanup for next iteration
          await mediaFile.delete();
          await jsonFile.delete();
        }
      });

      test('handles Google Photos camera app specific formats', () async {
        final cameraAppCases = [
          // Google Camera app patterns
          {
            'media': 'PXL_20230615_143022123-edited.jpg',
            'json': 'PXL_20230615_143022123.jpg.json',
          },
          {
            'media': 'PXL_20230615_143022123.PORTRAIT-effects.jpg',
            'json': 'PXL_20230615_143022123.PORTRAIT.jpg.json',
          },
          {
            'media': 'PXL_20230615_143022123.NIGHT-bearbeitet.dng',
            'json': 'PXL_20230615_143022123.NIGHT.dng.json',
          },
          {
            'media': 'PXL_20230615_143022123.MP-modifié.jpg',
            'json': 'PXL_20230615_143022123.MP.jpg.json',
          },

          // Samsung camera patterns
          {
            'media': '20230615_143022-edited.jpg',
            'json': '20230615_143022.jpg.json',
          },
          {
            'media': 'SAMSUNG_CAMERA_PICTURES_20230615_143022-effects.jpg',
            'json': 'SAMSUNG_CAMERA_PICTURES_20230615_143022.jpg.json',
          },

          // iPhone patterns imported to Google Photos
          {'media': 'IMG_0123-edited.HEIC', 'json': 'IMG_0123.HEIC.json'},
          {
            'media': 'IMG_E0123-effects.jpg',
            'json': 'IMG_E0123.jpg.json',
          }, // Edited on iPhone
          {
            'media': 'PORTRAIT_0123-bearbeitet.jpg',
            'json': 'PORTRAIT_0123.jpg.json',
          },

          // Truncated camera app patterns
          {
            'media': 'SAMSUNG_CAMERA_PICTURES_very_long_filename-ed.jpg',
            'json': 'SAMSUNG_CAMERA_PICTURES_very_long_filename.jpg.json',
          },
          {
            'media': 'PXL_20230615_143022123.PORTRAIT.Night_Sight-bear.dng',
            'json': 'PXL_20230615_143022123.PORTRAIT.Night_Sight.dng.json',
          },
        ];

        for (final testCase in cameraAppCases) {
          final mediaFile = fixture.createImageWithExif(testCase['media']!);
          final jsonFile = createTextFile(
            testCase['json']!,
            '{"title": "camera_app_photo", "photoTakenTime": {"timestamp": "1687008000"}, "imageViews": "1"}',
          );

          final result = await jsonForFile(mediaFile, tryhard: true);
          expect(
            result?.path,
            equals(jsonFile.path),
            reason: 'Should find camera app ${testCase['media']}',
          );

          // Cleanup for next iteration
          await mediaFile.delete();
          await jsonFile.delete();
        }
      });

      test('handles Google Photos edge cases and special characters', () async {
        final edgeCases = [
          // Files with special characters
          {
            'media': 'Photo_with_émojis_🎉_celebration-edited.jpg',
            'json': 'Photo_with_émojis_🎉_celebration.jpg.json',
          },
          {
            'media': 'Café_du_matin_☕_Paris-modifié.jpeg',
            'json': 'Café_du_matin_☕_Paris.jpeg.json',
          },
          {
            'media': 'Familie_Müller_Geburtstag_🎂-bearbeitet.JPG',
            'json': 'Familie_Müller_Geburtstag_🎂.JPG.json',
          },

          // Files with numbers and dates in names
          {
            'media': '2023-12-25_Christmas_Morning_123-edited.jpg',
            'json': '2023-12-25_Christmas_Morning_123.jpg.json',
          },
          {
            'media': 'Event_2023_Photo_001_of_500-effects.png',
            'json': 'Event_2023_Photo_001_of_500.png.json',
          },

          // Files with very long extensions
          {
            'media': 'document_scan-edited.jpeg',
            'json': 'document_scan.jpeg.json',
          },

          // Files with multiple dots
          {
            'media': 'file.name.with.dots-edited.jpg',
            'json': 'file.name.with.dots.jpg.json',
          },
          {
            'media': 'version.2.0.final-bearbeitet.png',
            'json': 'version.2.0.final.png.json',
          },
          // Truncated with special characters
          {
            'media': 'Very_long_filename_with_special_chars_and_symbols-ed.jpg',
            'json':
                'Very_long_filename_with_special_chars_and_symbols.jpg.json',
          },
          {
            'media': 'Descripción_muy_larga_con_acentos_y_ñ-modific.jpeg',
            'json': 'Descripción_muy_larga_con_acentos_y_ñ.jpeg.json',
          },
        ];

        for (final testCase in edgeCases) {
          final mediaFile = fixture.createImageWithExif(testCase['media']!);
          final jsonFile = createTextFile(
            testCase['json']!,
            '{"title": "special_chars", "photoTakenTime": {"timestamp": "1687008000"}}',
          );

          final result = await jsonForFile(mediaFile, tryhard: true);
          expect(
            result?.path,
            equals(jsonFile.path),
            reason: 'Should find special chars ${testCase['media']}',
          );

          // Cleanup for next iteration
          await mediaFile.delete();
          await jsonFile.delete();
        }
      });

      test('handles Google Photos video formats and patterns', () async {
        final videoCases = [
          // Standard video patterns
          {
            'media': 'VID_20230615_143022-edited.mp4',
            'json': 'VID_20230615_143022.mp4.json',
          },
          {
            'media': 'MOV_20230615_143022-effects.mov',
            'json': 'MOV_20230615_143022.mov.json',
          },
          {
            'media': 'MOVIE_20230615_143022-bearbeitet.avi',
            'json': 'MOVIE_20230615_143022.avi.json',
          },

          // Motion video patterns
          {
            'media': 'MVIMG_20230412_190301-edited.mp4',
            'json': 'MVIMG_20230412_190301.mp4.json',
          },
          {
            'media': 'MOTION_20230615_143022-effects.mp4',
            'json': 'MOTION_20230615_143022.mp4.json',
          },

          // Slow motion and time-lapse
          {
            'media': 'SLOW_MOTION_20230615_143022-modifié.mp4',
            'json': 'SLOW_MOTION_20230615_143022.mp4.json',
          },
          {
            'media': 'TIME_LAPSE_20230615_143022-edited.mp4',
            'json': 'TIME_LAPSE_20230615_143022.mp4.json',
          },

          // Pixel video formats
          {
            'media': 'PXL_20230615_143022123.MP-edited.mp4',
            'json': 'PXL_20230615_143022123.MP.mp4.json',
          },
          {
            'media': 'PXL_20230615_143022123.LS-effects.mp4',
            'json': 'PXL_20230615_143022123.LS.mp4.json',
          }, // Long Shot
          // Truncated video patterns
          {
            'media': 'Very_long_video_description_family_vacation-ed.mp4',
            'json': 'Very_long_video_description_family_vacation.mp4.json',
          },
          {
            'media': 'SLOW_MOTION_sunset_beach_waves_relaxing-bear.mov',
            'json': 'SLOW_MOTION_sunset_beach_waves_relaxing.mov.json',
          },
        ];

        for (final testCase in videoCases) {
          final mediaFile = fixture.createFile(
            testCase['media']!,
            utf8.encode('fake video data'),
          );
          final jsonFile = createTextFile(
            testCase['json']!,
            '{"title": "video_file", "photoTakenTime": {"timestamp": "1687008000"}, "videoProcessingState": "PROCESSED"}',
          );

          final result = await jsonForFile(mediaFile, tryhard: true);
          expect(
            result?.path,
            equals(jsonFile.path),
            reason: 'Should find video ${testCase['media']}',
          );

          // Cleanup for next iteration
          await mediaFile.delete();
          await jsonFile.delete();
        }
      });
    });
  });
}
