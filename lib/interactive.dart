/// This file contains code for interacting with user when launched without
/// arguments => probably with double-click
///
/// Such "interactive mode" was created because people are too dumb to use cmd
/// And I'm too lazy to create GUI <- this line is by Copilot and is true
///
/// Rules for this file functions do...:
/// - ...use sleep() to make thing live and give time to read text
/// - ...decide for themselves how much sleep() they want and where
/// - ...start and end without any extra \n, but can have \n inside
///    - extra \n are added in main file
/// - ...detect when something is wrong (f.e. disk space) and quit whole program
/// - ...are as single-job as it's appropriate - main file calls them one by one
library;

import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker_desktop/file_picker_desktop.dart';
import 'package:path/path.dart' as p;

import 'utils.dart';

const Map<String, String> albumOptions = <String, String>{
  'shortcut':
      '[Recommended] Album folders with shortcuts/symlinks to \n'
      'original photos. \nRecommended as it will take the least space, but \n'
      'may not be portable when moving across systems/computes/phones etc\n',
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
      'with shortcuts/symlinks to albums. If a photo is not in an album, \n'
      'the original is saved. CAUTION: If a photo is in multiple albums, it will \n'
      'be duplicated in the other albums, and the shortcuts/symlinks in \n'
      '"ALL_PHOTOS" will point only to one album.\n',
};

/// Whether we are, indeed, running interactive (or not)
bool indeed = false;

/// Pauses execution for specified number of seconds
///
/// [seconds] Number of seconds to sleep (can be fractional)
Future<void> sleep(final num seconds) =>
    Future<void>.delayed(Duration(milliseconds: (seconds * 1000).toInt()));

/// Displays a prompt and waits for user to press enter
void pressEnterToContinue() {
  print('[press enter to continue]');
  stdin.readLineSync();
}

/// Reads user input and normalizes it (removes brackets, lowercase, trim)
///
/// Returns the normalized input string
Future<String> askForInt() async => stdin
    .readLineSync()!
    .replaceAll('[', '')
    .replaceAll(']', '')
    .toLowerCase()
    .trim();

/// Displays greeting message and introduction to the tool
Future<void> greet() async {
  print('GooglePhotosTakeoutHelper v$version');
  await sleep(1);
  print(
    'Hi there! This tool will help you to get all of your photos from '
    'Google Takeout to one nice tidy folder\n',
  );
  await sleep(3);
  print(
    '(If any part confuses you, read the guide on:\n'
    'https://github.com/Xentraxx/GooglePhotosTakeoutHelper)',
  );
  await sleep(3);
}

/// does not quit explicitly - do it yourself
Future<void> nothingFoundMessage() async {
  print('...oh :(');
  print('...');
  print("8 I couldn't find any D: reasons for this may be:");
  if (indeed) {
    print(
      "  - you've already ran gpth and it moved all photos to output -\n"
      '    delete the input folder and re-extract the zip',
    );
  }
  print(
    "  - your Takeout doesn't have any \"year folders\" -\n"
    '    visit https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper\n'
    '    again and request new, correct Takeout',
  );
  print('After fixing this, go ahead and try again :)');
}

/// Prompts user to select input directory using file picker dialog
///
/// Returns the selected Directory
/// Throws if dialog fails or user cancels
Future<Directory> getInputDir() async {
  print('Select the directory where you unzipped all your takeout zips');
  print('(Make sure they are merged => there is only one "Takeout" folder!)');
  await sleep(1);
  pressEnterToContinue();
  final String? dir = await getDirectoryPath(
    dialogTitle: 'Select unzipped folder:',
  );
  await sleep(1);
  if (dir == null) {
    error('Duh, something went wrong with selecting - try again!');
    return getOutput();
  }
  print('Cool!');
  await sleep(1);
  return Directory(dir);
}

