import 'dart:io';

import '../domain/models/pipeline_step_model.dart';
import '../domain/services/core/logging_service.dart';
import '../shared/constants.dart';

/// Service for handling interactive user interface and console interactions
///
/// Extracted from interactive.dart to separate UI concerns from core business logic.
/// This service provides a clean interface for user interactions while maintaining
/// the same user experience as the original interactive mode.
class InteractivePresenter with LoggerMixin {
  /// Creates a new instance of InteractivePresenter
  InteractivePresenter({
    this.enableSleep = true,
    this.enableInputValidation = true,
  });

  /// Whether to use sleep delays for better UX (disable for testing)
  final bool enableSleep;

  /// Whether to validate user input (disable for testing)
  final bool enableInputValidation;

  /// Helper method for sleep delays (can be disabled for testing)
  Future<void> _sleep(final num seconds) async {
    if (enableSleep) {
      await Future<void>.delayed(
        Duration(milliseconds: (seconds * 1000).toInt()),
      );
    }
  }

  /// Album options with descriptions for user selection
  static const Map<String, String> albumOptions = <String, String>{
    'shortcut':
        '[Recommended] Album folders with symlinks to \n'
        'original photos. \nRecommended as it will take the least space and \n'
        'provides better compatibility with cloud services and file type detection\n',
    'duplicate-copy':
        'Album folders with photos copied into them. \n'
        'This will work across all systems, but may take wayyy more space!!\n',
    'json':
        'Put ALL photos (including Archive and Trash) in one folder and \n'
        'make a .json file with info about albums. \n'
        "Use if you're a programmer, or just want to get everything, \n"
        'ignoring lack of year-folders etc.\n',
    'nothing':
        'Just ignore them and put year-photos into one folder. \n'
        'WARNING: This ignores Archive/Trash !!!\n',
    'reverse-shortcut':
        'Album folders with ORIGINAL photos. "ALL_PHOTOS" folder \n'
        'with shortcuts/symlinks to albums. If a photo is in an album, \n'
        'the original is saved. CAUTION: If a photo is in multiple albums, it will \n'
        'be duplicated in the other albums, and the shortcuts/symlinks in \n'
        '"ALL_PHOTOS" will point only to one album.\n',
  };

  /// Displays greeting message and introduction to the tool
  Future<void> showGreeting() async {
    print('GooglePhotosTakeoutHelper v$version');
    await _sleep(1);
    print(
      'Hi there! This tool will help you to get all of your photos from '
      'Google Takeout to one nice tidy folder\n',
    );
    await _sleep(3);
    print(
      '(If any part confuses you, read the guide on:\n'
      'https://github.com/Xentraxx/GooglePhotosTakeoutHelper)',
    );
    await _sleep(3);
  }

  /// Shows message when no photos are found
  Future<void> showNothingFoundMessage() async {
    logWarning('...oh :(', forcePrint: true);
    logWarning('...', forcePrint: true);
    logWarning(
      "8 I couldn't find any photos :( reasons for this may be:",
      forcePrint: true,
    );
    logWarning(
      "  - you've already ran gpth and it moved all photos to output -\n"
      '    delete the input folder and re-extract the zip',
      forcePrint: true,
    );
    await _sleep(3);
    logWarning(
      '  - you have a different folder structure in your takeout\n'
      '    (this often happens when downloading takeout twice)\n'
      '    try browsing your zip file and re-extracting only\n'
      '    the "Takeout/Google Photos" folder',
      forcePrint: true,
    );
    await _sleep(3);
  }

  /// Prompts user to press enter to continue
  void showPressEnterPrompt() {
    print('[press enter to continue]');
    stdin.readLineSync();
  }

  /// Reads user input and normalizes it
  Future<String> readUserInput() async {
    final input = stdin.readLineSync();
    if (input == null) {
      throw Exception('No input received');
    }

    return input.replaceAll('[', '').replaceAll(']', '').toLowerCase().trim();
  }

