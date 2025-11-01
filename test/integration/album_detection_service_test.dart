/// Test suite for AlbumRelationshipService
///
/// Verifies album detection/normalization and statistics against the
/// Google Photos Takeout processing model (new data model with FileEntity).
library;

import 'dart:io';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('AlbumRelationshipService', () {
    late AlbumRelationshipService service;
    late TestFixture fixture;

    setUp(() async {
      await ServiceContainer.reset();
      await ServiceContainer.instance.initialize();
      service = ServiceContainer.instance.albumRelationshipService;
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      await fixture.tearDown();
      await ServiceContainer.reset();
    });

    /// Helper: build a MediaEntity using the new FileEntity-based model.
    MediaEntity entityFromFile(final File f, final DateTime dt) => MediaEntity(
      primaryFile: FileEntity(sourcePath: f.path),
      secondaryFiles: const <FileEntity>[],
      albumsMap: const <String, AlbumEntity>{},
      dateTaken: dt,
      dateTimeExtractionMethod: DateTimeExtractionMethod.none,
    );

    group('Album Detection and Merging', () {
      test('detects and merges duplicate files from albums', () async {
        // Same content in year and album → should merge and keep album membership
        final yearPhoto = fixture.createFile('2023/IMG_001.jpg', [
          1,
          2,
          3,
          4,
          5,
        ]);
        final albumPhoto = fixture.createFile('Albums/Vacation/IMG_001.jpg', [
          1,
          2,
          3,
          4,
          5,
        ]);

        final entities = [
          entityFromFile(yearPhoto, DateTime(2023)),
          entityFromFile(albumPhoto, DateTime(2023)),
        ];

        final merged = await service.detectAndMergeAlbums(entities);

        expect(merged.length, equals(1));
        expect(merged.first.hasAlbumAssociations, isTrue);
        expect(merged.first.albumNames, containsAll(['Vacation']));
        expect(merged.first.albumNames.length, equals(1));
      });

      test('keeps separate files when content is different', () async {
        final photo1 = fixture.createFile('2023/IMG_001.jpg', [1, 2, 3]);
        final photo2 = fixture.createFile('2023/IMG_002.jpg', [4, 5, 6]);

        final entities = [
          entityFromFile(photo1, DateTime(2023)),
          entityFromFile(photo2, DateTime(2023, 1, 2)),
        ];

        final merged = await service.detectAndMergeAlbums(entities);

        expect(merged.length, equals(2));
      });

      test('handles empty list gracefully', () async {
        final merged = await service.detectAndMergeAlbums([]);

        expect(merged, isEmpty);
      });

      test('handles single file without merging', () async {
        final photo = fixture.createFile('IMG_001.jpg', [1, 2, 3]);
        final entity = entityFromFile(photo, DateTime(2023));

        final merged = await service.detectAndMergeAlbums([entity]);

        expect(merged.length, equals(1));
        expect(merged.first, equals(entity));
      });

      test('merges multiple duplicates correctly', () async {
        final content = [1, 2, 3, 4, 5, 6, 7, 8];
        final yearPhoto = fixture.createFile('2023/IMG_001.jpg', content);
        final album1Photo = fixture.createFile(
          'Albums/Vacation/IMG_001.jpg',
          content,
        );
        final album2Photo = fixture.createFile(
          'Albums/Summer/IMG_001.jpg',
          content,
        );

        final entities = [
          entityFromFile(yearPhoto, DateTime(2023)),
          entityFromFile(album1Photo, DateTime(2023)),
          entityFromFile(album2Photo, DateTime(2023)),
        ];

        final merged = await service.detectAndMergeAlbums(entities);

        expect(merged.length, equals(1));
        expect(merged.first.hasAlbumAssociations, isTrue);
        expect(merged.first.albumNames, containsAll(['Vacation', 'Summer']));
        expect(merged.first.albumNames.length, equals(2));
      });
    });

    group('Album Media Detection', () {
      test('finds media with album associations', () {
        final yearPhoto = fixture.createFile('2023/IMG_001.jpg', [1, 2, 3]);
        final albumPhoto = fixture.createFile('Albums/Vacation/IMG_002.jpg', [
          4,
          5,
          6,
        ]);

        final entities = [
          entityFromFile(yearPhoto, DateTime(2023)),
          entityFromFile(albumPhoto, DateTime(2023, 1, 2)),
        ];

        final albumMedia = service.findAlbumMedia(entities);

        expect(albumMedia.length, equals(1));
        expect(albumMedia.first.hasAlbumAssociations, isTrue);
        expect(albumMedia.first.albumNames, contains('Vacation'));
      });

      test('finds media without album associations (year-only)', () {
        final yearPhoto1 = fixture.createFile('2023/IMG_001.jpg', [1, 2, 3]);
        final yearPhoto2 = fixture.createFile('2023/IMG_002.jpg', [4, 5, 6]);

        final entities = [
          entityFromFile(yearPhoto1, DateTime(2023)),
          entityFromFile(yearPhoto2, DateTime(2023, 1, 2)),
        ];

        final yearOnlyMedia = service.findYearOnlyMedia(entities);

        expect(yearOnlyMedia.length, equals(2));
      });

      test('handles mixed media types correctly', () {
        final yearPhoto = fixture.createFile('2023/IMG_001.jpg', [1, 2, 3]);
        final albumPhoto = fixture.createFile('Albums/Vacation/IMG_002.jpg', [
          4,
          5,
          6,
        ]);

        final entities = [
          entityFromFile(yearPhoto, DateTime(2023)),
          entityFromFile(albumPhoto, DateTime(2023, 1, 2)),
        ];

        final albumMedia = service.findAlbumMedia(entities);
        final yearOnlyMedia = service.findYearOnlyMedia(entities);

        expect(albumMedia.length, equals(1));
        expect(yearOnlyMedia.length, equals(1));
      });
    });

    group('Album Statistics', () {
      test('calculates basic statistics correctly', () async {
        final yearPhoto = fixture.createFile('2023/IMG_001.jpg', [1, 2, 3]);
        final albumPhoto1 = fixture.createFile('Albums/Vacation/IMG_002.jpg', [
          4,
          5,
          6,
        ]);
        final albumPhoto2 = fixture.createFile('Albums/Family/IMG_003.jpg', [
          7,
          8,
          9,
        ]);

        final entities = [
          entityFromFile(yearPhoto, DateTime(2023)),
          entityFromFile(albumPhoto1, DateTime(2023, 1, 2)),
          entityFromFile(albumPhoto2, DateTime(2023, 1, 3)),
        ];

        // Basic stats do not require explicit merging
        final stats = service.getAlbumStatistics(entities);

        expect(stats.totalFiles, equals(3));
        expect(stats.albumFiles, equals(2));
        expect(stats.yearOnlyFiles, equals(1));
        expect(stats.uniqueAlbums, equals(2));
        expect(stats.albumNames, contains('Vacation'));
        expect(stats.albumNames, contains('Family'));
      });

      test('handles files with multiple album associations', () async {
        // Two copies with the SAME content in different albums → after merge, 1 entity with 2 albums
        final content = [1, 2, 3];
        final a1 = fixture.createFile('Albums/Vacation/IMG_001.jpg', content);
        final a2 = fixture.createFile('Albums/Summer/IMG_001.jpg', content);

        final merged = await service.detectAndMergeAlbums([
          entityFromFile(a1, DateTime(2023)),
          entityFromFile(a2, DateTime(2023)),
        ]);

        final stats = service.getAlbumStatistics(merged);

        expect(stats.totalFiles, equals(1));
        expect(stats.albumFiles, equals(1));
        expect(stats.multiAlbumFiles, equals(1));
        expect(stats.uniqueAlbums, equals(2));
      });

      test('handles empty collection', () {
        final stats = service.getAlbumStatistics([]);

        expect(stats.totalFiles, equals(0));
        expect(stats.albumFiles, equals(0));
        expect(stats.yearOnlyFiles, equals(0));
        expect(stats.uniqueAlbums, equals(0));
        expect(stats.multiAlbumFiles, equals(0));
        expect(stats.albumNames, isEmpty);
      });

      test('provides meaningful string representation', () {
        final yearPhoto = fixture.createFile('2023/IMG_001.jpg', [1, 2, 3]);
        final albumPhoto = fixture.createFile('Albums/Vacation/IMG_002.jpg', [
          4,
          5,
          6,
        ]);

        final entities = [
          entityFromFile(yearPhoto, DateTime(2023)),
          entityFromFile(albumPhoto, DateTime(2023, 1, 2)),
        ];

        final stats = service.getAlbumStatistics(entities);
        final statsString = stats.toString();

        expect(statsString, contains('total: 2'));
        expect(statsString, contains('in albums: 1'));
        expect(statsString, contains('year-only: 1'));
        expect(statsString, contains('albums: 1'));
      });
    });

    group('Error Handling', () {
      test('handles corrupt files gracefully during merging', () async {
        final corruptFile = fixture.createFile('corrupt.jpg', []);
        final entity = entityFromFile(corruptFile, DateTime(2023));

        final merged = await service.detectAndMergeAlbums([entity]);

        expect(merged.length, equals(1));
      });

      test('handles non-existent files gracefully', () {
        final nonExistentFile = File('${fixture.basePath}/nonexistent.jpg');
        final entity = entityFromFile(nonExistentFile, DateTime(2023));

        final stats = service.getAlbumStatistics([entity]);
        expect(stats.totalFiles, equals(1));
      });
    });
  });
}
