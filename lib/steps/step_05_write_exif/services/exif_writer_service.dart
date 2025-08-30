import 'dart:io';
import 'dart:typed_data';
import 'package:coordinate_converter/coordinate_converter.dart';
import 'package:image/image.dart';
import 'package:intl/intl.dart';
import 'package:gpth/gpth-lib.dart';

/// Service that writes EXIF data (fast native JPEG path + adaptive exiftool batching).
/// Includes detailed instrumentation of counts and durations (seconds).
class ExifWriterService with LoggerMixin {
  ExifWriterService(this._exifTool);

  final ExifToolService _exifTool;

  // ───────────────────── Instrumentation (per-process static) ─────────────────
  // Calls
  static int exiftoolCalls = 0; // number of exiftool invocations

  // Unique file tracking (authoritative for Step 5 final “files got …”)
  static final Set<String> _touchedFiles = <String>{};
  static final Set<String> _dateTouchedFiles = <String>{};
  static final Set<String> _gpsTouchedFiles = <String>{};

  // NEW: split by primary/secondary so Step 5 can show the breakdown in parentheses.
  static final Set<String> _dateTouchedPrimary = <String>{};
  static final Set<String> _dateTouchedSecondary = <String>{};
  static final Set<String> _gpsTouchedPrimary = <String>{};
  static final Set<String> _gpsTouchedSecondary = <String>{};

  static void _markTouched(final File file, {required bool date, required bool gps}) {
    final p = file.path;
    _touchedFiles.add(p);
    if (date) _dateTouchedFiles.add(p);
    if (gps) _gpsTouchedFiles.add(p);
  }

  /// NEW: public helpers so Step 5 (who knows primary vs secondary) can annotate the unique sets accordingly.
  static void markDateTouchedFromStep5(final File file, {required bool isPrimary}) {
    final p = file.path;
    _touchedFiles.add(p);
    _dateTouchedFiles.add(p);
    if (isPrimary) {
      _dateTouchedPrimary.add(p);
      // If it was already in secondary set (shouldn't happen), keep unique semantics anyway.
      _dateTouchedSecondary.remove(p);
    } else {
      // Only add to secondary if not already marked as primary.
      if (!_dateTouchedPrimary.contains(p)) _dateTouchedSecondary.add(p);
    }
  }

  static void markGpsTouchedFromStep5(final File file, {required bool isPrimary}) {
    final p = file.path;
    _touchedFiles.add(p);
    _gpsTouchedFiles.add(p);
    if (isPrimary) {
      _gpsTouchedPrimary.add(p);
      _gpsTouchedSecondary.remove(p);
    } else {
      if (!_gpsTouchedPrimary.contains(p)) _gpsTouchedSecondary.add(p);
    }
  }

  static int get uniqueFilesTouchedCount => _touchedFiles.length;
  static int get uniqueDateFilesCount => _dateTouchedFiles.length;
  static int get uniqueGpsFilesCount => _gpsTouchedFiles.length;

  // NEW: getters for the split
  static int get uniqueDatePrimaryCount => _dateTouchedPrimary.length;
  static int get uniqueDateSecondaryCount => _dateTouchedSecondary.length;
  static int get uniqueGpsPrimaryCount => _gpsTouchedPrimary.length;
  static int get uniqueGpsSecondaryCount => _gpsTouchedSecondary.length;

  static void _resetTouched() {
    _touchedFiles.clear();
    _dateTouchedFiles.clear();
    _gpsTouchedFiles.clear();
    _dateTouchedPrimary.clear();
    _dateTouchedSecondary.clear();
    _gpsTouchedPrimary.clear();
    _gpsTouchedSecondary.clear();
  }

  // Native path (success/fail split by type)
  static int nativeDateWritten = 0;
  static int nativeGpsWritten = 0;
  static int nativeCombinedWritten = 0;
  static int nativeDateFails = 0;
  static int nativeGpsFails = 0;
  static int nativeCombinedFails = 0;

