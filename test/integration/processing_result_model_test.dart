import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessingResult', () {
    test('should create ProcessingResult with all parameters', () {
      const result = ProcessingResult(
        totalProcessingTime: Duration(minutes: 5),
        stepTimings: {'step1': Duration(seconds: 30)},
        stepResults: [],
        mediaProcessed: 100,
        duplicatesRemoved: 5,
        extrasSkipped: 10,
        extensionsFixed: 3,
        coordinatesWrittenToExif: 50,
        dateTimesWrittenToExif: 80,
        creationTimesUpdated: 25,
        extractionMethodStats: {
          DateTimeExtractionMethod.json: 70,
          DateTimeExtractionMethod.exif: 20,
          DateTimeExtractionMethod.guess: 10,
        },
      );

      expect(result.totalProcessingTime, equals(const Duration(minutes: 5)));
      expect(result.stepTimings, hasLength(1));
      expect(result.mediaProcessed, equals(100));
      expect(result.duplicatesRemoved, equals(5));
      expect(result.extrasSkipped, equals(10));
      expect(result.extensionsFixed, equals(3));
      expect(result.coordinatesWrittenToExif, equals(50));
      expect(result.dateTimesWrittenToExif, equals(80));
      expect(result.creationTimesUpdated, equals(25));
      expect(result.extractionMethodStats, hasLength(3));
      expect(result.isSuccess, isTrue);
      expect(result.error, isNull);
    });
    test('should create successful result by default', () {
      const result = ProcessingResult(
        totalProcessingTime: Duration.zero,
        stepTimings: {},
        stepResults: [],
        mediaProcessed: 0,
        duplicatesRemoved: 0,
        extrasSkipped: 0,
        extensionsFixed: 0,
        coordinatesWrittenToExif: 0,
        dateTimesWrittenToExif: 0,
        creationTimesUpdated: 0,
        extractionMethodStats: {},
      );

      expect(result.isSuccess, isTrue);
      expect(result.error, isNull);
    });

    test('should create failed result with error', () {
      final exception = Exception('Test error');
      final result = ProcessingResult.failure(exception);

      expect(result.isSuccess, isFalse);
      expect(result.error, equals(exception));
      expect(result.totalProcessingTime, equals(Duration.zero));
      expect(result.stepTimings, isEmpty);
      expect(result.mediaProcessed, equals(0));
      expect(result.duplicatesRemoved, equals(0));
      expect(result.extrasSkipped, equals(0));
      expect(result.extensionsFixed, equals(0));
      expect(result.coordinatesWrittenToExif, equals(0));
      expect(result.dateTimesWrittenToExif, equals(0));
      expect(result.creationTimesUpdated, equals(0));
      expect(result.extractionMethodStats, isEmpty);
    });

    group('Summary generation', () {
      test('should generate success summary with statistics', () {
        const result = ProcessingResult(
          totalProcessingTime: Duration(minutes: 5),
          stepTimings: {},
          stepResults: [],
          mediaProcessed: 100,
          duplicatesRemoved: 5,
          extrasSkipped: 10,
          extensionsFixed: 3,
          coordinatesWrittenToExif: 50,
          dateTimesWrittenToExif: 80,
          creationTimesUpdated: 25,
          extractionMethodStats: {
            DateTimeExtractionMethod.json: 70,
            DateTimeExtractionMethod.exif: 20,
          },
        );

        final summary = result.summary;

        expect(summary, contains('DONE! FREEEEEDOOOOM!!!'));
        expect(summary, contains('5 duplicates were found and skipped'));
        expect(
          summary,
          contains('50/100 files got their coordinates set in EXIF data'),
        );
        expect(
          summary,
          contains('80/100 files got their DateTime set in EXIF data'),
        );
        expect(summary, contains('3/100 files got their extensions fixed'));
        expect(
          summary,
          contains('25/100 files had their CreationDate updated'),
        );
        expect(summary, contains('10 extras were skipped'));
        expect(summary, contains('DateTime extraction method statistics:'));
        expect(summary, contains('json: 70 files'));
        expect(summary, contains('exif: 20 files'));
        expect(summary, contains('the script took 0h 05m 00s to complete'));
      });

      test('should generate minimal summary when no operations performed', () {
        const result = ProcessingResult(
          totalProcessingTime: Duration(minutes: 2),
          stepTimings: {},
          stepResults: [],
          mediaProcessed: 0,
          duplicatesRemoved: 0,
          extrasSkipped: 0,
          extensionsFixed: 0,
          coordinatesWrittenToExif: 0,
          dateTimesWrittenToExif: 0,
          creationTimesUpdated: 0,
          extractionMethodStats: {},
        );

        final summary = result.summary;

        expect(summary, contains('DONE! FREEEEEDOOOOM!!!'));
        expect(summary, contains('the script took 0h 02m 00s to complete'));
        expect(summary, isNot(contains('duplicates were found')));
        expect(summary, isNot(contains('coordinates set in EXIF')));
        expect(summary, isNot(contains('extensions fixed')));
      });

      test('should generate failure summary', () {
        final exception = Exception('Processing failed due to invalid input');
        final result = ProcessingResult.failure(exception);

        final summary = result.summary;

        expect(summary, contains('Processing failed:'));
        expect(summary, contains('Processing failed due to invalid input'));
      });

      test('should handle unknown error in failure summary', () {
        const result = ProcessingResult(
          totalProcessingTime: Duration.zero,
          stepTimings: {},
          stepResults: [],
          mediaProcessed: 0,
          duplicatesRemoved: 0,
          extrasSkipped: 0,
          extensionsFixed: 0,
          coordinatesWrittenToExif: 0,
          dateTimesWrittenToExif: 0,
          creationTimesUpdated: 0,
          extractionMethodStats: {},
          isSuccess: false,
        );

        final summary = result.summary;

        expect(summary, contains('Processing failed:'));
        expect(summary, contains('Unknown error'));
      });
    });

    group('Step timings validation', () {
      test('should handle multiple step timings', () {
        final stepTimings = {
          'Fix Extensions': const Duration(seconds: 10),
          'Discover Media': const Duration(seconds: 30),
          'Remove Duplicates': const Duration(seconds: 20),
          'Extract Dates': const Duration(seconds: 40),
          'Write EXIF': const Duration(seconds: 50),
          'Find Albums': const Duration(seconds: 15),
          'Move Files': const Duration(seconds: 60),
          'Update Creation Time': const Duration(seconds: 5),
        };
        final result = ProcessingResult(
          totalProcessingTime: const Duration(minutes: 4),
          stepTimings: stepTimings,
          stepResults: [],
          mediaProcessed: 100,
          duplicatesRemoved: 0,
          extrasSkipped: 0,
          extensionsFixed: 0,
          coordinatesWrittenToExif: 0,
          dateTimesWrittenToExif: 0,
          creationTimesUpdated: 0,
          extractionMethodStats: {},
        );

        expect(result.stepTimings, hasLength(8));
        expect(
          result.stepTimings['Fix Extensions'],
          equals(const Duration(seconds: 10)),
        );
        expect(
          result.stepTimings['Move Files'],
          equals(const Duration(seconds: 60)),
        );
      });
      test('should handle empty step timings', () {
        const result = ProcessingResult(
          totalProcessingTime: Duration(minutes: 1),
          stepTimings: {},
          stepResults: [],
          mediaProcessed: 0,
          duplicatesRemoved: 0,
          extrasSkipped: 0,
          extensionsFixed: 0,
          coordinatesWrittenToExif: 0,
          dateTimesWrittenToExif: 0,
          creationTimesUpdated: 0,
          extractionMethodStats: {},
        );

        expect(result.stepTimings, isEmpty);
      });
    });

    group('Extraction method statistics', () {
      test('should handle all extraction methods', () {
        final extractionStats = {
          DateTimeExtractionMethod.json: 50,
          DateTimeExtractionMethod.exif: 30,
          DateTimeExtractionMethod.guess: 15,
          DateTimeExtractionMethod.jsonTryHard: 5,
          DateTimeExtractionMethod.none: 0,
        };
        final result = ProcessingResult(
          totalProcessingTime: const Duration(minutes: 3),
          stepTimings: {},
          stepResults: [],
          mediaProcessed: 100,
          duplicatesRemoved: 0,
          extrasSkipped: 0,
          extensionsFixed: 0,
          coordinatesWrittenToExif: 0,
          dateTimesWrittenToExif: 0,
          creationTimesUpdated: 0,
          extractionMethodStats: extractionStats,
        );

        expect(result.extractionMethodStats, hasLength(5));
        expect(
          result.extractionMethodStats[DateTimeExtractionMethod.json],
          equals(50),
        );
        expect(
          result.extractionMethodStats[DateTimeExtractionMethod.none],
          equals(0),
        );

        final summary = result.summary;
        expect(summary, contains('json: 50 files'));
        expect(summary, contains('exif: 30 files'));
        expect(summary, contains('guess: 15 files'));
        expect(summary, contains('jsonTryHard: 5 files'));
        expect(summary, contains('none: 0 files'));
      });

      test('should handle empty extraction statistics', () {
        const result = ProcessingResult(
          totalProcessingTime: Duration(minutes: 1),
          stepTimings: {},
          mediaProcessed: 0,
          stepResults: [],
          duplicatesRemoved: 0,
          extrasSkipped: 0,
          extensionsFixed: 0,
          coordinatesWrittenToExif: 0,
          dateTimesWrittenToExif: 0,
          creationTimesUpdated: 0,
          extractionMethodStats: {},
        );

        final summary = result.summary;
        expect(summary, contains('json: 0 files'));
        expect(summary, contains('exif: 0 files'));
        expect(summary, contains('guess: 0 files'));
        expect(summary, contains('jsonTryHard: 0 files'));
        expect(summary, contains('folderYear: 0 files'));
        expect(summary, contains('none: 0 files'));
      });
    });

    group('Edge cases', () {
      test('should handle zero duration', () {
        const result = ProcessingResult(
          totalProcessingTime: Duration.zero,
          stepTimings: {},
          mediaProcessed: 0,
          duplicatesRemoved: 0,
          stepResults: [],
          extrasSkipped: 0,
          extensionsFixed: 0,
          coordinatesWrittenToExif: 0,
          dateTimesWrittenToExif: 0,
          creationTimesUpdated: 0,
          extractionMethodStats: {},
        );

        final summary = result.summary;
        expect(summary, contains('script took 0h 00m 00s to complete'));
      });

      test('should handle very large numbers', () {
        const result = ProcessingResult(
          totalProcessingTime: Duration(hours: 10),
          stepTimings: {},
          mediaProcessed: 999999,
          duplicatesRemoved: 100000,
          extrasSkipped: 50000,
          stepResults: [],
          extensionsFixed: 25000,
          coordinatesWrittenToExif: 800000,
          dateTimesWrittenToExif: 900000,
          creationTimesUpdated: 750000,
          extractionMethodStats: {DateTimeExtractionMethod.json: 999999},
        );

        final summary = result.summary;
        expect(summary, contains('999999 files'));
        expect(summary, contains('script took 10h 00m 00s to complete'));
      });

      test('should handle negative values gracefully', () {
        // This is more of a defensive programming test
        // In practice, negative values shouldn't occur
        const result = ProcessingResult(
          totalProcessingTime: Duration(minutes: 5),
          stepTimings: {},
          mediaProcessed: 100,
          stepResults: [],
          duplicatesRemoved: -1, // This shouldn't happen in practice
          extrasSkipped: 0,
          extensionsFixed: 0,
          coordinatesWrittenToExif: 0,
          dateTimesWrittenToExif: 0,
          creationTimesUpdated: 0,
          extractionMethodStats: {},
        );

        // Should still generate summary without crashing
        expect(() => result.summary, returnsNormally);
      });
    });
  });
}
