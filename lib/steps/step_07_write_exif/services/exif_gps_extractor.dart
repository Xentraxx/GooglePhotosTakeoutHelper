import 'dart:io';
import 'dart:typed_data';

import 'package:exif_reader/exif_reader.dart';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:mime/mime.dart';

/// GPS extractor with instrumentation (time in seconds).
class ExifGpsExtractor with LoggerMixin {
  ExifGpsExtractor(this.exiftool);
  final ExifToolService? exiftool;

  // Instrumentation
  static int hitNative = 0;
  static int missNative = 0;
  static int fallbackTried = 0;
  static int hitExiftool = 0;
  static int missExiftool = 0;

  static Duration nativeDur = Duration.zero;
  static Duration exiftoolDur = Duration.zero;

  static String _fmtSec(final Duration d) =>
      '${(d.inMilliseconds / 1000.0).toStringAsFixed(3)}s';

  static void dumpStats({
    final bool reset = false,
    final LoggerMixin? loggerMixin,
  }) {
    final lineNative =
        '[GPS-EXTRACT] Native  : hitNative=$hitNative, missNative=$missNative, nativeTime=${_fmtSec(nativeDur)}';
    final lineExiftool =
        '[GPS-EXTRACT] Exiftool: hitExifTool=$hitExiftool, missExifTool=$missExiftool, exiftoolTime=${_fmtSec(exiftoolDur)} (fallbackTried=$fallbackTried)';

    if (loggerMixin != null) {
      loggerMixin.logInfo(lineNative, forcePrint: true);
      loggerMixin.logInfo(lineExiftool, forcePrint: true);
      print('');
    } else {
      print(lineNative);
      print('');
    }

    if (reset) {
      hitNative = 0;
      missNative = 0;
      fallbackTried = 0;
      hitExiftool = 0;
      missExiftool = 0;
      nativeDur = Duration.zero;
      exiftoolDur = Duration.zero;
    }
  }

  // ignore: strict_top_level_inference
  bool _isValidCoord(final v) {
    if (v == null) return false;
    final s = v.toString().trim();
    if (s.isEmpty) return false;
    if (s == '0' || s == '0.0' || s == '0,0') return false;
    if (s.toLowerCase() == 'nan') return false;
    return true;
  }

  /// Extract GPS coordinates; native first for supported formats; fallback to ExifTool.
  Future<Map<String, dynamic>?> extractGPSCoordinates(
    final File file, {
    required final GlobalConfigService globalConfig,
  }) async {
    if (await file.length() > defaultMaxFileSize &&
        globalConfig.enforceMaxFileSize) {
      logError(
        'File is larger than ${defaultMaxFileSize.toString()} bytes. GPS read skipped: ${file.path}',
      );
      return null;
    }

    final List<int> headerBytes = await File(file.path).openRead(0, 128).first;
    final String? mimeType = lookupMimeType(
      file.path,
      headerBytes: headerBytes,
    );

    if (mimeType?.startsWith('video/') == true) {
      // Go straight to exiftool for videos
      if (globalConfig.exifToolInstalled) {
        final sw = Stopwatch()..start();
        final m = await _exifToolGPSExtractor(file);
        exiftoolDur += sw.elapsed;
        if (m != null) {
          hitExiftool++;
          return m;
        } else {
          missExiftool++;
        }
      }
      return null;
    }

    if (supportedNativeExifMimeTypes.contains(mimeType)) {
      final sw = Stopwatch()..start();
      final m = await _nativeExif_readerGpsExtractor(file);
      nativeDur += sw.elapsed;

      if (m != null) {
        hitNative++;
        return m;
      } else {
        missNative++;
        if (globalConfig.exifToolInstalled) {
          fallbackTried++;
          final sw2 = Stopwatch()..start();
          final n = await _exifToolGPSExtractor(file);
          exiftoolDur += sw2.elapsed;
          if (n != null) {
            hitExiftool++;
            return n;
          } else {
            missExiftool++;
          }
        }
      }
      return null;
    }

    if (globalConfig.exifToolInstalled) {
      final sw = Stopwatch()..start();
      final m = await _exifToolGPSExtractor(file);
      exiftoolDur += sw.elapsed;
      if (m != null) {
        hitExiftool++;
        return m;
      } else {
        missExiftool++;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _nativeExif_readerGpsExtractor(
    final File file,
  ) async {
    try {
      // Read only the first 64KB which typically contains EXIF APP segments
      const int exifScanWindow = 64 * 1024;
      final int fileLength = await file.length();
      final int end = fileLength < exifScanWindow ? fileLength : exifScanWindow;
      final bytesBuilder = BytesBuilder(copy: false);
      // ignore: prefer_foreach
      await for (final chunk in file.openRead(0, end)) {
        bytesBuilder.add(chunk);
      }
      final tags = await readExifFromBytes(bytesBuilder.takeBytes());

      final latitude = tags['GPS GPSLatitude']?.printable;
      final longitude = tags['GPS GPSLongitude']?.printable;
      final latRef = tags['GPS GPSLatitudeRef']?.printable;
      final longRef = tags['GPS GPSLongitudeRef']?.printable;

      if (_isValidCoord(latitude) && _isValidCoord(longitude)) {
        return {
          'GPSLatitude': latitude,
          'GPSLongitude': longitude,
          'GPSLatitudeRef': latRef,
          'GPSLongitudeRef': longRef,
        };
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _exifToolGPSExtractor(final File file) async {
    if (exiftool == null) return null;
    try {
      final tags = await exiftool!.readExifData(file);
      if (_isValidCoord(tags['GPSLatitude']) &&
          _isValidCoord(tags['GPSLongitude'])) {
        return {
          'GPSLatitude': tags['GPSLatitude'],
          'GPSLongitude': tags['GPSLongitude'],
          'GPSLatitudeRef': tags['GPSLatitudeRef'],
          'GPSLongitudeRef': tags['GPSLongitudeRef'],
        };
      }
      return null;
    } catch (e) {
      logError('exiftool GPS read failed: $e');
      return null;
    }
  }
}