  // ExifTool path (success/fail split by type)
  // IMPORTANT: “Processed” means success + fail (for symmetry with Native).
  static int exiftoolProcessedFiles = 0;    // success + fail (single or batch)
  static int exiftoolSuccessFiles = 0;      // success only
  static int exiftoolFailFiles = 0;         // fail only

  // Routing breakdown for ExifTool
  static int exiftoolDirectFiles = 0;       // sent directly (non-JPEG or decided to go exiftool)
  static int exiftoolFallbackFiles = 0;     // routed to exiftool after a native JPEG attempt failed

  // ExifTool success by category
  static int exiftoolDateWritten = 0;
  static int exiftoolGpsWritten = 0;
  static int exiftoolCombinedWritten = 0;

  // ExifTool fails by category
  static int exiftoolDateFails = 0;
  static int exiftoolGpsFails = 0;
  static int exiftoolCombinedFails = 0;

  // Durations
  static Duration nativeDateTimeDur = Duration.zero;
  static Duration nativeGpsDur = Duration.zero;
  static Duration nativeCombinedDur = Duration.zero;
  static Duration exiftoolDateTimeDur = Duration.zero;
  static Duration exiftoolGpsDur = Duration.zero;
  static Duration exiftoolCombinedDur = Duration.zero;

  static String _fmtSec(final Duration d) => '${(d.inMilliseconds / 1000.0).toStringAsFixed(3)}s';

  /// Print instrumentation lines; reset counters optionally.
  static void dumpWriterStats({final bool reset = true, final LoggerMixin? logger}) {
    // Native totals: processed = successes + fails
    final int nativeProcessed =
        nativeDateWritten + nativeGpsWritten + nativeCombinedWritten +
        nativeDateFails + nativeGpsFails + nativeCombinedFails;

    final lines = <String>[
      '[WRITE-EXIF] Native  : totalFiles=$nativeProcessed, dateWritten=$nativeDateWritten, gpsWritten=$nativeGpsWritten, combinedWritten=$nativeCombinedWritten, dateFails=$nativeDateFails, gpsFails=$nativeGpsFails, combinedFails=$nativeCombinedFails, dateTime=${_fmtSec(nativeDateTimeDur)}, gpsTime=${_fmtSec(nativeGpsDur)}, combinedTime=${_fmtSec(nativeCombinedDur)}',
      '[WRITE-EXIF] Exiftool: totalFiles=$exiftoolProcessedFiles (success=$exiftoolSuccessFiles, fail=$exiftoolFailFiles, direct=$exiftoolDirectFiles, fallback=$exiftoolFallbackFiles), dateWritten=$exiftoolDateWritten, gpsWritten=$exiftoolGpsWritten, combinedWritten=$exiftoolCombinedWritten, dateFails=$exiftoolDateFails, gpsFails=$exiftoolGpsFails, combinedFails=$exiftoolCombinedFails, dateTime=${_fmtSec(exiftoolDateTimeDur)}, gpsTime=${_fmtSec(exiftoolGpsDur)}, combinedTime=${_fmtSec(exiftoolCombinedDur)}, exiftoolCalls=$exiftoolCalls',
    ];
    print('');
    for (final l in lines) {
      if (logger != null) {
        logger.logInfo(l, forcePrint: true);
      } else {
        // ignore: avoid_print
        print(l);
      }
    }
    if (reset) {
      exiftoolCalls = 0;

      _resetTouched();

      nativeDateWritten = 0;
      nativeGpsWritten = 0;
      nativeCombinedWritten = 0;
      nativeDateFails = 0;
      nativeGpsFails = 0;
      nativeCombinedFails = 0;

      exiftoolProcessedFiles = 0;
      exiftoolSuccessFiles = 0;
      exiftoolFailFiles = 0;

      exiftoolDirectFiles = 0;
      exiftoolFallbackFiles = 0;

      exiftoolDateWritten = 0;
      exiftoolGpsWritten = 0;
      exiftoolCombinedWritten = 0;
      exiftoolDateFails = 0;
      exiftoolGpsFails = 0;
      exiftoolCombinedFails = 0;

      nativeDateTimeDur = Duration.zero;
      nativeGpsDur = Duration.zero;
      nativeCombinedDur = Duration.zero;
      exiftoolDateTimeDur = Duration.zero;
      exiftoolGpsDur = Duration.zero;
      exiftoolCombinedDur = Duration.zero;
    }
  }

