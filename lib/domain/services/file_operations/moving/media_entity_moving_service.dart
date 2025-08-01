import 'dart:async';
import 'dart:collection';

import '../../../models/media_entity_collection.dart';
import 'file_operation_service.dart';
import 'moving_context_model.dart';
import 'path_generator_service.dart';
import 'strategies/media_entity_moving_strategy.dart';
import 'strategies/media_entity_moving_strategy_factory.dart';
import 'symlink_service.dart';

/// Modern media moving service using immutable MediaEntity
///
/// This service coordinates all the moving logic components and provides
/// a clean interface for moving media files according to configuration.
/// Uses MediaEntity exclusively for better performance and immutability.
class MediaEntityMovingService {
  MediaEntityMovingService()
    : _strategyFactory = MediaEntityMovingStrategyFactory(
        FileOperationService(),
        PathGeneratorService(),
        SymlinkService(),
      );

  /// Custom constructor for dependency injection (useful for testing)
  MediaEntityMovingService.withDependencies({
    required final FileOperationService fileService,
    required final PathGeneratorService pathService,
    required final SymlinkService symlinkService,
  }) : _strategyFactory = MediaEntityMovingStrategyFactory(
         fileService,
         pathService,
         symlinkService,
       );

  final MediaEntityMovingStrategyFactory _strategyFactory;

  /// Moves media entities according to the provided context
  ///
  /// [entityCollection] Collection of media entities to process
  /// [context] Configuration and context for the moving operations
  /// Returns a stream of progress updates (number of files processed)
  Stream<int> moveMediaEntities(
    final MediaEntityCollection entityCollection,
    final MovingContext context,
  ) async* {
    // Create the appropriate strategy for the album behavior
    final strategy = _strategyFactory.createStrategy(context.albumBehavior);

    // Validate the context for this strategy
    strategy.validateContext(context);

    int processedCount = 0;
    final List<MediaEntityMovingResult> allResults = [];

    // Process each media entity
    for (final entity in entityCollection.entities) {
      await for (final result in strategy.processMediaEntity(entity, context)) {
        allResults.add(result);

        if (!result.success && context.verbose) {
          _logError(result);
        } else if (context.verbose) {
          _logResult(result);
        }
      }

      processedCount++;
      yield processedCount;
    }

    // Perform any finalization steps
    try {
      final finalizationResults = await strategy.finalize(
        context,
        entityCollection.entities.toList(),
      );
      allResults.addAll(finalizationResults);

      for (final result in finalizationResults) {
        if (!result.success && context.verbose) {
          _logError(result);
        } else if (context.verbose) {
          _logResult(result);
        }
      }
    } catch (e) {
      if (context.verbose) {
        print('[Error] Strategy finalization failed: $e');
      }
    }

    // Print summary if verbose
    if (context.verbose) {
      _printSummary(allResults, strategy);
    }
  }

  /// High-performance parallel media moving with batched operations
  ///
  /// Processes multiple media entities concurrently to dramatically improve
  /// throughput for large collections while preventing system overload
  Stream<int> moveMediaEntitiesParallel(
    final MediaEntityCollection entityCollection,
    final MovingContext context, {
    final int maxConcurrent = 10,
    final int batchSize = 100,
  }) async* {
    final strategy = _strategyFactory.createStrategy(context.albumBehavior);
    strategy.validateContext(context);

    final entities = entityCollection.entities.toList();
    int processedCount = 0;
    final allResults = <MediaEntityMovingResult>[];

    // Process entities in batches to avoid overwhelming the system
    for (int i = 0; i < entities.length; i += batchSize) {
      final batchEnd = (i + batchSize).clamp(0, entities.length);
      final batch = entities.sublist(i, batchEnd);

      // Process batch with controlled concurrency
      final futures = <Future<List<MediaEntityMovingResult>>>[];
      final semaphore = _Semaphore(maxConcurrent);
      for (final entity in batch) {
        futures.add(
          semaphore.acquire().then((_) async {
            try {
              final results = <MediaEntityMovingResult>[];
              // ignore: prefer_foreach
              await for (final result in strategy.processMediaEntity(
                entity,
                context,
              )) {
                results.add(result);
              }
              return results;
            } finally {
              semaphore.release();
            }
          }),
        );
      }

      // Wait for batch completion
      final batchResults = await Future.wait(futures);
      for (final results in batchResults) {
        allResults.addAll(results);
        processedCount += results.length;
      }

      yield processedCount;
    }

    // Finalize
    final finalizationResults = await strategy.finalize(context, entities);
    allResults.addAll(finalizationResults);

    if (context.verbose) {
      _printSummary(allResults, strategy);
    }
  }

  void _logResult(final MediaEntityMovingResult result) {
    final operation = result.operation;
    final status = result.success ? 'SUCCESS' : 'FAILED';
    print(
      '[${operation.operationType.name.toUpperCase()}] $status: ${operation.sourceFile.path}',
    );

    if (result.resultFile != null) {
      print('  → ${result.resultFile!.path}');
    }
  }

  void _logError(final MediaEntityMovingResult result) {
    print(
      '[Error] Failed to process ${result.operation.sourceFile.path}: '
      '${result.errorMessage}',
    );
  }

  void _printSummary(
    final List<MediaEntityMovingResult> results,
    final MediaEntityMovingStrategy strategy,
  ) {
    final successful = results.where((final r) => r.success).length;
    final failed = results.where((final r) => !r.success).length;

    print('\n=== Moving Summary (${strategy.name}) ===');
    print('Successful operations: $successful');
    print('Failed operations: $failed');
    print('Total operations: ${results.length}');

    if (failed > 0) {
      print('\nErrors encountered:');
      results.where((final r) => !r.success).take(5).forEach((final result) {
        print(
          '  • ${result.operation.sourceFile.path}: ${result.errorMessage}',
        );
      });
      if (failed > 5) {
        print('  ... and ${failed - 5} more errors');
      }
    }
  }
}

/// Simple semaphore implementation for controlling concurrency
class _Semaphore {
  _Semaphore(this.maxCount) : _currentCount = maxCount;

  final int maxCount;
  int _currentCount;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _currentCount++;
    }
  }
}
