// ignore_for_file: file_names

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'utils.dart';

ExiftoolInterface? exiftool;

/// Initializes the global ExiftoolInterface instance
///
/// Attempts to find and initialize exiftool, setting the global
/// [exifToolInstalled] flag accordingly.
///
/// Returns true if exiftool was found and initialized successfully
Future<bool> initExiftool() async {
  exiftool = await ExiftoolInterface.find();
  if (exiftool != null) {
    exifToolInstalled = true;
    return true;
  } else {
    return false;
  }
}

/// Cross-platform interface for exiftool (read/write EXIF data)
class ExiftoolInterface {
  ExiftoolInterface._(this.exiftoolPath);

  final String exiftoolPath;

  /// Attempts to find exiftool in PATH and returns an instance, or null if not found
  static Future<ExiftoolInterface?> find() async {
    final String exe = Platform.isWindows ? 'exiftool.exe' : 'exiftool';

    // Try finding exiftool in system PATH
    final String? path = await _which(exe);
    if (path != null) {
      return ExiftoolInterface._(path);
    }

    // Get the directory where the current executable (e.g., gpth.exe) resides
    String? binDir;
    try {
      binDir = File(Platform.resolvedExecutable).parent.path;
    } catch (_) {
      binDir = null;
    }

    // Try to also get the location of the main script (may not be reliable in compiled mode)
    // ignore: unnecessary_nullable_for_final_variable_declarations
    final String? scriptPath = Platform.script.toFilePath();
    final String? scriptDir = scriptPath != null
        ? File(scriptPath).parent.path
        : null;

    // Collect possible directories where exiftool might be located
    final List<String?> candidateDirs = [
      binDir, // Same directory as gpth.exe
      scriptDir, // Same directory as main.dart or main script
      p.join(
        binDir ?? '',
        'exif_tool',
      ), // subfolder "exif_tool" under executable directory
      p.join(
        scriptDir ?? '',
        'exif_tool',
      ), // subfolder "exif_tool" under script directory
      Directory.current.path, // Current working directory
      p.join(
        Directory.current.path,
        'exif_tool',
      ), // exif_tool under current working directory
      p.dirname(scriptDir ?? ''), // One level above script directory (fallback)
    ];

    // Try each candidate directory and return if exiftool is found
    for (final dir in candidateDirs) {
      if (dir == null) continue;
      final exiftoolFile = File(p.join(dir, exe));
      if (await exiftoolFile.exists()) {
        return ExiftoolInterface._(exiftoolFile.path);
      }
    }

    // Not found anywhere
    return null;
  }

  /// Reads all EXIF data from [file] and returns as a Map
  Future<Map<String, dynamic>> readExif(final File file) async {
    // Check if file exists before trying to read it
    if (!await file.exists()) {
      throw FileSystemException('File not found', file.path);
    }

    final args = ['-j', '-n'];

    // On Windows, explicitly set UTF-8 encoding for Unicode character support
    if (Platform.isWindows) {
      args.addAll(['-charset', 'filename=UTF8']);
      args.addAll(['-charset', 'exif=UTF8']);
    }

    args.add(file.path);

    final result = await Process.run(
      exiftoolPath,
      args,
      // Ensure UTF-8 encoding for the process
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    if (result.exitCode != 0) {
      log(
        'exiftool returned a non 0 code for reading ${file.path} with error: ${result.stderr}',
        level: 'error',
      );
    }
    try {
      final List<dynamic> jsonList = jsonDecode(result.stdout);
      if (jsonList.isEmpty) return {};
      final map = Map<String, dynamic>.from(jsonList.first);
      map.remove('SourceFile');
      return map;
    } on FormatException catch (_) {
      // this is when json is bad
      return {};
    } on FileSystemException catch (_) {
      // this happens for issue #143
      // "Failed to decode data using encoding 'utf-8'"
      // maybe this will self-fix when dart itself support more encodings
      return {};
    } on NoSuchMethodError catch (_) {
      // this is when tags like photoTakenTime aren't there
      return {};
    }
  }

  /// Reads only the specified EXIF tags from [file] and returns as a Map
  Future<Map<String, dynamic>> readExifBatch(
    final File file,
    final List<String> tags,
  ) async {
    final String filepath = file.path;

    // Check if file exists before trying to read it
    if (!await file.exists()) {
      throw FileSystemException('File not found', file.path);
    }

    if (tags.isEmpty) {
      return <String, dynamic>{};
    }

    final args = <String>['-j', '-n'];

    // On Windows, explicitly set UTF-8 encoding for Unicode character support
    if (Platform.isWindows) {
      args.addAll(['-charset', 'filename=UTF8']);
      args.addAll(['-charset', 'exif=UTF8']);
    }

    args.addAll(tags.map((final tag) => '-$tag'));
    args.add(filepath);

    final result = await Process.run(
      exiftoolPath,
      args,
      // Ensure UTF-8 encoding for the process
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    if (result.exitCode != 0) {
      log(
        'exiftool returned a non 0 code for reading ${file.path} with error: ${result.stderr}',
        level: 'error',
      );
    }
    try {
      final List<dynamic> jsonList = jsonDecode(result.stdout);
      if (jsonList.isEmpty) return {};
      final map = Map<String, dynamic>.from(jsonList.first);
      map.remove('SourceFile');
      return map;
    } on FormatException catch (_) {
      // this is when json is bad
      return {};
    } on FileSystemException catch (_) {
      // this happens for issue #143
      // "Failed to decode data using encoding 'utf-8'"
      // maybe this will self-fix when dart itself support more encodings
      return {};
    } on NoSuchMethodError catch (_) {
      // this is when tags like photoTakenTime aren't there
      return {};
    }
  }

  /// Writes multiple EXIF tags to [file]. [tags] is a map of tag name to value.
  Future<bool> writeExifBatch(
    final File file,
    final Map<String, String> tags,
  ) async {
    final String filepath = file.path;

    // Check if file exists before trying to write to it
    if (!await file.exists()) {
      throw FileSystemException('File not found', file.path);
    }

    final args = <String>['-overwrite_original'];

    // On Windows, explicitly set UTF-8 encoding for Unicode character support
    if (Platform.isWindows) {
      args.addAll(['-charset', 'filename=UTF8']);
      args.addAll(['-charset', 'exif=UTF8']);
    }

    tags.forEach((final tag, final value) => args.add('-$tag=$value'));
    args.add(filepath);

    final result = await Process.run(
      exiftoolPath,
      args,
      // Ensure UTF-8 encoding for the process
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    if (result.exitCode != 0) {
      log(
        '[Step 5/8] Writing exif to file ${file.path} failed.'
        '\n${result.stderr.replaceAll(" - ${file.path.replaceAll('\\', '/')}", "")}',
        level: 'error',
        forcePrint: true,
      );
    }
    if (result.exitCode != 0) {
      return false;
    } else {
      return true;
    }
  }
}

/// Cross-platform helper to find an executable in system PATH
///
/// Similar to Unix 'which' or Windows 'where' commands.
///
/// [bin] Executable name to search for
/// Returns full path to executable or null if not found
Future<String?> _which(final String bin) async {
  final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
    bin,
  ]);
  if (result.exitCode != 0) return null;
  final output = result.stdout.toString();
  final lines = output
      .split(RegExp(r'[\r\n]+'))
      .where((final l) => l.trim().isNotEmpty)
      .toList();
  return lines.isEmpty ? null : lines.first.trim();
}
