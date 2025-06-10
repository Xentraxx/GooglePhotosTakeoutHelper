import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:proper_filesize/proper_filesize.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import 'extras.dart';
import 'package:win32/win32.dart';
import 'interactive.dart' as interactive;
import 'media.dart';

// remember to bump this
const String version = '4.0.6';

// Processing constants
const int defaultBarWidth = 40;
const int defaultMaxFileSize = 64 * 1024 * 1024; // 64MB

// Cached GUIDs for performance (avoid repeated parsing)
const String _clsidShellLinkString = '{00021401-0000-0000-C000-000000000046}';
const String _iidShellLinkString = '{000214F9-0000-0000-C000-000000000046}';
const String _iidPersistFileString = '{0000010b-0000-0000-C000-000000000046}';

//initialising some global variables
bool isVerbose = false;

bool enforceMaxFileSize = false;

bool exifToolInstalled = false;

/// Prints error message to stderr with newline
void error(final Object? object) => stderr.write('$object\n');

/// Exits the program with optional code, showing interactive message if needed
///
/// [code] Exit code (default: 1)
Never quit([final int code = 1]) {
  if (interactive.indeed) {
    print(
      '[gpth ${code != 0 ? 'quitted :(' : 'finished :)'} (code $code) - '
      'press enter to close]',
    );
    stdin.readLineSync();
  }
  exit(code);
}

//Support raw formats (dng, cr2) and Pixel motion photos (mp, mv)
//CR2: https://github.com/dart-lang/tools/pull/2105
const List<String> _moreExtensions = <String>['.mp', '.mv', '.dng', '.cr2'];

extension X on Iterable<FileSystemEntity> {
  /// Easy extension allowing you to filter for files that are photo or video
  Iterable<File> wherePhotoVideo() => whereType<File>().where((final File e) {
    final String mime = lookupMimeType(e.path) ?? '';
    final String fileExtension = p.extension(e.path).toLowerCase();
    return mime.startsWith('image/') ||
        mime.startsWith('video/') ||
        // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/223
        // https://github.com/dart-lang/mime/issues/102
        // 🙃🙃
        mime == 'model/vnd.mts' ||
        _moreExtensions.contains(fileExtension);
  });
}

extension Y on Stream<FileSystemEntity> {
  /// Easy extension allowing you to filter for files that are photo or video
  Stream<File> wherePhotoVideo() => whereType<File>().where((final File e) {
    final String mime = lookupMimeType(e.path) ?? '';
    final String fileExtension = p.extension(e.path).toLowerCase();
    return mime.startsWith('image/') ||
        mime.startsWith('video/') ||
        // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/223
        // https://github.com/dart-lang/mime/issues/102
        // 🙃🙃
        mime == 'model/vnd.mts' ||
        _moreExtensions.contains(fileExtension);
  });
}

extension Util on Stream {
  Stream<T> whereType<T>() => where((final e) => e is T).cast<T>();
}

/// Returns disk free space in bytes for the given path
///
/// [path] Directory path to check (defaults to current directory)
/// Returns null if unable to determine free space
Future<int?> getDiskFree([String? path]) async {
  path ??= Directory.current.path;
  if (Platform.isLinux) {
    return _dfLinux(path);
  } else if (Platform.isWindows) {
    return _dfWindoza(path);
  } else if (Platform.isMacOS) {
    return _dfMcOS(path);
  } else {
    return null;
  }
}

/// Gets disk free space on Linux using df command
///
/// [path] Directory path to check
/// Returns free space in bytes or null on failure
Future<int?> _dfLinux(final String path) async {
  final ProcessResult res = await Process.run('df', <String>[
    '-B1',
    '--output=avail',
    path,
  ]);
  return res.exitCode != 0
      ? null
      : int.tryParse(
          res.stdout.toString().split('\n').elementAtOrNull(1) ?? '',
          radix: 10, // to be sure
        );
}