  /// Shows available album options and prompts user to select one
  Future<String> selectAlbumOption() async {
    print('How do you want to handle albums?');
    await _sleep(1);

    int index = 1;
    final options = <String>[];

    for (final entry in albumOptions.entries) {
      options.add(entry.key);
      print('[$index] ${entry.key}');
      print('    ${entry.value}');
      index++;
    }

    print('Please enter the number of your choice:');

    while (true) {
      final input = await readUserInput();
      final choice = int.tryParse(input);

      if (choice != null && choice >= 1 && choice <= options.length) {
        final selectedOption = options[choice - 1];
        print('You selected: $selectedOption');
        await _sleep(1);
        return selectedOption;
      }

      print(
        'Invalid choice. Please enter a number between 1 and ${options.length}:',
      );
    }
  }

  /// Shows directory selection prompt
  Future<Directory?> selectDirectory(final String prompt) async {
    print(prompt);
    await _sleep(1);

    // For now, delegate to file picker or manual input
    // This could be enhanced with a proper directory picker
    print('Please enter the full path to the directory:');

    final input = await readUserInput();
    if (input.isEmpty) {
      return null;
    }

    final directory = Directory(input);
    if (!await directory.exists()) {
      logWarning('Directory does not exist: $input', forcePrint: true);
      return null;
    }

    return directory;
  }

  /// Prompts user to select input directory
  Future<void> promptForInputDirectory() async {
    print('Select the directory where you unzipped all your takeout zips');
    print('(Make sure they are merged => there is only one "Takeout" folder!)');
    if (enableSleep) await _sleep(1);
  }

  /// Shows confirmation message for input directory selection
  Future<void> showInputDirectoryConfirmation() async {
    print('Cool!');
    if (enableSleep) await _sleep(1);
  }

  /// Prompts user to select ZIP files
  Future<void> promptForZipFiles() async {
    print(
      'First, select all .zips from Google Takeout '
      '(use Ctrl to select multiple)',
    );
    if (enableSleep) await _sleep(2);
  }

  /// Shows warning for single ZIP file selection
  Future<void> showSingleZipWarning() async {
    logWarning(
      "You selected only one zip - if that's only one you have, it's cool, "
      'but if you have multiple, Ctrl-C to exit gpth, and select them '
      '*all* again (with Ctrl)',
      forcePrint: true,
    );
    if (enableSleep) await _sleep(5);
  }

  /// Shows success message for ZIP selection with file count and size
  Future<void> showZipSelectionSuccess(
    final int count,
    final String size,
  ) async {
    print('Selected $count zip files ($size)');
    if (enableSleep) await _sleep(1);
  }

  /// Shows error message for ZIP selection
  Future<void> showZipSelectionError() async {
    logError('No zip files selected!');
    if (enableSleep) await _sleep(1);
  }

  /// Prompts user to select output directory
  Future<void> promptForOutputDirectory() async {
    print(
      'Select the output directory, where GPTH should move your photos to.',
    );
    if (enableSleep) await _sleep(1);
  }

  /// Shows confirmation message for output directory selection
  Future<void> showOutputDirectoryConfirmation() async {
    print('Great!');
    if (enableSleep) await _sleep(1);
  }

  /// Shows list of files to be processed
  Future<void> showFileList(final List<String> files) async {
    print('Files to be processed:');
    for (final file in files) {
      print('  - $file');
    }
    if (enableSleep) await _sleep(1);
  }

  /// Prompts user to select date division option
  Future<void> promptForDateDivision() async {
    print(
      'Do you want your photos in one big chronological folder, '
      'or divided to folders by year/month?',
    );
    print('[0] (default) - one big folder');
    print('[1] - year folders');
    print('[2] - year/month folders');
    print('[3] - year/month/day folders');
    print('(Type a number or press enter for default):');
    if (enableSleep) await _sleep(1);
  }

  /// Shows the selected date division choice
  Future<void> showDateDivisionChoice(final String choice) async {
    print('You selected: $choice');
    if (enableSleep) await _sleep(1);
  }