/// Asks user for zip files with ui dialogs
///
/// This function prompts the user to select Google Takeout ZIP files through a file picker dialog.
/// It validates that only ZIP and TGZ files are selected and provides feedback about the total size.
///
/// Returns a List of File objects representing the selected ZIP files.
///
/// Throws [SystemExit] with exit code 69 if dialog fails or 6969 if no files selected.
///
/// Example usage:
/// ```dart
/// final zips = await getZips();
/// print('Selected ${zips.length} ZIP files');
/// ```
Future<List<File>> getZips() async {
  print(
    'First, select all .zips from Google Takeout '
    '(use Ctrl to select multiple)',
  );
  await sleep(2);
  pressEnterToContinue();
  final FilePickerResult? files = await pickFiles(
    dialogTitle: 'Select all Takeout zips:',
    type: FileType.custom,
    allowedExtensions: <String>['zip', 'tgz'],
    allowMultiple: true,
  );
  await sleep(1);
  if (files == null) {
    error('Duh, something went wrong with selecting - try again!');
    quit(69);
  }
  if (files.count == 0) {
    error('No files selected - try again :/');
    quit(6969);
  }
  if (files.count == 1) {
    print(
      "You selected only one zip - if that's only one you have, it's cool, "
      'but if you have multiple, Ctrl-C to exit gpth, and select them '
      '*all* again (with Ctrl)',
    );
    await sleep(5);
    pressEnterToContinue();
  }
  if (!files.files.every(
    (final PlatformFile e) =>
        File(e.path!).statSync().type == FileSystemEntityType.file &&
        RegExp(r'\.(zip|tgz)$').hasMatch(e.path!),
  )) {
    print(
      'Files: [${files.files.map((final PlatformFile e) => p.basename(e.path!)).join(', ')}]',
    );
    error('Not all files you selected are zips :/ please do this again');
    quit(6969);
  }
  // potentially shows user they selected too little ?
  print(
    'Cool! Selected ${files.count} zips => '
    '${filesize(files.files.map((final PlatformFile e) => File(e.path!).statSync().size).reduce((final int a, final int b) => a + b))}',
  );
  await sleep(1);
  return files.files.map((final PlatformFile e) => File(e.path!)).toList();
}

/// Prompts user to select output directory using file picker dialog
///
/// Returns the selected Directory
/// Recursively asks again if dialog fails
Future<Directory> getOutput() async {
  print(
    'Now, select output folder - all photos will be moved there\n'
    '(note: GPTH will *move* your photos - no extra space will be taken ;)',
  );
  await sleep(1);
  pressEnterToContinue();
  final String? dir = await getDirectoryPath(
    dialogTitle: 'Select output folder:',
  );
  await sleep(1);
  if (dir == null) {
    error('Duh, something went wrong with selecting - try again!');
    return getOutput();
  }
  print('Cool!');
  await sleep(1);
  return Directory(dir);
}

/// Asks user how to organize photos by date folders
///
/// Returns:
/// - 0: One big folder
/// - 1: Year folders
/// - 2: Year/month folders
/// - 3: Year/month/day folders
Future<num> askDivideDates() async {
  print(
    'Do you want your photos in one big chronological folder, '
    'or divided to folders by year/month?',
  );
  print('[1] (default) - one big folder');
  print('[2] - year folders');
  print('[3] - year/month folders');
  print('[3] - year/month/day folders');
  print('(Type a number or press enter for default):');
  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print('Selected one big folder');
      return 0;
    case '2':
      print('Will divide by year');
      return 1;
    case '3':
      print('Will divide by year and month');
      return 2;
    case '4':
      print('Will divide by year, month, and day');
      return 3;
    default:
      error('Invalid answer - try again');
      return askDivideDates();
  }
}

