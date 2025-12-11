/// Test to verify that MediaEntity moving strategies work end-to-end
library;

import 'dart:io';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('MediaEntity Moving Integration Tests', () {
    late TestFixture fixture;
    late AlbumRelationshipService albumSvc;

    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();
      // Initialize ServiceContainer
      await ServiceContainer.instance.initialize();
      albumSvc = ServiceContainer.instance.albumRelationshipService;
    });

    tearDown(() async {
      await fixture.tearDown();
      await ServiceContainer.reset();
    });

    test(
      'moving service processes media entities without UnimplementedError',
      () async {
        // Entity 1: normal (year-only)
        final f1 = fixture.createFile('2023/test1.jpg', [1, 2, 3]);
        final e1 = MediaEntity.single(
          file: FileEntity(sourcePath: f1.path),
          dateTaken: DateTime(2023, 6, 15),
        );

        // Entity 2: same content in year + album → merged into one entity with albumNames=['Vacation']
        final bytes2 = [4, 5, 6];
        final f2Year = fixture.createFile('2023/test2.jpg', bytes2);
        final f2Album = fixture.createFile('Albums/Vacation/test2.jpg', bytes2);

        final merged = await albumSvc.detectAndMergeAlbums([
          MediaEntity.single(
            file: FileEntity(sourcePath: f2Year.path),
            dateTaken: DateTime(2023, 7, 20),
          ),
          MediaEntity.single(
            file: FileEntity(sourcePath: f2Album.path),
            dateTaken: DateTime(2023, 7, 20),
          ),
        ]);
        final e2 = merged.single;

        final collection = MediaEntityCollection([e1, e2]);
        final outputDir = fixture.createDirectory('output');

        final context = MovingContext(
          outputDirectory: outputDir,
          dateDivision: DateDivisionLevel.year,
          albumBehavior: AlbumBehavior.shortcut,
        );

        final movingService = MoveMediaEntityService();

        // Should not throw UnimplementedError
        expect(() async {
          await for (final _ in movingService.moveMediaEntities(
            collection,
            context,
          )) {
            // progress
          }
        }, returnsNormally);
      },
    );

    test('shortcut strategy creates expected directory structure', () async {
      // Simulate year + album (same content) and merge into a single entity
      final bytes = [1, 2, 3];
      final y = fixture.createFile('2023/vacation_photo.jpg', bytes);
      final a = fixture.createFile(
        'Albums/Summer Vacation/vacation_photo.jpg',
        bytes,
      );

      final merged = await albumSvc.detectAndMergeAlbums([
        MediaEntity.single(
          file: FileEntity(sourcePath: y.path),
          dateTaken: DateTime(2023, 8, 15),
        ),
        MediaEntity.single(
          file: FileEntity(sourcePath: a.path),
          dateTaken: DateTime(2023, 8, 15),
        ),
      ]);
      final entity = merged.single;

      final collection = MediaEntityCollection([entity]);
      final outputDir = fixture.createDirectory('output');

      final context = MovingContext(
        outputDirectory: outputDir,
        dateDivision: DateDivisionLevel.year,
        albumBehavior: AlbumBehavior.shortcut,
      );

      final movingService = MoveMediaEntityService();

      var processedCount = 0;
      await for (final progress in movingService.moveMediaEntities(
        collection,
        context,
      )) {
        processedCount = progress;
      }

      expect(processedCount, equals(1));

      // Verify ALL_PHOTOS directory
      final allPhotosDir = Directory('${outputDir.path}/ALL_PHOTOS/2023');
      expect(allPhotosDir.existsSync(), isTrue);

      // Verify flattened album directory
      final albumDir = Directory('${outputDir.path}/Albums/Summer Vacation');
      expect(albumDir.existsSync(), isTrue);
    });

    test('json strategy creates albums-info.json', () async {
      // Year + album (same content) → single merged entity
      final bytes = [1, 2, 3];
      final y = fixture.createFile('2023/family_photo.jpg', bytes);
      final a = fixture.createFile('Albums/Family/family_photo.jpg', bytes);

      final merged = await albumSvc.detectAndMergeAlbums([
        MediaEntity.single(
          file: FileEntity(sourcePath: y.path),
          dateTaken: DateTime(2023, 9, 10),
        ),
        MediaEntity.single(
          file: FileEntity(sourcePath: a.path),
          dateTaken: DateTime(2023, 9, 10),
        ),
      ]);
      final entity = merged.single;

      final collection = MediaEntityCollection([entity]);
      final outputDir = fixture.createDirectory('output');

      final context = MovingContext(
        outputDirectory: outputDir,
        dateDivision: DateDivisionLevel.year,
        albumBehavior: AlbumBehavior.json,
      );
      final movingService = MoveMediaEntityService();

      await for (final _ in movingService.moveMediaEntities(
        collection,
        context,
      )) {
        // progress
      }

      // albums-info.json must exist
      final jsonFile = File('${outputDir.path}/albums-info.json');
      expect(jsonFile.existsSync(), isTrue);
    });

    test('all album behaviors work without errors', () async {
      for (final behavior in AlbumBehavior.values) {
        final f = fixture.createFile('2023/test_${behavior.value}.jpg', [
          1,
          2,
          3,
        ]);
        final e = MediaEntity.single(
          file: FileEntity(sourcePath: f.path),
          dateTaken: DateTime(2023, 6, 15),
        );

        final collection = MediaEntityCollection([e]);
        final outputDir = fixture.createDirectory('output_${behavior.value}');

        final context = MovingContext(
          outputDirectory: outputDir,
          dateDivision: DateDivisionLevel.year,
          albumBehavior: behavior,
        );
        final movingService = MoveMediaEntityService();

        expect(
          () async {
            await for (final _ in movingService.moveMediaEntities(
              collection,
              context,
            )) {
              // progress
            }
          },
          returnsNormally,
          reason: 'Strategy ${behavior.value} should work without errors',
        );
      }
    });
  });
}