  /// Prompts user to select album behavior
  Future<void> promptForAlbumBehavior() async {
    print('What should be done with albums?');
    print('[1] shortcut: [Recommended] Album folders with symlinks to');
    print(
      '    original photos. Recommended as it provides better compatibility',
    );
    print('    with cloud services and takes the least space');
    print('');
    print('[2] duplicate-copy: Album folders with photos copied into them.');
    print(
      '    This will work across all systems, but may take wayyy more space!!',
    );
    print('');
    print(
      '[3] json: Put ALL photos (including Archive and Trash) in one folder and',
    );
    print('    make a .json file with info about albums.');
    print('    Use if you\'re a programmer, or just want to get everything,');
    print('    ignoring lack of year-folders etc.');
    print('');
    print('[4] nothing: Just ignore them and put year-photos into one folder.');
    print('    WARNING: This ignores Archive/Trash !!!');
    print('');
    print('(Type a number or press enter for recommended option):');
    if (enableSleep) await _sleep(1);
  }

  /// Shows an album option to the user
  void showAlbumOption(final int index, final String key, final String value) {
    print('[$index] $key: $value');
  }

  /// Shows the selected album choice
  Future<void> showAlbumChoice(final String choice) async {
    print('You selected album option: $choice');
    if (enableSleep) await _sleep(1);
  }

  /// Prompts for output cleanup
  Future<void> promptForOutputCleanup() async {
    print('Output folder IS NOT EMPTY! What to do? Type either:');
    print('[1] - delete *all* files inside output folder and continue');
    print('[2] - continue as usual - put output files alongside existing');
    print('[3] - exit program to examine situation yourself');
    print('(Type 1, 2, or 3):');
    if (enableSleep) await _sleep(1);
  }

  /// Shows output cleanup response
  Future<void> showOutputCleanupResponse(final String answer) async {
    print('You selected: $answer');
    if (enableSleep) await _sleep(1);
  }

  /// Prompts for Pixel MP transform
  Future<void> promptForPixelMpTransform() async {
    print(
      'Pixel Motion Pictures are saved with the .MP or .MV '
      'extensions. Do you want to change them to .mp4 '
      'for better compatibility?',
    );
    print('[1] - yes, change extension to .mp4');
    print('[2] (default) - no, keep original extension');
    print('(Type 1 or 2, or press enter for default):');
    if (enableSleep) await _sleep(1);
  }

  /// Shows Pixel MP transform response
  Future<void> showPixelMpTransformResponse(final String answer) async {
    print('You selected: $answer');
    if (enableSleep) await _sleep(1);
  }

  /// Prompts for creation time update
  Future<void> promptForCreationTimeUpdate() async {
    print(
      'This program fixes file "modified times". '
      'Due to language limitations, creation times remain unchanged. '
      'Would you like to run a separate script at the end to sync '
      'creation times with modified times?'
      '\nNote: ONLY ON WINDOWS',
    );
    print('[1] (Default) - No, don\'t update creation time');
    print('[2] - Yes, update creation time to match modified time');
    print('(Type 1 or 2, or press enter for default):');
    if (enableSleep) await _sleep(1);
  }

  /// Shows creation time update response
  Future<void> showCreationTimeUpdateResponse(final String answer) async {
    print('You selected: $answer');
    if (enableSleep) await _sleep(1);
  }

  /// Prompts for EXIF writing
  Future<void> promptForExifWriting(final bool exifToolInstalled) async {
    if (exifToolInstalled) {
      print(
        'This mode will write Exif data (dates/times/coordinates) back to your files. '
        'Do you want to continue with writing exif data enabled?',
      );
    } else {
      print(
        'This mode will write Exif data (dates/times/coordinates) back to your files. '
        'We detected that ExifTool is NOT available! '
        'To achieve the best results, we strongly recommend to download Exiftool and place it next to this executable or in your \$PATH.'
        'If you plan on using this mode, close the program, install exiftool and come back.'
        'Please read the README.md to learn how to get Exiftool for your platform.'
        'Do you want to continue with writing exif data enabled?',
      );
    }
    print('[1] (Default) - Yes, write exif');
    print('[2] - No, don\'t write to exif');
    print('(Type 1 or 2, or press enter for default):');
    if (enableSleep) await _sleep(1);
  }

