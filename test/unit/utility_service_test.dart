/// Test suite for FormattingService (formerly UtilityService)
///
/// Tests utility functions for file operations, calculations, and formatting.
library;

import 'dart:io';
import 'package:gpth/gpth-lib.dart';
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('FormattingService', () {
    late FormattingService service;
    late TestFixture fixture;
    setUp(() async {
      service = const FormattingService();
      fixture = TestFixture();
      await fixture.setUp();
      // Sanity check: ensure fixture initialized a non-empty base path
      expect(
        fixture.basePath.isNotEmpty,
        isTrue,
        reason: 'TestFixture basePath should be initialized',
      );
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    group('calculateOutputFileCount', () {
      test('calculates count for shortcut album option', () {
        final file1 = File('test1.jpg');
        final file2 = File('test2.jpg');

        final media1 = MediaEntity.single(file: file1);
        final media2 = MediaEntity.single(
          file: file2,
        ).withFile('Album1', file2).withFile('Album2', file2);

        final count = service.calculateOutputFileCount([
          media1,
          media2,
        ], 'shortcut');

        // media1 has 1 file, media2 has 3 files (original + 2 album files)
        expect(count, equals(4));
      });

      test('calculates count for duplicate-copy album option', () {
        final file1 = File('test1.jpg');
        final file2 = File('test2.jpg');

        final media1 = MediaEntity.single(file: file1);
        final media2 = MediaEntity.single(
          file: file2,
        ).withFile('Album1', file2);

        final count = service.calculateOutputFileCount([
          media1,
          media2,
        ], 'duplicate-copy');

        // media1 has 1 file, media2 has 2 files
        expect(count, equals(3));
      });

      test('calculates count for reverse-shortcut album option', () {
        final file1 = File('test1.jpg');
        final file2 = File('test2.jpg');

        final media1 = MediaEntity.single(file: file1);
        final media2 = MediaEntity.single(
          file: file2,
        ).withFile('Album1', file2);

        final count = service.calculateOutputFileCount([
          media1,
          media2,
        ], 'reverse-shortcut');

        // Same as shortcut/duplicate-copy - counts all file associations
        expect(count, equals(3));
      });

      test('calculates count for json album option', () {
        final file1 = File('test1.jpg');
        final file2 = File('test2.jpg');

        final media1 = MediaEntity.single(file: file1);
        final media2 = MediaEntity.single(
          file: file2,
        ).withFile('Album1', file2).withFile('Album2', file2);

        final count = service.calculateOutputFileCount([
          media1,
          media2,
        ], 'json');

        // For json option, returns count of media entities
        expect(count, equals(2));
      });
      test('calculates count for nothing album option with year-based files', () {
        final file1 = File('test1.jpg');
        final file2 = File('test2.jpg');

        // Create media with year-based files (files without album associations)
        final media1 = MediaEntity.single(
          file: file1,
        ); // Has year-based file (null key)

        // Create media with only album files (no year-based files)
        final media2 = MediaEntity(
          files: MediaFilesCollection.fromMap({
            'Album1': file2,
          }), // Only album files
        );

        final count = service.calculateOutputFileCount([
          media1,
          media2,
        ], 'nothing');

        // Only counts media with year-based files (no album associations)
        expect(count, equals(1)); // Only media1 qualifies
      });

      test('throws ArgumentError for invalid album option', () {
        final file = File('test.jpg');
        final media = MediaEntity.single(file: file);

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
    group('printError', () {
      test('prints error message to stderr', () {
        // Note: Direct testing of stderr writing is complex in Dart tests
        // This test documents the expected behavior
        expect(() => service.printError('Test error'), returnsNormally);
      });
    });
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
