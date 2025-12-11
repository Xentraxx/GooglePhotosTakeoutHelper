import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

void main() {
  group('DateTimeExtractionMethod', () {
    test('should have all expected enum values', () {
      expect(DateTimeExtractionMethod.values, hasLength(6));
      expect(
        DateTimeExtractionMethod.values,
        contains(DateTimeExtractionMethod.json),
      );
      expect(
        DateTimeExtractionMethod.values,
        contains(DateTimeExtractionMethod.exif),
      );
      expect(
        DateTimeExtractionMethod.values,
        contains(DateTimeExtractionMethod.guess),
      );
      expect(
        DateTimeExtractionMethod.values,
        contains(DateTimeExtractionMethod.jsonTryHard),
      );
      expect(
        DateTimeExtractionMethod.values,
        contains(DateTimeExtractionMethod.folderYear),
      );
      expect(
        DateTimeExtractionMethod.values,
        contains(DateTimeExtractionMethod.none),
      );
    });

    group('Accuracy scoring', () {
      test('should have correct accuracy scores', () {
        expect(DateTimeExtractionMethod.json.accuracyScore, equals(1));
        expect(DateTimeExtractionMethod.exif.accuracyScore, equals(2));
        expect(DateTimeExtractionMethod.guess.accuracyScore, equals(3));
        expect(DateTimeExtractionMethod.jsonTryHard.accuracyScore, equals(4));
        expect(DateTimeExtractionMethod.folderYear.accuracyScore, equals(5));
        expect(DateTimeExtractionMethod.none.accuracyScore, equals(99));
      });

      test('should maintain accuracy order', () {
        final scores = DateTimeExtractionMethod.values
            .map((final method) => method.accuracyScore)
            .toList();

        // JSON should be most accurate (lowest score)
        expect(scores[0], equals(1)); // json
        expect(scores[1], equals(2)); // exif
        expect(scores[2], equals(3)); // guess
        expect(scores[3], equals(4)); // jsonTryHard
        expect(scores[4], equals(5)); // folderYear
        expect(scores[5], equals(99)); // none
      });

      test('should have unique accuracy scores except for edge cases', () {
        const methods = DateTimeExtractionMethod.values;
        final scores = methods.map((final m) => m.accuracyScore).toList();

        // All scores should be different
        expect(scores.toSet().length, equals(scores.length));
      });
    });

    group('Reliability check', () {
      test('should correctly identify reliable methods', () {
        expect(DateTimeExtractionMethod.json.isReliable, isTrue);
        expect(DateTimeExtractionMethod.exif.isReliable, isTrue);
        expect(DateTimeExtractionMethod.guess.isReliable, isTrue);
        expect(DateTimeExtractionMethod.folderYear.isReliable, isTrue);
        expect(DateTimeExtractionMethod.none.isReliable, isFalse);
      });

      test('should have only none as unreliable', () {
        final unreliableMethods = DateTimeExtractionMethod.values
            .where((final method) => !method.isReliable)
            .toList();

        expect(unreliableMethods, hasLength(1));
        expect(unreliableMethods.first, equals(DateTimeExtractionMethod.none));
      });
    });

    group('Descriptions', () {
      test('should have meaningful descriptions', () {
        expect(
          DateTimeExtractionMethod.json.description,
          equals('JSON metadata'),
        );
        expect(DateTimeExtractionMethod.exif.description, contains('EXIF'));
        expect(
          DateTimeExtractionMethod.guess.description,
          contains('filename'),
        );
        expect(
          DateTimeExtractionMethod.jsonTryHard.description,
          contains('JSON'),
        );
        expect(
          DateTimeExtractionMethod.folderYear.description,
          contains('folder'),
        );
        expect(
          DateTimeExtractionMethod.none.description,
          contains('extraction'),
        );
      });

      test('should have non-empty descriptions for all methods', () {
        for (final method in DateTimeExtractionMethod.values) {
          expect(method.description, isNotEmpty);
          expect(method.description.length, greaterThan(5));
        }
      });

      test('should have descriptive and unique descriptions', () {
        final descriptions = DateTimeExtractionMethod.values
            .map((final method) => method.description)
            .toList();

        // All descriptions should be unique
        expect(descriptions.toSet().length, equals(descriptions.length));

        // Each description should contain some key identifying words
        expect(descriptions[0], contains('JSON')); // json
        expect(descriptions[1], contains('EXIF')); // exif
        expect(descriptions[2], contains('filename')); // guess
        expect(descriptions[3], contains('JSON')); // jsonTryHard
        expect(descriptions[4], contains('folder')); // folderYear
        expect(descriptions[5], contains('No')); // none
      });
    });

    group('Enum ordering', () {
      test('should maintain preference order', () {
        // The enum order should reflect accuracy preference
        const methods = DateTimeExtractionMethod.values;

        expect(methods[0], equals(DateTimeExtractionMethod.json));
        expect(methods[1], equals(DateTimeExtractionMethod.exif));
        expect(methods[2], equals(DateTimeExtractionMethod.guess));
        expect(methods[3], equals(DateTimeExtractionMethod.jsonTryHard));
        expect(methods[4], equals(DateTimeExtractionMethod.folderYear));
        expect(methods[5], equals(DateTimeExtractionMethod.none));
      });

      test('should support comparison by accuracy', () {
        // More accurate methods should have lower scores
        expect(
          DateTimeExtractionMethod.json.accuracyScore,
          lessThan(DateTimeExtractionMethod.exif.accuracyScore),
        );
        expect(
          DateTimeExtractionMethod.exif.accuracyScore,
          lessThan(DateTimeExtractionMethod.guess.accuracyScore),
        );
        expect(
          DateTimeExtractionMethod.guess.accuracyScore,
          lessThan(DateTimeExtractionMethod.jsonTryHard.accuracyScore),
        );
        expect(
          DateTimeExtractionMethod.jsonTryHard.accuracyScore,
          lessThan(DateTimeExtractionMethod.folderYear.accuracyScore),
        );
        expect(
          DateTimeExtractionMethod.folderYear.accuracyScore,
          lessThan(DateTimeExtractionMethod.none.accuracyScore),
        );
      });
    });

    group('Edge cases', () {
      test('should handle toString properly', () {
        for (final method in DateTimeExtractionMethod.values) {
          final str = method.toString();
          expect(str, contains('DateTimeExtractionMethod.'));
          expect(str, contains(method.name));
        }
      });

      test('should support equality comparison', () {
        expect(
          DateTimeExtractionMethod.json,
          equals(DateTimeExtractionMethod.json),
        );
        expect(
          DateTimeExtractionMethod.json,
          isNot(equals(DateTimeExtractionMethod.exif)),
        );
      });

      test('should support hash codes', () {
        final hashCodes = DateTimeExtractionMethod.values
            .map((final method) => method.hashCode)
            .toSet();

        // All hash codes should be unique
        expect(
          hashCodes.length,
          equals(DateTimeExtractionMethod.values.length),
        );
      });
    });

    group('Business logic validation', () {
      test('should prioritize JSON over other methods', () {
        expect(DateTimeExtractionMethod.json.accuracyScore, equals(1));
        expect(DateTimeExtractionMethod.json.isReliable, isTrue);
      });

      test('should treat EXIF as second best option', () {
        expect(DateTimeExtractionMethod.exif.accuracyScore, equals(2));
        expect(DateTimeExtractionMethod.exif.isReliable, isTrue);
      });

      test('should treat filename guessing as fallback', () {
        expect(DateTimeExtractionMethod.guess.accuracyScore, equals(3));
        expect(DateTimeExtractionMethod.guess.isReliable, isTrue);
      });

      test('should treat tryhard JSON as last resort reliable method', () {
        expect(DateTimeExtractionMethod.jsonTryHard.accuracyScore, equals(4));
        expect(DateTimeExtractionMethod.jsonTryHard.isReliable, isTrue);
      });

      test('should treat folder year as fallback before none', () {
        expect(DateTimeExtractionMethod.folderYear.accuracyScore, equals(5));
        expect(DateTimeExtractionMethod.folderYear.isReliable, isTrue);
      });

      test('should treat none as unreliable', () {
        expect(DateTimeExtractionMethod.none.accuracyScore, equals(99));
        expect(DateTimeExtractionMethod.none.isReliable, isFalse);
      });
    });
  });
}
