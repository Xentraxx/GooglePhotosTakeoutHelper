// ignore_for_file: unintended_html_in_doc_comment
import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:gpth/gpth-lib.dart';

// Parses hidden test-only flags from argv, applies them, and returns a list
// with those flags removed so ArgParser won't choke on unknown options.
// Supported examples:
//   --_test-standard-multiplier=2
//   --_test-conservative-multiplier=4
//   --_test-disk-optimized-multiplier=8
List<String> _applyAndStripTestMultipliers(final List<String> args) {
  final re = RegExp(r'^--_test-([a-z0-9-]+)=(\d+)$', caseSensitive: false);
  final cleaned = <String>[];
  for (final arg in args) {
    final m = re.firstMatch(arg);
    if (m == null) {
      cleaned.add(arg);
      continue;
    }
    final name = m.group(1)!.toLowerCase();
    final val = int.tryParse(m.group(2)!);
    if (val == null) continue; // silently ignore malformed
    switch (name) {
      case 'standard-multiplier':
        ConcurrencyManager.setMultipliers(standard: val);
        break;
      case 'conservative-multiplier':
        ConcurrencyManager.setMultipliers(conservative: val);
        break;
      case 'disk-optimized-multiplier':
        ConcurrencyManager.setMultipliers(diskOptimized: val);
        break;
      default:
        // Unknown hidden flag -> ignore (do not forward to parser)
        break;
    }
  }
  return cleaned;
}

/// ############################### GOOGLE PHOTOS TAKEOUT HELPER #############################
///
/// **PROCESSING FLOW:**
/// 1. Parse command line arguments → ProcessingConfig
/// 2. Initialize dependencies (ExifTool, ServiceContainer)
/// 3. Execute ProcessingPipeline with 8 steps:
///    - Fix Extensions: Correct mismatched file extensions (optional)
///    - Discover Media: Find and classify all media files
///    - Remove Duplicates: Eliminate duplicate files using content hashing
///    - Extract Dates: Determine accurate timestamps from multiple sources
///    - Write EXIF: Embed metadata into files (when ExifTool available)
///    - Find Albums: Detect and merge album relationships
///    - Move Files: Organize files to output structure using selected album behavior
///    - Update Creation Time: Sync file creation timestamps (Windows only, optional)
/// 4. Display comprehensive results and statistics
///
/// **DESIGN PATTERNS USED:**
/// - Builder Pattern: For complex ProcessingConfig construction
/// - Template Method: ProcessingStep base class with consistent interface
/// - Pipeline Pattern: Sequential step execution with error handling
/// - Domain Models: Type-safe data structures replacing Maps
///
/// **MAINTAINABILITY FEATURES:**
/// - Each function has a single, clear responsibility
/// - All components are independently testable
/// - Configuration is type-safe and validated
/// - Error handling is consistent throughout
/// - Documentation covers both technical and business logic
///
/// ##############################################################################
/// **MAIN ENTRY POINT**
///
/// This is the main entry point for the Google Photos Takeout Helper (GPTH).
/// It orchestrates the entire photo processing workflow using clean architecture principles.
///
/// **HIGH-LEVEL FLOW:**
/// 1. Parse and validate command line arguments
/// 2. Initialize external dependencies (ExifTool, global settings)
/// 3. Execute the main processing pipeline
/// 4. Display comprehensive results to the user
///
/// **ERROR HANDLING:**
/// - All exceptions are caught and handled gracefully
/// - Specific exit codes are used for different error types
/// - User-friendly error messages are displayed
///
/// **PERFORMANCE CONSIDERATIONS:**
/// - Asynchronous processing throughout the pipeline
/// - Memory-efficient streaming for large photo collections
/// - Progress reporting for long-running operations
///
/// @param arguments Command line arguments from the user
Future<void> main(final List<String> arguments) async {
  // Initialize logger early with default settings
  _logger = LoggingService();
  // Apply & strip hidden test-only concurrency multiplier flags before parsing normal args.
  final parsedArguments = _applyAndStripTestMultipliers(arguments);
  try {
    // Initialize ServiceContainer early to support interactive mode during argument parsing
    await ServiceContainer.instance.initialize();

    // Parse command line arguments
    final config = await _parseArguments(parsedArguments);
    if (config == null) {
      return; // Help was shown or other early exit
    }

    // Update logger with correct verbosity and reinitialize services with it
    _logger = LoggingService(isVerbose: config.verbose);

    // Reinitialize ServiceContainer with the properly configured logger
    await ServiceContainer.instance.initialize(loggingService: _logger);

    // Configure dependencies with the parsed config
    await _configureDependencies(config);

    // Load optional fileDates dictionary AFTER the second initialize
    await _loadFileDatesIntoGlobalConfigFromArgs(parsedArguments);

    // Execute the processing pipeline
    final result = await _executeProcessing(config);

    // Show final results
    _showResults(config, result);

    // Cleanup services
    await ServiceContainer.instance.dispose();
  } catch (e) {
    _logger.error('Fatal error: $e');
    _logger.quit();
  }
}

/// Global logger instance
late LoggingService _logger;