  // ─────────────────────────── Internal helpers ──────────────────────────────

  /// Heuristic: determine if this exiftool write looks like a fallback after a native JPEG attempt.
  /// In current Step 5 implementation, tags for JPEG are only enqueued when native fails.
  static bool _looksLikeFallbackToExiftool(final File file, final Map<String, dynamic> tags) {
    final p = file.path.toLowerCase();
    if (!(p.endsWith('.jpg') || p.endsWith('.jpeg'))) return false;
    final keys = tags.keys;
    final hasDate = keys.any((k) => k == 'DateTimeOriginal' || k == 'DateTimeDigitized' || k == 'DateTime');
    final hasGps = keys.any((k) => k == 'GPSLatitude' || k == 'GPSLongitude' || k == 'GPSLatitudeRef' || k == 'GPSLongitudeRef');
    return hasDate || hasGps;
  }

  /// Classify tag map into (date/gps/combined) for counters.
  static ({bool isDate, bool isGps, bool isCombined}) _classifyTags(final Map<String, dynamic> tags) {
    final keys = tags.keys;
    final hasDate = keys.any((k) => k == 'DateTimeOriginal' || k == 'DateTimeDigitized' || k == 'DateTime');
    final hasGps = keys.any((k) => k == 'GPSLatitude' || k == 'GPSLongitude' || k == 'GPSLatitudeRef' || k == 'GPSLongitudeRef');
    return (isDate: hasDate && !hasGps, isGps: !hasDate && hasGps, isCombined: hasDate && hasGps);
  }

  static void _countExiftoolSuccess(final bool isDate, final bool isGps, final bool isCombined, final Duration elapsed, final File file) {
    exiftoolSuccessFiles++;
    if (isCombined) {
      exiftoolCombinedWritten++;
      exiftoolCombinedDur += elapsed;
      _markTouched(file, date: true, gps: true);
    } else {
      if (isDate) {
        exiftoolDateWritten++;
        exiftoolDateTimeDur += elapsed;
        _markTouched(file, date: true, gps: false);
      }
      if (isGps) {
        exiftoolGpsWritten++;
        exiftoolGpsDur += elapsed;
        _markTouched(file, date: false, gps: true);
      }
    }
  }

  static void _countExiftoolFail(final bool isDate, final bool isGps, final bool isCombined) {
    exiftoolFailFiles++;
    if (isCombined) {
      exiftoolCombinedFails++;
    } else {
      if (isDate) exiftoolDateFails++;
      if (isGps) exiftoolGpsFails++;
    }
  }

  // ─────────────────────────── Public helpers ────────────────────────────────

  /// Single-exec write for arbitrary tags (counts as one exiftool call).
  Future<bool> writeTagsWithExifTool(
    final File file,
    final Map<String, dynamic> tags, {
    final bool countAsCombined = false, // kept for backward compat, but classification below is preferred
    final bool isDate = false,          // kept for backward compat
    final bool isGps = false,           // kept for backward compat
  }) async {
    if (tags.isEmpty) return false;

    final sw = Stopwatch()..start();
    final looksFallback = _looksLikeFallbackToExiftool(file, tags);
    final cls = _classifyTags(tags);
    final bool asCombined = countAsCombined || cls.isCombined;
    final bool asDate = isDate || cls.isDate;
    final bool asGps = isGps || cls.isGps;

    // Count as “processed” no matter success or failure (symmetry with Native).
    exiftoolProcessedFiles++;
    if (looksFallback) exiftoolFallbackFiles++; else exiftoolDirectFiles++;

    try {
      await _exifTool.writeExifData(file, tags);
      exiftoolCalls++;
      _countExiftoolSuccess(asDate, asGps, asCombined, sw.elapsed, file);
      return true;
    } catch (e) {
      _countExiftoolFail(asDate, asGps, asCombined);
      logError('Failed to write tags ${tags.keys.toList()} to ${file.path}: $e');
      return false;
    }
  }

