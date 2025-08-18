import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/services/core/logging_service.dart';

/// Infrastructure service for ExifTool external process management
class ExifToolService with LoggerMixin {
  /// Constructor for dependency injection
  ExifToolService(this.exiftoolPath);

  final String exiftoolPath; // Persistent process management
  Process? _persistentProcess;
  StreamSubscription<String>? _outputSubscription;
  StreamSubscription<String>? _errorSubscription;
  final Map<int, Completer<String>> _pendingCommands = {};
  final Map<int, String> _commandOutputs = {};
  bool _isDisposed = false;
  bool _isStarting = false;

  /// Factory method to find and create ExifTool service
  static Future<ExifToolService?> find() async {
    final isWindows = Platform.isWindows;

    // Common ExifTool executable names
    final exiftoolNames = isWindows
        ? ['exiftool.exe', 'exiftool']
        : ['exiftool']; // Check if ExifTool is in PATH first
    for (final name in exiftoolNames) {
      try {
        final result = await Process.run(name, ['-ver']);
        if (result.exitCode == 0) {
          final version = result.stdout.toString().trim();
          print('ExifTool found in PATH: $name (version $version)');
          return ExifToolService(name);
        }
      } catch (e) {
        // Continue to next option
      }
    } // Get the directory where the current executable (e.g., gpth.exe) resides
    String? binDir;
    try {
      binDir = File(Platform.resolvedExecutable).parent.path;
      print('Binary directory: $binDir');
    } catch (_) {
      binDir = null;
    } // Try to also get the location of the main script (may not be reliable in compiled mode)
    // ignore: unnecessary_nullable_for_final_variable_declarations
    final String? scriptPath = Platform.script.toFilePath();
    final String? scriptDir = (scriptPath != null && scriptPath.isNotEmpty)
        ? File(scriptPath).parent.path
        : null;
    if (scriptDir != null) {
      print('Script directory: $scriptDir');
    }

    // Collect possible directories where exiftool might be located
    // This restores the v4.0.8 behavior for relative path searches
    final List<String?> candidateDirs = [
      binDir, // Same directory as gpth.exe
      scriptDir, // Same directory as main.dart or main script
      if (binDir != null)
        p.join(
          binDir,
          'exif_tool',
        ), // subfolder "exif_tool" under executable directory
      if (scriptDir != null)
        p.join(
          scriptDir,
          'exif_tool',
        ), // subfolder "exif_tool" under script directory
      Directory.current.path, // Current working directory
      p.join(
        Directory.current.path,
        'exif_tool',
      ), // exif_tool under current working directory
      if (scriptDir != null)
        p.dirname(
          scriptDir,
        ), // One level above script directory (requested in issue #39)
      if (binDir != null)
        p.dirname(binDir), // One level above executable directory
      if (binDir != null)
        p.join(
          p.dirname(binDir),
          'exif_tool',
        ), // exif_tool one level above executable directory
    ];

    // Try each candidate directory and return if exiftool is found
    for (final dir in candidateDirs) {
      if (dir == null || dir.isEmpty) continue;

      for (final exeName in exiftoolNames) {
        final exiftoolFile = File(p.join(dir, exeName));
        if (await exiftoolFile.exists()) {
          try {
            final result = await Process.run(exiftoolFile.path, ['-ver']);
            if (result.exitCode == 0) {
              return ExifToolService(exiftoolFile.path);
            }
          } catch (e) {
            // Continue to next option
          }
        }
      }
    }

    // If not found in relative paths, check common installation directories
    final commonPaths = isWindows
        ? [
            r'C:\Program Files\exiftool\exiftool.exe',
            r'C:\Program Files (x86)\exiftool\exiftool.exe',
            r'C:\exiftool\exiftool.exe',
          ]
        : [
            '/usr/bin/exiftool',
            '/usr/local/bin/exiftool',
            '/opt/homebrew/bin/exiftool',
          ];

    for (final path in commonPaths) {
      if (await File(path).exists()) {
        try {
          final result = await Process.run(path, ['-ver']);
          if (result.exitCode == 0) {
            return ExifToolService(path);
          }
        } catch (e) {
          // Continue to next option
        }
      }
    }

    return null;
  }

