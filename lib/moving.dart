// moving.dart
//
// This file contains the core logic for moving, copying, and organizing media files exported from Google Photos Takeout.
// It provides utilities for de-duplicating, sorting, and placing files into user-friendly folder structures, supporting various album handling modes.
//
// Key Features:
// - Unique file naming to avoid overwrites
// - Cross-platform shortcut/symlink creation (Windows/Unix)
// - Multiple album handling strategies: shortcut, reverse-shortcut, duplicate-copy, json, nothing
// - Flexible date-based folder organization
// - Robust error handling for file operations
// - Metadata preservation (modification dates)
//
// Main Functions:
//
// 1. findNotExistingName: Ensures a file path is unique by appending (1), (2), etc. if needed.
// 2. createShortcut: Creates a shortcut (Windows .lnk) or symlink (Unix) to a target file, using relative paths for portability.
// 3. moveFileAndCreateShortcut: Moves/copies a file to a new location and creates a shortcut in the original location (used for reverse-shortcut mode).
// 4. moveFiles: The main entry point. Iterates over all media, applies the selected album handling mode, and moves/copies/links files into the output structure. Supports progress reporting via Stream.
//
// Album Handling Modes:
// - shortcut: All real files go to ALL_PHOTOS; album folders contain shortcuts.
// - reverse-shortcut: Real files go to album folders; ALL_PHOTOS contains shortcuts.
// - duplicate-copy: Every folder gets a real copy (max compatibility, more space).
// - json: Only ALL_PHOTOS with real files; album membership is written to albums-info.json.
// - nothing: Only ALL_PHOTOS with real files from year folders; albums ignored.
//
// Error Handling:
// - Handles cross-device move errors, PowerShell failures, and Windows date limitations.
// - Ensures no data loss by falling back to copy if move/shortcut fails.
//
// Usage:
// - Used by the main application to process Google Photos Takeout exports into organized, deduplicated, and user-friendly folder structures.
// - Designed for extensibility and robust cross-platform operation.

// ignore_for_file: prefer_single_quotes

library;

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'interactive.dart' as interactive;
import 'media.dart';
import 'utils.dart';

/// Creates a unique file name by appending (1), (2), etc. until non-existing
///
/// [initialFile] The file to find a unique name for
/// Returns a File object with a unique path that doesn't exist yet
File findNotExistingName(final File initialFile) {
  File file = initialFile;
  int counter = 1;
  while (file.existsSync()) {
    final String baseName = p.withoutExtension(initialFile.path);
    final String extension = p.extension(initialFile.path);
    file = File('$baseName($counter)$extension');
    counter++;
  }
  return file;
}

/// Creates a symbolic link (Unix) or shortcut (Windows) to target file
///
/// [location] Directory where the link/shortcut will be created
/// [target] File to link to
/// Returns the created link/shortcut file
/// Uses relative paths to avoid breaking when folders are moved
Future<File> createShortcut(final Directory location, final File target) async {
  final String basename = p.basename(target.path);
  final String name = Platform.isWindows
      ? (basename.endsWith('.lnk') ? basename : '$basename.lnk')
      : basename;
  final File link = findNotExistingName(
    File(p.join(location.path, name)),
  ); // Ensure the parent directory for the shortcut exists (important for Windows)
  final linkDir = Directory(p.dirname(link.path));
  if (!await linkDir.exists()) {
    await linkDir.create(recursive: true);
  }
  // Ensure the target directory exists before creating shortcuts
  if (!await location.exists()) {
    await location.create(recursive: true);
  }

  // this must be relative to not break when user moves whole folder around:
  // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/232
  final String targetRelativePath = p.relative(
    target.path,
    from: link.parent.path,
  );
  final String targetPath = target.absolute.path;
  if (Platform.isWindows) {
    // Try native shortcut creation, fallback to PowerShell if needed.
    try {
      await createShortcutWin(link.path, targetPath);
    } catch (e) {
      try {
        final ProcessResult res = await Process.run('powershell.exe', <String>[
          '-ExecutionPolicy',
          'Bypass',
          '-NoLogo',
          '-NonInteractive',
          '-NoProfile',
          '-Command',
          '''
          try {
            \$ws = New-Object -ComObject WScript.Shell
            \$s = \$ws.CreateShortcut("${link.path}")
            \$s.TargetPath = "$targetPath"
            \$s.Save()
          } catch {
            Write-Error \$_.Exception.Message
            exit 1
          }
          ''',
        ]);
        if (res.exitCode != 0) {
          throw Exception('PowerShell shortcut creation failed: ${res.stderr}');
        }
      } catch (fallbackError) {
        throw Exception(
          'PowerShell doesnt work :( - \n\n'
          'report that to @TheLastGimbus on GitHub:\n\n'
          'https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues\n\n'
          '...or try other album solution\n'
          'sorry for inconvenience :('
          '\nOriginal error: $e'
          '\nFallback error: $fallbackError',
        );
      }
    }
    return File(link.path);
  } else {
    // Unix: create a symlink
    return File((await Link(link.path).create(targetRelativePath)).path);
  }
}

