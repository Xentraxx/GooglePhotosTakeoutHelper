import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:gpth/gpth-lib.dart';

/// Service for handling ZIP file extraction with safety checks and error handling.
///
/// This service provides secure ZIP extraction functionality with comprehensive
/// error handling, progress reporting, and security validation to prevent
/// common ZIP-based vulnerabilities like path traversal attacks (Zip Slip).
/// Filenames and directory names are sanitized with a policy that:
/// - Replaces invalid Windows filename characters [<>:"|?*] with '_'
/// - Keeps Unicode characters (Ñ, accents, emojis) untouched
/// - Handles Windows reserved device names by suffixing with `_file`
/// - Removes trailing dots/spaces on Windows
/// Additionally, a light heuristic fixes mojibake where 'Ñ/ñ' appears as '¥'.
class ZipExtractionService {
  /// Creates a new instance of ZipExtractionService
  ZipExtractionService({
    final InteractivePresenterService? presenter,
    this.enableNameDiagnostics = false, // set to false to silence name logs
  }) : _presenter = presenter ?? InteractivePresenterService();

  final InteractivePresenterService _presenter;
  final LoggingService _logger = LoggingService();

  /// When true, the extractor logs suspicious entry names (e.g., ones containing '¥', 'Ñ', 'ñ', '~')
  /// with their code points before and after sanitization to diagnose mojibake issues.
  final bool enableNameDiagnostics;