/// Print a helpful message and exit with given code.
/// Uses stderr and the logger when available. Optionally shows an interactive
/// prompt before exit when `showInteractivePrompt` is true and INTERACTIVE
/// environment variable is set.
///
/// Exit codes:
/// - 0: Success
/// - 1: General failure/processing error
/// - 11: Input validation error (folder doesn't exist, etc.)
/// - Other codes: Specific error conditions
Never _exitWithMessage(
  final int code,
  final String message, {
  final bool showInteractivePrompt = false,
}) {
  final errorType = switch (code) {
    0 => 'SUCCESS',
    1 => 'PROCESSING_ERROR',
    11 => 'INPUT_VALIDATION_ERROR',
    _ => 'ERROR_CODE_$code',
  };

  final fullMessage = '[$errorType] $message';

  try {
    stderr.writeln(fullMessage);
  } catch (_) {}
  try {
    // logger may not be set early in startup, guard against that
    _logger.error(fullMessage);
  } catch (_) {}

  if (showInteractivePrompt && Platform.environment['INTERACTIVE'] == 'true') {
    print('[gpth ${code != 0 ? 'quitted :(' : 'finished :)'} (code $code) - press enter to close]');
    stdin.readLineSync();
  }

  exit(code);
}

/// **ARGUMENT PARSING & CONFIGURATION BUILDING**
///
/// Converts raw command line arguments into a type-safe ProcessingConfig object.
/// This replaces the original unsafe Map<String, dynamic> approach with proper
/// domain models that provide validation and type safety.
///
/// **SUPPORTED MODES:**
/// - Normal processing: Full Google Photos Takeout organization
/// - Fix mode: Special mode to just fix dates on existing photos
/// - Interactive mode: Guided setup with user prompts
/// - CLI mode: Direct command line operation
///
/// **VALIDATION:**
/// - All required parameters are validated
/// - Invalid combinations are caught early
/// - Descriptive error messages guide the user
///
/// @param arguments Raw command line arguments
/// @returns ProcessingConfig object or null if help was shown
/// @throws FormatException for invalid argument formats
/// @throws ProcessExit for validation failures
Future<ProcessingConfig?> _parseArguments(final List<String> arguments) async {
  final parser = _createArgumentParser();

  try {
    final res = parser.parse(arguments);

    if (res['help']) {
      _showHelp(parser);
      return null;
    }

    // Convert ArgResults to configuration
    return await _buildConfigFromArgs(res);
  } on FormatException catch (e) {
    _logger.error('$e');
    _exitWithMessage(
      2,
      'Argument parsing failed: ${e.toString()}. Run `gpth --help` for usage.',
    );
  }
}

/// **COMMAND LINE PARSER FACTORY**
///
/// Creates the argument parser with all supported options and flags.
/// This centralizes all CLI option definitions in one place for maintainability.
///
/// **OPTION CATEGORIES:**
/// - Input/Output: Specify source and destination directories
/// - Processing: Control how photos are processed (copy vs move, etc.)
/// - Organization: Album handling and date-based folder organization
/// - Metadata: EXIF writing, date extraction, coordinate handling
/// - Extensions: File extension fixing and transformation
/// - Platform: Windows-specific features like creation time updates
/// - Debugging: Verbose output and file size limits
///
/// **DEFAULTS:**
/// - Most options have sensible defaults for typical use cases
/// - Interactive mode is automatically enabled when no args provided
/// - Help flag shows comprehensive usage information
///
/// @returns Configured ArgParser instance
ArgParser _createArgumentParser() => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false)
  ..addOption('fix', help: 'Folder with any photos to fix dates (special mode)')
  ..addFlag('interactive', help: 'Use interactive mode')
  ..addFlag('verbose', abbr: 'v', help: 'Shows extensive output')
  ..addOption('input', abbr: 'i', help: 'Input folder with extracted takeouts')
  ..addOption('output', abbr: 'o', help: 'Output folder for organized photos')
  ..addOption(
    'albums',
    help: 'What to do about albums?',
    allowed: InteractivePresenterService.albumOptions.keys,
    allowedHelp: InteractivePresenterService.albumOptions,
    defaultsTo: 'shortcut',
  )
  ..addOption(
    'divide-to-dates',
    help: 'Divide output to folders by nothing/year/month/day',
    allowed: ['0', '1', '2', '3'],
    defaultsTo: '0',
  )
  ..addFlag('skip-extras', help: 'Skip extra images (like -edited etc)')
  ..addFlag(
    'guess-from-name',
    help: 'Try to guess file dates from their names',
    defaultsTo: true,
  )
  ..addOption(
    'fix-extensions',
    help: 'Fix incorrect file extensions',
    allowed: ['none', 'standard', 'conservative', 'solo'],
    allowedHelp: {
      'none': 'No extension fixing',
      'standard': 'Fix extensions (skip TIFF-based files like RAW) - Default',
      'conservative': 'Fix extensions (skip TIFF and JPEG files)',
      'solo': 'Fix extensions then exit immediately',
    },
    defaultsTo: 'standard',
  )
  ..addFlag('transform-pixel-mp', help: 'Transform Pixel .MP/.MV to .mp4')
  ..addFlag(
    'update-creation-time',
    help: 'Set creation time equal to modification date (Windows only)',
  )
  ..addFlag(
    'write-exif',
    help: 'Write geodata and DateTime to EXIF (requires ExifTool for non-JPEG)',
    defaultsTo: true,
  )
  ..addFlag(
    'limit-filesize',
    help: 'Enforces 64MB file size limit for low RAM systems',
  )
  ..addFlag(
    'divide-partner-shared',
    help: 'Move partner shared media to separate folder (PARTNER_SHARED)',
  )
  // NEW: allow a JSON with precomputed dates
  ..addOption(
    'fileDates',
    help: 'Path to a JSON file with a date dictionary (OldestDate per file)',
  )
  // NEW: keep the original input folder untouched by working on a sibling copy "<input>_tmp"
  ..addFlag(
    'keep-input',
    help: 'Work on a temporary sibling copy of --input (suffix _tmp), keeping the original untouched',
  );