  /// Batch write: list of (file -> tags). Counts one exiftool call.
  /// Time attribution is **proportional** across categories to avoid overcount.
  /// Also splits "direct vs fallback" using the same heuristic per entry.
  Future<void> writeBatchWithExifTool(
    final List<MapEntry<File, Map<String, dynamic>>> batch, {
    required final bool useArgFileWhenLarge,
  }) async {
    if (batch.isEmpty) return;

    // Before running the batch, classify every entry so we can record processed and routing consistently.
    final entriesMeta = <({File file, bool isDate, bool isGps, bool isCombined, bool isFallback})>[];
    int countDate = 0, countGps = 0, countCombined = 0;
    int direct = 0, fallback = 0;

    for (final entry in batch) {
      final cls = _classifyTags(entry.value);
      final isFallback = _looksLikeFallbackToExiftool(entry.key, entry.value);
      entriesMeta.add((
        file: entry.key,
        isDate: cls.isDate,
        isGps: cls.isGps,
        isCombined: cls.isCombined,
        isFallback: isFallback,
      ));
      if (cls.isCombined) countCombined++; else if (cls.isDate) countDate++; else if (cls.isGps) countGps++;
      if (isFallback) fallback++; else direct++;
    }

    // Mark all entries as “processed” and attribute routing now (batch is one attempt).
    exiftoolProcessedFiles += batch.length;
    exiftoolDirectFiles += direct;
    exiftoolFallbackFiles += fallback;

    final totalTagged = (countDate + countGps + countCombined).clamp(1, 1 << 30); // avoid div/0
    final sw = Stopwatch()..start();
    try {
      if (useArgFileWhenLarge) {
        await _exifTool.writeExifDataBatchViaArgFile(batch);
      } else {
        await _exifTool.writeExifDataBatch(batch);
      }
      exiftoolCalls++;

      final elapsed = sw.elapsed;
      // Proportional time attribution for success totals
      if (countCombined > 0) {
        exiftoolCombinedWritten += countCombined;
        exiftoolCombinedDur += elapsed * (countCombined / totalTagged);
      }
      if (countDate > 0) {
        exiftoolDateWritten += countDate;
        exiftoolDateTimeDur += elapsed * (countDate / totalTagged);
      }
      if (countGps > 0) {
        exiftoolGpsWritten += countGps;
        exiftoolGpsDur += elapsed * (countGps / totalTagged);
        logInfo('[WRITE-EXIF] GPS written via exiftool (batch): $countGps files');
      }

      // All entries succeeded → count successes and mark unique files by type.
      exiftoolSuccessFiles += batch.length;
      for (final m in entriesMeta) {
        if (m.isCombined) {
          _markTouched(m.file, date: true, gps: true);
        } else if (m.isDate) {
          _markTouched(m.file, date: true, gps: false);
        } else if (m.isGps) {
          _markTouched(m.file, date: false, gps: true);
        }
      }
    } catch (e) {
      // Batch failed as a whole; Step 5 will split and retry per-file.
      logError('Batch exiftool write failed: $e');
      rethrow;
    }
  }

  // ─────────────────────── Native JPEG implementations ───────────────────────