  /// Extracts all ZIP files to the specified directory.
  ///
  /// Streamed extraction is used (archive v4 decodeStream). Memory fallback is guarded.
  Future<void> extractAll(final List<File> zips, final Directory dir) async {
    // Clean up and create destination directory
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    await _presenter.showUnzipStartMessage();

    // Pre-check for very large files and warn user
    var hasLargeFiles = false;
    var totalSize = 0;
    for (final File zip in zips) {
      if (await zip.exists()) {
        final size = await zip.length();
        totalSize += size;
        if (size > 10 * 1024 * 1024 * 1024) {
          // > 10GB
          hasLargeFiles = true;
        }
      }
    }

    if (hasLargeFiles) {
      _logger.warning('⚠️  LARGE FILE WARNING');
      _logger.warning('Some ZIP files are very large (>10GB).');
      _logger.warning('Total size: ${totalSize ~/ (1024 * 1024 * 1024)}GB');
      _logger.warning('This may cause memory issues during extraction.');
      _logger.warning('');
      _logger.warning('If extraction fails with memory errors:');
      _logger.warning('1. Extract ZIP files manually');
      _logger.warning('2. Run GPTH on the extracted folder instead');
      _logger.warning('');
    }

    for (final File zip in zips) {
      await _presenter.showUnzipProgress(p.basename(zip.path));

      try {
        // Validate ZIP file exists and is readable
        if (!await zip.exists()) {
          throw FileSystemException('ZIP file not found', zip.path);
        }
        final int zipSize = await zip.length();
        if (zipSize == 0) {
          throw FileSystemException('ZIP file is empty', zip.path);
        }

        // Log file size for large files
        if (zipSize > 1024 * 1024 * 1024) {
          // > 1GB
          _logger.info('Processing large ZIP file: ${p.basename(zip.path)} (${zipSize ~/ (1024 * 1024)}MB)');
        }

        // ─────────────────────────────────────────────────────────────────────
        // Windows: 7-Zip (PATH + common locations + ./gpth_tool/7zip/7z.exe) -> Native (Dart)
        // macOS/Linux: 7-Zip -> unzip -> Native (Dart)
        // ─────────────────────────────────────────────────────────────────────
        final extracted = await _extractZipWithStrategy(zip, dir);
        if (!extracted) {
          _logger.warning('No external extractor succeeded; falling back to native streamed extractor (safety fallback).');
          await _extractZipStreamed(zip, dir);
        }

        await _presenter.showUnzipSuccess(p.basename(zip.path));
      } on ArchiveException catch (e) {
        try {
          _handleExtractionError(zip, e, isArchiveError: true);
        } catch (extractionError) {
          _logger.warning('Failed to extract ${p.basename(zip.path)}: $e');
          _logger.warning('Continuing with remaining ZIP files...');
        }
      } on PathNotFoundException catch (e) {
        try {
          _handleExtractionError(zip, e, isPathError: true);
        } catch (extractionError) {
          _logger.warning('Failed to extract ${p.basename(zip.path)}: $e');
          _logger.warning('Continuing with remaining ZIP files...');
        }
      } on FileSystemException catch (e) {
        try {
          _handleExtractionError(zip, e, isFileSystemError: true);
        } catch (extractionError) {
          _logger.warning('Failed to extract ${p.basename(zip.path)}: $e');
          _logger.warning('Continuing with remaining ZIP files...');
        }
      } catch (e) {
        // Handle memory exhaustion specifically
        final errorMessage = e.toString().toLowerCase();
        if (errorMessage.contains('exhausted heap') ||
            errorMessage.contains('out of memory') ||
            errorMessage.contains('cannot allocate')) {
          _logger.error('');
          _logger.error('❌ MEMORY EXHAUSTION ERROR');
          _logger.error('ZIP file too large: ${p.basename(zip.path)}');
          _logger.error('Available memory insufficient for processing this file.');
          _logger.error('');
          _logger.error('🔧 SOLUTIONS:');
          _logger.error('1. Extract ZIP files manually using your system tools');
          _logger.error('2. Use smaller ZIP files (split large exports)');
          _logger.error('3. Run GPTH on the manually extracted folder');
          _logger.error('4. Increase available memory and try again');
          _logger.error('');
          _logger.error('Manual extraction guide:');
          _logger.error('https://github.com/Xentraxx/GooglePhotosTakeoutHelper#manual-extraction');
          _logger.warning('Continuing with remaining ZIP files...');
        } else {
          try {
            _handleExtractionError(zip, e);
          } catch (extractionError) {
            _logger.warning('Failed to extract ${p.basename(zip.path)}: $e');
            _logger.warning('Continuing with remaining ZIP files...');
          }
        }
      }
    }

    await _presenter.showUnzipComplete();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Cross-platform strategy orchestrator
  // ───────────────────────────────────────────────────────────────────────────

  /// Orchestrates extraction attempts depending on the OS.
  /// Returns true if any external/native strategy completed the extraction.
  Future<bool> _extractZipWithStrategy(final File zip, final Directory destinationDir) async {
    final String zipName = p.basename(zip.path);
    _logger.info('Starting extraction strategy for $zipName');

    if (Platform.isWindows) {
      // 1) Try 7-Zip with deep discovery
      try {
        final ok = await _timed('7-Zip', () => _tryExtractWith7zip(zip, destinationDir));
        if (ok) {
          _logger.info('7-Zip extraction succeeded for $zipName');
          return true;
        } else {
          _logger.warning('7-Zip not available or failed for $zipName, using native streamed extractor...');
        }
      } catch (e) {
        _logger.warning('7-Zip extraction threw an error for $zipName: $e');
      }

      // 2) Fallback: native streamed extractor (Dart)
      try {
        final ok = await _timed('Native(Dart)', () async {
          await _extractZipStreamed(zip, destinationDir);
          return true;
        });
        if (ok) {
          _logger.info('Native streamed extractor succeeded for $zipName');
          return true;
        }
      } catch (e) {
        _logger.warning('Native streamed extractor failed for $zipName: $e');
      }

      return false;
    } else {
      // macOS / Linux
      // 1) Try 7-Zip
      try {
        final ok = await _timed('7-Zip', () => _tryExtractWith7zip(zip, destinationDir));
        if (ok) {
          _logger.info('7-Zip extraction succeeded for $zipName');
          return true;
        } else {
          _logger.warning('7-Zip failed or not found for $zipName, trying unzip...');
        }
      } catch (e) {
        _logger.warning('7-Zip extraction threw an error for $zipName: $e');
      }

      // 2) Try unzip
      try {
        final ok = await _timed('unzip', () => _tryExtractWithUnzip(zip, destinationDir));
        if (ok) {
          _logger.info('unzip succeeded for $zipName');
          return true;
        } else {
          _logger.warning('unzip failed for $zipName, falling back to native streamed extractor...');
        }
      } catch (e) {
        _logger.warning('unzip extraction threw an error for $zipName: $e');
      }

      // 3) Fallback: native streamed extractor
      try {
        final ok = await _timed('Native(Dart)', () async {
          await _extractZipStreamed(zip, destinationDir);
          return true;
        });
        if (ok) {
          _logger.info('Native streamed extractor succeeded for $zipName');
          return true;
        }
      } catch (e) {
        _logger.warning('Native streamed extractor failed for $zipName: $e');
      }

      return false;
    }
  }

  /// Run an async action and log its duration.
  Future<bool> _timed(final String label, final Future<bool> Function() action) async {
    final sw = Stopwatch()..start();
    try {
      final ok = await action();
      sw.stop();
      _logger.debug('[$label] completed in ${sw.elapsed.inMilliseconds} ms (success=$ok)', forcePrint: true);
      return ok;
    } catch (e) {
      sw.stop();
      _logger.debug('[$label] failed in ${sw.elapsed.inMilliseconds} ms with error: $e', forcePrint: true);
      rethrow;
    }
  }

  /// Try 7-Zip (7z/7za/7zz). Returns true on success.
  /// Windows: searches PATH and common install locations (Program Files, Chocolatey, Scoop) and ./gpth_tool/7zip/7z.exe.
  Future<bool> _tryExtractWith7zip(final File zip, final Directory destinationDir) async {
    final String? sevenZip = Platform.isWindows ? await _find7zipWindows() : await _whichFirst(['7z', '7za', '7zz']);
    if (sevenZip == null) {
      _logger.debug('7-Zip not found; skipping 7-Zip extraction. Hint: add 7-Zip to PATH or place it at ./gpth_tool/7zip/7z.exe', forcePrint: true);
      return false;
    }

    final String zipPath = zip.path;
    final String outDir = destinationDir.path;

    // 7z x "<zip>" -o"<outDir>" -y -aoa -mmt=on
    final List<String> args = ['x', zipPath, '-o$outDir', '-y', '-aoa', '-mmt=on'];
    _logger.debug('Running 7-Zip: $sevenZip ${args.join(' ')}', forcePrint: true);

    try {
      final ProcessResult result = await Process.run(sevenZip, args, runInShell: true);
      _logger.debug('7-Zip exitCode: ${result.exitCode}', forcePrint: true);
      final String so = (result.stdout ?? '').toString().trim();
      final String se = (result.stderr ?? '').toString().trim();
      if (so.isNotEmpty) _logger.debug('7-Zip stdout: $so', forcePrint: true);
      if (se.isNotEmpty) _logger.debug('7-Zip stderr: $se', forcePrint: true);
      return result.exitCode == 0;
    } catch (e) {
      _logger.debug('7-Zip invocation failed: $e', forcePrint: true);
      return false;
    }
  }

  /// Windows-specific deep search for 7-Zip executables.
  Future<String?> _find7zipWindows() async {
    // 1) PATH lookup
    final String? onPath = await _whichFirst(['7z.exe', '7za.exe', '7zz.exe']);
    if (onPath != null) return onPath;

    // 2) Common install locations
    final env = Platform.environment;
    final programFiles = env['ProgramFiles'];
    final programFilesX86 = env['ProgramFiles(x86)'];
    final chocolatey = env['ChocolateyInstall'];
    final scoop = env['SCOOP'];

    final List<String> candidates = <String>[
      if (programFiles != null) p.join(programFiles, '7-Zip', '7z.exe'),
      if (programFilesX86 != null) p.join(programFilesX86, '7-Zip', '7z.exe'),
      if (chocolatey != null) p.join(chocolatey, 'bin', '7z.exe'),
      if (scoop != null) p.join(scoop, 'apps', '7zip', 'current', '7z.exe'),
      // Project-relative bundled location (recommended to ship): ./gpth_tool/7zip/7z.exe
      p.normalize(p.join(Directory.current.path, 'gpth_tool', '7zip', '7z.exe')),
    ];

    for (final path in candidates) {
      final f = File(path);
      if (await f.exists()) {
        _logger.debug('Found 7-Zip at: $path', forcePrint: true);
        return path;
      }
    }
    return null;
  }

  /// Try unzip (macOS/Linux). Returns true on success.
  Future<bool> _tryExtractWithUnzip(final File zip, final Directory destinationDir) async {
    if (Platform.isWindows) return false;
    final String? unzipCmd = await _which('unzip');
    if (unzipCmd == null) {
      _logger.debug('unzip not found on PATH; skipping unzip extraction', forcePrint: true);
      return false;
    }

    final String zipPath = zip.path;
    final String outDir = destinationDir.path;

    // unzip -o "<zip>" -d "<outDir>"
    final List<String> args = ['-o', zipPath, '-d', outDir];
    _logger.debug('Running unzip: $unzipCmd ${args.join(' ')}', forcePrint: true);

    try {
      final ProcessResult result = await Process.run(unzipCmd, args, runInShell: true);
      _logger.debug('unzip exitCode: ${result.exitCode}', forcePrint: true);
      final String so = (result.stdout ?? '').toString().trim();
      final String se = (result.stderr ?? '').toString().trim();
      if (so.isNotEmpty) _logger.debug('unzip stdout: $so', forcePrint: true);
      if (se.isNotEmpty) _logger.debug('unzip stderr: $se', forcePrint: true);
      return result.exitCode == 0;
    } catch (e) {
      _logger.debug('unzip invocation failed: $e', forcePrint: true);
      return false;
    }
  }

  /// which for a single binary name.
  Future<String?> _which(final String cmd) async {
    try {
      if (Platform.isWindows) {
        final ProcessResult res = await Process.run('where', [cmd], runInShell: true);
        if (res.exitCode == 0) {
          final String out = (res.stdout ?? '').toString().trim();
          if (out.isNotEmpty) {
            final String first = out.split(RegExp(r'[\r\n]+')).first.trim();
            return first.isEmpty ? null : first;
          }
        }
      } else {
        final ProcessResult res = await Process.run('which', [cmd], runInShell: true);
        if (res.exitCode == 0) {
          final String out = (res.stdout ?? '').toString().trim();
          return out.isEmpty ? null : out;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Try multiple candidates; returns the first found.
  Future<String?> _whichFirst(final List<String> candidates) async {
    for (final c in candidates) {
      final String? found = await _which(c);
      if (found != null) return found;
    }
    return null;
  }

  /// Streamed extraction using archive v4 `decodeStream` API.
  ///
  /// Applies a mojibake fix (¥ -> Ñ/ñ) before sanitizing, then standard sanitization.
  Future<void> _extractZipStreamed(
    final File zip,
    final Directory destinationDir,
  ) async {
    final String destCanonical = p.canonicalize(destinationDir.path);

    final input = InputFileStream(zip.path);
    Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } finally {
      await input.close();
    }

    for (final ArchiveFile entry in archive) {
      // Diagnostics: log decoder-provided name
      if (enableNameDiagnostics && _looksSuspicious(entry.name)) {
        _logNameDiagnostics('decoder', entry.name);
      }

      // Heuristic fix for mojibake where Ñ/ñ became ¥
      final fixedName = _fixMojibakeYenToEnye(entry.name);

      // Diagnostics: log fixed form
      if (enableNameDiagnostics && fixedName != entry.name && _looksSuspicious(fixedName)) {
        _logNameDiagnostics('fixed', fixedName);
      }

      // Sanitize after fixing
      final String sanitizedRelative = _sanitizeFileName(fixedName);

      if (enableNameDiagnostics && _looksSuspicious(sanitizedRelative)) {
        _logNameDiagnostics('sanitized', sanitizedRelative);
      }

      final String fullPath = p.join(destinationDir.path, sanitizedRelative);

      // Zip Slip protection
      final String entryDirCanonical = p.canonicalize(p.dirname(fullPath));
      if (!entryDirCanonical.startsWith(destCanonical)) {
        throw SecurityException('Path traversal attempt detected: ${entry.name} -> $fullPath');
      }

      if (entry.isFile) {
        // Ensure parent directory exists
        final Directory parent = Directory(p.dirname(fullPath));
        await parent.create(recursive: true);

        // Streamed write using OutputFileStream
        final output = OutputFileStream(fullPath);
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
        }

        // Preserve file modification time if available
        try {
          await File(fullPath).setLastModified(DateTime.fromMillisecondsSinceEpoch(entry.lastModTime * 1000));
        } catch (e) {
          _logger.warning('Warning: Could not set modification time for $fullPath: $e');
        }
      } else if (entry.isDirectory) {
        final Directory outDir = Directory(fullPath);
        await outDir.create(recursive: true);
      }
    }
  }

  /// Heuristic to fix mojibake where 'Ñ/ñ' shows up as '¥'.
  ///
  /// Rules:
  /// - Replace U+00A5 with 'Ñ' if surrounded by uppercase context.
  /// - Replace U+00A5 with 'ñ' otherwise.
  /// - This is conservative and only touches the yen sign.
  String _fixMojibakeYenToEnye(final String name) {
    if (!name.contains('¥')) return name;

    final runes = name.runes.toList();
    final buffer = StringBuffer();

    bool isLatinUpper(final int r) => (r >= 0x41 && r <= 0x5A) || r == 0x00D1; // A-Z or Ñ
    for (int i = 0; i < runes.length; i++) {
      final r = runes[i];
      if (r == 0x00A5) {
        final prev = i > 0 ? runes[i - 1] : null;
        final next = i + 1 < runes.length ? runes[i + 1] : null;
        final upperContext = (prev != null && isLatinUpper(prev)) || (next != null && isLatinUpper(next));
        buffer.write(upperContext ? 'Ñ' : 'ñ');
      } else {
        buffer.write(String.fromCharCode(r));
      }
    }
    return buffer.toString();
  }

  /// Sanitizes file and directory names inside the archive path.
  ///
  /// Keeps Unicode characters (Ñ, accents, emojis) untouched. Only replaces
  /// characters invalid on Windows file systems and handles reserved names.
  /// Trailing dots/spaces are removed on Windows.
  ///
  /// NEW (cross-platform hardening):
  /// - Trim **trailing spaces and dots** on **every path segment** for *all* OS.
  ///   Google Takeout sometimes produces folder names with a trailing space
  ///   (e.g., `"Fotos de "`). We normalize those here to avoid later “No such file
  ///   or directory” when other modules compose paths.
  String _sanitizeFileName(final String fileName) {
    // The ZIP format uses forward slashes. Normalize, then sanitize each segment.
    final String unified = fileName.replaceAll('\\', '/');
    final List<String> rawSegments = unified.split('/');

    if (rawSegments.isEmpty) return fileName;

    final List<String> sanitizedSegments = <String>[];

    for (int i = 0; i < rawSegments.length; i++) {
      var seg = rawSegments[i];
      if (seg.isEmpty) continue; // skip empty (avoid accidental //)

      // Replace invalid characters (keep Unicode intact)
      seg = seg.replaceAll(RegExp(r'[<>:"|?*]'), '_');

      // Remove ASCII control characters from the segment
      seg = seg.replaceAll(RegExp(r'[\x00-\x1F]'), '_');

      // IMPORTANT: trim trailing spaces/dots on *all* platforms (Takeout quirk)
      // This is the only behavior change vs before; it prevents creating folders
      // ending with a space which later break path resolution.
      seg = seg.replaceAll(RegExp(r'[. ]+$'), '');

      // Windows reserved device names — we keep original behavior (apply on last segment).
      if (Platform.isWindows && i == rawSegments.length - 1) {
        final List<String> reservedNames = <String>[
          'CON','PRN','AUX','NUL','COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9','LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9',
        ];
        final String baseName = p.basenameWithoutExtension(seg);
        final String ext = p.extension(seg);
        if (reservedNames.contains(baseName.toUpperCase())) {
          seg = '${baseName}_file$ext';
        }
      }

      // Do not produce empty path components after trimming; substitute a safe marker.
      if (seg.isEmpty) seg = '_';

      sanitizedSegments.add(seg);
    }

    // Join using the platform separator so later p.join(...) remains consistent.
    return sanitizedSegments.join(Platform.pathSeparator);
  }

  /// Returns true if the name contains characters that usually indicate encoding issues.
  // ignore: prefer_expression_function_bodies
  bool _looksSuspicious(final String name) {
    return name.contains('¥') || name.contains('�') || name.contains('~');
    // The tilde (~) often appears in DOS 8.3 short names (e.g., RESIDE~4).
  }

  /// Logs the name with code points for diagnostics.
  void _logNameDiagnostics(final String stage, final String name) {
    final codePoints = name.runes.map((final r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(' ');
    _logger.info('[NameDiag][$stage] "$name"  ->  $codePoints', forcePrint: true);
  }

  /// Handles extraction errors with detailed error messages and user guidance.
  Never _handleExtractionError(
    final File zip,
    final Object errorObject, {
    final bool isArchiveError = false,
    final bool isPathError = false,
    final bool isFileSystemError = false,
  }) {
    final String zipName = p.basename(zip.path);

    _logger.error('');
    _logger.error('===============================================');
    _logger.error('❌ ERROR: Failed to extract $zipName');
    _logger.error('===============================================');

    if (isArchiveError) {
      _logger.error('💥 ZIP Archive Error:');
      _logger.error('The ZIP file appears to be corrupted or uses an unsupported format.');
      _logger.error('');
      _logger.error('🔧 Suggested Solutions:');
      _logger.error('• Re-download the ZIP file from Google Takeout');
      _logger.error('• Verify the file wasn\'t corrupted during download');
      _logger.error('• Try extracting manually with your system\'s built-in extractor');
    } else if (isPathError) {
      _logger.error('📁 Path/File Error:');
      _logger.error('There was an issue accessing files or creating directories.');
      _logger.error('');
      _logger.error('🔧 Suggested Solutions:');
      _logger.error('• Ensure you have sufficient permissions in the target directory');
      _logger.error('• Check that the target path is not too long (Windows limitation)');
      _logger.error('• Verify sufficient disk space is available');
    } else if (isFileSystemError) {
      _logger.error('💾 File System Error:');
      _logger.error('Unable to read the ZIP file or write extracted files.');
      _logger.error('');
      _logger.error('🔧 Suggested Solutions:');
      _logger.error('• Check file permissions on the ZIP file');
      _logger.error('• Ensure the ZIP file is not currently open in another program');
      _logger.error('• Verify the target directory is writable');
    } else {
      _logger.error('⚠️  Unexpected Error:');
      _logger.error('An unexpected error occurred during extraction.');
    }

    _logger.error('');
    _logger.error('📋 Error Details: $errorObject');
    _logger.error('');
    _logger.error('🔄 Alternative Options:');
    _logger.error('• Extract ZIP files manually using your system tools');
    _logger.error('• Use GPTH with command-line options on pre-extracted files');
    _logger.error('• See manual extraction guide: https://github.com/Xentraxx/GooglePhotosTakeoutHelper?tab=readme-ov-file#command-line-usage');
    _logger.error('');
    _logger.error('===============================================');
    _logger.error('');
    _logger.error('⚠️  ZIP EXTRACTION FAILED - CONTINUING WITH PROCESSING');
    _logger.error('The ZIP extraction failed, but GPTH will continue processing');
    _logger.error('any files that were successfully extracted before the error.');
    _logger.error('Please check the extraction directory for partial results.');

    // Propagate to caller
    throw Exception('ZIP extraction failed: $errorObject');
  }
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