/// **HELP TEXT DISPLAY**
///
/// Shows comprehensive help information including usage examples and setup instructions.
/// This guides users through the Google Photos Takeout process and GPTH usage.
///
/// **HELP CONTENT:**
/// - Overview of the Google Photos export process
/// - ExifTool installation requirements
/// - Basic usage examples with input/output folders
/// - Complete list of all available command line options
///
/// @param parser The configured argument parser for generating usage text
void _showHelp(final ArgParser parser) =>
    print('''GooglePhotosTakeoutHelper v$version - The Dart successor

gpth is meant to help you with exporting your photos from Google Photos.

First, go to https://takeout.google.com/ , deselect all and select only Photos.
When ready, download all .zips, and extract them into *one* folder.
To read and write exif data, you have to install exiftool (e.g. from here https://exiftool.org)
for your OS and make sure the executable is in a folder in the \$PATH.

Then, run: gpth --input "folder/with/all/takeouts" --output "your/output/folder"
...and gpth will parse and organize all photos into one big chronological folder

${parser.usage}''');

/// **CONFIGURATION BUILDER**
///
/// Transforms parsed command line arguments into a type-safe ProcessingConfig using
/// the builder pattern. This provides a fluent API for complex configuration setup
/// while ensuring all validation rules are applied.
///
/// **CONFIGURATION CATEGORIES:**
/// 1. **Mode Detection**: Normal vs Fix vs Interactive mode
/// 2. **Path Resolution**: Input/output directories from args or interactive prompts
/// 3. **Processing Options**: Copy/move, EXIF writing, duplicate handling
/// 4. **Organization**: Album behavior and date-based folder structure
/// 5. **Metadata**: Date extraction preferences and coordinate handling
/// 6. **Extensions**: File extension fixing and format transformations
/// 7. **Platform Features**: Windows creation time updates, file size limits
///
/// **VALIDATION:**
/// - Builder pattern ensures all required fields are set
/// - Invalid option combinations are caught during build()
/// - Interactive mode can override and enhance CLI arguments
///
/// @param res Parsed command line arguments
/// @returns Fully configured and validated ProcessingConfig
/// @throws ConfigurationException for invalid configurations
Future<ProcessingConfig> _buildConfigFromArgs(final ArgResults res) async {
  // Handle special fix mode
  if (res['fix'] != null) {
    return _handleFixMode(res);
  }
  // Set up interactive mode if needed
  final isInteractiveMode =
      res['interactive'] || (res.arguments.isEmpty && stdin.hasTerminal);
  // Get input/output paths (interactive or from args)
  final paths = await _getInputOutputPaths(res, isInteractiveMode);

  // NOTE: the --fileDates JSON is now loaded AFTER the second initialize,
  // inside _loadFileDatesIntoGlobalConfigFromArgs() in main(), to avoid being reset.

  // Build configuration using the builder pattern
  final configBuilder = ProcessingConfig.builder(
    inputPath: paths.inputPath,
    outputPath: paths.outputPath,
  );
  // Apply all configuration options
  if (res['verbose']) configBuilder.verboseOutput = true;
  if (res['skip-extras']) configBuilder.skipExtras = true;
  if (!res['guess-from-name']) configBuilder.guessFromName = false;

  // Propagate if input comes from an internal ZIP extraction
  configBuilder.inputExtractedFromZip = paths.extractedFromZip;

  // Propagate the original user-provided root directory (before resolving subfolder)
  configBuilder.userInputRoot = paths.userInputRoot;

  // Set album behavior
  final albumBehavior = AlbumBehavior.fromString(res['albums']);
  configBuilder.albumBehavior = albumBehavior;

  // Set extension fixing mode
  ExtensionFixingMode extensionFixingMode;
  if (isInteractiveMode) {
    // Ask user for date division preference in interactive mode
    print('');
    final dateDivision = await ServiceContainer.instance.interactiveService.askDivideDates();
    final divisionLevel = DateDivisionLevel.fromInt(dateDivision);
    configBuilder.dateDivision = divisionLevel;

    // Ask user for extension fixing preference in interactive mode
    print('');
    final extensionFixingChoice = await ServiceContainer.instance.interactiveService.askFixExtensions();
    extensionFixingMode = ExtensionFixingMode.fromString(extensionFixingChoice);

    // Ask user for EXIF writing preference in interactive mode
    print('');
    final writeExif = await ServiceContainer.instance.interactiveService.askIfWriteExif();
    configBuilder.exifWriting = writeExif;

    // Ask user for Album mode
    print('');
    final albumModeString = await ServiceContainer.instance.interactiveService.askAlbums();
    final AlbumBehavior albumBehaviour = AlbumBehavior.fromString(albumModeString);
    configBuilder.albumBehavior = albumBehaviour;

    // Ask user for Pixel/MP file transformation in interactive mode
    print('');
    final transformPixelMP = await ServiceContainer.instance.interactiveService.askTransformPixelMP();
    configBuilder.pixelTransformation = transformPixelMP;

    // Ask user for file size limiting in interactive mode
    print('');
    final limitFileSize = await ServiceContainer.instance.interactiveService.askIfLimitFileSize();
    configBuilder.fileSizeLimit = limitFileSize;

    // Ask whether to keep the original input (work on "<input>_tmp")
    print('');
    final keepInputFlag = await ServiceContainer.instance.interactiveService.askKeepInput();
    configBuilder.keepInput = keepInputFlag;

    // Ask user for creation time update in interactive mode (Windows only)
    if (Platform.isWindows) {
      print('');
      final updateCreationTime = await ServiceContainer.instance.interactiveService.askChangeCreationTime();
      configBuilder.creationTimeUpdate = updateCreationTime;
    }
    configBuilder.interactiveMode = true;
  } else {
    // Set date division from command line arguments
    final divisionLevel = DateDivisionLevel.fromInt(
      int.parse(res['divide-to-dates']),
    );
    configBuilder.dateDivision = divisionLevel;

    // Use command line arguments or defaults
    final fixExtensionsArg = res['fix-extensions'] ?? 'standard';
    extensionFixingMode = ExtensionFixingMode.fromString(fixExtensionsArg);

    // Apply remaining configuration options from command line
    if (!res['write-exif']) configBuilder.exifWriting = false;
    if (res['transform-pixel-mp']) configBuilder.pixelTransformation = true;
    if (res['update-creation-time']) configBuilder.creationTimeUpdate = true;
    if (res['limit-filesize']) configBuilder.fileSizeLimit = true;
    if (res['divide-partner-shared']) configBuilder.dividePartnerShared = true;
    if (res['keep-input']) configBuilder.keepInput = true; // CLI: honor --keep-input
  }
  configBuilder.extensionFixing = extensionFixingMode;

  return configBuilder.build();
}