  /// Start persistent ExifTool process for better performance
  Future<void> startPersistentProcess() async {
    // Prevent concurrent start attempts
    if (_persistentProcess != null || _isDisposed || _isStarting) return;

    _isStarting = true;
    try {
      _persistentProcess = await Process.start(exiftoolPath, [
        '-stay_open',
        'True',
        '-@',
        '-',
      ]);

      // Set up output handling
      _outputSubscription = _persistentProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleOutput);

      _errorSubscription = _persistentProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleError);
    } catch (e) {
      print('Failed to start ExifTool persistent process: $e');
      _persistentProcess = null;
    } finally {
      _isStarting = false;
    }
  }

  /// Handle output from persistent process
  void _handleOutput(final String line) {
    if (line.startsWith('{ready}')) {
      // Find the most recent pending command to complete
      if (_pendingCommands.isNotEmpty) {
        final commandId = _pendingCommands.keys.last;
        final output = _commandOutputs[commandId] ?? '';
        _pendingCommands[commandId]!.complete(output);
        _pendingCommands.remove(commandId);
        _commandOutputs.remove(commandId);
      }
    } else {
      // Add output to the most recent command
      if (_pendingCommands.isNotEmpty) {
        final currentCommandId = _pendingCommands.keys.last;
        _commandOutputs[currentCommandId] =
            '${_commandOutputs[currentCommandId] ?? ''}$line\n';
      }
    }
  }

  /// Handle error output from persistent process
  void _handleError(final String line) {
    print('ExifTool error: $line');
  }

  /// Execute ExifTool command
  Future<String> executeCommand(final List<String> args) async =>
      _executeOneShot(args);

  /// Execute ExifTool command as one-shot process
  Future<String> _executeOneShot(final List<String> args) async {
    try {
      final result = await Process.run(exiftoolPath, args);
      if (result.exitCode != 0) {
        logger.error(
          'ExifTool command failed with exit code ${result.exitCode}',
        );
        logger.error('Command: $exiftoolPath ${args.join(' ')}');
        logger.error('Error output: ${result.stderr}');
        throw Exception(
          'ExifTool command failed with exit code ${result.exitCode}: ${result.stderr}',
        );
      }
      return result.stdout.toString();
    } catch (e) {
      print('ExifTool one-shot execution failed: $e');
      rethrow;
    }
  }

  /// Read EXIF data from file
  Future<Map<String, dynamic>> readExifData(final File file) async {
    final args = ['-fast', '-j', '-n', file.path];
    final output = await executeCommand(args);

    if (output.trim().isEmpty) {
      print('ExifTool returned empty output for file: ${file.path}');
      return {};
    }

    try {
      final List<dynamic> jsonList = jsonDecode(output);
      if (jsonList.isNotEmpty && jsonList[0] is Map<String, dynamic>) {
        final data = Map<String, dynamic>.from(jsonList[0]);

        // Normalize GPS reference values
        if (data.containsKey('GPSLatitudeRef')) {
          final latRef = data['GPSLatitudeRef'];
          if (latRef == 'North') {
            data['GPSLatitudeRef'] = 'N';
          } else if (latRef == 'South') {
            data['GPSLatitudeRef'] = 'S';
          }
        }
        if (data.containsKey('GPSLongitudeRef')) {
          final lngRef = data['GPSLongitudeRef'];
          if (lngRef == 'East') {
            data['GPSLongitudeRef'] = 'E';
          } else if (lngRef == 'West') {
            data['GPSLongitudeRef'] = 'W';
          }
        }

        return data;
      }
      return {};
    } catch (e) {
      print('Failed to parse ExifTool JSON output: $e');
      print('Raw output was: "$output"');
      return {};
    }
  }

  /// Write EXIF data to file
  Future<void> writeExifData(
    final File file,
    final Map<String, dynamic> exifData,
  ) async {
    if (exifData.isEmpty) return;

    final args = <String>['-overwrite_original'];

    // Add each EXIF tag as an argument
    for (final entry in exifData.entries) {
      args.add('-${entry.key}=${entry.value}');
    }

    args.add(file.path);

    try {
      final output = await executeCommand(args);

      if (output.contains('error') ||
          output.contains('Error') ||
          output.contains("weren't updated due to errors")) {
        print('ExifTool may have encountered an error writing to ${file.path}');
        print('Output: $output');
        throw Exception(
          'ExifTool failed to write metadata to ${file.path}: $output',
        );
      }
    } catch (e) {
      // Handle unsupported file formats gracefully - don't throw for these
      if (e.toString().contains('is not yet supported') ||
          e.toString().contains('file format not supported') ||
          e.toString().contains("Can't currently write RIFF AVI files") ||
          e.toString().contains('AVI files')) {
        logInfo(
          'ExifTool does not support writing to this file format: ${file.path}',
        );
        return; // Return normally instead of throwing
      }
      // Re-throw other exceptions (like file not found)
      rethrow;
    }
  }

  /// Dispose of resources and cleanup
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    // Cancel pending commands
    for (final completer in _pendingCommands.values) {
      completer.completeError('ExifTool service disposed');
    }
    _pendingCommands.clear();
    _commandOutputs.clear();

    // Cancel subscriptions
    await _outputSubscription?.cancel();
    await _errorSubscription?.cancel();

    // Cleanup persistent process
    if (_persistentProcess != null) {
      try {
        _persistentProcess!.stdin.write('-stay_open\nFalse\n');
        await _persistentProcess!.stdin.flush();
        await _persistentProcess!.stdin.close();

        final exitCode = await _persistentProcess!.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _persistentProcess!.kill();
            return -1;
          },
        );

        print('ExifTool process exited with code $exitCode');
      } catch (e) {
        print('Error disposing ExifTool process: $e');
        _persistentProcess!.kill();
      } finally {
        _persistentProcess = null;
      }
    }
  }
}
