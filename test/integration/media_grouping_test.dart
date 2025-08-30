/// Test suite for Modern Media Entity Grouping and Collection Management
///
/// This test suite validates the modern media management system using
/// MediaEntity and MediaEntityCollection classes for processing photos
/// and videos from Google Photos Takeout exports.
library;

import 'dart:typed_data';
import 'package:gpth/gpth-lib.dart';
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('Modern Media Entity and Collection Tests', () {
    late TestFixture fixture;
    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();
      // Initialize ServiceContainer for tests that use services
      await ServiceContainer.instance.initialize();
    });

    tearDown(() async {
      await ServiceContainer.reset();
      await fixture.tearDown();
    });

    group('MediaEntity - Object Creation and Property Management', () {
      test('creates MediaEntity with single file', () {
        final file = fixture.createFile(
          'test.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final entity = MediaEntity.single(file: file);

        expect(entity.files.firstFile, file);
        expect(entity.files.length, 1);
        expect(entity.dateTaken, isNull);
        expect(entity.dateAccuracy, isNull);
      });

      test('creates MediaEntity with date information', () {
        final file = fixture.createFile(
          'test.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final date = DateTime(2023, 1, 15);
        final entity = MediaEntity.single(
          file: file,
          dateTaken: date,
          dateAccuracy: DateAccuracy.good,
          dateTimeExtractionMethod: DateTimeExtractionMethod.exif,
        );

        expect(entity.dateTaken, date);
        expect(entity.dateAccuracy, DateAccuracy.good);
        expect(entity.dateTimeExtractionMethod, DateTimeExtractionMethod.exif);
      });

      test('creates MediaEntity from legacy map structure', () {
        final file1 = fixture.createFile(
          'test.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final file2 = fixture.createFile(
          'test_album.jpg',
          Uint8List.fromList([4, 5, 6]),
        );

        final entity = MediaEntity.fromMap(
          files: {null: file1, 'Album Name': file2},
          dateTaken: DateTime(2023, 1, 15),
          dateTakenAccuracy: 2, // corresponds to DateAccuracy.good
        );

        expect(entity.files.length, 2);
        expect(entity.files.firstFile, file1);
        expect(entity.files.getFileForAlbum('Album Name'), file2);
        expect(entity.dateAccuracy, DateAccuracy.good);
      });

      test('MediaEntity has album associations', () {
        final file1 = fixture.createFile(
          'test.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final file2 = fixture.createFile(
          'test_album.jpg',
          Uint8List.fromList([4, 5, 6]),
        );

        final entityWithAlbum = MediaEntity.fromMap(
          files: {null: file1, 'Album Name': file2},
        );

        final entityWithoutAlbum = MediaEntity.single(file: file1);

        expect(entityWithAlbum.hasAlbumAssociations, isTrue);
        expect(entityWithoutAlbum.hasAlbumAssociations, isFalse);
      });
    });

    group('MediaEntityCollection - Collection Management', () {
      test('creates empty collection', () {
        final collection = MediaEntityCollection();

        expect(collection.isEmpty, isTrue);
        expect(collection.length, 0);
        expect(collection.media, isEmpty);
      });

      test('creates collection with initial entities', () {
        final file1 = fixture.createFile(
          'test1.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final file2 = fixture.createFile(
          'test2.jpg',
          Uint8List.fromList([4, 5, 6]),
        );

        final entity1 = MediaEntity.single(file: file1);
        final entity2 = MediaEntity.single(file: file2);

        final collection = MediaEntityCollection([entity1, entity2]);

        expect(collection.length, 2);
        expect(collection.isNotEmpty, isTrue);
        expect(collection.media.contains(entity1), isTrue);
        expect(collection.media.contains(entity2), isTrue);
      });

      test('adds entities to collection', () {
        final collection = MediaEntityCollection();
        final file = fixture.createFile(
          'test.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final entity = MediaEntity.single(file: file);

        collection.add(entity);

        expect(collection.length, 1);
        expect(collection.media.first, entity);
      });

      test('removes entities from collection', () {
        final file = fixture.createFile(
          'test.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final entity = MediaEntity.single(file: file);
        final collection = MediaEntityCollection([entity]);

        final removed = collection.remove(entity);

        expect(removed, isTrue);
        expect(collection.isEmpty, isTrue);
      });
    });

    group('MediaEntityCollection - Duplicate Detection', () {
      test('removes duplicate entities successfully', () async {
        final file1 = fixture.createFile(
          'test1.jpg',
          Uint8List.fromList([1, 2, 3, 4, 5]),
        );
        final file2 = fixture.createFile(
          'test2.jpg',
          Uint8List.fromList([1, 2, 3, 4, 5]),
        ); // Same content
        final file3 = fixture.createFile(
          'test3.jpg',
          Uint8List.fromList([6, 7, 8, 9, 10]),
        ); // Different content

        final entity1 = MediaEntity.single(file: file1);
        final entity2 = MediaEntity.single(file: file2);
        final entity3 = MediaEntity.single(file: file3);

        final collection = MediaEntityCollection([entity1, entity2, entity3]);

        final removedCount = await collection.removeDuplicates();

        expect(collection.length, 2); // One duplicate should be removed
        expect(removedCount, 1);
      });

      test('handles collection with no duplicates', () async {
        final file1 = fixture.createFile(
          'test1.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final file2 = fixture.createFile(
          'test2.jpg',
          Uint8List.fromList([4, 5, 6]),
        );

        final entity1 = MediaEntity.single(file: file1);
        final entity2 = MediaEntity.single(file: file2);

        final collection = MediaEntityCollection([entity1, entity2]);

        final removedCount = await collection.removeDuplicates();

        expect(collection.length, 2);
        expect(removedCount, 0);
      });
    });

    group('MediaEntityCollection - Album Detection', () {
      test('finds albums in collection', () async {
        final file1 = fixture.createFile(
          'test1.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final file2 = fixture.createFile(
          'test2.jpg',
          Uint8List.fromList([4, 5, 6]),
        );

        final entity1 = MediaEntity.single(file: file1);
        final entity2 = MediaEntity.single(file: file2);

        final collection = MediaEntityCollection([entity1, entity2]);

        await collection.findAlbums();

        // Just verify the method completes successfully
        expect(collection.length, 2);
      });

      test('processes entities with album associations', () async {
        final file1 = fixture.createFile(
          'test.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final file2 = fixture.createFile(
          'test_album.jpg',
          Uint8List.fromList([4, 5, 6]),
        );

        final entity = MediaEntity.fromMap(
          files: {null: file1, 'Vacation 2023': file2},
        );

        final collection = MediaEntityCollection([entity]);

        await collection.findAlbums();

        expect(collection.length, 1);
        expect(entity.hasAlbumAssociations, isTrue);
      });
    });

    group('MediaFilesCollection - File Management', () {
      test('creates single file collection', () {
        final file = fixture.createFile(
          'test.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final collection = MediaFilesCollection.single(file);

        expect(collection.length, 1);
        expect(collection.firstFile, file);
        expect(collection.hasYearBasedFiles, isTrue);
        expect(collection.hasAlbumFiles, isFalse);
      });

      test('creates collection from map', () {
        final file1 = fixture.createFile(
          'test.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final file2 = fixture.createFile(
          'test_album.jpg',
          Uint8List.fromList([4, 5, 6]),
        );

        final collection = MediaFilesCollection.fromMap({
          null: file1,
          'Album Name': file2,
        });

        expect(collection.length, 2);
        expect(collection.hasYearBasedFiles, isTrue);
        expect(collection.hasAlbumFiles, isTrue);
        expect(collection.albumNames, {'Album Name'});
      });

      test('adds files to collection', () {
        final file1 = fixture.createFile(
          'test.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final file2 = fixture.createFile(
          'test_album.jpg',
          Uint8List.fromList([4, 5, 6]),
        );

        final collection = MediaFilesCollection.single(file1);
        final updated = collection.withFile('Album Name', file2);

        expect(updated.length, 2);
        expect(updated.getFileForAlbum('Album Name'), file2);
        expect(collection.length, 1); // Original unchanged
      });

      test('removes album from collection', () {
        final file1 = fixture.createFile(
          'test.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        final file2 = fixture.createFile(
          'test_album.jpg',
          Uint8List.fromList([4, 5, 6]),
        );

        final collection = MediaFilesCollection.fromMap({
          null: file1,
          'Album Name': file2,
        });

        final updated = collection.withoutAlbum('Album Name');

        expect(updated.length, 1);
        expect(updated.hasAlbumFiles, isFalse);
        expect(collection.length, 2); // Original unchanged
      });
    });
  });
}
