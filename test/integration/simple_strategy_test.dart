/// Simple test to debug the strategy issue
library;

import 'dart:io';
import 'package:gpth/gpth-lib.dart';
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

    test('MediaEntity.single has year-based files', () {
      final sourceFile = fixture.createFile('test.jpg', [1, 2, 3]);
      final entity = MediaEntity.single(
        file: sourceFile,
        dateTaken: DateTime(2023, 6, 15),
      );

      print('Entity files map: ${entity.files.files}');
      print('hasYearBasedFiles: ${entity.files.hasYearBasedFiles}');
      print('Files containsKey(null): ${entity.files.files.containsKey(null)}');

      expect(entity.files.hasYearBasedFiles, isTrue);
    });

    test('NothingMovingStrategy can process a single file', () async {
      final strategy = NothingMovingStrategy(fileService, pathService);

      final sourceFile = fixture.createFile('test.jpg', [1, 2, 3]);
      final entity = MediaEntity.single(
        file: sourceFile,
        dateTaken: DateTime(2023, 6, 15),
      );
      final results = <dynamic>[];
      try {
        print('About to process entity with strategy...');
        print('Entity hasYearBasedFiles: ${entity.files.hasYearBasedFiles}');
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
        if (results.isNotEmpty) {
          expect(results[0].success, isTrue);
        }
      } catch (e, stackTrace) {
        print('Exception details: $e');
        print('Stack trace: $stackTrace');
        fail('Strategy threw an exception: $e');
      }
    });
  });
}