/// **FIX MODE HANDLER**
///
/// Handles the special "fix mode" where GPTH only processes existing photos
/// to correct their dates without doing full Google Photos Takeout organization.
/// This is useful for post-processing photos that have been moved or copied
/// and lost their original timestamps.
///
/// **FIX MODE BEHAVIOR:**
/// - Uses the same directory as both input and output (in-place processing)
/// - Focuses only on date extraction and timestamp correction
/// - Skips album organization, duplicate removal, and file moving
/// - Applies date extraction heuristics to determine correct timestamps
/// - Updates file modification times to match extracted dates
///
/// **USE CASES:**
/// - Photos imported from various sources with incorrect timestamps
/// - Bulk date correction after file transfers
/// - Cleanup of manually organized photo collections
///
/// @param res Parsed command line arguments containing fix path
/// @returns ProcessingConfig configured for fix mode operation
Future<ProcessingConfig> _handleFixMode(final ArgResults res) async {
  final fixPath =
      res['fix']
          as String; // For fix mode, we use the same directory as input and output
  final builder = ProcessingConfig.builder(
    inputPath: fixPath,
    outputPath: fixPath,
  );
  builder.verboseOutput = res['verbose'];
  builder.guessFromName = res['guess-from-name'];
  return builder.build();
}

/// **INPUT/OUTPUT PATH RESOLUTION**
///
/// Determines the input and output directories from either command line arguments
/// or interactive mode prompts. Handles the complexity of Google Takeout ZIP files
/// and provides a unified interface for path resolution.
///
/// **PATH RESOLUTION MODES:**
/// 1. **CLI Mode**: Paths provided directly via --input and --output flags
/// 2. **Interactive Mode**: User-guided selection with validation
/// 3. **ZIP Processing**: User selects extraction location, then output location
/// 4. **Pre-extracted**: Direct processing of already extracted folders
///
/// **ZIP HANDLING:**
/// - Space requirement calculation and validation (double space needed since ZIPs remain)
/// - User-controlled extraction to chosen directory
/// - Transparent location for temporary files
/// - Cleanup responsibility lies with user
///
/// **VALIDATION:**
/// - Input directory existence verification
/// - Output directory creation and cleanup prompts
/// - Path accessibility and permission checks
/// - Automatic navigation to Google Photos directory within Takeout structure
///
/// @param res Parsed command line arguments
/// @returns InputOutputPaths object with resolved and validated paths
/// @throws ProcessExit for invalid or inaccessible paths
Future<InputOutputPaths> _getInputOutputPaths(
  final ArgResults res,
  final bool isInteractiveMode,
) async {
  String? inputPath = res['input'];
  String? outputPath = res['output'];
  var extractedFromZip = false; // NEW
  String? userInputRoot; // NEW: keep the original root before resolve

  if (isInteractiveMode) {
    // Interactive mode handles path collection
    await ServiceContainer.instance.interactiveService.showGreeting();
    print('');

    final bool shouldUnzip = await ServiceContainer.instance.interactiveService.askIfUnzip();
    print('');

    late Directory inDir;
    if (shouldUnzip) {
      final zips = await ServiceContainer.instance.interactiveService.selectZipFiles();
      print('');

      final extractDir = await ServiceContainer.instance.interactiveService.selectExtractionDirectory();
      print('');

      final out = await ServiceContainer.instance.interactiveService.selectOutputDirectory();
      print('');
      // Calculate space requirements
      final cumZipsSize =
          zips.map((final e) => e.lengthSync()).reduce((final a, final b) => a + b);
      final requiredSpace =
          (cumZipsSize * 2) +
          256 * 1024 * 1024; // Double because original ZIPs remain
      await ServiceContainer.instance.interactiveService.freeSpaceNotice(requiredSpace, extractDir);
      print('');
      inDir = extractDir;
      outputPath = out.path;

      await ServiceContainer.instance.interactiveService.extractAll(zips, extractDir);
      print('');
      extractedFromZip = true;
    } else {
      try {
        inDir = await ServiceContainer.instance.interactiveService.selectInputDirectory();
      } catch (e) {
        _logger.warning('⚠️  INTERACTIVE DIRECTORY SELECTION FAILED');
        _logger.warning(
          'Interactive selecting input dir crashed... \n'
          "It looks like you're running headless/on Synology/NAS...\n"
          "If so, you have to use cli options - run 'gpth --help' to see them",
        );
        _logger.warning('');
        _logger.warning('Please restart the program with CLI options instead.');
        _logger.error('No input directory could be selected');
        _exitWithMessage(
          2,
          'Interactive input directory selection failed. If you are running headless or on a NAS, run with CLI options: `gpth --input <path> --output <path>`',
        );
      }
      print('');
      final out = await ServiceContainer.instance.interactiveService.selectOutputDirectory();
      outputPath = out.path;
      print('');
    }

    inputPath = inDir.path;
    userInputRoot = inputPath; // keep original root before resolving
  }

  // If running in non-interactive CLI mode and the provided input path
  // points to a ZIP file or contains ZIP files, automatically extract them
  // into a local `.gpth-unzipped` directory and use that as the input.
  if (!isInteractiveMode && inputPath != null) {
    try {
      final provided = File(inputPath);
      final Directory extractDir;
      final List<File> zips = [];

      if (await provided.exists() &&
          provided.statSync().type == FileSystemEntityType.file &&
          path.extension(provided.path).toLowerCase() == '.zip') {
        // Single zip file provided as --input
        zips.add(provided);
        extractDir = Directory(path.join(path.dirname(provided.path), '.gpth-unzipped'),
        );
      } else {
        final providedDir = Directory(inputPath);
        if (await providedDir.exists()) {
          // Find zip files in directory (non-recursive)
          for (final ent in providedDir.listSync()) {
            if (ent is File && path.extension(ent.path).toLowerCase() == '.zip') {
              zips.add(ent);
            }
          }
        }
        extractDir = Directory(path.join(inputPath, '.gpth-unzipped'));
      }

      if (zips.isNotEmpty) {
        _logger.info('Detected ${zips.length} ZIP file(s) in input path - extracting before processing...');

        // Compute rough required space and warn
        var cumZipsSize = 0;
        for (final z in zips) {
          try {
            cumZipsSize += z.lengthSync();
          } catch (_) {}
        }
        final requiredSpace = (cumZipsSize * 2) + 256 * 1024 * 1024;
        _logger.info('Estimated required temporary space for extraction: ${requiredSpace ~/ (1024 * 1024)} MB');

        try {
          await ServiceContainer.instance.interactiveService.extractAll(
            zips,
            extractDir,
          );
          inputPath = extractDir.path;
          userInputRoot = inputPath; // keep original root (extraction root) for completeness
          extractedFromZip = true;
          _logger.info('Extraction complete. Using extracted folder: $inputPath');
        } catch (e) {
          _logger.error('Automatic ZIP extraction failed: $e');
          _exitWithMessage(
            12,
            'Automatic ZIP extraction failed: ${e.toString()}. Try extracting manually and run again with the extracted folder as --input.',
          );
        }
      } else {
        // No ZIPs detected in CLI mode: remember original root as provided
        userInputRoot ??= inputPath;
      }
    } catch (e) {
      // Non-fatal: log and continue; failure here will be caught later by path resolution
      _logger.warning('ZIP auto-detection/extraction encountered an error: $e');
      // Still remember the original root as provided
      userInputRoot ??= inputPath;
    }
  }

  // Validate required paths
  if (inputPath == null) {
    _logger.error('No --input folder specified :/');
    _exitWithMessage(
      10,
      'Missing required --input path. Provide --input <folder> or run interactive mode.',
    );
  }
  if (outputPath == null) {
    _logger.error('No --output folder specified :/');
    _exitWithMessage(
      10,
      'Missing required --output path. Provide --output <folder> or run interactive mode.',
    );
  }
  // Resolve input path to Google Photos directory using the domain service
  try {
    inputPath = PathResolverService.resolveGooglePhotosPath(inputPath);
  } catch (e) {
    _logger.error('Path resolution failed: $e');
    _exitWithMessage(
      12,
      'Could not resolve Google Photos directory from input path: ${e.toString()}. Make sure the folder contains a Takeout/Google Photos structure or pass the correct --input path.',
    );
  }

  return InputOutputPaths(
    inputPath: inputPath,
    outputPath: outputPath,
    extractedFromZip: extractedFromZip,
    userInputRoot: userInputRoot ?? inputPath, // fallback if not set
  );
}