  /// Shows EXIF writing response
  Future<void> showExifWritingResponse(final String answer) async {
    print('You selected: $answer');
    if (enableSleep) await _sleep(1);
  }

  /// Prompts for file size limit
  Future<void> promptForFileSizeLimit() async {
    print(
      'By default we will process all your files.'
      'However, if you have large video files and run this script on a low ram system (e.g. a NAS or your smart toaster), you might want to '
      'limit the maximum file size to 64 MB not run out of memory.'
      'We recommend to only activate this if you run into problems as this fork made significant improvements to memory management',
    );
    print('[1] (Default) - Don\'t limit me! Process everything!');
    print('[2] - I operate a Toaster. Limit supported media size to 64 MB');
    print('(Type 1 or 2, or press enter for default):');
    if (enableSleep) await _sleep(1);
  }

  /// Shows file size limit response
  Future<void> showFileSizeLimitResponse(final String answer) async {
    print('You selected: $answer');
    if (enableSleep) await _sleep(1);
  }

  /// Prompts for extension fixing
  Future<void> promptForExtensionFixing() async {
    print(
      'Google Photos sometimes saves files with incorrect extensions. '
      'For example, a HEIC file might be saved as .jpg. '
      'Do you want to fix these mismatched extensions?',
    );
    print('[1] (default) - Standard: Fix extensions but skip TIFF-based files');
    print(
      '[2] - Conservative: Fix extensions but skip both TIFF-based and JPEG files',
    );
    print('[3] - Solo: Fix extensions then exit immediately');
    print('[4] - None: Don\'t fix extensions');
    print('(Type a number or press enter for default):');
    if (enableSleep) await _sleep(1);
  }

  /// Shows extension fixing response
  Future<void> showExtensionFixingResponse(final String answer) async {
    print('You selected: $answer');
    if (enableSleep) await _sleep(1);
  }

  /// Prompts for data source
  Future<void> promptForDataSource() async {
    print('Select your data source:');
    await _sleep(1);

    print('[1] (Recommended) - Select ZIP files from Google Takeout');
    print('    GPTH will automatically extract and process them');
    print('    ✓ Convenient and automated');
    print('    ✓ Validates file integrity');
    print('    ✓ Handles multiple ZIP files seamlessly');
    print('');
    print('[2] - Use already extracted folder');
    print('    You have manually extracted ZIP files to a folder');
    print('    ✓ Faster if files are already extracted');
    print('    ✓ Uses less temporary disk space');
    print('    ⚠️  Requires manual extraction and merging of ZIP files');
    print('');

    print('(Type 1 or 2, or press enter for recommended option):');
    if (enableSleep) await _sleep(1);
  }

  /// Shows data source response
  Future<void> showDataSourceResponse(final String answer) async {
    print('You selected: $answer');
    if (enableSleep) await _sleep(1);
  }

  /// Shows disk space notice
  Future<void> showDiskSpaceNotice(final String message) async {
    print('Disk space notice: $message');
    if (enableSleep) await _sleep(1);
  }

  /// Shows unzip start message
  Future<void> showUnzipStartMessage() async {
    print('Starting unzip process...');
    if (enableSleep) await _sleep(1);
  }

  /// Shows unzip progress
  Future<void> showUnzipProgress(final String fileName) async {
    print('Unzipping: $fileName');
    if (enableSleep) await _sleep(1);
  }

  /// Shows unzip success
  Future<void> showUnzipSuccess(final String fileName) async {
    print('Successfully unzipped: $fileName');
    if (enableSleep) await _sleep(1);
  }

  /// Shows unzip complete
  Future<void> showUnzipComplete() async {
    print('Unzip process complete.');
    if (enableSleep) await _sleep(1);
  }

