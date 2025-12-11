/// Test suite for GlobalConfigService
///
/// Tests the global configuration management functionality.
library;

import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

void main() {
  group('GlobalConfigService', () {
    late GlobalConfigService service;

    setUp(() {
      service = GlobalConfigService();
    });

    group('Initialization', () {
      test('starts with default values', () {
        expect(service.isVerbose, isFalse);
        expect(service.enforceMaxFileSize, isFalse);
        expect(service.exifToolInstalled, isFalse);
      });

      test('initializes from ProcessingConfig correctly', () {
        const config = ProcessingConfig(
          inputPath: '/input',
          outputPath: '/output',
          verbose: true,
          limitFileSize: true,
        );

        service.initializeFrom(config);

        expect(service.isVerbose, isTrue);
        expect(service.enforceMaxFileSize, isTrue);
        // exifToolInstalled is not set by config, remains false
        expect(service.exifToolInstalled, isFalse);
      });

      test('handles config with false values', () {
        const config = ProcessingConfig(
          inputPath: '/input',
          outputPath: '/output',
        );

        service.initializeFrom(config);

        expect(service.isVerbose, isFalse);
        expect(service.enforceMaxFileSize, isFalse);
      });
    });

    group('Reset Functionality', () {
      test('resets all values to defaults', () {
        // Set non-default values
        service.isVerbose = true;
        service.enforceMaxFileSize = true;
        service.exifToolInstalled = true;

        service.reset();

        expect(service.isVerbose, isFalse);
        expect(service.enforceMaxFileSize, isFalse);
        expect(service.exifToolInstalled, isFalse);
      });

      test('can be called multiple times safely', () {
        service.reset();
        service.reset();

        expect(service.isVerbose, isFalse);
        expect(service.enforceMaxFileSize, isFalse);
        expect(service.exifToolInstalled, isFalse);
      });
    });

    group('ExifTool Installation Status', () {
      test('can be set independently of config', () {
        const config = ProcessingConfig(
          inputPath: '/input',
          outputPath: '/output',
          verbose: true,
        );

        service.initializeFrom(config);
        service.exifToolInstalled = true;

        expect(service.isVerbose, isTrue);
        expect(service.exifToolInstalled, isTrue);
      });

      test('persists through config initialization', () {
        service.exifToolInstalled = true;

        const config = ProcessingConfig(
          inputPath: '/input',
          outputPath: '/output',
        );

        service.initializeFrom(config);

        // Should preserve exifToolInstalled value
        expect(service.exifToolInstalled, isTrue);
        expect(service.isVerbose, isFalse);
      });
    });

    group('Configuration Updates', () {
      test('allows individual property updates', () {
        expect(service.isVerbose, isFalse);

        service.isVerbose = true;
        expect(service.isVerbose, isTrue);

        service.enforceMaxFileSize = true;
        expect(service.enforceMaxFileSize, isTrue);
      });

      test('handles multiple config initializations', () {
        const config1 = ProcessingConfig(
          inputPath: '/input1',
          outputPath: '/output1',
          verbose: true,
        );

        service.initializeFrom(config1);
        expect(service.isVerbose, isTrue);
        expect(service.enforceMaxFileSize, isFalse);

        const config2 = ProcessingConfig(
          inputPath: '/input2',
          outputPath: '/output2',
          limitFileSize: true,
        );

        service.initializeFrom(config2);
        expect(service.isVerbose, isFalse);
        expect(service.enforceMaxFileSize, isTrue);
      });
    });

    group('Thread Safety and State Management', () {
      test('maintains state correctly across operations', () {
        // Simulate a typical usage pattern
        service.reset();

        const config = ProcessingConfig(
          inputPath: '/input',
          outputPath: '/output',
          verbose: true,
          limitFileSize: true,
        );

        service.initializeFrom(config);
        service.exifToolInstalled = true;

        // Verify all values are as expected
        expect(service.isVerbose, isTrue);
        expect(service.enforceMaxFileSize, isTrue);
        expect(service.exifToolInstalled, isTrue);

        // Reset and verify cleanup
        service.reset();
        expect(service.isVerbose, isFalse);
        expect(service.enforceMaxFileSize, isFalse);
        expect(service.exifToolInstalled, isFalse);
      });
    });
  });
}
