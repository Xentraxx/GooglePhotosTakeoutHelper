import 'package:console_bars/console_bars.dart';

import '../models/pipeline_step_model.dart';

/// Step 4: Extract dates from media files
///
/// This critical step determines the correct date and time for each media file using
/// multiple extraction methods in order of reliability. Accurate date extraction is
/// essential for proper chronological organization of photos and videos.
///
/// ## Extraction Methods (Priority Order)
///
/// ### 1. JSON Metadata (Highest Priority)
/// - **Source**: Google Photos metadata files (.json)
/// - **Accuracy**: Highest - preserves original Google Photos timestamps
/// - **Content**: Contains exact photo/video creation time from Google's servers
/// - **Format**: Unix timestamp with timezone information
/// - **Reliability**: Most trustworthy as it comes directly from Google Photos
///
/// ### 2. EXIF Data (High Priority)
/// - **Source**: Embedded metadata within image/video files
/// - **Accuracy**: High - original camera/device timestamps
/// - **Content**: Camera-recorded date/time, GPS coordinates, device settings
/// - **Format**: Various EXIF date formats (DateTime, DateTimeOriginal, etc.)
/// - **Reliability**: Very reliable but can be modified by editing software
///
/// ### 3. Filename Patterns (Medium Priority)
/// - **Source**: Date patterns extracted from filenames
/// - **Accuracy**: Medium - depends on consistent naming conventions
/// - **Content**: Dates embedded in filename patterns (IMG_20230615_143022.jpg)
/// - **Format**: Various patterns (YYYYMMDD, YYYY-MM-DD, etc.)
/// - **Reliability**: Moderate - useful when metadata is missing
/// - **Configuration**: Can be enabled/disabled via `guessFromName` setting
///
/// ### 4. Aggressive JSON Matching (Lowest Priority)
/// - **Source**: JSON files with similar names or in same directory
/// - **Accuracy**: Lower - heuristic matching when direct association fails
/// - **Content**: Best-guess timestamps from related JSON files
/// - **Format**: Inferred from nearby files with similar naming patterns
/// - **Reliability**: Last resort when other methods fail
///
/// ## Processing Logic
///
/// ### Extraction Priority System
/// For each media file, the step:
/// 1. **Attempts each extractor in priority order** until a valid date is found
/// 2. **Records the extraction method used** for statistics and debugging
/// 3. **Assigns accuracy scores** based on the extraction method reliability
/// 4. **Handles timezone conversions** when timezone data is available
/// 5. **Validates extracted dates** to ensure they're reasonable
///
/// ### Date Accuracy Tracking
/// Each extracted date is assigned an accuracy level:
/// - **Level 0**: JSON metadata (most accurate)
/// - **Level 1**: EXIF data (very accurate)
/// - **Level 2**: Filename patterns (moderately accurate)
/// - **Level 3**: Aggressive matching (least accurate)
/// - **Level 999**: No date found (will use fallback strategies)
///
/// ### Statistics Collection
/// The step tracks detailed statistics:
/// - **Extraction method distribution**: How many files used each method
/// - **Success/failure rates**: Percentage of files with successful date extraction
/// - **Accuracy distribution**: Breakdown of accuracy levels achieved
/// - **Processing performance**: Time taken and files processed per second
///
/// ## Configuration Options
///
/// ### Date Extractor Selection
/// - **JSON Extractor**: Always enabled (highest priority)
/// - **EXIF Extractor**: Always enabled (high reliability)
/// - **Filename Extractor**: Controlled by `guessFromName` configuration
/// - **Aggressive Extractor**: Always enabled as fallback
///
/// ### Processing Behavior
/// - **Verbose Mode**: Provides detailed progress reporting and statistics
/// - **Progress Reporting**: Updates every 100 files for large collections
/// - **Error Handling**: Continues processing when individual files fail
/// - **Performance Optimization**: Efficient processing for large photo libraries
///
/// ## Error Handling and Edge Cases
///
/// ### Invalid Date Detection
/// - **Future dates**: Dates more than 1 year in the future are flagged
/// - **Prehistoric dates**: Dates before 1900 are considered suspicious
/// - **Timezone issues**: Handles various timezone formats and conversions
/// - **Corrupted metadata**: Gracefully handles malformed JSON or EXIF data
///
/// ### Fallback Strategies
/// - **No date found**: Files without extractable dates are marked for manual review
/// - **Conflicting dates**: Priority system resolves conflicts automatically
/// - **Partial metadata**: Extracts what's available even with incomplete data
/// - **File access issues**: Skips inaccessible files without stopping processing
///
/// ### Performance Considerations
/// - **Batch processing**: Efficiently handles thousands of files
/// - **Memory management**: Processes files incrementally to avoid memory issues
/// - **I/O optimization**: Minimizes file system access through smart caching
/// - **Progress tracking**: Provides user feedback for long-running operations
///
/// ## Integration with Other Steps
///
/// ### Prerequisites
/// - **Media Discovery**: Requires populated MediaCollection from Step 2
/// - **File Accessibility**: Files must be readable and not corrupted
///
/// ### Outputs Used By Later Steps
/// - **Chronological Organization**: Date information enables year/month folder creation
/// - **EXIF Data Source**: Extracted dates provide input for EXIF writing step
/// - **Duplicate Resolution**: Date accuracy helps choose best duplicate to keep
/// - **Album Processing**: Temporal information aids in album organization
///
/// ### Data Flow
/// - **Input**: MediaCollection with discovered files
/// - **Processing**: Date extraction and accuracy assignment
/// - **Output**: MediaCollection with date metadata and extraction statistics
/// - **Side Effects**: Updates each Media object with date and accuracy information
class ExtractDatesStep extends ProcessingStep {
  const ExtractDatesStep() : super('Extract Dates');

  @override
  Future<StepResult> execute(final ProcessingContext context) async {
    final stopwatch = Stopwatch()..start();

    try {
      print('\n[Step 4/8] Extracting metadata (this may take a while)...');

      final extractors = context.config.dateExtractors;

      // Initialize progress bar if verbose mode is enabled
      FillingBar? progressBar;
      if (context.config.verbose) {
        progressBar = FillingBar(
          desc: 'Processing media files',
          total: context.mediaCollection.length,
          width: 50,
        );
      }

      final extractionStats = await context.mediaCollection.extractDates(
        extractors,
        onProgress: context.config.verbose
            ? (final int current, final int total) {
                progressBar?.update(current);
                if (current == total) {
                  print(''); // Add a newline after progress bar completion
                }
              }
            : null,
      );

      print('Date extraction completed:');
      for (final entry in extractionStats.entries) {
        print('  ${entry.key.name}: ${entry.value} files');
      }

      stopwatch.stop();
      return StepResult.success(
        stepName: name,
        duration: stopwatch.elapsed,
        data: {
          'extractionStats': extractionStats,
          'processedMedia': context.mediaCollection.length,
        },
        message: 'Extracted dates for ${context.mediaCollection.length} files',
      );
    } catch (e) {
      stopwatch.stop();
      return StepResult.failure(
        stepName: name,
        duration: stopwatch.elapsed,
        error: e is Exception ? e : Exception(e.toString()),
        message: 'Failed to extract dates: $e',
      );
    }
  }

  @override
  bool shouldSkip(final ProcessingContext context) =>
      context.mediaCollection.isEmpty;
}