  /// Prompts user to select extraction directory for ZIP files
  Future<void> promptForExtractionDirectory() async {
    print('Now select where you want to extract the ZIP files to.');
    print(
      'This directory will contain the extracted Google Photos data and serve as the input directory for GPTH.',
    );
    print(
      '(You can delete this directory after processing if you want to save space)',
    );
    if (enableSleep) await _sleep(1);
  }

  /// Shows error message for invalid user input
  Future<void> showInvalidAnswerError([final String? customMessage]) async {
    final message = customMessage ?? 'Invalid answer - try again';
    logError(message, forcePrint: true);
    if (enableSleep) await _sleep(1);
  }

  /// Shows the user's selection with the actual value chosen
  Future<void> showUserSelection(
    final String input,
    final String selectedValue,
  ) async {
    String displayValue = selectedValue;

    // If user pressed enter (empty input), it's always a default choice
    if (input.isEmpty) {
      displayValue = '$selectedValue (default)';
    }

    print('You selected: $displayValue');
    if (enableSleep) await _sleep(1);
  }

  // ============================================================================
  // PROCESSING SUMMARY DISPLAY METHODS
  // ============================================================================
  /// Displays a summary of warnings and errors encountered during processing
  ///
  /// Only shown in verbose mode, provides detailed information about any
  /// issues that occurred during processing steps and throughout the application.
  Future<void> showWarningsAndErrorsSummary(
    final List<StepResult> stepResults,
  ) async {
    final failedSteps = stepResults.where((final r) => !r.isSuccess).toList();

    // Get all logged warnings and errors from the logging service
    final loggedWarnings = logger.warnings;
    final loggedErrors = logger.errors;

    // Collect additional warnings from step messages that might not have been logged
    final additionalWarnings = <String>[];
    for (final result in stepResults) {
      if (result.message != null &&
          (result.message!.toLowerCase().contains('warning') ||
              result.message!.toLowerCase().contains('skipped'))) {
        final warningMessage =
            '${result.stepName}: ${result.message}'; // Only add if not already in logged warnings
        if (!loggedWarnings.any((final w) => w.contains(result.message!))) {
          additionalWarnings.add(warningMessage);
        }
      }
    }

    final hasWarnings =
        loggedWarnings.isNotEmpty || additionalWarnings.isNotEmpty;
    final hasErrors = loggedErrors.isNotEmpty || failedSteps.isNotEmpty;

    if (hasWarnings || hasErrors) {
      print('\n=== Warnings and Errors Summary ===');

      if (hasErrors) {
        print('Errors:');

        // Show logged errors first
        for (final error in loggedErrors) {
          print('  ❌ $error');
        }

        // Show failed steps that haven't been logged as errors
        for (final step in failedSteps) {
          final stepError =
              '${step.stepName}: ${step.message ?? 'Unknown error'}';
          if (!loggedErrors.any((final e) => e.contains(step.stepName))) {
            print('  ❌ $stepError');
            if (step.error != null) {
              print('     Details: ${step.error}');
            }
          }
        }
      }

      if (hasWarnings) {
        print('Warnings:');

        // Show logged warnings first
        for (final warning in loggedWarnings) {
          print('  ⚠️  $warning');
        }

        // Show additional warnings from step results
        for (final warning in additionalWarnings) {
          print('  ⚠️  $warning');
        }
      }

      if (!hasWarnings && !hasErrors) {
        print('No warnings or errors encountered during processing.');
      }
    }

    if (enableSleep) await _sleep(1);
  }