/// Gets disk free space on Windows using PowerShell
///
/// [path] Directory path to check
/// Returns free space in bytes or null on failure
Future<int?> _dfWindoza(final String path) async {
  final String driveLetter = p
      .rootPrefix(p.absolute(path))
      .replaceAll('\\', '')
      .replaceAll(':', '');
  final ProcessResult res = await Process.run('powershell', <String>[
    '-Command',
    'Get-PSDrive -Name ${driveLetter[0]} | Select-Object -ExpandProperty Free',
  ]);
  final int? result = res.exitCode != 0 ? null : int.tryParse(res.stdout);
  return result;
}

/// Gets disk free space on macOS using df command
///
/// [path] Directory path to check
/// Returns free space in bytes or null on failure
Future<int?> _dfMcOS(final String path) async {
  final ProcessResult res = await Process.run('df', <String>['-k', path]);
  if (res.exitCode != 0) return null;
  final String? line2 = res.stdout.toString().split('\n').elementAtOrNull(1);
  if (line2 == null) return null;
  final List<String> elements = line2.split(' ')
    ..removeWhere((final String e) => e.isEmpty);
  final int? macSays = int.tryParse(
    elements.elementAtOrNull(3) ?? '',
    radix: 10, // to be sure
  );
  return macSays != null ? macSays * 1024 : null;
}

/// Formats byte count into human-readable file size string
///
/// [bytes] Number of bytes to format
/// Returns formatted string like "1.5 MB"
String filesize(final int bytes) => FileSize.fromBytes(bytes).toString(
  unit: Unit.auto(size: bytes, baseType: BaseType.metric),
  decimals: 2,
);

/// Calculates total number of output files based on album behavior
///
/// [media] List of media objects
/// [albumOption] Album handling option ('shortcut', 'duplicate-copy', etc.)
/// Returns expected number of output files
int outputFileCount(final List<Media> media, final String albumOption) {
  if (<String>[
    'shortcut',
    'duplicate-copy',
    'reverse-shortcut',
  ].contains(albumOption)) {
    return media.fold(
      0,
      (final int prev, final Media e) => prev + e.files.length,
    );
  } else if (albumOption == 'json') {
    return media.length;
  } else if (albumOption == 'nothing') {
    return media.where((final Media e) => e.files.containsKey(null)).length;
  } else {
    throw ArgumentError.value(albumOption, 'albumOption');
  }
}

extension Z on String {
  /// Returns same string if pattern not found
  String replaceLast(final String from, final String to) {
    final int lastIndex = lastIndexOf(from);
    if (lastIndex == -1) return this;
    return replaceRange(lastIndex, lastIndex + from.length, to);
  }
}

/// Renames incorrectly named JSON files by removing supplemental metadata suffix
///
/// Searches recursively for .json files with patterns like:
/// filename.jpg.supplemental-metadata.json -> filename.jpg.json
///
/// [directory] Root directory to search recursively
Future<void> renameIncorrectJsonFiles(final Directory directory) async {
  int renamedCount = 0;
  await for (final FileSystemEntity entity in directory.list(recursive: true)) {
    if (entity is File && p.extension(entity.path) == '.json') {
      final String originalName = p.basename(entity.path);

      // Regex to dettect pattern
      final RegExp regex = RegExp(
        r'^(.*\.[a-z0-9]{3,5})\..+\.json$',
        caseSensitive: false,
      );

      final RegExpMatch? match = regex.firstMatch(originalName);
      if (match != null) {
        final String newName = '${match.group(1)}.json';
        if (newName != originalName) {
          final String newPath = p.join(p.dirname(entity.path), newName);
          final File newFile = File(newPath);

          // Verify if the file renamed already exists
          if (await newFile.exists()) {
            log(
              '[Step 1/8] Skipped renaming of json because it already exists: $newPath',
            );
          } else {
            try {
              await entity.rename(newPath);
              renamedCount++;
              log('[Step 1/8] Renamed: ${entity.path} -> $newPath');
            } on FileSystemException catch (e) {
              log(
                '[Step 1/8] While renaming json ${entity.path}: ${e.message}',
                level: 'error',
              );
            }
          }
        }
      }
    }
  }
  print(
    '[Step 1/8] Successfully renamed JSON files (suffix removed): $renamedCount',
  );
}

