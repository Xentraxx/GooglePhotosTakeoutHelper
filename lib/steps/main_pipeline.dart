import 'dart:io';
import 'package:gpth/gpth-lib.dart';

/// Processing Pipeline for Google Photos Takeout Helper
///
/// This pipeline executes 8 processing steps in their fixed order:
/// 1. Fix Extensions - Correct mismatched file extensions (configurable)
/// 2. Discover Media - Find and classify all media files from input directory
/// 3. Remove Duplicates - Remove duplicate files using content hashing
/// 4. Extract Dates - Determine accurate timestamps from JSON, EXIF, and filenames
/// 5. Write EXIF - Embed metadata into files (requires ExifTool for non-JPEG formats)
/// 6. Find Albums - Detect and merge album relationships between duplicate files
/// 7. Move Files - Organize files to output structure using selected album behavior
/// 8. Update Creation Time - Sync file creation timestamps (Windows only, configurable)
///
/// Each step checks configuration flags to determine if it should run.
/// This eliminates the need for complex builder patterns while maintaining
/// full flexibility through configuration.
class ProcessingPipeline {
  /// Create a processing pipeline
  const   ProcessingPipeline({this.interactiveService});

  /// Optional interactive service for displaying processing summaries and results
  final ConsolidatedInteractiveService? interactiveService;

  /// Execute the complete processing pipeline
  ///
  /// Runs all 8 steps in sequence, with each step checking configuration
  /// to determine if it should execute. Returns comprehensive results
  /// including timing, statistics, and any errors encountered.
  Future<ProcessingResult> execute({
    required final ProcessingConfig config,
    required final Directory inputDirectory,
    required final Directory outputDirectory,
  }) async {
    final overallStopwatch = Stopwatch()..start();
    final mediaCollection = MediaEntityCollection();

    // Create processing context
    final context = ProcessingContext(
      config: config,
      mediaCollection: mediaCollection,
      inputDirectory: inputDirectory,
      outputDirectory: outputDirectory,
    );

    // Configure concurrency manager logging to respect processing configuration
    ConcurrencyManager.logger = LoggingService.fromConfig(context.config);

    // Define the 8 processing steps in fixed order
    final steps = [
      FixExtensionsStep(), // Step 1
      DiscoverMediaStep(), // Step 2
      RemoveDuplicatesStep(), // Step 3
      ExtractDatesStep(), // Step 4
      WriteExifStep(), // Step 5
      FindAlbumsStep(), // Step 6
      MoveFilesStep(), // Step 7
      UpdateCreationTimeStep(), // Step 8
    ];

    final stepResults = <StepResult>[];
    final stepTimings = <String, Duration>{};

    // Counters for ProcessingResult
    var duplicatesRemoved = 0;
    var extrasSkipped = 0;
    var extensionsFixed = 0;
    var coordinatesWrittenToExif = 0;
    var dateTimesWrittenToExif = 0;
    var creationTimesUpdated = 0;
    final extractionMethodStats = <DateTimeExtractionMethod, int>{};

    if (config.verbose) {
      print('\n=== Starting Google Photos Takeout Helper Processing ===');
      print('Input: ${config.inputPath}');
      print('Output: ${outputDirectory.path}');
      print(
        'Configuration: ${config.albumBehavior.name} album behavior, '
        '${config.dateDivision.name} date division',
      );
    } // Execute each step in sequence
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final stepNumber = i + 1;

      print('\n--- Step $stepNumber/8: ${step.name} ---');

      // Check if step should be skipped
      if (step.shouldSkip(context)) {
        if (config.verbose) {
          print('Skipping ${step.name} (conditions not met)');
        }

        stepResults.add(
          StepResult.success(
            stepName: step.name,
            duration: Duration.zero,
            data: {'skipped': true},
            message: 'Step skipped due to configuration or conditions',
          ),
        );
        continue;
      }

      // Execute the step
      try {
        final result = await step.execute(context);
        stepResults.add(result);
        stepTimings[step.name] = result.duration;

        // Extract statistics from step results
        _extractStepStatistics(
          step,
          result,
          duplicatesRemoved: (final int value) => duplicatesRemoved = value,
          extrasSkipped: (final int value) => extrasSkipped = value,
          extensionsFixed: (final int value) => extensionsFixed = value,
          coordinatesWrittenToExif: (final int value) =>
              coordinatesWrittenToExif = value,
          dateTimesWrittenToExif: (final int value) =>
              dateTimesWrittenToExif = value,
          creationTimesUpdated: (final int value) =>
              creationTimesUpdated = value,
          extractionMethodStats: extractionMethodStats,
        );
        if (result.isSuccess) {
          print(
            '✅ ${step.name} completed in ${const FormattingService().formatDuration(result.duration)}',
          );
          if (result.message != null) {
            print('   ${result.message}');
          }
        } else {
          print('❌ ${step.name} failed: ${result.message}');
          if (result.error != null) {
            print('   Error: ${result.error}');
          }
        } // Stop processing if a critical step fails
        if (!result.isSuccess && _isCriticalStep(step)) {
          if (config.verbose) {
            print('\n⚠️  Critical step failed, stopping pipeline execution');
          }
          break;
        }

        // Stop after extension fixing in solo mode
        if (step is FixExtensionsStep &&
            !config.shouldContinueAfterExtensionFix) {
          if (config.verbose) {
            print(
              '\n⚠️  Extension fixing solo mode complete, stopping pipeline execution',
            );
          }
          break;
        }
      } catch (e) {
        final error = Exception('Unexpected error in ${step.name}: $e');
        final failureResult = StepResult.failure(
          stepName: step.name,
          duration: Duration.zero,
          error: error,
          message: 'Step failed with unexpected error',
        );

        stepResults.add(failureResult);

        if (config.verbose) {
          print('❌ ${step.name} failed with unexpected error: $e');
        }

        // Stop on critical step failure
        if (_isCriticalStep(step)) {
          break;
        }
      }
    }
    overallStopwatch.stop();

