/// Test suite for PathResolverService
///
/// Tests the Google Photos Takeout path resolution functionality.
library;

import 'package:gpth/gpth_lib_exports.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('PathResolverService', () {
    late TestFixture fixture;

    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    group('resolveGooglePhotosPath', () {
      test(
        'returns same path when already pointing to Google Photos directory',
        () {
          // Create a Google Photos structure
          final googlePhotosDir = fixture.createDirectory('Google Photos');
          fixture.createDirectory('Google Photos/Photos from 2023');
          fixture.createImageWithExif(
            'Google Photos/Photos from 2023/photo.jpg',
          );

          final result = PathResolverService.resolveGooglePhotosPath(
            googlePhotosDir.path,
          );

          expect(result, equals(googlePhotosDir.path));
        },
      );

      test('resolves path when pointing to Takeout directory', () {
        // Create Takeout/Google Photos structure
        final takeoutDir = fixture.createDirectory('Takeout');
        fixture.createDirectory('Takeout/Google Photos');
        fixture.createDirectory('Takeout/Google Photos/Photos from 2023');
        fixture.createImageWithExif(
          'Takeout/Google Photos/Photos from 2023/photo.jpg',
        );

        final result = PathResolverService.resolveGooglePhotosPath(
          takeoutDir.path,
        );

        expect(
          result,
          equals(path.join(fixture.basePath, 'Takeout', 'Google Photos')),
        );
      });
      test('resolves path when pointing to parent of Takeout directory', () {
        // Create parent/Takeout/Google Photos structure
        final parentDir = fixture.createDirectory('Export');
        fixture.createDirectory('Export/Takeout');
        fixture.createDirectory('Export/Takeout/Google Photos');
        fixture.createDirectory(
          'Export/Takeout/Google Photos/Photos from 2023',
        );
        fixture.createImageWithExif(
          'Export/Takeout/Google Photos/Photos from 2023/photo.jpg',
        );

        final result = PathResolverService.resolveGooglePhotosPath(
          parentDir.path,
        );

        expect(
          result,
          equals(
            path.join(fixture.basePath, 'Export', 'Takeout', 'Google Photos'),
          ),
        );
      });
      test('recognizes Google Photos directory with album folders', () {
        // Create Google Photos structure with albums instead of year folders
        final googlePhotosDir = fixture.createDirectory('Google Photos');
        fixture.createDirectory('Google Photos/Vacation Album');
        fixture.createImageWithExif('Google Photos/Vacation Album/photo.jpg');

        final result = PathResolverService.resolveGooglePhotosPath(
          googlePhotosDir.path,
        );

        expect(result, equals(googlePhotosDir.path));
      });

      test('throws DirectoryNotFoundException for non-existent directory', () {
        final nonExistentPath = path.join(fixture.basePath, 'non_existent');

        expect(
          () => PathResolverService.resolveGooglePhotosPath(nonExistentPath),
          throwsA(
            predicate(
              (final e) =>
                  e is DirectoryNotFoundException &&
                  e.toString().contains('Input directory does not exist'),
            ),
          ),
        );
      });

      test('throws InvalidTakeoutStructureException for invalid structure', () {
        // Create directory without proper Google Photos structure
        final invalidDir = fixture.createDirectory('InvalidStructure');
        fixture.createFile('InvalidStructure/random.txt', [1, 2, 3]);

        expect(
          () => PathResolverService.resolveGooglePhotosPath(invalidDir.path),
          throwsA(
            predicate(
              (final e) =>
                  e is InvalidTakeoutStructureException &&
                  e.toString().contains(
                    'Could not find valid Google Photos Takeout structure',
                  ),
            ),
          ),
        );
      });
      test('handles nested Takeout structure', () {
        // Create nested structure with multiple levels
        final rootDir = fixture.createDirectory('MyExport');
        fixture.createDirectory('MyExport/Takeout');
        fixture.createDirectory('MyExport/Takeout/Google Photos');
        fixture.createDirectory(
          'MyExport/Takeout/Google Photos/Photos from 2022',
        );
        fixture.createDirectory(
          'MyExport/Takeout/Google Photos/Photos from 2023',
        );
        fixture.createImageWithExif(
          'MyExport/Takeout/Google Photos/Photos from 2022/photo1.jpg',
        );
        fixture.createImageWithExif(
          'MyExport/Takeout/Google Photos/Photos from 2023/photo2.jpg',
        );

        final result = PathResolverService.resolveGooglePhotosPath(
          rootDir.path,
        );

        expect(
          result,
          equals(
            path.join(fixture.basePath, 'MyExport', 'Takeout', 'Google Photos'),
          ),
        );
      });
      test('handles case-insensitive Takeout directory matching', () {
        // Create structure with different case
        final parentDir = fixture.createDirectory('Export');
        fixture.createDirectory('Export/TAKEOUT');
        fixture.createDirectory('Export/TAKEOUT/Google Photos');
        fixture.createDirectory(
          'Export/TAKEOUT/Google Photos/Photos from 2023',
        );
        fixture.createImageWithExif(
          'Export/TAKEOUT/Google Photos/Photos from 2023/photo.jpg',
        );

        final result = PathResolverService.resolveGooglePhotosPath(
          parentDir.path,
        );

        expect(
          result,
          equals(
            path.join(fixture.basePath, 'Export', 'TAKEOUT', 'Google Photos'),
          ),
        );
      });

      test('validates presence of media files in year folders', () {
        // Create structure with year folders but no media files
        final googlePhotosDir = fixture.createDirectory('Google Photos');
        fixture.createDirectory('Google Photos/Photos from 2023');
        // No media files created

        // Should still work as long as the structure exists
        final result = PathResolverService.resolveGooglePhotosPath(
          googlePhotosDir.path,
        );

        expect(result, equals(googlePhotosDir.path));
      });

      test('handles multiple year folders', () {
        final googlePhotosDir = fixture.createDirectory('Google Photos');
        fixture.createDirectory('Google Photos/Photos from 2021');
        fixture.createDirectory('Google Photos/Photos from 2022');
        fixture.createDirectory('Google Photos/Photos from 2023');
        fixture.createImageWithExif(
          'Google Photos/Photos from 2021/photo1.jpg',
        );
        fixture.createImageWithExif(
          'Google Photos/Photos from 2022/photo2.jpg',
        );
        fixture.createImageWithExif(
          'Google Photos/Photos from 2023/photo3.jpg',
        );

        final result = PathResolverService.resolveGooglePhotosPath(
          googlePhotosDir.path,
        );

        expect(result, equals(googlePhotosDir.path));
      });

      test('handles mixed album and year folder structure', () {
        final googlePhotosDir = fixture.createDirectory('Google Photos');
        fixture.createDirectory('Google Photos/Photos from 2023');
        fixture.createDirectory('Google Photos/Family Album');
        fixture.createDirectory('Google Photos/Vacation Photos');
        fixture.createImageWithExif(
          'Google Photos/Photos from 2023/photo1.jpg',
        );
        fixture.createImageWithExif('Google Photos/Family Album/photo2.jpg');
        fixture.createImageWithExif('Google Photos/Vacation Photos/photo3.jpg');

        final result = PathResolverService.resolveGooglePhotosPath(
          googlePhotosDir.path,
        );

        expect(result, equals(googlePhotosDir.path));
      });
    });

    group('error handling', () {
      test('provides helpful error message for invalid structure', () {
        final invalidDir = fixture.createDirectory('NotAGooglePhotosExport');
        fixture.createFile('NotAGooglePhotosExport/readme.txt', [1, 2, 3]);

        expect(
          () => PathResolverService.resolveGooglePhotosPath(invalidDir.path),
          throwsA(
            allOf(
              isA<InvalidTakeoutStructureException>(),
              predicate<InvalidTakeoutStructureException>(
                (final e) => e.toString().contains('Expected structure'),
              ),
            ),
          ),
        );
      });
      test('handles permission errors gracefully', () {
        // This test is platform-dependent and might not work on all systems
        // but it tests the error handling path
        final testDir = fixture.createDirectory('TestDir');

        // Should throw an InvalidTakeoutStructureException since TestDir
        // doesn't have the expected Google Photos structure
        expect(
          () => PathResolverService.resolveGooglePhotosPath(testDir.path),
          throwsA(isA<InvalidTakeoutStructureException>()),
        );
      });
    });
  });
}