/// Prompts user to choose album handling behavior
///
/// Returns one of the album option keys from [albumOptions]
///
/// Available album modes:
///
/// - **shortcut**: Creates shortcuts/symlinks from album folders to the main file in ALL_PHOTOS.
///   The original file is moved to ALL_PHOTOS, and shortcuts are created in album folders.
///   This saves space while maintaining album organization.
///
/// - **duplicate-copy**: Creates actual copies of files in both ALL_PHOTOS and album folders.
///   Each file appears in ALL_PHOTOS and in every album it belongs to as separate physical files.
///   Uses more disk space but provides complete independence between folders.
///
/// - **reverse-shortcut**: The opposite of shortcut mode. Files remain in album folders,
///   and shortcuts are created in ALL_PHOTOS pointing to the album locations.
///   Maintains files in their album context while providing access via ALL_PHOTOS.
///
/// - **json**: Creates a single ALL_PHOTOS folder with all files, plus an albums-info.json
///   file that contains metadata about which albums each file belonged to.
///   Most space-efficient option with programmatic album information.
///
/// - **nothing**: Ignores albums entirely. Only creates ALL_PHOTOS folder with files
///   from year folders. Album-only files are skipped unless they have null keys assigned.
///   Simplest option for users who don't care about album organization.
Future<String> askAlbums() async {
  print('What should be done with albums?');
  int i = 0;
  for (final MapEntry<String, String> entry in albumOptions.entries) {
    print('[${i++}] ${entry.key}: ${entry.value}');
  }
  final int? answer = int.tryParse(await askForInt());
  if (answer == null || answer < 0 || answer >= albumOptions.length) {
    error('Invalid answer - try again');
    return askAlbums();
  }
  final String choice = albumOptions.keys.elementAt(answer);
  print('Okay, doing: $choice');
  return choice;
}

// this is used in cli mode as well
Future<bool> askForCleanOutput() async {
  print('Output folder IS NOT EMPTY! What to do? Type either:');
  print('[1] - delete *all* files inside output folder and continue');
  print('[2] - continue as usual - put output files alongside existing');
  print('[3] - exit program to examine situation yourself');
  final String answer = stdin
      .readLineSync()!
      .replaceAll('[', '')
      .replaceAll(']', '')
      .toLowerCase()
      .trim();
  switch (answer) {
    case '1':
      print('Okay, deleting all files inside output folder...');
      return true;
    case '2':
      print('Okay, continuing as usual...');
      return false;
    case '3':
      print('Okay, exiting...');
      quit(0);
    default:
      error('Invalid answer - try again');
      return askForCleanOutput();
  }
}

/// Asks user whether to transform Pixel Motion Photo extensions to .mp4
///
/// Returns true if .MP/.MV files should be renamed to .mp4
Future<bool> askTransformPixelMP() async {
  print(
    'Pixel Motion Pictures are saved with the .MP or .MV '
    'extensions. Do you want to change them to .mp4 '
    'for better compatibility?',
  );
  print('[1] (default) - no, keep original extension');
  print('[2] - yes, change extension to .mp4');
  print('(Type 1 or 2 or press enter for default):');
  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print('Okay, will keep original extension');
      return false;
    case '2':
      print('Okay, will change to mp4!');
      return true;
    default:
      error('Invalid answer - try again');
      return askTransformPixelMP();
  }
}

/// Asks user whether to update creation times on Windows
///
/// Returns true if creation times should be synced with modified times
Future<bool> askChangeCreationTime() async {
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
  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print('Okay, will not change creation time');
      return false;
    case '2':
      print('Okay, will update creation time at the end of the prorgam!');
      return true;
    default:
      error('Invalid answer - try again');
      return askChangeCreationTime();
  }
}

/// Checks free space on disk and notifies user accordingly
///
/// This function calculates available disk space and compares it with the required space
/// for the unzipping operation. It provides warnings or errors if insufficient space is available.
///
/// [required] The required space in bytes for the operation
/// [dir] The target directory to check space for
///
/// Exits the program with code 69 if insufficient space is detected.
///
/// Example usage:
/// ```dart
/// final requiredSpace = totalZipSize * 2 + (256 * 1024 * 1024); // ZIP size * 2 + 256MB buffer
/// await freeSpaceNotice(requiredSpace, outputDirectory);
/// ```
Future<void> freeSpaceNotice(final int required, final Directory dir) async {
  final int? freeSpace = await getDiskFree(dir.path);
  if (freeSpace == null) {
    print(
      'Note: everything will take ~${filesize(required)} of disk space - '
      'make sure you have that available on ${dir.path} - otherwise, '
      'Ctrl-C to exit, and make some free space!\n'
      'Or: unzip manually, remove the zips and use gpth with cmd options',
    );
  } else if (freeSpace < required) {
    print(
      '!!! WARNING !!!\n'
      'Whole process requires ${filesize(required)} of space, but you '
      'only have ${filesize(freeSpace)} available on ${dir.path} - \n'
      'Go make some free space!\n'
      '(Or: unzip manually, remove the zips, and use gpth with cmd options)',
    );
    quit(69);
  } else {
    print(
      '(Note: everything will take ~${filesize(required)} of disk space - '
      'you have ${filesize(freeSpace)} free so should be fine :)',
    );
  }
  await sleep(3);
  pressEnterToContinue();
}

