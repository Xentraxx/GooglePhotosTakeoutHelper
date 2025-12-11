/// Test suite for FormattingService (formerly UtilityService)
///
/// Tests utility functions for file operations, calculations, and formatting.
library;

import 'dart:io';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('FormattingService', () {
    late FormattingService service;
    late TestFixture fixture;
    late AlbumRelationshipService albumSvc;

    setUp(() async {
      service = const FormattingService();
      fixture = TestFixture();
      await fixture.setUp();

      // Required to use albumRelationshipService in the tests
      await ServiceContainer.instance.initialize();
      albumSvc = ServiceContainer.instance.albumRelationshipService;

      // Sanity check: ensure fixture initialized a non-empty base path
      expect(
        fixture.basePath.isNotEmpty,
        isTrue,
        reason: 'TestFixture basePath should be initialized',
      );
    });

    tearDown(() async {
      await fixture.tearDown();
      await ServiceContainer.reset();
    });

    group('calculateOutputFileCount', () {
      test('calculates count for shortcut album option', () async {
        // media1: year-only → 1 association
        final f1 = fixture.createFile('2023/test1.jpg', [1, 1, 1]);
        final media1 = MediaEntity.single(
          file: FileEntity(sourcePath: f1.path),
        );

        // media2: year + 2 albums → 3 associations
        final bytes2 = [2, 2, 2];
        final y2 = fixture.createFile('2023/test2.jpg', bytes2);
        final a21 = fixture.createFile('Albums/Album1/test2.jpg', bytes2);
        final a22 = fixture.createFile('Albums/Album2/test2.jpg', bytes2);
        final merged2 = await albumSvc.detectAndMergeAlbums([
          MediaEntity.single(file: FileEntity(sourcePath: y2.path)),
          MediaEntity.single(file: FileEntity(sourcePath: a21.path)),
          MediaEntity.single(file: FileEntity(sourcePath: a22.path)),
        ]);
        final media2 = merged2.single;

        final count = service.calculateOutputFileCount([
          media1,
          media2,
        ], 'shortcut');

        // media1 has 1, media2 has 3 → total 4
        expect(count, equals(4));
      });

      test('calculates count for duplicate-copy album option', () async {
        // media1: year-only → 1
        final f1 = fixture.createFile('2023/test1.jpg', [3, 3, 3]);
        final media1 = MediaEntity.single(
          file: FileEntity(sourcePath: f1.path),
        );

        // media2: year + 1 album → 2
        final bytes2 = [4, 4, 4];
        final y2 = fixture.createFile('2023/test2.jpg', bytes2);
        final a21 = fixture.createFile('Albums/Album1/test2.jpg', bytes2);
        final media2 = (await albumSvc.detectAndMergeAlbums([
          MediaEntity.single(file: FileEntity(sourcePath: y2.path)),
          MediaEntity.single(file: FileEntity(sourcePath: a21.path)),
        ])).single;

        final count = service.calculateOutputFileCount([
          media1,
          media2,
        ], 'duplicate-copy');

        // 1 + 2 = 3
        expect(count, equals(3));
      });

      test('calculates count for reverse-shortcut album option', () async {
        // Same as the previous case
        final f1 = fixture.createFile('2023/test1.jpg', [5, 5, 5]);
        final media1 = MediaEntity.single(
          file: FileEntity(sourcePath: f1.path),
        );

        final bytes2 = [6, 6, 6];
        final y2 = fixture.createFile('2023/test2.jpg', bytes2);
        final a21 = fixture.createFile('Albums/Album1/test2.jpg', bytes2);
        final media2 = (await albumSvc.detectAndMergeAlbums([
          MediaEntity.single(file: FileEntity(sourcePath: y2.path)),
          MediaEntity.single(file: FileEntity(sourcePath: a21.path)),
        ])).single;

        final count = service.calculateOutputFileCount([
          media1,
          media2,
        ], 'reverse-shortcut');

        expect(count, equals(3));
      });

      test('calculates count for json album option', () async {
        // media1: year-only
        final f1 = fixture.createFile('2023/test1.jpg', [7]);
        final media1 = MediaEntity.single(
          file: FileEntity(sourcePath: f1.path),
        );

        // media2: year + 2 albums (but JSON counts 1 per entity)
        final bytes2 = [8];
        final y2 = fixture.createFile('2023/test2.jpg', bytes2);
        final a21 = fixture.createFile('Albums/Album1/test2.jpg', bytes2);
        final a22 = fixture.createFile('Albums/Album2/test2.jpg', bytes2);
        final media2 = (await albumSvc.detectAndMergeAlbums([
          MediaEntity.single(file: FileEntity(sourcePath: y2.path)),
          MediaEntity.single(file: FileEntity(sourcePath: a21.path)),
          MediaEntity.single(file: FileEntity(sourcePath: a22.path)),
        ])).single;

        final count = service.calculateOutputFileCount([
          media1,
          media2,
        ], 'json');

        // For json, count entities: 2
        expect(count, equals(2));
      });

      test(
        'calculates count for nothing album option with year-based files',
        () async {
          // media1: year-only → counts
          final f1 = fixture.createFile('2023/test1.jpg', [9]);
          final media1 = MediaEntity.single(
            file: FileEntity(sourcePath: f1.path),
          );

          // media2: album-only (no year) → also count for "nothing" with the new strategy implementation because all Albums files are now moved into ALL_PHOTOS folder but no associated to any Album.
          final bytes2 = [10];
          final a21 = fixture.createFile('Albums/Album1/test2.jpg', bytes2);
          final media2 = (await albumSvc.detectAndMergeAlbums([
            MediaEntity.single(file: FileEntity(sourcePath: a21.path)),
          ])).single;

          final count = service.calculateOutputFileCount([
            media1,
            media2,
          ], 'nothing');

          // Expected 1 + 1 → 2
          expect(count, equals(2));
        },
      );

      test('throws ArgumentError for invalid album option', () {
        final file = fixture.createFile('2023/test.jpg', [11]);
        final media = MediaEntity.single(
          file: FileEntity(sourcePath: file.path),
        );

        expect(
          () => service.calculateOutputFileCount([media], 'invalid-option'),
          throwsArgumentError,
        );
      });
    });

    group('validateDirectory', () {
      test(
        'returns success for existing directory when shouldExist is true',
        () async {
          final dir = Directory(fixture.basePath);

          final result = service.validateDirectory(dir);

          expect(result.isSuccess, isTrue);
        },
      );
      test(
        'returns failure for non-existing directory when shouldExist is true',
        () async {
          final dir = Directory('${fixture.basePath}/non-existent');

          final result = service.validateDirectory(dir);

          expect(result.isFailure, isTrue);
        },
      );
      test(
        'returns success for non-existing directory when shouldExist is false',
        () async {
          final dir = Directory('${fixture.basePath}/non-existent');

          final result = service.validateDirectory(dir, shouldExist: false);

          expect(result.isSuccess, isTrue);
        },
      );
      test(
        'returns failure for existing directory when shouldExist is false',
        () async {
          final dir = Directory(fixture.basePath);

          final result = service.validateDirectory(dir, shouldExist: false);

          expect(result.isFailure, isTrue);
        },
      );
    });

    group('safeCreateDirectory', () {
      test('creates directory successfully', () async {
        final dir = Directory('${fixture.basePath}/new-directory');

        final result = await service.safeCreateDirectory(dir);

        expect(result, isTrue);
        expect(await dir.exists(), isTrue);
      });

      test('creates nested directory successfully', () async {
        final dir = Directory('${fixture.basePath}/nested/deep/directory');

        final result = await service.safeCreateDirectory(dir);

        expect(result, isTrue);
        expect(await dir.exists(), isTrue);
      });

      test('succeeds when directory already exists', () async {
        final dir = Directory('${fixture.basePath}/existing');
        await dir.create();

        final result = await service.safeCreateDirectory(dir);

        expect(result, isTrue);
        expect(await dir.exists(), isTrue);
      });
    });

    group('exitProgram', () {
      test('exits with specified code', () {
        // Set up test override to prevent actual process termination
        FormattingService.testExitOverride = (final code) {
          // Override captures the exit code for verification
        };

        // Now exitProgram should throw _TestExitException with descriptive message
        expect(
          () => service.exitProgram(0),
          throwsA(
            allOf([
              isA<Exception>(),
              predicate<Exception>(
                (final e) => e.toString().contains(
                  'Program attempted to exit with code 0',
                ),
              ),
              predicate<Exception>(
                (final e) => e.toString().contains(
                  'Check logs above for the specific cause',
                ),
              ),
            ]),
          ),
        );

        // Clean up override
        FormattingService.testExitOverride = null;
      });
    });

    // group('printError', () {
    //   test('prints error message to stderr', () {
    //     // Note: Direct testing of stderr writing is complex in Dart tests
    //     // This test documents the expected behavior
    //     expect(() => service.printError('Test error'), returnsNormally);
    //   });
    // });
  });

  group('StringUtilityExtensions', () {
    test('replaceLast replaces last occurrence', () {
      const text = 'hello world hello';
      final result = text.replaceLastOcurrence('hello', 'hi');
      expect(result, equals('hello world hi'));
    });

    test('replaceLast returns same string when pattern not found', () {
      const text = 'hello world';
      final result = text.replaceLastOcurrence('xyz', 'abc');
      expect(result, equals('hello world'));
    });

    test('replaceLast handles empty strings', () {
      const text = '';
      final result = text.replaceLastOcurrence('hello', 'hi');
      expect(result, equals(''));
    });

    test('replaceLast handles single occurrence', () {
      const text = 'hello world';
      final result = text.replaceLastOcurrence('hello', 'hi');
      expect(result, equals('hi world'));
    });

    test('replaceLast replaces with empty string', () {
      const text = 'hello world hello';
      final result = text.replaceLastOcurrence('hello', '');
      expect(result, equals('hello world '));
    });
  });
}