/// **DEPENDENCY INITIALIZATION**
///
/// Sets up external dependencies and global application state before processing begins.
/// This ensures all required tools and configurations are properly initialized.
///
/// **INITIALIZATION TASKS:**
/// 1. **Debug/Verbose Mode**: Enable detailed logging based on configuration
/// 2. **Global State**: Set file size limits and processing constraints
/// 3. **ExifTool Integration**: Verify ExifTool availability for metadata operations
/// 4. **Performance Settings**: Configure memory limits and processing constraints
///
/// **EXIFTOOL INTEGRATION:**
/// - Checks for ExifTool installation in system PATH
/// - Gracefully handles missing ExifTool (disables EXIF features)
/// - Provides clear feedback about metadata processing capabilities
///
/// **GLOBAL STATE MANAGEMENT:**
/// - Sets verbose logging flag for detailed output
/// - Configures file size limits for low-memory systems
/// - Initializes performance monitoring and progress tracking
///
/// @param config Processing configuration with user preferences
Future<void> _configureDependencies(final ProcessingConfig config) async {
  // Set up global verbose mode
  bool isDebugMode = false;
  assert(() {
    isDebugMode = true;
    return true;
  }(), 'Debug mode assertion');
  if (config.verbose || isDebugMode) {
    ServiceContainer.instance.globalConfig.isVerbose = true;
    _logger.info('Verbose mode active!');
  }
  // Set global file size enforcement
  if (config.limitFileSize) {
    ServiceContainer.instance.globalConfig.enforceMaxFileSize = true;
  }

  // Log ExifTool status (already set during ServiceContainer initialization)
  if (ServiceContainer.instance.exifTool != null) {
    print('Exiftool found! Continuing with EXIF support...');
  } else {
    print('Exiftool not found! Continuing without EXIF support...');
  }

  // EXTRA: let the user know if we have a file dates dictionary loaded
  final dict = ServiceContainer.instance.globalConfig.fileDatesDictionary;
  if (dict != null) {
    _logger.info('fileDates dictionary is loaded with ${dict.length} entries.');
  } else {
    _logger.info('fileDates dictionary not loaded.');
  }

  sleep(const Duration(seconds: 3));
}

