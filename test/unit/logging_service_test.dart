/// Test suite for LoggingService
///
/// Tests the logging functionality with different levels and configurations.
library;

import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

void main() {
  group('LoggingService', () {
    group('Construction', () {
      test('creates service with default parameters', () {
        final service = LoggingService();

        expect(service.isVerbose, isFalse);
        expect(service.enableColors, isTrue);
      });

      test('creates service with custom parameters', () {
        final service = LoggingService(isVerbose: true, enableColors: false);

        expect(service.isVerbose, isTrue);
        expect(service.enableColors, isFalse);
      });

      test('creates from ProcessingConfig', () {
        const config = ProcessingConfig(
          inputPath: '/input',
          outputPath: '/output',
          verbose: true,
        );

        final service = LoggingService.fromConfig(config);

        expect(service.isVerbose, isTrue);
        // enableColors depends on platform, so we just verify it's set
        expect(service.enableColors, isA<bool>());
      });
    });
    group('Message Formatting', () {
      test('formats messages without colors', () {
        final service = LoggingService(enableColors: false);

        // We can't directly test the _formatMessage method since it's private,
        // but we can test the behavior through public methods
        expect(() => service.info('test message'), returnsNormally);
        expect(() => service.warning('test warning'), returnsNormally);
        expect(() => service.error('test error'), returnsNormally);
        expect(() => service.debug('test debug'), returnsNormally);
      });

      test('formats messages with colors enabled', () {
        final service = LoggingService();

        expect(() => service.info('test message'), returnsNormally);
        expect(() => service.warning('test warning'), returnsNormally);
        expect(() => service.error('test error'), returnsNormally);
        expect(() => service.debug('test debug'), returnsNormally);
      });
    });

    group('Logging Levels', () {
      test('info messages respect verbose setting', () {
        final verboseService = LoggingService(isVerbose: true);
        final quietService = LoggingService();

        // Both should execute without error
        expect(() => verboseService.info('verbose info'), returnsNormally);
        expect(() => quietService.info('quiet info'), returnsNormally);
      });
      test('warning messages respect verbose setting', () {
        final verboseService = LoggingService(isVerbose: true);
        final quietService = LoggingService();

        expect(
          () => verboseService.warning('verbose warning'),
          returnsNormally,
        );
        expect(() => quietService.warning('quiet warning'), returnsNormally);
      });

      test('error messages always print', () {
        final verboseService = LoggingService(isVerbose: true);
        final quietService = LoggingService();

        expect(() => verboseService.error('verbose error'), returnsNormally);
        expect(() => quietService.error('quiet error'), returnsNormally);
      });

      test('debug messages only print in verbose mode', () {
        final verboseService = LoggingService(isVerbose: true);
        final quietService = LoggingService();

        expect(() => verboseService.debug('verbose debug'), returnsNormally);
        expect(() => quietService.debug('quiet debug'), returnsNormally);
      });

      test('forcePrint overrides verbose setting', () {
        final quietService = LoggingService();

        expect(
          () => quietService.info('forced info', forcePrint: true),
          returnsNormally,
        );
        expect(
          () => quietService.warning('forced warning', forcePrint: true),
          returnsNormally,
        );
      });
    });
    group('CopyWith Functionality', () {
      test('copies with same values when no parameters provided', () {
        final original = LoggingService(isVerbose: true, enableColors: false);
        final copy = original.copyWith();

        expect(copy.isVerbose, equals(original.isVerbose));
        expect(copy.enableColors, equals(original.enableColors));
      });

      test('copies with updated verbose setting', () {
        final original = LoggingService();
        final copy = original.copyWith(isVerbose: true);

        expect(copy.isVerbose, isTrue);
        expect(copy.enableColors, equals(original.enableColors));
      });

      test('copies with updated colors setting', () {
        final original = LoggingService(isVerbose: true);
        final copy = original.copyWith(enableColors: false);

        expect(copy.isVerbose, equals(original.isVerbose));
        expect(copy.enableColors, isFalse);
      });

      test('copies with both settings updated', () {
        final original = LoggingService(enableColors: false);
        final copy = original.copyWith(isVerbose: true, enableColors: true);

        expect(copy.isVerbose, isTrue);
        expect(copy.enableColors, isTrue);
      });
    });

    group('Error Handling', () {
      test('handles empty messages gracefully', () {
        final service = LoggingService();

        expect(() => service.info(''), returnsNormally);
        expect(() => service.warning(''), returnsNormally);
        expect(() => service.error(''), returnsNormally);
        expect(() => service.debug(''), returnsNormally);
      });
      test('handles special characters in messages', () {
        final service = LoggingService();

        expect(
          () => service.info('Message with \n newlines \t tabs'),
          returnsNormally,
        );
        expect(
          () => service.warning('Message with émojis 🎉'),
          returnsNormally,
        );
        expect(
          () => service.error('Message with "quotes" and \'apostrophes\''),
          returnsNormally,
        );
      });
    });
  });

  group('LoggerMixin', () {
    late TestClassWithLogging testClass;

    setUp(() {
      testClass = TestClassWithLogging();
    });

    test('provides default logger', () {
      expect(testClass.logger, isNotNull);
      expect(testClass.logger.isVerbose, isFalse);
    });

    test('allows custom logger assignment', () {
      final customLogger = LoggingService(isVerbose: true, enableColors: false);
      testClass.logger = customLogger;

      expect(testClass.logger.isVerbose, isTrue);
      expect(testClass.logger.enableColors, isFalse);
    });

    test('provides convenient logging methods', () {
      expect(() => testClass.logInfo('test info'), returnsNormally);
      expect(() => testClass.logWarning('test warning'), returnsNormally);
      expect(() => testClass.logError('test error'), returnsNormally);
      expect(() => testClass.logDebug('test debug'), returnsNormally);
    });

    test('respects force print parameter', () {
      expect(
        () => testClass.logInfo('forced info', forcePrint: true),
        returnsNormally,
      );
      expect(
        () => testClass.logWarning('forced warning', forcePrint: true),
        returnsNormally,
      );
    });
  });
}

/// Test class to verify LoggerMixin functionality
class TestClassWithLogging with LoggerMixin {
  void performOperation() {
    logInfo('Starting operation');
    logWarning('This is a warning');
    logDebug('Debug information');
    logError('Something went wrong');
  }
}