/// Fixes incorrectly named files by changin their extensions to what mimeType suggests
///
/// Searches recursively for non-.json files
///
/// [directory] Root directory to search recursively
/// [nonJpeg] only processes files that do not contain JPEG header
Future<void> fixIncorrectExtensions(final Directory directory,
    final bool? nonJpeg) async {
  int fixedCount = 0;
  await for (final FileSystemEntity file in directory
      .list(recursive: true)
      .wherePhotoVideo()) {
    final List<int> headerBytes = await File(file.path)
        .openRead(0, 128)
        .first;
    final String? mimeTypeFromHeader = lookupMimeType(
      file.path,
      headerBytes: headerBytes,
    );

    if (nonJpeg == true && mimeTypeFromHeader == 'image/jpeg') {
      continue; // Skip 'actual' JPEGs in non-jpeg mode
    }

    final String? mimeTypeFromExtension = lookupMimeType(file.path);

    // Since for ex. CR2 is based on TIFF and mime lib does not support RAW
    // lets skip everything that has TIFF header
    if (mimeTypeFromHeader != null && mimeTypeFromHeader != 'image/tiff' &&
        mimeTypeFromHeader != mimeTypeFromExtension) {
      final String? newExtension = extensionFromMime(mimeTypeFromHeader);

      if (newExtension == null) {
        log('Could not determine correct extension for file ${p.basename(file.path)}. Moving on..',
            level: 'warning');
        continue;
      }

      final String newFilePath = '${file.path}.$newExtension';
      final File newFile = File(newFilePath);
      final File jsonFile = File('${file.path}.json');

      if (!jsonFile.existsSync() && !isExtra(file.path)) {
        log(
            '[Step 1.5/8] unable to find matching json: ${jsonFile.path}',
            level: 'warning',
            forcePrint: true
        );
      }

      // Verify if the file renamed already exists
      if (await newFile.exists()) {
        log(
            '[Step 1.5/8] Skipped fixing extension because it already exists: $newFilePath',
            level: 'warning',
            forcePrint: true
        );
        continue;
      }

      try {
        if (jsonFile.existsSync() && !isExtra(file.path)) {
          // There is only one .json file for both original and any edited files
          await jsonFile.rename('$newFilePath.json');
          log('[Step 1.5/8] Fixed: ${jsonFile.path} -> $newFilePath.json');
        }
        await file.rename(newFilePath);
        log('[Step 1.5/8] Fixed: ${file.path} -> $newFilePath');
        fixedCount++;
      } on FileSystemException catch (e) {
        log(
            '[Step 1.5/8] While fixing extension ${file.path}: ${e.message}',
            level: 'error',
            forcePrint: true
        );
      }
    }
  }
  print(
    '[Step 1.5/8] Successfully fixed extensions: $fixedCount',
  );
}

/// Changes file extensions from .MP/.MV to specified extension (usually .mp4)
///
/// Updates Media objects in-place to reflect the new file paths
///
/// [allMedias] List of Media objects to process
/// [finalExtension] Target extension (e.g., '.mp4')
Future<void> changeMPExtensions(
  final List<Media> allMedias,
  final String finalExtension,
) async {
  int renamedCount = 0;
  for (final Media m in allMedias) {
    for (final MapEntry<String?, File> entry in m.files.entries) {
      final File file = entry.value;
      final String ext = p.extension(file.path).toLowerCase();
      if (ext == '.mv' || ext == '.mp') {
        final String originalName = p.basenameWithoutExtension(file.path);
        final String normalizedName = unorm.nfc(originalName);

        final String newName = '$normalizedName$finalExtension';
        if (newName != normalizedName) {
          final String newPath = p.join(p.dirname(file.path), newName);
          // Rename file and update reference in map
          try {
            final File newFile = await file.rename(newPath);
            m.files[entry.key] = newFile;
            renamedCount++;
          } on FileSystemException catch (e) {
            print(
              '[Step 6/8] [Error] Error changing extension to $finalExtension -> ${file.path}: ${e.message}',
            );
          }
        }
      }
    }
  }
  print(
    '[Step 6/8] Successfully changed Pixel Motion Photos files extensions (change it to $finalExtension): $renamedCount',
  );
}

