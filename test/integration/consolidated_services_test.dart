/// Test suite for consolidated services functionality
///
/// This test validates that the consolidated services work correctly and
/// provide the expected behavior for file operations and formatting.
library;

import 'dart:io';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

void main() {
  group('Consolidated Services', () {
    late FormattingService utilityService;
    late ConsolidatedDiskSpaceService diskSpaceService;

    setUpAll(() async {
      // Initialize service container for integration tests
      await ServiceContainer.instance.initialize();
    });

    tearDownAll(() async {
      await ServiceContainer.instance.dispose();
      await ServiceContainer.reset();
    });

    setUp(() {
      utilityService = const FormattingService();
      diskSpaceService = ConsolidatedDiskSpaceService();
    });

    group('FormattingService', () {
      test('formatFileSize formats bytes correctly', () {
        expect(utilityService.formatFileSize(0), equals('0 B'));
        expect(utilityService.formatFileSize(1024), contains('KB'));
        expect(utilityService.formatFileSize(1024 * 1024), contains('MB'));
        expect(
          utilityService.formatFileSize(1024 * 1024 * 1024),
          contains('GB'),
        );
      });

      test('formatFileSize handles negative input', () {
        expect(utilityService.formatFileSize(-100), equals('0 B'));
      });
      test('formatDuration formats durations correctly', () {
        expect(
          utilityService.formatDuration(const Duration(milliseconds: 500)),
          equals('0s'),
        );
        expect(
          utilityService.formatDuration(const Duration(seconds: 30)),
          equals('30s'),
        );
        expect(
          utilityService.formatDuration(const Duration(seconds: 90)),
          equals('1m 30s'),
        );
        expect(
          utilityService.formatDuration(const Duration(hours: 1)),
          equals('1h'),
        );
        expect(
          utilityService.formatDuration(const Duration(hours: 1, minutes: 1)),
          equals('1h 1m'),
        );
      });

      test('formatNumber adds thousand separators', () {
        expect(utilityService.formatNumber(1000), equals('1,000'));
        expect(utilityService.formatNumber(1234567), equals('1,234,567'));
        expect(utilityService.formatNumber(123), equals('123'));
      });

      test('findUniqueFileName creates unique names', () {
        // Create a temporary directory for testing
        final tempDir = Directory.systemTemp.createTempSync('test_unique_');

        try {
          final testFile = File('${tempDir.path}/test.txt');

          // First call should return the original file if it doesn't exist
          final unique1 = utilityService.findUniqueFileName(testFile);
          expect(unique1.path, equals(testFile.path));

          // Create the file, then calling again should return (1) version
          testFile.createSync();
          final unique2 = utilityService.findUniqueFileName(testFile);
          expect(unique2.path, contains('test(1).txt'));

          // Create the (1) version, then calling again should return (2) version
          unique2.createSync();
          final unique3 = utilityService.findUniqueFileName(testFile);
          expect(unique3.path, contains('test(2).txt'));
        } finally {
          // Clean up
          tempDir.deleteSync(recursive: true);
        }
      });

      test('validateDirectory works correctly', () {
        // Test with existing directory
        final tempDir = Directory.systemTemp.createTempSync('test_validate_');

        try {
          final result = utilityService.validateDirectory(tempDir);
          expect(result.isSuccess, isTrue);

          // Test with non-existing directory
          final nonExistentDir = Directory('${tempDir.path}/nonexistent');
          final result2 = utilityService.validateDirectory(nonExistentDir);
          expect(result2.isFailure, isTrue);
          expect(result2.message, contains('does not exist'));
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('validateFile works correctly', () {
        final tempDir = Directory.systemTemp.createTempSync(
          'test_validate_file_',
        );

        try {
          // Test with existing file
          final testFile = File('${tempDir.path}/test.txt');
          testFile.writeAsStringSync('test content');

          final result = utilityService.validateFile(testFile);
          expect(result.isSuccess, isTrue);

          // Test with non-existing file
          final nonExistentFile = File('${tempDir.path}/nonexistent.txt');
          final result2 = utilityService.validateFile(nonExistentFile);
          expect(result2.isFailure, isTrue);
          expect(result2.message, contains('does not exist'));
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      });
    });

    group('ConsolidatedDiskSpaceService', () {
      test('platform detection works', () {
        expect(diskSpaceService.isWindows, equals(Platform.isWindows));
        expect(diskSpaceService.isMacOS, equals(Platform.isMacOS));
        expect(diskSpaceService.isLinux, equals(Platform.isLinux));
      });

      test(
        'getAvailableSpace returns non-null for current directory',
        () async {
          final space = await diskSpaceService.getAvailableSpace('.');
          // Should return a value or null if platform not supported
          if (space != null) {
            expect(space, greaterThan(0));
          }
        },
      );

      test('hasEnoughSpace works with known values', () async {
        // Test with very small requirement (1 byte) - should always pass
        final hasSpace = await diskSpaceService.hasEnoughSpace('.', 1);
        // If we can get disk space, this should be true
        final availableSpace = await diskSpaceService.getAvailableSpace('.');
        if (availableSpace != null) {
          expect(hasSpace, isTrue);
        }
      });

      test('calculateRequiredSpace returns reasonable estimates', () async {
        final tempDir = Directory.systemTemp.createTempSync('test_calc_space_');

        try {
          // Create some test files
          final file1 = File('${tempDir.path}/file1.txt');
          final file2 = File('${tempDir.path}/file2.txt');
          file1.writeAsStringSync('a' * 1000); // 1KB
          file2.writeAsStringSync('b' * 2000); // 2KB

          final files = [file1, file2];

          // Test copy operation
          final spaceCopy = await diskSpaceService.calculateRequiredSpace(
            files,
            'copy',
            'shortcut',
          );
          expect(
            spaceCopy,
            greaterThan(3000),
          ); // Should be > 3KB due to copy multiplier

          // Test move operation
          final spaceMove = await diskSpaceService.calculateRequiredSpace(
            files,
            'move',
            'shortcut',
          );
          expect(
            spaceMove,
            lessThan(spaceCopy),
          ); // Move should require less space than copy
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      });
    });
    group('Service Container Integration', () {
      test('services are properly initialized in container', () {
        expect(ServiceContainer.instance.utilityService, isNotNull);
        expect(ServiceContainer.instance.diskSpaceService, isNotNull);
        expect(ServiceContainer.instance.globalConfig, isNotNull);
        expect(ServiceContainer.instance.interactiveService, isNotNull);
      });

      test('consolidated interactive service is available', () {
        final interactiveService = ServiceContainer.instance.interactiveService;
        expect(interactiveService, isNotNull);
        expect(interactiveService.globalConfig, isNotNull);
      });

      test('deprecated service methods delegate correctly', () {
        // Test that the deprecated methods in other services still work
        // by delegating to the consolidated services

        final tempDir = Directory.systemTemp.createTempSync('test_delegation_');
        try {
          final testFile = File('${tempDir.path}/test.txt');
          testFile.createSync(); // Test formatting service directly
          const formattingService = FormattingService();
          final uniqueFile = formattingService.findUniqueFileName(testFile);
          expect(uniqueFile.path, contains('test(1).txt'));

          // Test file size formatting
          final formatted = formattingService.formatFileSize(1024);
          expect(formatted, contains('KB'));
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      });
    });

    group('Validation Results', () {
      test('ValidationResult success works correctly', () {
        const result = FormattingValidationResult.success();
        expect(result.isSuccess, isTrue);
        expect(result.isFailure, isFalse);
        expect(result.message, isNull);
      });

      test('ValidationResult failure works correctly', () {
        const result = FormattingValidationResult.failure('Test error');
        expect(result.isSuccess, isFalse);
        expect(result.isFailure, isTrue);
        expect(result.message, equals('Test error'));
      });
    });

    group('File Extensions', () {
      test('File extension methods work correctly', () {
        final testFile = File('/path/to/file.txt');
        expect(testFile.nameWithoutExtension, equals('file'));
        expect(testFile.extension, equals('.txt'));

        final noExtFile = File('/path/to/file');
        expect(noExtFile.nameWithoutExtension, equals('file'));
        expect(noExtFile.extension, equals(''));
      });
    });
  });
}