/// **MAIN PROCESSING PIPELINE EXECUTION**
///
/// Executes the core photo processing workflow using the ProcessingPipeline.
/// This is where the actual work happens - transforming Google Photos Takeout
/// data into an organized photo library.
///
/// **PRE-PROCESSING VALIDATION:**
/// - Input directory existence verification
/// - Output directory preparation and cleanup handling
/// - User confirmation for destructive operations
///
/// **PIPELINE EXECUTION:**
/// The ProcessingPipeline orchestrates 8 sequential steps:
/// 1. Fix Extensions - Correct mismatched file extensions
/// 2. Discover Media - Find and classify all media files
/// 3. Remove Duplicates - Remove duplicate files
/// 4. Extract Dates - Determine accurate timestamps
/// 5. Write EXIF - Embed metadata into files
/// 6. Find Albums - Merge album relationships
/// 7. Move Files - Organize files to output structure
/// 8. Update Creation Time - Sync timestamps (Windows only)
///
/// **ERROR HANDLING:**
/// - Each step can fail independently with proper error reporting
/// - Critical steps halt processing on failure
/// - Non-critical steps continue processing with warnings
/// - Comprehensive error logging for troubleshooting
///
/// **PROGRESS TRACKING:**
/// - Real-time progress reporting for each step
/// - Timing information for performance analysis
/// - Statistics collection throughout processing
///
/// @param config Validated processing configuration
/// @returns ProcessingResult with comprehensive statistics and status
Future<ProcessingResult> _executeProcessing(
  final ProcessingConfig config,
) async {
  Directory inputDir = Directory(config.inputPath);
  final outputDir = Directory(config.outputPath);

  // Validate directories
  if (!await inputDir.exists()) {
    _logger.error('Input folder does not exist :/');
    _exitWithMessage(11, 'Input folder does not exist: ${inputDir.path}');
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Early ZIP auto-extraction inside execute() to prevent wrong cloning decision
  // This is a safety net for scenarios where the config still has inputExtractedFromZip=false
  // but the userInputRoot actually contains ZIP files that must be extracted first.
  // ─────────────────────────────────────────────────────────────────────────────

  bool extractedNow = false;
  String effectiveUserRoot = config.userInputRoot;
  if (!config.inputExtractedFromZip) {
    try {
      final root = Directory(config.userInputRoot);
      if (await root.exists()) {
        final zips = <File>[];
        await for (final ent in root.list(followLinks: false)) {
          if (ent is File && path.extension(ent.path).toLowerCase() == '.zip') {
            zips.add(ent);
          }
        }
        if (zips.isNotEmpty) {
          final extractDir = Directory(path.join(root.path, '.gpth-unzipped'));
          _logger.info('Found ${zips.length} ZIP file(s) under userInputRoot - extracting to ${extractDir.path} before processing', forcePrint: true);

          // Compute rough required space and log
          var cumZipsSize = 0;
          for (final z in zips) {
            try { cumZipsSize += z.lengthSync(); } catch (_) {}
          }
          final requiredSpace = (cumZipsSize * 2) + 256 * 1024 * 1024;
          _logger.info('Estimated required temporary space for extraction: ${requiredSpace ~/ (1024 * 1024)} MB', forcePrint: true);

          await ServiceContainer.instance.interactiveService.extractAll(zips, extractDir);
          effectiveUserRoot = extractDir.path;

          // Re-resolve Google Photos path inside the extraction dir
          final resolvedInside = PathResolverService.resolveGooglePhotosPath(extractDir.path);
          inputDir = Directory(resolvedInside);
          extractedNow = true;
          _logger.info('Extraction completed in execute(); effective input is now $resolvedInside', forcePrint: true);
        }
      }
    } catch (e) {
      _logger.error('Late ZIP extraction failed inside execute(): $e', forcePrint: true);
      _exitWithMessage(12, 'Late ZIP extraction failed: ${e.toString()}');
    }
  }

  // NEW: honor keep-input but avoid cloning when input was (now) extracted from ZIPs
  final bool inputExtractedFromZipFlag = config.inputExtractedFromZip || extractedNow;

  // Log de diagnóstico para confirmar decisión de clonado
  final bool shouldClone = config.keepInput && !inputExtractedFromZipFlag;
  _logger.info('keepInput=${config.keepInput}, inputExtractedFromZip=$inputExtractedFromZipFlag, shouldClone=$shouldClone', forcePrint: true);
  _logger.info('Creating input clone because keepInput=true and input does not come from ZIP extraction (inputExtractedFromZip=false).', forcePrint: true);

  Directory effectiveInputDir = inputDir;

  if (shouldClone) {
    final cloner = InputCloneService();
    // Clone the **original user root**, not the already resolved Google Photos subfolder
    final Directory clonedRoot = await cloner.cloneToSiblingTmp(Directory(effectiveUserRoot));
    _logger.info('Using temporary input copy root: ${clonedRoot.path}');
    effectiveUserRoot = clonedRoot.path;

    // Now resolve the Google Photos subfolder INSIDE the clone for the pipeline
    final String resolvedInsideClone = PathResolverService.resolveGooglePhotosPath(clonedRoot.path);
    effectiveInputDir = Directory(resolvedInsideClone);
    _logger.info('Effective input inside clone: $resolvedInsideClone');
  } else if (config.keepInput && inputExtractedFromZipFlag) {
    // Explicit message explaining why we skip clone
    _logger.info('Skipping clone because input comes from ZIP extraction (inputExtractedFromZip=true).', forcePrint: true);
  }

  // IMPORTANT: from here on, use a runtimeConfig that reflects the effective input dir
  final ProcessingConfig runtimeConfig = (shouldClone || extractedNow)
      ? config.copyWith(
          inputPath: effectiveInputDir.path,
          userInputRoot: effectiveUserRoot,
          inputExtractedFromZip: inputExtractedFromZipFlag,
        )
      : config;

  // Handle output directory cleanup if needed (compare against runtimeConfig.inputPath)
  if (await outputDir.exists() && !await _isOutputDirectoryEmpty(outputDir, runtimeConfig)) {
    if (runtimeConfig.isInteractiveMode) {
      // Interactivo: pregunta antes de limpiar
      if (await ServiceContainer.instance.interactiveService.askForCleanOutput()) {
        await _cleanOutputDirectory(outputDir, runtimeConfig);
      }
    } else {
      // No interactivo: limpiar siempre automáticamente
      _logger.info('Output directory is not empty. Cleaning it automatically (non-interactive mode).');
      await _cleanOutputDirectory(outputDir, runtimeConfig);
    }
  }

  await outputDir.create(recursive: true);

  // Execute the processing pipeline
  final pipeline = ProcessingPipeline(
    interactiveService: ServiceContainer.instance.interactiveService,
  );
  return pipeline.execute(
    config: runtimeConfig,
    inputDirectory: Directory(runtimeConfig.inputPath), // passes the effective folder (cloned/extracted if applies)
    outputDirectory: outputDir,
  );
}


/// **OUTPUT DIRECTORY VALIDATION**
///
/// Checks if the output directory is empty or only contains the input folder.
/// This prevents accidental data loss by ensuring the user is aware of existing
/// content that might be overwritten during processing.
///
/// **VALIDATION LOGIC:**
/// - Considers directory empty if it has no files/folders
/// - Allows input folder to exist inside output folder (common scenario)
/// - Uses absolute paths to handle relative path edge cases
/// - Provides basis for cleanup confirmation prompts
///
/// @param outputDir The output directory to check
/// @param config Processing configuration with input path
/// @returns true if directory is empty (safe to proceed)
Future<bool> _isOutputDirectoryEmpty(
  final Directory outputDir,
  final ProcessingConfig config,
) => outputDir
    .list()
    .where((final e) => path.absolute(e.path) != path.absolute(config.inputPath))
    .isEmpty;

/// **OUTPUT DIRECTORY CLEANUP**
///
/// Safely removes existing content from the output directory while preserving
/// the input folder if it exists inside the output directory. This handles
/// the common case where users extract Google Takeout files directly into
/// their desired output location.
///
/// **SAFETY MEASURES:**
/// - Only removes items that are not the input directory
/// - Uses absolute path comparison to prevent accidental deletion
/// - Removes both files and directories recursively
/// - Called only after user confirmation
///
/// @param outputDir The output directory to clean
/// @param config Processing configuration with input path
Future<void> _cleanOutputDirectory(
  final Directory outputDir,
  final ProcessingConfig config,
) async {
  await for (final file in outputDir.list().where(
    (final e) => path.absolute(e.path) != path.absolute(config.inputPath),
  )) {
    await file.delete(recursive: true);
  }
}

/// **FINAL RESULTS DISPLAY**
///
/// Presents comprehensive processing results and statistics to the user.
/// This provides transparency about what was accomplished and helps users
/// understand the scope and success of the processing operation.
///
/// **STATISTICS CATEGORIES:**
/// - **File Operations**: Creation time updates, duplicate removal
/// - **Metadata Processing**: EXIF coordinate and timestamp writing
/// - **File Corrections**: Extension fixes and format transformations
/// - **Content Filtering**: Extra files skipped during processing
/// - **Date Extraction**: Statistics by extraction method used
/// - **Performance**: Total processing time and efficiency metrics
///
/// **DISPLAY LOGIC:**
/// - Only shows statistics for operations that actually occurred
/// - Groups related statistics for easier reading
/// - Provides clear labels and units for all metrics
/// - Uses consistent formatting for professional appearance
///
/// **EXIT HANDLING:**
/// - Success: Exit code 0 for successful processing
/// - Failure: Exit code 1 for processing failures
/// - Provides clear indication of overall operation success
///
/// **ACKNOWLEDGMENTS:**
/// - Shows appreciation message and donation links
/// - Recognizes the significant development effort invested
/// - Encourages user support for continued development
///
/// @param config Processing configuration for context
/// @param result Comprehensive processing results and statistics
void _showResults(
  final ProcessingConfig config,
  final ProcessingResult result,
) {
  const barWidth = 50;

  print('');
  print('=' * barWidth);
  print('DONE! FREEEEEDOOOOM!!!');
  print('Some statistics for the achievement hunters:');

  if (result.creationTimesUpdated > 0) {
    print(
      '${result.creationTimesUpdated} files had their CreationDate updated',
    );
  }
  if (result.duplicatesRemoved > 0) {
    print('${result.duplicatesRemoved} duplicates were found and skipped');
  }
  if (result.coordinatesWrittenToExif > 0) {
    print(
      '${result.coordinatesWrittenToExif} files got their coordinates set in EXIF data (from json)',
    );
  }
  if (result.dateTimesWrittenToExif > 0) {
    print(
      '${result.dateTimesWrittenToExif} files got their DateTime set in EXIF data',
    );
  }
  if (result.extensionsFixed > 0) {
    print('${result.extensionsFixed} files got their extensions fixed');
  }
  if (result.extrasSkipped > 0) {
    print('${result.extrasSkipped} extras were skipped');
  }

  // Show extraction method statistics
  if (result.extractionMethodStats.isNotEmpty) {
    print('DateTime extraction method statistics:');
    for (final entry in result.extractionMethodStats.entries) {
      print('${entry.key.name}: ${entry.value} files');
    }
  }

  final totalMinutes = result.totalProcessingTime.inMinutes;
  print('In total GPTH took $totalMinutes minutes to complete');

  print('=' * barWidth);

  // Final exit with descriptive message based on processing result
  final exitCode = result.isSuccess ? 0 : 1;
  final exitMessage = result.isSuccess
      ? 'Processing completed successfully'
      : 'Processing completed with errors - check logs above for details';

  if (!result.isSuccess) {
    stderr.writeln('[PROCESSING_RESULT] $exitMessage');
  } else {
    print('[SUCCESS] $exitMessage');
  }

  exit(exitCode);
}

/// Helper to load the optional external dates dictionary into GlobalConfig
/// after the ServiceContainer has been re-initialized with the final logger.
Future<void> _loadFileDatesIntoGlobalConfigFromArgs(
  final List<String> parsedArguments,
) async {
  try {
    final parser = _createArgumentParser();
    final res = parser.parse(parsedArguments);
    final String? jsonPath = res['fileDates'] as String?;
    if (jsonPath == null) {
      _logger.info(
        '--fileDates not provided; skipping external dictionary load.',
        forcePrint: true,
      );
      return;
    }

    _logger.info(
      'Attempting to load fileDates JSON from: $jsonPath',
      forcePrint: true,
    );

    final file = File(jsonPath);
    if (!await file.exists()) {
      _logger.error(
        'Failed to load fileDates JSON: file does not exist at "$jsonPath"',
        forcePrint: true,
      );
      return;
    }

    final jsonString = await file.readAsString();
    final dynamic raw = jsonDecode(jsonString);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'Top-level JSON must be an object/dictionary.',
      );
    }

    // Ensure Map<String, Map<String, dynamic>>-like structure (skip non-map values)
    final Map<String, Map<String, dynamic>> normalized = {};
    raw.forEach((final k, final v) {
      if (v is Map<String, dynamic>) {
        normalized[k] = v;
      } else if (v is Map) {
        final m = <String, dynamic>{};
        v.forEach((final kk, final vv) => m[kk.toString()] = vv);
        normalized[k] = m;
      } else {
        // skip non-map entries
      }
    });

    ServiceContainer.instance.globalConfig.fileDatesDictionary = normalized;
    _logger.info(
      'Loaded ${normalized.length} entries from $jsonPath',
      forcePrint: true,
    );
  } catch (e) {
    _logger.error('Failed to load fileDates JSON: $e', forcePrint: true);
  }
}