/// Moves or copies a file to new location and creates a shortcut in the original location
///
/// Used for reverse-shortcut album behavior where originals go to albums
/// and shortcuts are created in year folders.
///
/// [newLocation] Directory to move/copy the file to
/// [target] File to move/copy
/// [copy] Whether to copy (true) or move (false) the file
/// Returns the created shortcut file
Future<File> moveFileAndCreateShortcut(
  final Directory newLocation,
  final File target, {
  required final bool copy,
}) async {
  final String newPath = p.join(newLocation.path, p.basename(target.path));
  final File outputFile = copy
      ? await target.copy(newPath) // Copy the file if copy mode
      : await target.rename(newPath); // Move the file if move mode

  // Create shortcut in the original path (year folder)
  return createShortcut(target.parent, outputFile);
}

/// Big-ass logic of moving files from input to output
///
/// [allMediaFinal] should be nice, de-duplicated and album-ed etc
///
/// [copy] indicates whether to copy files or move them
///
/// [divideToDates] 1. One folder 2. Year folder 3. Year/Month 4. Year/Month/Day
///
/// [albumBehavior] must be one of [interactive.albumOptions]
///
/// Emits number of files that it copied/created/whatever (starting from 1) -
/// use [outputFileCount] function for progress measurement
Stream<int> moveFiles(
  final List<Media> allMediaFinal,
  final Directory output, {
  required final bool copy,
  required final num divideToDates,
  required final String albumBehavior,
}) async* {
  assert(
    interactive.albumOptions.keys.contains(albumBehavior),
    'Invalid albumBehavior: $albumBehavior. Must be one of ${interactive.albumOptions.keys}',
  );

  /// used only in 'json' behavior
  /// key = name of main outputted file | value = list of albums it belongs to
  final Map<String, List<String>> infoJson = <String, List<String>>{};
  int i = 0;
  for (final Media m in allMediaFinal) {
    // mainFile is the real file that album shortcuts/symlinks will point to.
    File? mainFile;

    // Sort files so the null key (ALL_PHOTOS/year folder) comes first.
    // This ensures shortcuts in albums point to the correct file.
    final List<MapEntry<String?, File>> nullFirst = albumBehavior == 'json'
        // in 'json' case, we want to copy ALL files (like Archive) as normals
        ? <MapEntry<Null, File>>[
            MapEntry<Null, File>(null, m.files.values.first),
          ]
        // this will put null media first so album shortcuts can link to it
        : m.files.entries.sorted(
            (
              final MapEntry<String?, File> a,
              final MapEntry<String?, File> b,
            ) => (a.key ?? '').compareTo(b.key ?? ''),
          );
    // iterate over all media of file to do something about them
    // ignore non-nulls with 'ignore', copy with 'duplicate-copy',
    // symlink with 'shortcut' etc
    for (final MapEntry<String?, File> file in nullFirst) {
      // Skip album files in 'nothing' and 'json' modes.
      if (file.key != null &&
          <String>['nothing', 'json'].contains(albumBehavior)) {
        continue;
      }
      // In reverse-shortcut mode, skip creating a real file in ALL_PHOTOS (null key)
      if (albumBehavior == 'reverse-shortcut' && file.key == null) {
        // Do not create a real file in ALL_PHOTOS; shortcut will be created after album file is created
        continue;
      }
      // In reverse-shortcut mode, set mainFile to the album file for shortcut creation
      if (albumBehavior == 'reverse-shortcut' && file.key != null) {
        mainFile = file.value;
      }
      // now on, logic is shared for nothing+null/shortcut/copy cases
      final DateTime? date = m.dateTaken;
      String folderName;
      if (file.key != null) {
        folderName = file.key!.trim();
      } else {
        folderName = 'ALL_PHOTOS';
      }

      String dateFolder;
      if (divideToDates == 0) {
        dateFolder = '';
      } else if (date == null) {
        dateFolder = 'date-unknown';
      } else {
        if (divideToDates == 3) {
          dateFolder = p.join(
            '${date.year}',
            date.month.toString().padLeft(2, '0'),
            date.day.toString().padLeft(2, '0'),
          );
        } else if (divideToDates == 2) {
          dateFolder = p.join(
            '${date.year}',
            date.month.toString().padLeft(2, '0'),
          );
        } else if (divideToDates == 1) {
          dateFolder = '${date.year}';
        } else {
          dateFolder = '';
        }
      }

      final Directory folder = Directory(
        p.join(output.path, folderName, dateFolder),
      );
      // now folder logic is so complex i'll just create it every time 🤷
      await folder.create(recursive: true);

      /// result file/symlink to later change modify time
      File? result;

      /// moves/copies file with safe name
      // it's here because we do this for two cases
      Future<File> moveFile() async {
        final File freeFile = findNotExistingName(
          File(p.join(folder.path, p.basename(file.value.path))),
        );
        try {
          return copy
              ? await file.value.copy(freeFile.path)
              : await file.value.rename(freeFile.path);
        } on FileSystemException catch (e) {
          final String errorMessage =
              '[Step 7/8] [Error] Uh-uh, it looks like you selected another output drive than\n'
              "your input drive - gpth can't move files between them. But, you don't have\n"
              "to do this! Gpth *moves* files, so this doesn't take any extra space!\n"
              'Please run again and select different output location <3 Error message: $e';

          print(errorMessage);

          // In test environment, throw an exception instead of quitting
          // Check multiple ways to detect test environment
          final isTestEnvironment =
              Platform.environment.containsKey('FLUTTER_TEST') ||
              Platform.environment.containsKey('DART_TEST') ||
              Platform.environment.containsKey('_DART_TEST') ||
              // Check if we're running under dart test command
              Platform.script.path.contains('test') ||
              // Check if current executable is test-related
              Platform.executable.contains('dart') &&
                  Platform.script.toString().contains('test');

          if (isTestEnvironment) {
            throw Exception(
              'Cross-device move error: Cannot move files between different drives',
            );
          }

          quit();
        }
      }

      // Album handling logic:
      // - For ALL_PHOTOS (null key): move/copy the file and set as mainFile.
      // - For shortcut mode: create a shortcut in the album folder pointing to mainFile.
      // - For reverse-shortcut: move/copy the file to the album folder and create a shortcut in ALL_PHOTOS.
      // - For duplicate-copy: copy/move the file to every folder.
      // - For json/nothing: only process ALL_PHOTOS.
      if (file.key == null) {
        // if it's just normal "Photos from .." (null) file, just move it
        result = await moveFile();
        mainFile = result;
      } else if (albumBehavior == 'shortcut' && mainFile != null) {
        try {
          result = await createShortcut(folder, mainFile);
        } catch (e) {
          // in case powershell fails/whatever
          print(
            '[Step 7/8] [Error] Creating shortcut for '
            '${p.basename(mainFile.path)} in ${p.basename(folder.path)} '
            'failed :(\n$e\n - copying normal file instead',
          );
          result = await moveFile();
        }
      } else if (albumBehavior == 'reverse-shortcut' &&
          file.key != null &&
          mainFile != null) {
        // Move/copy the file to the album folder and create a shortcut in ALL_PHOTOS
        try {
          result = await moveFileAndCreateShortcut(
            folder,
            mainFile,
            copy: copy,
          );
        } catch (e) {
          if (e is FileSystemException) {
            result = await moveFile();
          } else {
            print(
              '[Step 7/8] [Error] Creating shortcut for '
              '${p.basename(mainFile.path)} in ${p.basename(folder.path)} '
              'failed :(\n$e\n - copying normal file instead',
            );
            result = await moveFile();
          }
        }
        // After creating the album file, create a shortcut in ALL_PHOTOS
        final allPhotosDir = Directory(p.join(output.path, 'ALL_PHOTOS'));
        await allPhotosDir.create(recursive: true);
        await createShortcut(allPhotosDir, result);
      } else if (albumBehavior == 'reverse-shortcut' && file.key == null) {
        // Skip creating a real file in ALL_PHOTOS (null key)
        continue;
      } else {
        // else - if we either run duplicate-copy or main file is missing:
        // (this happens with archive/trash/weird situation)

        // Special handling for duplicate-copy mode in move operations
        if (albumBehavior == 'duplicate-copy' &&
            !copy &&
            mainFile != null &&
            file.key != null) {
          // In move mode with duplicate-copy, we already moved the file to ALL_PHOTOS
          // Now we need to copy from the mainFile to the album folder
          final File freeFile = findNotExistingName(
            File(p.join(folder.path, p.basename(file.value.path))),
          );
          result = await mainFile.copy(freeFile.path);
        } else {
          // Normal case: move/copy from original source
          result = await moveFile();
        }
      }

      // Done! Now, set the date:

      DateTime time = m.dateTaken ?? DateTime.now();
      if (Platform.isWindows && time.isBefore(DateTime(1970))) {
        print(
          '\r[Step 7/8] [Info]: ${m.firstFile.path} has date $time, which is before 1970 '
          '(not supported on Windows) - will be set to 1970-01-01',
        );
        time = DateTime(1970);
      }
      try {
        await result.setLastModified(time);
      } on OSError catch (e) {
        // Sometimes windoza throws error but successes anyway 🙃:
        // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/229#issuecomment-1685085899
        // That's why this is here
        if (e.errorCode != 0) {
          print(
            "[Step 7/8] [Error]: Can't set modification time on $result: $e",
          );
        }
      } catch (e) {
        log(
          "[Step 7/8]: Can't set modification time on $result: $e. This happens on Windows sometimes. Can be ignored.",
          level: 'warning',
        ); //If error code 0, no need to notify user. Only log.
      }

      // Yield progress for each file processed.
      yield ++i;

      // In 'json' mode, record album membership for this file.
      if (albumBehavior == 'json') {
        infoJson[p.basename(result.path)] = m.files.keys.nonNulls.toList();
      }
    }
    // done with this media - next!
  }
  // If in 'json' mode, write the album membership info to albums-info.json in the output folder.
  if (albumBehavior == 'json') {
    await File(
      p.join(output.path, 'albums-info.json'),
    ).writeAsString(jsonEncode(infoJson));
  }
}