  /// Native JPEG DateTime write (returns true if wrote; false if failed).
  Future<bool> writeDateTimeNativeJpeg(
    final File file,
    final DateTime dateTime,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final Uint8List orig = await file.readAsBytes();
      final exif = decodeJpgExif(orig);
      if (exif == null || exif.isEmpty) { nativeDateFails++; return false; }

      final fmt = DateFormat('yyyy:MM:dd HH:mm:ss');
      final dt = fmt.format(dateTime);

      exif.imageIfd['DateTime'] = dt;
      exif.exifIfd['DateTimeOriginal'] = dt;
      exif.exifIfd['DateTimeDigitized'] = dt;

      final Uint8List? out = injectJpgExif(orig, exif);
      if (out == null) { nativeDateFails++; return false; }

      await file.writeAsBytes(out);
      nativeDateWritten++;
      nativeDateTimeDur += sw.elapsed;
      _markTouched(file, date: true, gps: false);
      return true;
    } catch (e) {
      nativeDateFails++;
      logError('Native JPEG DateTime write failed for ${file.path}: $e');
      return false;
    }
  }

  /// Native JPEG GPS write (returns true if wrote; false if failed).
  Future<bool> writeGpsNativeJpeg(
    final File file,
    final DMSCoordinates coords,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final Uint8List orig = await file.readAsBytes();
      final exif = decodeJpgExif(orig);
      if (exif == null || exif.isEmpty) { nativeGpsFails++; return false; }

      exif.gpsIfd.gpsLatitude = coords.toDD().latitude;
      exif.gpsIfd.gpsLongitude = coords.toDD().longitude;
      exif.gpsIfd.gpsLatitudeRef = coords.latDirection.abbreviation;
      exif.gpsIfd.gpsLongitudeRef = coords.longDirection.abbreviation;

      final Uint8List? out = injectJpgExif(orig, exif);
      if (out == null) { nativeGpsFails++; return false; }

      await file.writeAsBytes(out);
      nativeGpsWritten++;
      nativeGpsDur += sw.elapsed;
      _markTouched(file, date: false, gps: true);
      logInfo('[WRITE-EXIF] GPS written natively (JPEG): ${file.path}');
      return true;
    } catch (e) {
      nativeGpsFails++;
      logError('Native JPEG GPS write failed for ${file.path}: $e');
      return false;
    }
  }

  /// Native JPEG combined write (Date+GPS). Returns true if wrote; false if failed.
  Future<bool> writeCombinedNativeJpeg(
    final File file,
    final DateTime dateTime,
    final DMSCoordinates coords,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final Uint8List orig = await file.readAsBytes();
      final exif = decodeJpgExif(orig);
      if (exif == null || exif.isEmpty) { nativeCombinedFails++; return false; }

      final fmt = DateFormat('yyyy:MM:dd HH:mm:ss');
      final dt = fmt.format(dateTime);

      exif.imageIfd['DateTime'] = dt;
      exif.exifIfd['DateTimeOriginal'] = dt;
      exif.exifIfd['DateTimeDigitized'] = dt;

      exif.gpsIfd.gpsLatitude = coords.toDD().latitude;
      exif.gpsIfd.gpsLongitude = coords.toDD().longitude;
      exif.gpsIfd.gpsLatitudeRef = coords.latDirection.abbreviation;
      exif.gpsIfd.gpsLongitudeRef = coords.longDirection.abbreviation;

      final Uint8List? out = injectJpgExif(orig, exif);
      if (out == null) { nativeCombinedFails++; return false; }

      await file.writeAsBytes(out);
      nativeCombinedWritten++;
      nativeCombinedDur += sw.elapsed;
      _markTouched(file, date: true, gps: true);
      logInfo('[WRITE-EXIF] Date+GPS written natively (JPEG): ${file.path}');
      return true;
    } catch (e) {
      nativeCombinedFails++;
      logError('Native JPEG combined write failed for ${file.path}: $e');
      return false;
    }
  }
}