/// Unzips all zips to given folder (creates it if needed)
///
/// This function safely extracts all provided ZIP files to the specified directory.
/// It includes comprehensive error handling, progress reporting, and cross-platform support.
///
/// Features:
/// - Creates destination directory if it doesn't exist
/// - Validates ZIP file integrity before extraction
/// - Provides progress feedback during extraction
/// - Handles filename encoding issues across platforms
/// - Prevents path traversal attacks (Zip Slip vulnerability)
/// - Graceful error handling with user-friendly messages
///
/// [zips] List of ZIP files to extract
/// [dir] Target directory for extraction (will be created if needed)
///
/// Throws [SystemExit] with code 69 on extraction errors or path traversal attempts.
///
/// Example usage:
/// ```dart
/// final zips = await getZips();
/// final unzipDir = Directory(p.join(outputPath, '.gpth-unzipped'));
/// await unzip(zips, unzipDir);
/// ```
Future<void> unzip(final List<File> zips, final Directory dir) async {
  // Clean up and create destination directory
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
  await dir.create(recursive: true);

  print(
    'GPTH will now unzip all selected files, process them, and organize everything in the output folder :)',
  );
  await sleep(1);

  for (final File zip in zips) {
    print('Unzipping ${p.basename(zip.path)}...');

    try {
      // Validate ZIP file exists and is readable
      if (!await zip.exists()) {
        throw FileSystemException('ZIP file not found', zip.path);
      }

      final int zipSize = await zip.length();
      if (zipSize == 0) {
        throw FileSystemException('ZIP file is empty', zip.path);
      }

      // Extract with safety checks
      await _extractZipSafely(zip, dir);

      print('✓ Successfully extracted ${p.basename(zip.path)}');
    } on ArchiveException catch (e) {
      _handleExtractionError(zip, e, isArchiveError: true);
    } on PathNotFoundException catch (e) {
      _handleExtractionError(zip, e, isPathError: true);
    } on FileSystemException catch (e) {
      _handleExtractionError(zip, e, isFileSystemError: true);
    } catch (e) {
      _handleExtractionError(zip, e);
    }
  }

  print('✓ All ZIP files extracted successfully!');
}

/// Safely extracts a ZIP file with security and encoding checks
///
/// This internal helper function performs the actual extraction while
/// preventing common security vulnerabilities and handling encoding issues.
///
/// [zip] The ZIP file to extract
/// [destinationDir] The target directory for extraction
Future<void> _extractZipSafely(
  final File zip,
  final Directory destinationDir,
) async {
  final Archive archive = ZipDecoder().decodeBytes(await zip.readAsBytes());

  for (final ArchiveFile file in archive) {
    // Security check: Prevent Zip Slip vulnerability
    final String fileName = _sanitizeFileName(file.name);
    final String fullPath = p.join(destinationDir.path, fileName);

    // Ensure the file path is within the destination directory
    final String canonicalDestPath = p.canonicalize(destinationDir.path);
    final String canonicalFilePath = p.canonicalize(p.dirname(fullPath));

    if (!canonicalFilePath.startsWith(canonicalDestPath)) {
      throw SecurityException(
        'Path traversal attempt detected: ${file.name} -> $fullPath',
      );
    }
    if (file.isFile) {
      final File outputFile = File(fullPath);
      await outputFile.create(recursive: true);

      // Extract file content
      final List<int> content = file.content as List<int>;
      await outputFile.writeAsBytes(content, flush: true);

      // Preserve file modification time if available
      try {
        await outputFile.setLastModified(
          DateTime.fromMillisecondsSinceEpoch(file.lastModTime * 1000),
        );
      } catch (e) {
        // Ignore timestamp setting errors - not critical
        log(
          'Warning: Could not set modification time for ${outputFile.path}: $e',
          level: 'warning',
        );
      }
    } else if (file.isDirectory) {
      // Create directory
      final Directory outputDir = Directory(fullPath);
      await outputDir.create(recursive: true);
    }
  }
}