  /// Displays detailed results for each processing step
  ///
  /// Shows step-by-step breakdown of what was accomplished
  Future<void> showStepResults(
    final List<StepResult> stepResults,
    final Map<String, Duration> stepTimings,
  ) async {
    print('\n=== Step-by-Step Results ===');

    for (final result in stepResults) {
      final timing = stepTimings[result.stepName] ?? result.duration;
      final status = result.isSuccess ? '✅' : '❌';
      final skipped = result.data['skipped'] == true;

      print('$status ${result.stepName} (${_formatDuration(timing)})');

      if (skipped) {
        print('   Status: Skipped');
        print('   Reason: ${result.message ?? 'Conditions not met'}');
      } else if (result.isSuccess) {
        print('   Status: Completed successfully');
        if (result.message != null) {
          print('   Result: ${result.message}');
        }

        // Display specific metrics for each step
        _showStepMetrics(result);
      } else {
        print('   Status: Failed');
        print('   Error: ${result.message ?? 'Unknown error'}');
      }
      print('');
    }

    if (enableSleep) await _sleep(1);
  }

  /// Displays a processing summary header and statistics
  Future<void> showProcessingSummary({
    required final Duration totalTime,
    required final int successfulSteps,
    required final int failedSteps,
    required final int skippedSteps,
    required final int mediaCount,
  }) async {
    print('\n=== Processing Summary ===');
    print('Total time: ${totalTime.inMinutes}m ${totalTime.inSeconds % 60}s');
    print(
      'Steps: $successfulSteps successful, $failedSteps failed, $skippedSteps skipped',
    );
    print('Final media count: $mediaCount');

    if (enableSleep) await _sleep(1);
  }

  /// Helper method to display step-specific metrics
  void _showStepMetrics(final StepResult result) {
    final data = result.data;

    switch (result.stepName) {
      case 'Fix Extensions':
        if (data['extensionsFixed'] != null) {
          print('   Extensions fixed: ${data['extensionsFixed']} files');
        }
        break;

      case 'Discover Media':
        if (data['mediaFound'] != null) {
          print('   Media files found: ${data['mediaFound']}');
        }
        if (data['jsonFilesFound'] != null) {
          print('   JSON metadata files: ${data['jsonFilesFound']}');
        }
        if (data['extrasSkipped'] != null) {
          print('   Extra files skipped: ${data['extrasSkipped']}');
        }
        break;

      case 'Remove Duplicates':
        if (data['duplicatesRemoved'] != null) {
          print('   Duplicates removed: ${data['duplicatesRemoved']} files');
        }
        if (data['uniqueFiles'] != null) {
          print('   Unique files remaining: ${data['uniqueFiles']}');
        }
        break;

      case 'Extract Dates':
        if (data['datesExtracted'] != null) {
          print('   Dates extracted: ${data['datesExtracted']} files');
        }
        if (data['extractionStats'] != null) {
          final stats = data['extractionStats'] as Map<dynamic, dynamic>;
          print('   Extraction methods used:');
          for (final entry in stats.entries) {
            if (entry.value > 0) {
              print('     ${entry.key}: ${entry.value} files');
            }
          }
        }
        break;

      case 'Write EXIF':
        if (data['coordinatesWritten'] != null) {
          print(
            '   GPS coordinates written: ${data['coordinatesWritten']} files',
          );
        }
        if (data['dateTimesWritten'] != null) {
          print('   DateTime written: ${data['dateTimesWritten']} files');
        }
        break;

      case 'Find Albums':
        if (data['initialCount'] != null && data['finalCount'] != null) {
          print('   Initial media count: ${data['initialCount']}');
          print('   Final media count: ${data['finalCount']}');
        }
        if (data['mergedCount'] != null) {
          print('   Album relationships merged: ${data['mergedCount']}');
        }
        break;

      case 'Move Files':
        if (data['processedCount'] != null) {
          print('   Files processed: ${data['processedCount']}');
        }
        if (data['albumBehavior'] != null) {
          print('   Album behavior: ${data['albumBehavior']}');
        }
        break;

      case 'Update Creation Time':
        if (data['updatedCount'] != null) {
          print('   Creation times updated: ${data['updatedCount']} files');
        }
        break;
    }
  }

  /// Formats a duration as a human-readable string
  String _formatDuration(final Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s';
    } else {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      return '${minutes}m ${seconds}s';
    }
  }
}
