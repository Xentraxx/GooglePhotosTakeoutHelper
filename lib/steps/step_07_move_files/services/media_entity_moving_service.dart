import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:gpth/gpth-lib.dart';

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

  // Keeps the last full set of results for verification/reporting purposes
  final List<MediaEntityMovingResult> _lastResults = [];

  /// Expose an immutable view of the last results after a run
  List<MediaEntityMovingResult> get lastResults => List.unmodifiable(_lastResults);

  /// Moves media entities according to the provided context
  ///
  /// [entityCollection] Collection of media entities to process
  /// [context] Configuration and context for the moving operations
  /// Returns a stream of progress updates (number of files processed)
  Stream<int> moveMediaEntities(
    final MediaEntityCollection entityCollection,
    final MovingContext context,
  ) async* {
    // Reset previous results
    _lastResults.clear();

    // Create the appropriate strategy for the album behavior
    final strategy = _strategyFactory.createStrategy(context.albumBehavior);

    // Validate the context for this strategy
    strategy.validateContext(context);

    int processedCount = 0;
    final List<MediaEntityMovingResult> allResults = [];

    // Process each media entity
    for (final entity in entityCollection.entities) {
      // Track which source files got an emitted operation by the strategy
      final expectedSources =
          entity.files.files.values.map((final f) => f.path).toSet(); // all source paths in the entity
      final coveredSources = <String>{};

      await for (final result in strategy.processMediaEntity(entity, context)) {
        allResults.add(result);
        coveredSources.add(result.operation.sourceFile.path);

        if (!result.success && context.verbose) {
          _logError(result);
        } else if (context.verbose) {
          _logResult(result);
        }
      }

      // Inject synthetic failures for files with no emitted operation
      final missing = expectedSources.difference(coveredSources);
      if (missing.isNotEmpty) {
        for (final missingPath in missing) {
          final syntheticOp = MediaEntityMovingOperation(
            sourceFile: File(missingPath),
            targetDirectory: Directory(context.outputDirectory.path),
            operationType: MediaEntityOperationType.move, // nominal intent
            mediaEntity: entity,
          );
          final synthetic = MediaEntityMovingResult.failure(
            operation: syntheticOp,
            errorMessage: 'No operation emitted by strategy for this source file',
            duration: Duration.zero,
          );
          allResults.add(synthetic);
          if (context.verbose) {
            _logError(synthetic);
          }
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

    // Store results for external verification (MoveFilesStep)
    _lastResults
      ..clear()
      ..addAll(allResults);

    // Print summary
    _printSummary(allResults, strategy);
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
    // Reset previous results
    _lastResults.clear();

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
              final expectedSources =
                  entity.files.files.values.map((final f) => f.path).toSet();
              final coveredSources = <String>{};

              // ignore: prefer_foreach
              await for (final result in strategy.processMediaEntity(
                entity,
                context,
              )) {
                results.add(result);
                coveredSources.add(result.operation.sourceFile.path);
              }

              // Inject synthetic failures for files with no emitted operation
              final missing = expectedSources.difference(coveredSources);
              if (missing.isNotEmpty) {
                for (final missingPath in missing) {
                  results.add(
                    MediaEntityMovingResult.failure(
                      operation: MediaEntityMovingOperation(
                        sourceFile: File(missingPath),
                        targetDirectory: Directory(context.outputDirectory.path),
                        operationType: MediaEntityOperationType.move,
                        mediaEntity: entity,
                      ),
                      errorMessage: 'No operation emitted by strategy for this source file',
                      duration: Duration.zero,
                    ),
                  );
                }
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

    // Store results for external verification (MoveFilesStep)
    _lastResults
      ..clear()
      ..addAll(allResults);

    // Print summary
    _printSummary(allResults, strategy);
  }

  void _logResult(final MediaEntityMovingResult result) {
    final operation = result.operation;
    final status = result.success ? 'SUCCESS' : 'FAILED';
    print('[${operation.operationType.name.toUpperCase()}] $status: ${operation.sourceFile.path}');

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
    int primaryMoves = 0;
    int duplicatesMovedToFolder = 0; // renamed meaning: moved to _Duplicates
    int symlinksCreated = 0;
    int failures = 0;

    for (final r in results) {
      if (!r.success) {
        failures++;
        continue;
      }

      switch (r.operation.operationType) {
        case MediaEntityOperationType.move:
          final src = r.operation.sourceFile.path.replaceAll('\\', '/').toLowerCase();
          final prim = r.operation.mediaEntity.primaryFile.path.replaceAll('\\', '/').toLowerCase();
          if (src == prim) {
            primaryMoves++;
          } else {
            // Treat any successful move of a non-primary source as a "duplicate identified and moved to _Duplicates"
            duplicatesMovedToFolder++;
          }
          break;
        case MediaEntityOperationType.createSymlink:
        case MediaEntityOperationType.createReverseSymlink:
          symlinksCreated++;
          break;
        case MediaEntityOperationType.copy:
          // Not included in headline counters
          break;
        case MediaEntityOperationType.createJsonReference:
          // Not included in headline counters
          break;
      }
    }

    final totalOps = results.length;

    print ('');
    print('\n=== Moving Summary (${strategy.name}) ===');
    print('Primary files moved: $primaryMoves');
    print('Duplicates identified and moved to "_Duplicates": $duplicatesMovedToFolder');
    print('Symlinks created: $symlinksCreated');
    print('Failures: $failures');
    print('Total operations: $totalOps');

    if (failures > 0) {
      print('\nErrors encountered:');
      results.where((final r) => !r.success).take(5).forEach((final result) {
        print('  • ${result.operation.sourceFile.path}: ${result.errorMessage}');
      });
      if (failures > 5) {
        print('  ... and ${failures - 5} more errors');
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
