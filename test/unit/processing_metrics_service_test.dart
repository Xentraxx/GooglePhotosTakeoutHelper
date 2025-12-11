/// Test suite for ProcessingMetricsService
///
/// Tests the processing statistics and file count calculations.
library;

import 'dart:typed_data';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('ProcessingMetricsService', () {
    late ProcessingMetricsService service;
    late TestFixture fixture;
    late AlbumRelationshipService albumSvc;

    // Helpers ────────────────────────────────────────────────────────────────
    // Creates a year-only entity with the provided bytes.
    Future<MediaEntity> yearOnly({
      required final String path,
      required final List<int> bytes,
      final DateTime? date,
    }) async {
      final file = fixture.createFile(path, Uint8List.fromList(bytes));
      return MediaEntity.single(
        file: FileEntity(sourcePath: file.path),
        dateTaken: date,
      );
    }

    // Creates an album-only entity (under Albums/<album>/...) with the provided bytes.
    Future<MediaEntity> albumOnly({
      required final String album,
      required final String name,
      required final List<int> bytes,
      final DateTime? date,
    }) async {
      final fAlbum = fixture.createFile(
        'Albums/$album/$name',
        Uint8List.fromList(bytes),
      );
      // No year file, so this is album-only.
      final merged = await albumSvc.detectAndMergeAlbums([
        MediaEntity.single(
          file: FileEntity(sourcePath: fAlbum.path),
          dateTaken: date,
        ),
      ]);
      return merged.single;
    }

    // Creates an entity with year + multiple albums (each album has its own path).
    Future<MediaEntity> yearPlusAlbums({
      required final String yearPath,
      required final String name,
      required final List<String> albums,
      required final List<int> bytes,
      final DateTime? date,
    }) async {
      final entities = <MediaEntity>[];
      final fYear = fixture.createFile(yearPath, Uint8List.fromList(bytes));
      entities.add(
        MediaEntity.single(
          file: FileEntity(sourcePath: fYear.path),
          dateTaken: date,
        ),
      );
      for (final a in albums) {
        final fAlbum = fixture.createFile(
          'Albums/$a/$name',
          Uint8List.fromList(bytes),
        );
        entities.add(
          MediaEntity.single(
            file: FileEntity(sourcePath: fAlbum.path),
            dateTaken: date,
          ),
        );
      }
      final merged = await albumSvc.detectAndMergeAlbums(entities);
      return merged.single;
    }

    setUp(() async {
      service = const ProcessingMetricsService();
      fixture = TestFixture();
      await fixture.setUp();
      await ServiceContainer.instance.initialize();
      albumSvc = ServiceContainer.instance.albumRelationshipService;
    });

    tearDown(() async {
      await fixture.tearDown();
      await ServiceContainer.reset();
    });

    group('calculateOutputFileCount', () {
      test('calculates correctly for shortcut option (keeping 4)', () async {
        // A: year-only → 1 association
        final eA = await yearOnly(path: '2023/photo1.jpg', bytes: [1, 1, 1]);

        // B: two albums (no year) → 2 associations
        final bytesB = [2, 2, 2];
        final fB1 = fixture.createFile(
          'Albums/vacation/photo2.jpg',
          Uint8List.fromList(bytesB),
        );
        final fB2 = fixture.createFile(
          'Albums/family/photo2.jpg',
          Uint8List.fromList(bytesB),
        );
        final mergedB = await albumSvc.detectAndMergeAlbums([
          MediaEntity.single(file: FileEntity(sourcePath: fB1.path)),
          MediaEntity.single(file: FileEntity(sourcePath: fB2.path)),
        ]);
        final eB = mergedB.single;

        // C: year-only → 1 association
        final eC = await yearOnly(path: '2023/photo3.jpg', bytes: [3, 3, 3]);

        final collection = MediaEntityCollection([eA, eB, eC]);
        final result = service.calculateOutputFileCount(collection, 'shortcut');

        // 1 + 2 + 1 = 4
        expect(result, equals(4));
      });

      test('calculates correctly for duplicate-copy option', () async {
        // A: year-only → 1
        final eA = await yearOnly(path: '2023/photo1.jpg', bytes: [4, 4, 4]);

        // B: two albums (no year) → 2
        final bytesB = [5, 5, 5];
        final fB1 = fixture.createFile(
          'Albums/vacation/photo2.jpg',
          Uint8List.fromList(bytesB),
        );
        final fB2 = fixture.createFile(
          'Albums/family/photo2.jpg',
          Uint8List.fromList(bytesB),
        );
        final eB = (await albumSvc.detectAndMergeAlbums([
          MediaEntity.single(file: FileEntity(sourcePath: fB1.path)),
          MediaEntity.single(file: FileEntity(sourcePath: fB2.path)),
        ])).single;

        final collection = MediaEntityCollection([eA, eB]);
        final result = service.calculateOutputFileCount(
          collection,
          'duplicate-copy',
        );

        // 1 + 2 = 3
        expect(result, equals(3));
      });

      test('calculates correctly for reverse-shortcut option', () async {
        // Same as previous: 1 + 2 = 3
        final eA = await yearOnly(path: '2023/photo1.jpg', bytes: [6, 6, 6]);
        final bytesB = [7, 7, 7];
        final fB1 = fixture.createFile(
          'Albums/vacation/photo2.jpg',
          Uint8List.fromList(bytesB),
        );
        final fB2 = fixture.createFile(
          'Albums/family/photo2.jpg',
          Uint8List.fromList(bytesB),
        );
        final eB = (await albumSvc.detectAndMergeAlbums([
          MediaEntity.single(file: FileEntity(sourcePath: fB1.path)),
          MediaEntity.single(file: FileEntity(sourcePath: fB2.path)),
        ])).single;

        final collection = MediaEntityCollection([eA, eB]);
        final result = service.calculateOutputFileCount(
          collection,
          'reverse-shortcut',
        );

        expect(result, equals(3));
      });

      test('calculates correctly for json option', () async {
        // JSON counts one per entity
        final eA = await yearOnly(path: '2023/photo1.jpg', bytes: [8]);
        final bytesB = [9];
        final fB1 = fixture.createFile(
          'Albums/vacation/photo2.jpg',
          Uint8List.fromList(bytesB),
        );
        final fB2 = fixture.createFile(
          'Albums/family/photo2.jpg',
          Uint8List.fromList(bytesB),
        );
        final eB = (await albumSvc.detectAndMergeAlbums([
          MediaEntity.single(file: FileEntity(sourcePath: fB1.path)),
          MediaEntity.single(file: FileEntity(sourcePath: fB2.path)),
        ])).single;
        final eC = await yearOnly(path: '2023/photo3.jpg', bytes: [10]);

        final collection = MediaEntityCollection([eA, eB, eC]);
        final result = service.calculateOutputFileCount(collection, 'json');

        // 3 entities
        expect(result, equals(3));
      });

      test('calculates correctly for nothing option', () async {
        final eA = await yearOnly(path: '2023/photo1.jpg', bytes: [11]);
        final eB = await yearOnly(path: '2023/photo2.jpg', bytes: [12]);

        final collection = MediaEntityCollection([eA, eB]);
        final result = service.calculateOutputFileCount(collection, 'nothing');

        expect(result, equals(2));
      });

      test('throws for invalid album option', () async {
        final e = await yearOnly(path: '2023/photo.jpg', bytes: [13]);
        final collection = MediaEntityCollection([e]);

        expect(
          () => service.calculateOutputFileCount(collection, 'invalid-option'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('handles empty collection', () {
        final collection = MediaEntityCollection([]);
        expect(service.calculateOutputFileCount(collection, 'shortcut'), 0);
        expect(service.calculateOutputFileCount(collection, 'json'), 0);
        expect(service.calculateOutputFileCount(collection, 'nothing'), 0);
      });
    });

    group('calculateStatistics', () {
      test('calculates basic statistics correctly', () async {
        // e1: has date
        final e1 = await yearOnly(
          path: '2023/photo1.jpg',
          bytes: [21],
          date: DateTime(2023),
        );

        // e2: album-only (one album), also has date
        final e2 = await albumOnly(
          album: 'vacation',
          name: 'photo2.jpg',
          bytes: [22],
          date: DateTime(2023, 2),
        );

        // e3: no date
        final e3 = await yearOnly(path: '2023/photo3.jpg', bytes: [23]);

        final collection = MediaEntityCollection([e1, e2, e3]);
        final stats = service.calculateStatistics(collection);

        expect(stats['totalMedia'], equals(3));
        expect(stats['mediaWithDates'], equals(2));
        expect(stats['mediaWithAlbums'], equals(1));
        // totalFiles: e1 (1) + e2 (1, album-only) + e3 (1) = 3
        expect(stats['totalFiles'], equals(3));
      });

      test('includes output counts for all album options', () async {
        final e = await yearOnly(path: '2023/photo.jpg', bytes: [24]);
        final collection = MediaEntityCollection([e]);

        final stats = service.calculateStatistics(collection);
        expect(stats.containsKey('outputCount_shortcut'), isTrue);
        expect(stats.containsKey('outputCount_duplicate-copy'), isTrue);
        expect(stats.containsKey('outputCount_json'), isTrue);
        expect(stats.containsKey('outputCount_nothing'), isTrue);

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

      test('correctly identifies media with albums', () async {
        // e1: year-only → 1
        final e1 = await yearOnly(path: '2023/p1.jpg', bytes: [31]);

        // e2: album-only (vacation) → 1
        final e2 = await albumOnly(
          album: 'vacation',
          name: 'p2.jpg',
          bytes: [32],
        );

        // e3: two albums (family + work), no year → 2
        final bytesE3 = [33];
        final f1 = fixture.createFile(
          'Albums/family/p3.jpg',
          Uint8List.fromList(bytesE3),
        );
        final f2 = fixture.createFile(
          'Albums/work/p3.jpg',
          Uint8List.fromList(bytesE3),
        );
        final e3 = (await albumSvc.detectAndMergeAlbums([
          MediaEntity.single(file: FileEntity(sourcePath: f1.path)),
          MediaEntity.single(file: FileEntity(sourcePath: f2.path)),
        ])).single;

        final collection = MediaEntityCollection([e1, e2, e3]);
        final stats = service.calculateStatistics(collection);

        expect(stats['mediaWithAlbums'], equals(2)); // e2 + e3
        expect(stats['totalFiles'], equals(4)); // 1 + 1 + 2
      });

      test('counts total files correctly with multiple associations', () async {
        // e1: year + 1 album → 2
        final e1 = await yearPlusAlbums(
          yearPath: '2023/p1.jpg',
          name: 'p1.jpg',
          albums: ['vacation'],
          bytes: [41],
        );

        // e2: 3 albums (no year) → 3
        final bytesE2 = [42];
        final a = fixture.createFile(
          'Albums/family/p2.jpg',
          Uint8List.fromList(bytesE2),
        );
        final b = fixture.createFile(
          'Albums/work/p2.jpg',
          Uint8List.fromList(bytesE2),
        );
        final c = fixture.createFile(
          'Albums/personal/p2.jpg',
          Uint8List.fromList(bytesE2),
        );
        final e2 = (await albumSvc.detectAndMergeAlbums([
          MediaEntity.single(file: FileEntity(sourcePath: a.path)),
          MediaEntity.single(file: FileEntity(sourcePath: b.path)),
          MediaEntity.single(file: FileEntity(sourcePath: c.path)),
        ])).single;

        final collection = MediaEntityCollection([e1, e2]);
        final stats = service.calculateStatistics(collection);

        expect(stats['totalFiles'], equals(5)); // 2 + 3
        expect(stats['outputCount_shortcut'], equals(5));
        expect(stats['outputCount_json'], equals(2)); // one per entity
      });
    });
  });
}