/// Recursively updates creation time of files to match last modified time
///
/// Currently only supports Windows using PowerShell commands.
/// Processes files in batches to avoid command line length limits.
///
/// [directory] Root directory to process recursively
/// Returns number of files successfully updated
Future<int> updateCreationTimeRecursively(final Directory directory) async {
  if (!Platform.isWindows) {
    print(
      '[Step 8/8] Skipping: Updating creation time is only supported on Windows.',
    );
    return 0;
  }
  int changedFiles = 0;
  const int maxChunkSize =
      32000; //Avoid 32768 char limit in command line with chunks

  String currentChunk = '';
  await for (final FileSystemEntity entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) {
      //Command for each file
      final String command =
          "(Get-Item '${entity.path}').CreationTime = (Get-Item '${entity.path}').LastWriteTime;";
      //If current command + chunk is larger than 32000, commands in currentChunk is executed and current comand is passed for the next execution
      if (currentChunk.length + command.length > maxChunkSize) {
        final bool success = await _executePShellCreationTimeCmd(currentChunk);
        if (success) {
          changedFiles +=
              currentChunk.split(';').length - 1; // -1 to ignore last ';'
        }
        currentChunk = command;
      } else {
        currentChunk += command;
      }
    }
  }

  //Leftover chunk is executed after the for
  if (currentChunk.isNotEmpty) {
    final bool success = await _executePShellCreationTimeCmd(currentChunk);
    if (success) {
      changedFiles +=
          currentChunk.split(';').length - 1; // -1 to ignore last ';'
    }
  }
  print(
    '[Step 8/8] Successfully updated creation time for $changedFiles files!',
  );
  return changedFiles;
}

/// Executes a batch of PowerShell commands for updating creation times
///
/// [commandChunk] String containing multiple PowerShell commands
/// Returns true if execution was successful
Future<bool> _executePShellCreationTimeCmd(final String commandChunk) async {
  try {
    final ProcessResult result = await Process.run('powershell', <String>[
      '-ExecutionPolicy',
      'Bypass',
      '-NonInteractive',
      '-Command',
      commandChunk,
    ]);

    if (result.exitCode != 0) {
      print(
        '[Step 8/8] Error updateing creation time in batch: ${result.stderr}',
      );
      return false;
    }
    return true;
  } catch (e) {
    print('[Step 8/8] Error updating creation time: $e');
    return false;
  }
}

/// Creates a Windows shortcut (.lnk file) using native Win32 API first,
/// falling back to PowerShell if needed
///
/// [shortcutPath] Path where the shortcut will be created
/// [targetPath] Path to the target file/folder
/// Throws Exception if both native and PowerShell methods fail
Future<void> createShortcutWin(
  final String shortcutPath,
  final String targetPath,
) async {
  // Ensure target path is absolute
  final String absoluteTargetPath = p.isAbsolute(targetPath)
      ? targetPath
      : p.absolute(targetPath);

  // Thread-safe directory creation with retry logic for race conditions
  final Directory parentDir = Directory(p.dirname(shortcutPath));
  await _ensureDirectoryExistsSafe(parentDir);

  // Thread-safe target existence verification with retry
  await _verifyTargetExistsSafe(absoluteTargetPath);

  // Try native Win32 API first
  if (Platform.isWindows) {
    try {
      await _createShortcutNative(shortcutPath, absoluteTargetPath);
      return;
    } catch (e) {
      log(
        'Native shortcut creation failed, falling back to PowerShell: $e',
        level: 'warning',
      );
    }
  }

  // Fallback to PowerShell
  await _createShortcutPowerShell(shortcutPath, absoluteTargetPath);
}