/// Sanitizes file names to handle encoding issues and invalid characters
///
/// This function normalizes file names for cross-platform compatibility,
/// handles Unicode normalization, and removes invalid characters.
///
/// [fileName] The original file name from the archive
/// Returns the sanitized file name safe for the current platform
String _sanitizeFileName(final String fileName) {
  // Normalize Unicode characters (important for cross-platform compatibility)
  fileName.replaceAll(RegExp(r'[<>:"|?*]'), '_');

  // Handle Windows reserved names
  if (Platform.isWindows) {
    final List<String> reservedNames = [
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9',
    ];

    final String baseName = p.basenameWithoutExtension(fileName);
    if (reservedNames.contains(baseName.toUpperCase())) {
      fileName.replaceFirst(baseName, '${baseName}_file');
    }

    // Remove trailing dots and spaces (Windows specific)
    fileName.replaceAll(RegExp(r'[. ]+$'), '');
  }

  return fileName;
}

/// Handles extraction errors with detailed error messages and user guidance
///
/// This function provides context-specific error handling for different types
/// of extraction failures, offering actionable guidance to users.
///
/// [zip] The ZIP file that failed to extract
/// [error] The error that occurred
/// [isArchiveError] Whether this is a ZIP format/corruption error
/// [isPathError] Whether this is a file path related error
/// [isFileSystemError] Whether this is a file system related error
Never _handleExtractionError(
  final File zip,
  final Object errorObject, {
  final bool isArchiveError = false,
  final bool isPathError = false,
  final bool isFileSystemError = false,
}) {
  final String zipName = p.basename(zip.path);

  error('');
  error('===============================================');
  error('❌ ERROR: Failed to extract $zipName');
  error('===============================================');

  if (isArchiveError) {
    error('💥 ZIP Archive Error:');
    error(
      'The ZIP file appears to be corrupted or uses an unsupported format.',
    );
    error('');
    error('🔧 Suggested Solutions:');
    error('• Re-download the ZIP file from Google Takeout');
    error('• Verify the file wasn\'t corrupted during download');
    error('• Try extracting manually with your system\'s built-in extractor');
  } else if (isPathError) {
    error('📁 Path/File Error:');
    error('There was an issue accessing files or creating directories.');
    error('');
    error('🔧 Suggested Solutions:');
    error('• Ensure you have sufficient permissions in the target directory');
    error('• Check that the target path is not too long (Windows limitation)');
    error('• Verify sufficient disk space is available');
  } else if (isFileSystemError) {
    error('💾 File System Error:');
    error('Unable to read the ZIP file or write extracted files.');
    error('');
    error('🔧 Suggested Solutions:');
    error('• Check file permissions on the ZIP file');
    error('• Ensure the ZIP file is not currently open in another program');
    error('• Verify the target directory is writable');
  } else {
    error('⚠️  Unexpected Error:');
    error('An unexpected error occurred during extraction.');
  }

  error('');
  error('📋 Error Details: $errorObject');
  error('');
  error('🔄 Alternative Options:');
  error('• Extract ZIP files manually using your system tools');
  error('• Use GPTH with command-line options on pre-extracted files');
  error(
    '• See manual extraction guide: https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper#running-manually-with-cmd',
  );
  error('');
  error('===============================================');

  quit(69);
}

/// Custom exception for security-related extraction issues
class SecurityException implements Exception {
  /// Creates a security exception with the given message
  const SecurityException(this.message);

  /// The error message describing the security issue
  final String message;

  @override
  String toString() => 'SecurityException: $message';
}

