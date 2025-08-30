/// Test suite for ProcessingMetricsService
///
/// Tests the processing statistics and file count calculations.
library;

import 'package:gpth/gpth-lib.dart';
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('ProcessingMetricsService', () {
    late ProcessingMetricsService service;
    late TestFixture fixture;

    setUp(() async {
      service = const ProcessingMetricsService();
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    group('calculateOutputFileCount', () {
      test('calculates correctly for shortcut option', () {
        final file1 = fixture.createImageWithExif('photo1.jpg');
        final file2 = fixture.createImageWithExif('photo2.jpg');
        final file3 = fixture.createImageWithExif('photo3.jpg');

        final entities = [
          MediaEntity.single(file: file1),
          MediaEntity(
            files: MediaFilesCollection.fromMap({
              'vacation': file2,
              'family': file2,
            }),
          ),
          MediaEntity.single(file: file3),
        ];

        final collection = MediaEntityCollection(entities);
        final result = service.calculateOutputFileCount(collection, 'shortcut');

        // Should count all file associations: 1 + 2 + 1 = 4
        expect(result, equals(4));
      });

      test('calculates correctly for duplicate-copy option', () {
        final file1 = fixture.createImageWithExif('photo1.jpg');
        final file2 = fixture.createImageWithExif('photo2.jpg');

        final entities = [
          MediaEntity.single(file: file1),
          MediaEntity(
            files: MediaFilesCollection.fromMap({
              'vacation': file2,
              'family': file2,
            }),
          ),
        ];

        final collection = MediaEntityCollection(entities);
        final result = service.calculateOutputFileCount(
          collection,
          'duplicate-copy',
        );

        // Should count all file associations: 1 + 2 = 3
        expect(result, equals(3));
      });

      test('calculates correctly for reverse-shortcut option', () {
        final file1 = fixture.createImageWithExif('photo1.jpg');
        final file2 = fixture.createImageWithExif('photo2.jpg');

        final entities = [
          MediaEntity.single(file: file1),
          MediaEntity(
            files: MediaFilesCollection.fromMap({
              'vacation': file2,
              'family': file2,
            }),
          ),
        ];

        final collection = MediaEntityCollection(entities);
        final result = service.calculateOutputFileCount(
          collection,
          'reverse-shortcut',
        );

        // Should count all file associations: 1 + 2 = 3
        expect(result, equals(3));
      });

      test('calculates correctly for json option', () {
        final file1 = fixture.createImageWithExif('photo1.jpg');
        final file2 = fixture.createImageWithExif('photo2.jpg');
        final file3 = fixture.createImageWithExif('photo3.jpg');

        final entities = [
          MediaEntity.single(file: file1),
          MediaEntity(
            files: MediaFilesCollection.fromMap({
              'vacation': file2,
              'family': file2,
            }),
          ),
          MediaEntity.single(file: file3),
        ];

        final collection = MediaEntityCollection(entities);
        final result = service.calculateOutputFileCount(collection, 'json');

        // Should count one per media entity: 3
        expect(result, equals(3));
      });

      test('calculates correctly for nothing option', () {
        final file1 = fixture.createImageWithExif('photo1.jpg');
        final file2 = fixture.createImageWithExif('photo2.jpg');

        final entities = [
          MediaEntity.single(file: file1),
          MediaEntity.single(file: file2),
        ];

        final collection = MediaEntityCollection(entities);
        final result = service.calculateOutputFileCount(collection, 'nothing');

        // Should count media with files: 2
        expect(result, equals(2));
      });

      test('throws for invalid album option', () {
        final file = fixture.createImageWithExif('photo.jpg');
        final entities = [MediaEntity.single(file: file)];
        final collection = MediaEntityCollection(entities);

        expect(
          () => service.calculateOutputFileCount(collection, 'invalid-option'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('handles empty collection', () {
        final collection = MediaEntityCollection([]);

        expect(
          service.calculateOutputFileCount(collection, 'shortcut'),
          equals(0),
        );
        expect(service.calculateOutputFileCount(collection, 'json'), equals(0));
        expect(
          service.calculateOutputFileCount(collection, 'nothing'),
          equals(0),
        );
      });
    });

    group('calculateStatistics', () {
      test('calculates basic statistics correctly', () {
        final file1 = fixture.createImageWithExif('photo1.jpg');
        final file2 = fixture.createImageWithExif('photo2.jpg');
        final file3 = fixture.createImageWithExif('photo3.jpg');

        final entities = [
          MediaEntity.single(file: file1, dateTaken: DateTime(2023)),
          MediaEntity(
            files: MediaFilesCollection.fromMap({'vacation': file2}),
            dateTaken: DateTime(2023, 2),
          ),
          MediaEntity.single(file: file3), // No date
        ];

        final collection = MediaEntityCollection(entities);
        final stats = service.calculateStatistics(collection);

        expect(stats['totalMedia'], equals(3));
        expect(stats['mediaWithDates'], equals(2));
        expect(stats['mediaWithAlbums'], equals(1));
        expect(stats['totalFiles'], equals(3));
      });

      test('includes output counts for all album options', () {
        final file = fixture.createImageWithExif('photo.jpg');
        final entities = [MediaEntity.single(file: file)];
        final collection = MediaEntityCollection(entities);

        final stats = service.calculateStatistics(collection);
        expect(stats.containsKey('outputCount_shortcut'), isTrue);
        expect(stats.containsKey('outputCount_duplicate-copy'), isTrue);
        expect(stats.containsKey('outputCount_json'), isTrue);
        expect(stats.containsKey('outputCount_nothing'), isTrue);

        // All should be 1 for a single media with one file
        expect(stats['outputCount_shortcut'], equals(1));
        expect(stats['outputCount_duplicate-copy'], equals(1));
        expect(stats['outputCount_json'], equals(1));
        expect(stats['outputCount_nothing'], equals(1));
      });

      test('handles empty collection', () {
        final collection = MediaEntityCollection([]);
        final stats = service.calculateStatistics(collection);

        expect(stats['totalMedia'], equals(0));
        expect(stats['mediaWithDates'], equals(0));
        expect(stats['mediaWithAlbums'], equals(0));
        expect(stats['totalFiles'], equals(0));
        expect(stats['outputCount_shortcut'], equals(0));
        expect(stats['outputCount_json'], equals(0));
      });

      test('correctly identifies media with albums', () {
        final file1 = fixture.createImageWithExif('photo1.jpg');
        final file2 = fixture.createImageWithExif('photo2.jpg');
        final file3 = fixture.createImageWithExif('photo3.jpg');

        final entities = [
          MediaEntity.single(file: file1), // No albums
          MediaEntity(
            files: MediaFilesCollection.fromMap({'vacation': file2}),
          ), // Has album
          MediaEntity(
            files: MediaFilesCollection.fromMap({
              'family': file3,
              'work': file3,
            }),
          ), // Has multiple albums
        ];

        final collection = MediaEntityCollection(entities);
        final stats = service.calculateStatistics(collection);

        expect(stats['mediaWithAlbums'], equals(2));
        expect(stats['totalFiles'], equals(4)); // 1 + 1 + 2
      });

      test('counts total files correctly with multiple associations', () {
        final file1 = fixture.createImageWithExif('photo1.jpg');
        final file2 = fixture.createImageWithExif('photo2.jpg');

        final entities = [
          MediaEntity(
            files: MediaFilesCollection.fromMap({
              null: file1, // Year-based
              'vacation': file1, // Album copy
            }),
          ),
          MediaEntity(
            files: MediaFilesCollection.fromMap({
              'family': file2,
              'work': file2,
              'personal': file2,
            }),
          ),
        ];

        final collection = MediaEntityCollection(entities);
        final stats = service.calculateStatistics(collection);

        expect(stats['totalFiles'], equals(5)); // 2 + 3
        expect(stats['outputCount_shortcut'], equals(5));
        expect(stats['outputCount_json'], equals(2)); // One per media entity
      });
    });
  });
}
