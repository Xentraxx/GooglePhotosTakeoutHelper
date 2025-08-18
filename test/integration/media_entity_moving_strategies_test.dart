/// Test suite for MediaEntity moving strategies
///
/// Tests the complete implementation of all album behavior strategies including
/// shortcut, duplicate-copy, reverse-shortcut, json, and nothing modes.
// ignore_for_file: prefer_foreach

library;

import 'dart:convert';
import 'dart:io';

import 'package:gpth/domain/entities/media_entity.dart';
import 'package:gpth/domain/models/processing_config_model.dart';
import 'package:gpth/domain/services/core/service_container.dart';
import 'package:gpth/domain/services/file_operations/moving/file_operation_service.dart';
import 'package:gpth/domain/services/file_operations/moving/moving_context_model.dart';
import 'package:gpth/domain/services/file_operations/moving/path_generator_service.dart';
import 'package:gpth/domain/services/file_operations/moving/strategies/duplicate_copy_moving_strategy.dart';
import 'package:gpth/domain/services/file_operations/moving/strategies/json_moving_strategy.dart';
import 'package:gpth/domain/services/file_operations/moving/strategies/media_entity_moving_strategy.dart';
import 'package:gpth/domain/services/file_operations/moving/strategies/media_entity_moving_strategy_factory.dart';
import 'package:gpth/domain/services/file_operations/moving/strategies/nothing_moving_strategy.dart';
import 'package:gpth/domain/services/file_operations/moving/strategies/reverse_shortcut_moving_strategy.dart';
import 'package:gpth/domain/services/file_operations/moving/strategies/shortcut_moving_strategy.dart';
import 'package:gpth/domain/services/file_operations/moving/symlink_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('MediaEntity Moving Strategies', () {
    late TestFixture fixture;
    late FileOperationService fileService;
    late PathGeneratorService pathService;
    late SymlinkService symlinkService;
    late Directory outputDir;
    late MovingContext context;
    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();

      // Initialize ServiceContainer
      await ServiceContainer.instance.initialize();

      fileService = FileOperationService();
      pathService = PathGeneratorService();
      symlinkService = SymlinkService();

      outputDir = fixture.createDirectory('output');
      context = MovingContext(
        outputDirectory: outputDir,
        dateDivision: DateDivisionLevel.year,
        albumBehavior: AlbumBehavior.shortcut,
      );
    });

    tearDown(() async {
      await fixture.tearDown();
      await ServiceContainer.reset();
    });

    group('MediaEntityMovingStrategyFactory', () {
      late MediaEntityMovingStrategyFactory factory;

      setUp(() {
        factory = MediaEntityMovingStrategyFactory(
          fileService,
          pathService,
          symlinkService,
        );
      });

      test('creates shortcut strategy', () {
        final strategy = factory.createStrategy(AlbumBehavior.shortcut);
        expect(strategy, isA<ShortcutMovingStrategy>());
        expect(strategy.name, equals('Shortcut'));
        expect(strategy.createsShortcuts, isTrue);
        expect(strategy.createsDuplicates, isFalse);
      });

      test('creates duplicate-copy strategy', () {
        final strategy = factory.createStrategy(AlbumBehavior.duplicateCopy);
        expect(strategy, isA<DuplicateCopyMovingStrategy>());
        expect(strategy.name, equals('Duplicate Copy'));
        expect(strategy.createsShortcuts, isFalse);
        expect(strategy.createsDuplicates, isTrue);
      });

      test('creates reverse-shortcut strategy', () {
        final strategy = factory.createStrategy(AlbumBehavior.reverseShortcut);
        expect(strategy, isA<ReverseShortcutMovingStrategy>());
        expect(strategy.name, equals('Reverse Shortcut'));
        expect(strategy.createsShortcuts, isTrue);
        expect(strategy.createsDuplicates, isFalse);
      });

      test('creates json strategy', () {
        final strategy = factory.createStrategy(AlbumBehavior.json);
        expect(strategy, isA<JsonMovingStrategy>());
        expect(strategy.name, equals('JSON'));
        expect(strategy.createsShortcuts, isFalse);
        expect(strategy.createsDuplicates, isFalse);
      });

      test('creates nothing strategy', () {
        final strategy = factory.createStrategy(AlbumBehavior.nothing);
        expect(strategy, isA<NothingMovingStrategy>());
        expect(strategy.name, equals('Nothing'));
        expect(strategy.createsShortcuts, isFalse);
        expect(strategy.createsDuplicates, isFalse);
      });
    });

    group('ShortcutMovingStrategy', () {
      late ShortcutMovingStrategy strategy;

      setUp(() {
        strategy = ShortcutMovingStrategy(
          fileService,
          pathService,
          symlinkService,
        );
      });

      test('moves file to ALL_PHOTOS and creates album shortcuts', () async {
        final sourceFile = fixture.createFile('test.jpg', [1, 2, 3]);
        final entity = MediaEntity.fromMap(
          files: {null: sourceFile, 'Vacation': sourceFile},
          dateTaken: DateTime(2023, 6, 15),
        );

        final results = <MediaEntityMovingResult>[];
        await for (final result in strategy.processMediaEntity(
          entity,
          context,
        )) {
          results.add(result);
        }

        expect(results.length, equals(2)); // Move + shortcut
        expect(results[0].success, isTrue);
        expect(
          results[0].operation.operationType,
          equals(MediaEntityOperationType.move),
        );
        expect(results[1].success, isTrue);
        expect(
          results[1].operation.operationType,
          equals(MediaEntityOperationType.createSymlink),
        );

        // Verify file was moved to ALL_PHOTOS
        final allPhotosPath = p.join(outputDir.path, 'ALL_PHOTOS', '2023');
        expect(Directory(allPhotosPath).existsSync(), isTrue);
      });

      test('handles entity without album associations', () async {
        final sourceFile = fixture.createFile('test.jpg', [1, 2, 3]);
        final entity = MediaEntity.single(
          file: sourceFile,
          dateTaken: DateTime(2023, 6, 15),
        );

        final results = <MediaEntityMovingResult>[];
        await for (final result in strategy.processMediaEntity(
          entity,
          context,
        )) {
          results.add(result);
        }

        expect(results.length, equals(1)); // Only move operation
        expect(results[0].success, isTrue);
        expect(
          results[0].operation.operationType,
          equals(MediaEntityOperationType.move),
        );
      });
    });

    group('DuplicateCopyMovingStrategy', () {
      late DuplicateCopyMovingStrategy strategy;

      setUp(() {
        strategy = DuplicateCopyMovingStrategy(fileService, pathService);
      });

      test('moves file to ALL_PHOTOS and copies to album folders', () async {
        final sourceFile = fixture.createFile('test.jpg', [1, 2, 3]);
        final entity = MediaEntity.fromMap(
          files: {null: sourceFile, 'Vacation': sourceFile},
          dateTaken: DateTime(2023, 6, 15),
        );

        final results = <MediaEntityMovingResult>[];
        await for (final result in strategy.processMediaEntity(
          entity,
          context,
        )) {
          results.add(result);
        }

        expect(results.length, equals(2)); // Move + copy
        expect(results[0].success, isTrue);
        expect(
          results[0].operation.operationType,
          equals(MediaEntityOperationType.move),
        );
        expect(results[1].success, isTrue);
        expect(
          results[1].operation.operationType,
          equals(MediaEntityOperationType.copy),
        );

        // Verify files exist in both locations
        final allPhotosPath = p.join(outputDir.path, 'ALL_PHOTOS', '2023');
        final albumPath = p.join(outputDir.path, 'Vacation');
        expect(Directory(allPhotosPath).existsSync(), isTrue);
        expect(Directory(albumPath).existsSync(), isTrue);
      });
    });

    group('JsonMovingStrategy', () {
      late JsonMovingStrategy strategy;

      setUp(() {
        strategy = JsonMovingStrategy(fileService, pathService);
      });

      test('moves files to ALL_PHOTOS and creates albums-info.json', () async {
        final sourceFile1 = fixture.createFile('test1.jpg', [1, 2, 3]);
        final sourceFile2 = fixture.createFile('test2.jpg', [4, 5, 6]);

        final entity1 = MediaEntity.fromMap(
          files: {null: sourceFile1, 'Vacation': sourceFile1},
          dateTaken: DateTime(2023, 6, 15),
        );
        final entity2 = MediaEntity.fromMap(
          files: {null: sourceFile2, 'Family': sourceFile2},
          dateTaken: DateTime(2023, 7, 20),
        );

        final results1 = <MediaEntityMovingResult>[];
        await for (final result in strategy.processMediaEntity(
          entity1,
          context,
        )) {
          results1.add(result);
        }

        final results2 = <MediaEntityMovingResult>[];
        await for (final result in strategy.processMediaEntity(
          entity2,
          context,
        )) {
          results2.add(result);
        }

        expect(results1.length, equals(1));
        expect(results2.length, equals(1));
        expect(results1[0].success, isTrue);
        expect(results2[0].success, isTrue);

        // Finalize to create JSON
        final finalizationResults = await strategy.finalize(context, [
          entity1,
          entity2,
        ]);

        expect(finalizationResults.length, equals(1));
        expect(finalizationResults[0].success, isTrue);

        // Verify albums-info.json was created
        final jsonFile = File(p.join(outputDir.path, 'albums-info.json'));
        expect(jsonFile.existsSync(), isTrue);

        // Verify JSON content
        final jsonContent = await jsonFile.readAsString();
        final albumData = jsonDecode(jsonContent) as Map<String, dynamic>;
        expect(albumData['albums'], isA<Map<String, dynamic>>());
        expect(albumData['metadata']['total_albums'], equals(2));
      });
    });

    group('NothingMovingStrategy', () {
      late NothingMovingStrategy strategy;

      setUp(() {
        strategy = NothingMovingStrategy(fileService, pathService);
      });

      test('moves only year-based files to ALL_PHOTOS', () async {
        final sourceFile = fixture.createFile('test.jpg', [1, 2, 3]);
        final entity = MediaEntity.single(
          file: sourceFile,
          dateTaken: DateTime(2023, 6, 15),
        );

        final results = <MediaEntityMovingResult>[];
        await for (final result in strategy.processMediaEntity(
          entity,
          context,
        )) {
          results.add(result);
        }

        expect(results.length, equals(1));
        expect(results[0].success, isTrue);
        expect(
          results[0].operation.operationType,
          equals(MediaEntityOperationType.move),
        );
      });
      test('processes album-only files (fixed behavior)', () async {
        final sourceFile = fixture.createFile('test.jpg', [1, 2, 3]);
        final entity = MediaEntity.fromMap(
          files: {'Vacation': sourceFile}, // No null key = album-only
          dateTaken: DateTime(2023, 6, 15),
        );

        final results = <MediaEntityMovingResult>[];
        await for (final result in strategy.processMediaEntity(
          entity,
          context,
        )) {
          results.add(result);
        }

        expect(
          results.length,
          equals(1),
        ); // Should now process album-only files
        expect(results[0].success, isTrue);
        expect(
          results[0].operation.operationType,
          equals(MediaEntityOperationType.move),
        );
      });
    });

    group('Integration Tests', () {
      test('all strategies can be created and validate context', () {
        final factory = MediaEntityMovingStrategyFactory(
          fileService,
          pathService,
          symlinkService,
        );

        for (final behavior in AlbumBehavior.values) {
          final strategy = factory.createStrategy(behavior);
          expect(strategy, isA<MediaEntityMovingStrategy>());

          // Should not throw
          expect(() => strategy.validateContext(context), returnsNormally);
        }
      });

      test('strategies handle file operation errors gracefully', () async {
        // Create a strategy with a non-existent source file
        final strategy = ShortcutMovingStrategy(
          fileService,
          pathService,
          symlinkService,
        );

        final nonExistentFile = File('${fixture.basePath}/nonexistent.jpg');
        final entity = MediaEntity.single(
          file: nonExistentFile,
          dateTaken: DateTime(2023, 6, 15),
        );

        final results = <MediaEntityMovingResult>[];
        await for (final result in strategy.processMediaEntity(
          entity,
          context,
        )) {
          results.add(result);
        }

        expect(results.length, equals(1));
        expect(results[0].success, isFalse);
        expect(
          results[0].errorMessage,
          contains('Failed to move primary file'),
        );
      });
    });
  });
}
