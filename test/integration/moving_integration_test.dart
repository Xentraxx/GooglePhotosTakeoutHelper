/// Test to verify that MediaEntity moving strategies work end-to-end
library;

import 'dart:io';

import 'package:gpth/domain/entities/media_entity.dart';
import 'package:gpth/domain/models/media_entity_collection.dart';
import 'package:gpth/domain/models/processing_config_model.dart';
import 'package:gpth/domain/services/core/service_container.dart';
import 'package:gpth/domain/services/file_operations/moving/media_entity_moving_service.dart';
import 'package:gpth/domain/services/file_operations/moving/moving_context_model.dart';
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('MediaEntity Moving Integration Tests', () {
    late TestFixture fixture;
    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();

      // Initialize ServiceContainer
      await ServiceContainer.instance.initialize();
    });

    tearDown(() async {
      await fixture.tearDown();
      await ServiceContainer.reset();
    });

    test(
      'moving service processes media entities without UnimplementedError',
      () async {
        // Create test media files
        final file1 = fixture.createFile('test1.jpg', [1, 2, 3]);
        final file2 = fixture.createFile('test2.jpg', [4, 5, 6]);

        final entity1 = MediaEntity.single(
          file: file1,
          dateTaken: DateTime(2023, 6, 15),
        );
        final entity2 = MediaEntity.fromMap(
          files: {null: file2, 'Vacation': file2},
          dateTaken: DateTime(2023, 7, 20),
        );

        final collection = MediaEntityCollection([entity1, entity2]);
        final outputDir = fixture.createDirectory('output');

        final context = MovingContext(
          outputDirectory: outputDir,
          dateDivision: DateDivisionLevel.year,
          albumBehavior: AlbumBehavior.shortcut,
        );

        final movingService = MediaEntityMovingService();

        // This should not throw UnimplementedError anymore
        expect(() async {
          await for (final _ in movingService.moveMediaEntities(
            collection,
            context,
          )) {
            // Progress updates
          }
        }, returnsNormally);
      },
    );

    test('shortcut strategy creates expected directory structure', () async {
      final file = fixture.createFile('vacation_photo.jpg', [1, 2, 3]);
      final entity = MediaEntity.fromMap(
        files: {null: file, 'Summer Vacation': file},
        dateTaken: DateTime(2023, 8, 15),
      );

      final collection = MediaEntityCollection([entity]);
      final outputDir = fixture.createDirectory('output');

      final context = MovingContext(
        outputDirectory: outputDir,
        dateDivision: DateDivisionLevel.year,
        albumBehavior: AlbumBehavior.shortcut,
      );

      final movingService = MediaEntityMovingService();

      var processedCount = 0;
      await for (final progress in movingService.moveMediaEntities(
        collection,
        context,
      )) {
        processedCount = progress;
      }

      expect(processedCount, equals(1));

      // Verify ALL_PHOTOS directory exists
      final allPhotosDir = Directory('${outputDir.path}/ALL_PHOTOS/2023');
      expect(allPhotosDir.existsSync(), isTrue);

      // Verify album directory exists
      final albumDir = Directory('${outputDir.path}/Summer Vacation');
      expect(albumDir.existsSync(), isTrue);
    });

    test('json strategy creates albums-info.json', () async {
      final file = fixture.createFile('family_photo.jpg', [1, 2, 3]);
      final entity = MediaEntity.fromMap(
        files: {null: file, 'Family': file},
        dateTaken: DateTime(2023, 9, 10),
      );

      final collection = MediaEntityCollection([entity]);
      final outputDir = fixture.createDirectory('output');

      final context = MovingContext(
        outputDirectory: outputDir,
        dateDivision: DateDivisionLevel.year,
        albumBehavior: AlbumBehavior.json,
      );
      final movingService = MediaEntityMovingService();

      await for (final _ in movingService.moveMediaEntities(
        collection,
        context,
      )) {
        // Process
      }

      // Verify albums-info.json was created
      final jsonFile = File('${outputDir.path}/albums-info.json');
      expect(jsonFile.existsSync(), isTrue);
    });

    test('all album behaviors work without errors', () async {
      for (final behavior in AlbumBehavior.values) {
        final file = fixture.createFile('test_${behavior.value}.jpg', [
          1,
          2,
          3,
        ]);
        final entity = MediaEntity.single(
          file: file,
          dateTaken: DateTime(2023, 6, 15),
        );

        final collection = MediaEntityCollection([entity]);
        final outputDir = fixture.createDirectory('output_${behavior.value}');

        final context = MovingContext(
          outputDirectory: outputDir,
          dateDivision: DateDivisionLevel.year,
          albumBehavior: behavior,
        );
        final movingService = MediaEntityMovingService();

        // Should not throw for any strategy
        expect(
          () async {
            await for (final _ in movingService.moveMediaEntities(
              collection,
              context,
            )) {
              // Process
            }
          },
          returnsNormally,
          reason: 'Strategy ${behavior.value} should work without errors',
        );
      }
    });
  });
}