    // Calculate final statistics
    final successfulSteps = stepResults
        .where((final StepResult r) => r.isSuccess)
        .length;
    final failedSteps = stepResults
        .where((final StepResult r) => !r.isSuccess)
        .length;
    final skippedSteps = stepResults
        .where((final StepResult r) => r.data['skipped'] == true)
        .length;
    final totalProcessingTime = overallStopwatch.elapsed;
    if (config.verbose && interactiveService != null) {
      // Display warnings and errors summary first
      await interactiveService!.showWarningsAndErrorsSummary(stepResults);

      // Display processing summary
      await interactiveService!.showProcessingSummary(
        totalTime: totalProcessingTime,
        successfulSteps: successfulSteps,
        failedSteps: failedSteps,
        skippedSteps: skippedSteps,
        mediaCount: mediaCollection.length,
      );

      // Display detailed step results
      await interactiveService!.showStepResults(stepResults, stepTimings);
    } // Create comprehensive result
    // Extract low-level operation count from Move Files step if present
    int? operationCount;
    for (final r in stepResults) {
      if (r.stepName == 'Move Files') {
        final oc = r.data['operationCount'];
        if (oc is int) operationCount = oc;
      }
    }

    return ProcessingResult(
      totalProcessingTime: totalProcessingTime,
      stepTimings: stepTimings,
      stepResults: stepResults,
      mediaProcessed: mediaCollection.length,
      duplicatesRemoved: duplicatesRemoved,
      extrasSkipped: extrasSkipped,
      extensionsFixed: extensionsFixed,
      coordinatesWrittenToExif: coordinatesWrittenToExif,
      dateTimesWrittenToExif: dateTimesWrittenToExif,
      creationTimesUpdated: creationTimesUpdated,
      extractionMethodStats: extractionMethodStats,
      albumBehavior: config.albumBehavior,
      totalMoveOperations: operationCount,
      isSuccess: failedSteps == 0,
    );
  }

  /// Determine if a step is critical for processing
  ///
  /// Critical steps will stop the pipeline if they fail
  bool _isCriticalStep(final ProcessingStep step) =>
      step is DiscoverMediaStep || step is MoveFilesStep;

  /// Extract statistics from individual step results
  void _extractStepStatistics(
    final ProcessingStep step,
    final StepResult result, {
    required final Function(int) duplicatesRemoved,
    required final Function(int) extrasSkipped,
    required final Function(int) extensionsFixed,
    required final Function(int) coordinatesWrittenToExif,
    required final Function(int) dateTimesWrittenToExif,
    required final Function(int) creationTimesUpdated,
    required final Map<DateTimeExtractionMethod, int> extractionMethodStats,
  }) {
    final data = result.data;

    if (step is DiscoverMediaStep) {
      extrasSkipped(data['extrasSkipped'] as int? ?? 0);
    } else if (step is RemoveDuplicatesStep) {
      duplicatesRemoved(data['duplicatesRemoved'] as int? ?? 0);
    } else if (step is FixExtensionsStep) {
      extensionsFixed(data['extensionsFixed'] as int? ?? 0);
    } else if (step is WriteExifStep) {
      coordinatesWrittenToExif(data['coordinatesWritten'] as int? ?? 0);
      dateTimesWrittenToExif(data['dateTimesWritten'] as int? ?? 0);
    } else if (step is UpdateCreationTimeStep) {
      creationTimesUpdated(data['creationTimesUpdated'] as int? ?? 0);
    } else if (step is ExtractDatesStep) {
      final stepStats = data['extractionStats'] as Map<dynamic, dynamic>? ?? {};
      for (final entry in stepStats.entries) {
        // Convert string keys to DateTimeExtractionMethod enum values
        final methodName = entry.key.toString();
        final count = entry.value as int? ?? 0;

        // Try to find matching enum value
        for (final method in DateTimeExtractionMethod.values) {
          if (method.toString().split('.').last == methodName ||
              method.name == methodName) {
            extractionMethodStats[method] = count;
            break;
          }
        }
      }
    }
  }
}