/// Safely ensures a directory exists, handling race conditions
///
/// [directory] The directory to create
/// Retries up to 3 times with delays to handle concurrent creation
Future<void> _ensureDirectoryExistsSafe(final Directory directory) async {
  const int maxRetries = 3;
  const Duration retryDelay = Duration(milliseconds: 50);

  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return; // Success
    } catch (e) {
      // Check if directory was created by another thread
      if (await directory.exists()) {
        return; // Another thread created it, we're good
      }

      if (attempt == maxRetries) {
        throw Exception(
          'Failed to create directory after $maxRetries attempts: $e',
        );
      }

      // Wait before retry to reduce contention
      await Future.delayed(retryDelay);
    }
  }
}

/// Safely verifies target exists, handling race conditions
///
/// [targetPath] The target file/directory path to verify
/// Retries up to 3 times with delays to handle file system delays
Future<void> _verifyTargetExistsSafe(final String targetPath) async {
  const int maxRetries = 3;
  const Duration retryDelay = Duration(milliseconds: 10);

  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    if (File(targetPath).existsSync() || Directory(targetPath).existsSync()) {
      return; // Target exists
    }

    if (attempt == maxRetries) {
      throw Exception('Target path does not exist: $targetPath');
    }

    // Small delay to handle file system propagation delays
    await Future.delayed(retryDelay);
  }
}

/// Creates a Windows shortcut using native Win32 API
///
/// [shortcutPath] Path where the shortcut will be created
/// [targetPath] Path to the target file/folder
/// Throws Exception if Win32 API calls fail
Future<void> _createShortcutNative(
  final String shortcutPath,
  final String targetPath,
) async {
  if (!Platform.isWindows) {
    throw Exception('Native shortcut creation only supported on Windows');
  }

  // Run the synchronous COM operations in a separate isolate to avoid blocking
  await Isolate.run(() => _createShortcutSync(shortcutPath, targetPath));
}

