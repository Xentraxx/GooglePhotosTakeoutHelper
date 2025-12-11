/// Simple test to debug the strategy issue
library;

import 'dart:io';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('Simple Strategy Test', () {
    late TestFixture fixture;
    late FileOperationService fileService;
    late PathGeneratorService pathService;
    late Directory outputDir;
    late MovingContext context;

    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();

      // Initialize ServiceContainer
      await ServiceContainer.instance.initialize();

      fileService = FileOperationService();
      pathService = PathGeneratorService();
      outputDir = fixture.createDirectory('output');

      context = MovingContext(
        outputDirectory: outputDir,
        dateDivision: DateDivisionLevel.year,
        albumBehavior: AlbumBehavior.nothing,
      );
    });

    tearDown(() async {
      await fixture.tearDown();
      await ServiceContainer.reset();
    });

    test('MediaEntity.single basic properties (no album)', () {
      final sourceFile = fixture.createFile('2023/test.jpg', [1, 2, 3]);

      // IMPORTANT: MediaEntity.single now expects a FileEntity, not a File
      final entity = MediaEntity.single(
        file: FileEntity(sourcePath: sourceFile.path),
        dateTaken: DateTime(2023, 6, 15),
      );

      print('Primary file (effective path): ${entity.primaryFile.path}');
      print('hasAlbumAssociations: ${entity.hasAlbumAssociations}');
      print('albumNames: ${entity.albumNames}');

      // Compare paths (FileEntity vs File)
      expect(entity.primaryFile.path, equals(sourceFile.path));
      expect(entity.hasAlbumAssociations, isFalse);
      expect(entity.albumNames, isEmpty);
    });

    test('NothingMovingStrategy can process a single year-based file', () async {
      final strategy = NothingMovingStrategy(fileService, pathService);

      // Place the file under a year folder so it is "year-based"
      final sourceFile = fixture.createFile('2023/test.jpg', [1, 2, 3]);

      // Use FileEntity wrapper
      final entity = MediaEntity.single(
        file: FileEntity(sourcePath: sourceFile.path),
        dateTaken: DateTime(2023, 6, 15),
      );

      final results = <MoveMediaEntityResult>[];
      try {
        print('About to process entity with strategy...');
        print(
          'Entity primaryFile (effective path): ${entity.primaryFile.path}',
        );
        print('Entity hasAlbumAssociations: ${entity.hasAlbumAssociations}');

        await for (final result in strategy.processMediaEntity(
          entity,
          context,
        )) {
          print('Got result: success=${result.success}');
          if (!result.success) {
            print('Error message: ${result.errorMessage}');
          }
          results.add(result);
        }

        print('Processing completed with ${results.length} results');
        expect(results.length, equals(1));
        expect(results.first.success, isTrue);

        // Verify it moved to ALL_PHOTOS/2023 (behavior of NothingMovingStrategy)
        final allPhotosDir = Directory('${outputDir.path}/ALL_PHOTOS/2023');
        expect(allPhotosDir.existsSync(), isTrue);
      } catch (e, stackTrace) {
        print('Exception details: $e');
        print('Stack trace: $stackTrace');
        fail('Strategy threw an exception: $e');
      }
    });
  });
}