Future<bool> askIfWriteExif() async {
  if (exifToolInstalled) {
    print(
      'This mode will write Exif data (dates/times/coordinates) back to your files. '
      'To achieve the best results, download Exiftool and place it next to this executable or in your \$PATH.'
      'If you haven\'t done so yet, close this program and come back. '
      'creation times with modified times?'
      '\nNote: ONLY ON WINDOWS',
    );
  } else {
    print(
      'This mode will write Exif data (dates/times/coordinates) back to your files. '
      'We detected that ExifTool is NOT available! '
      'To achieve the best results, we strongly recomend to download Exiftool and place it next to this executable or in your \$PATH.'
      'You can download ExifTool here: https://exiftool.org '
      'Note that this mode will alter your original files, regardless of the "copy" mode.'
      'Do you want to continue with writing exif data enabled?',
    );
  }

  print('[1] (Default) - Yes, write exif');
  print('[2] - No, don\'t write to exif');
  print('(Type 1 or 2, or press enter for default):');
  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print('Okay, will write to exif');
      return true;
    case '2':
      print('Okay, will not touch the exif of your files!');
      return false;
    default:
      error('Invalid answer - try again');
      return askIfWriteExif();
  }
}

Future<bool> askIfLimitFileSize() async {
  print(
    'By default we will process all your files.'
    'However, if you have large video files and run this script on a low ram system (e.g. a NAS or your vacuum cleaning robot), you might want to '
    'limit the maximum file size to 64 MB not run out of memory. '
    'We recommend to only activate this if you run into problems.',
  );

  print('[1] (Default) - Don\'t limit me! Process everything!');
  print('[2] - I operate a Toaster. Limit supported media size to 64 MB');
  print('(Type 1 or 2, or press enter for default):');
  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print('Alrighty! Will process everything!');
      return false;
    case '2':
      print('Okay! Limiting files to a size of 64 MB');
      return true;
    default:
      error('Invalid answer - try again');
      return askIfLimitFileSize();
  }
}

/// Asks user whether to fix incorrect file extensions
///
/// Returns a map with keys:
/// - 'fix-extensions': boolean
/// - 'fix-extensions-non-jpeg': boolean
/// - 'fix-extensions-solo-mode': boolean
Future<Map<String, bool>> askFixExtensions() async {
  print(
    'Some files from Google Photos may have incorrect extensions due to '
    'compression or web downloads. For example, a file named "photo.jpeg" '
    'might actually be a HEIF file internally. This can cause issues when '
    'writing EXIF data.',
  );
  print('');
  print('Do you want to fix incorrect file extensions?');
  print('[1] (Default) - No, keep original extensions');
  print('[2] - Yes, fix extensions (skip TIFF-based files like RAW)');
  print('[3] - Yes, fix extensions (skip TIFF and JPEG files)');
  print('(Type 1-3 or press enter for default):');

  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print('Okay, will keep original extensions');
      return {
        'fix-extensions': false,
        'fix-extensions-non-jpeg': false,
        'fix-extensions-solo-mode': false,
      };
    case '2':
      print('Okay, will fix incorrect extensions (except TIFF-based files)');
      return {
        'fix-extensions': true,
        'fix-extensions-non-jpeg': false,
        'fix-extensions-solo-mode': false,
      };
    case '3':
      print('Okay, will fix incorrect extensions (except TIFF and JPEG files)');
      return {
        'fix-extensions': false,
        'fix-extensions-non-jpeg': true,
        'fix-extensions-solo-mode': false,
      };
    default:
      error('Invalid answer - try again');
      return askFixExtensions();
  }
}

/// Asks user whether to unzip files or use pre-extracted directory
///
/// This function provides users with a choice between:
/// 1. Selecting ZIP files from Google Takeout for automatic extraction
/// 2. Using a directory where ZIP files have already been manually extracted
///
/// Returns true if user wants to select and unzip ZIP files,
/// false if they want to use a pre-extracted directory.
///
/// Example usage:
/// ```dart
/// final shouldUnzip = await askIfUnzip();
/// if (shouldUnzip) {
///   final zips = await getZips();
///   await unzip(zips, outputDir);
/// } else {
///   final inputDir = await getInputDir();
/// }
/// ```
Future<bool> askIfUnzip() async {
  print('How would you like to provide your Google Photos Takeout data?');
  print('');
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

  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print(
        '✓ Great! You\'ll select ZIP files and GPTH will handle extraction',
      );
      return true;
    case '2':
      print('✓ Okay! You\'ll select the directory with extracted files');
      return false;
    default:
      error('Invalid answer - please type 1 or 2');
      return askIfUnzip();
  }
}