/// Synchronous COM shortcut creation (runs in isolate)
///
/// [shortcutPath] Path where the shortcut will be created
/// [targetPath] Path to the target file/folder
void _createShortcutSync(final String shortcutPath, final String targetPath) {
  using((final Arena arena) {
    // Initialize COM with optimized threading model
    var hr = _initializeCOMSafe();
    if (FAILED(hr)) {
      throw Exception('Failed to initialize COM: 0x${hr.toRadixString(16)}');
    }

    IShellLink? shellLink;
    IPersistFile? persistFile;

    try {
      // Create the ShellLink COM object using cached GUIDs
      final shellLinkPtr = arena<COMObject>();

      // Use cached GUID constants for better performance
      final clsidShellLink = GUIDFromString(_clsidShellLinkString);
      final iidShellLink = GUIDFromString(_iidShellLinkString);

      hr = CoCreateInstance(
        clsidShellLink,
        nullptr,
        CLSCTX_INPROC_SERVER,
        iidShellLink,
        shellLinkPtr.cast<Pointer<COMObject>>(),
      );

      if (FAILED(hr)) {
        throw Exception(
          'Failed to create IShellLink: 0x${hr.toRadixString(16)}',
        );
      }

      shellLink = IShellLink(shellLinkPtr);

      // Convert strings to UTF16 once and reuse
      final targetPathPtr = targetPath.toNativeUtf16(allocator: arena);

      // Set the target path
      hr = shellLink.setPath(targetPathPtr);
      if (FAILED(hr)) {
        throw Exception('Failed to set target path: 0x${hr.toRadixString(16)}');
      }

      // Set working directory (directory of target) - performance optimized
      final workingDir = p.dirname(targetPath);
      if (workingDir != targetPath) {
        // Only set if different from target
        final workingDirPtr = workingDir.toNativeUtf16(allocator: arena);
        hr = shellLink.setWorkingDirectory(workingDirPtr);
        if (FAILED(hr)) {
          // Non-critical error, log but continue for performance
          if (isVerbose) {
            print(
              'Warning: Failed to set working directory: 0x${hr.toRadixString(16)}',
            );
          }
        }
      }

      // Query for IPersistFile interface using cached GUID
      final persistFilePtr = arena<COMObject>();
      final iidPersistFile = GUIDFromString(_iidPersistFileString);

      hr = shellLink.queryInterface(
        iidPersistFile,
        persistFilePtr.cast<Pointer<COMObject>>(),
      );

      if (FAILED(hr)) {
        throw Exception(
          'Failed to get IPersistFile: 0x${hr.toRadixString(16)}',
        );
      }

      persistFile = IPersistFile(persistFilePtr);

      // Save the shortcut with optimized retry logic
      _saveShortcutOptimized(persistFile, shortcutPath, arena);

      if (isVerbose) {
        print('Successfully created native Windows shortcut: $shortcutPath');
      }
    } catch (e) {
      // Clean exception handling - cleanup happens in finally
      rethrow;
    } finally {
      // Always release COM interfaces to prevent memory leaks
      // Release in reverse order of acquisition for safety
      _safeReleaseCOMInterface(() => persistFile?.release(), 'IPersistFile');
      _safeReleaseCOMInterface(() => shellLink?.release(), 'IShellLink');

      // Always uninitialize COM
      try {
        CoUninitialize();
      } catch (e) {
        if (isVerbose) {
          print('Warning: Failed to uninitialize COM: $e');
        }
      }
    }
  });
}

/// Safely releases a COM interface with error handling
///
/// [releaseFunc] Function that performs the release
/// [interfaceName] Name of interface for error reporting
void _safeReleaseCOMInterface(
  final void Function() releaseFunc,
  final String interfaceName,
) {
  try {
    releaseFunc();
  } catch (e) {
    if (isVerbose) {
      print('Warning: Failed to release $interfaceName: $e');
    }
  }
}

/// Optimized shortcut saving with minimal retry overhead
///
/// [persistFile] The IPersistFile interface
/// [shortcutPath] Path where the shortcut will be saved
/// [arena] Memory arena for string allocation
void _saveShortcutOptimized(
  final IPersistFile persistFile,
  final String shortcutPath,
  final Arena arena,
) {
  // Convert path to UTF16 once
  final shortcutPathPtr = shortcutPath.toNativeUtf16(allocator: arena);

  // First attempt - most shortcuts succeed on first try
  var hr = persistFile.save(shortcutPathPtr, TRUE);
  if (SUCCEEDED(hr)) {
    return; // Success on first try - optimal path
  }

  // Retry logic for edge cases only
  const int maxRetries = 2; // Reduced from 3 for better performance
  const int retryDelayMs = 50; // Reduced delay

  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    // Short delay to allow file system to settle
    sleep(const Duration(milliseconds: retryDelayMs));

    hr = persistFile.save(shortcutPathPtr, TRUE);
    if (SUCCEEDED(hr)) {
      return; // Success
    }

    if (attempt == maxRetries) {
      throw Exception(
        'Failed to save shortcut after ${maxRetries + 1} attempts: 0x${hr.toRadixString(16)}',
      );
    }
  }
}

/// Safely initializes COM, handling threading issues
///
/// Returns the HRESULT from COM initialization
int _initializeCOMSafe() {
  // Try apartment-threaded first (most compatible)
  var hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // If already initialized with different mode, that's usually OK
  if (hr == RPC_E_CHANGED_MODE) {
    return S_OK;
  }

  // If failed, try multi-threaded as fallback
  if (FAILED(hr)) {
    hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (hr == RPC_E_CHANGED_MODE) {
      return S_OK;
    }
  }

  return hr;
}

/// Creates a Windows shortcut using PowerShell (fallback method)
///
/// [shortcutPath] Path where the shortcut will be created
/// [targetPath] Path to the target file/folder
/// Throws Exception if PowerShell command fails
Future<void> _createShortcutPowerShell(
  final String shortcutPath,
  final String targetPath,
) async {
  // Properly escape paths for PowerShell by wrapping in single quotes and escaping internal single quotes
  final String escapedShortcutPath = shortcutPath.replaceAll("'", "''");
  final String escapedTargetPath = targetPath.replaceAll("'", "''");

  const int maxRetries = 3;
  const Duration retryDelay = Duration(milliseconds: 200);

  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      final ProcessResult res = await Process.run('powershell.exe', <String>[
        '-ExecutionPolicy',
        'Bypass',
        '-NoLogo',
        '-NonInteractive',
        '-NoProfile',
        '-Command',
        // Use single quotes to properly handle paths with spaces and special characters
        // ignore: no_adjacent_strings_in_list
        '\$ws = New-Object -ComObject WScript.Shell; '
            '\$s = \$ws.CreateShortcut(\'$escapedShortcutPath\'); '
            '\$s.TargetPath = \'$escapedTargetPath\'; '
            '\$s.Save()',
      ]);

      if (res.exitCode == 0) {
        log('Successfully created PowerShell shortcut: $shortcutPath');
        return; // Success
      }

      // Check if shortcut was created despite error code (sometimes happens)
      if (File(shortcutPath).existsSync()) {
        log('PowerShell shortcut created despite error code: $shortcutPath');
        return;
      }

      if (attempt == maxRetries) {
        throw Exception(
          'PowerShell failed to create shortcut after $maxRetries attempts: ${res.stderr}',
        );
      }

      // Log retry attempt
      log(
        'PowerShell shortcut creation attempt $attempt failed, retrying: ${res.stderr}',
        level: 'warning',
      );

      // Wait before retry to reduce contention
      await Future.delayed(retryDelay);
    } catch (e) {
      if (attempt == maxRetries) {
        throw Exception(
          'PowerShell shortcut creation failed after $maxRetries attempts: $e',
        );
      }

      log(
        'PowerShell shortcut creation attempt $attempt threw exception, retrying: $e',
        level: 'warning',
      );

      await Future.delayed(retryDelay);
    }
  }
}

/// Custom logging function with color-coded output levels
///
/// [message] The message to log
/// [level] Log level: 'info' (green), 'warning' (yellow), 'error' (red)
/// [forcePrint] If true, prints even when verbose mode is disabled
void log(
  final String message, {
  final String level = 'info',
  final bool forcePrint = false,
}) {
  if (isVerbose || forcePrint == true) {
    final String color;
    switch (level.toLowerCase()) {
      case 'error':
        color = '\x1B[31m'; // Red for errors
        break;
      case 'warning':
        color = '\x1B[33m'; // Yellow for warnings
        break;
      case 'info':
      default:
        color = '\x1B[32m'; // Green for info
        break;
    }
    print(
      '\r$color[${level.toUpperCase()}] $message\x1B[0m',
    ); // Reset color after the message
  }
}

/// Validates directory exists and is accessible
Future<bool> validateDirectory(
  final Directory dir, {
  final bool shouldExist = true,
}) async {
  final exists = await dir.exists();
  if (shouldExist && !exists) {
    error('Directory does not exist: ${dir.path}');
    return false;
  }
  if (!shouldExist && exists) {
    error('Directory already exists: ${dir.path}');
    return false;
  }
  return true;
}

/// Safely creates directory with error handling
Future<bool> safeCreateDirectory(final Directory dir) async {
  try {
    await dir.create(recursive: true);
    return true;
  } catch (e) {
    error('Failed to create directory ${dir.path}: $e');
    return false;
  }
}
