import 'dart:io';
import 'dart:typed_data';
import 'package:exif_reader/exif_reader.dart';
import 'package:mime/mime.dart';
import 'package:gpth/gpth-lib.dart';

/// GPS extractor with instrumentation (time in seconds).
class ExifCoordinateExtractor with LoggerMixin {
  ExifCoordinateExtractor(this.exiftool);
  final ExifToolService? exiftool;

  // Instrumentation
  static int nativeHit = 0;
  static int nativeMiss = 0;
  static int fallbackTried = 0;
  static int exifToolHit = 0;
  static int exifToolMiss = 0;

  static Duration nativeDur = Duration.zero;
  static Duration exiftoolDur = Duration.zero;

  static String _fmtSec(final Duration d) =>
      '${(d.inMilliseconds / 1000.0).toStringAsFixed(3)}s';

  static void dumpStats({
    final bool reset = false,
    final LoggerMixin? loggerMixin,
  }) {
    final line =
        '[GPS-EXTRACT]: '
        'nativeHit=$nativeHit, nativeMiss=$nativeMiss, fallbackTried=$fallbackTried, '
        'exifToolHit=$exifToolHit, exifToolMiss=$exifToolMiss, '
        'nativeTime=${_fmtSec(nativeDur)}, exiftoolTime=${_fmtSec(exiftoolDur)}';

    if (loggerMixin != null) {
      loggerMixin.logInfo(line, forcePrint: true);
      print('');
    } else {
      print(line);
      print('');
    }

    if (reset) {
      nativeHit = 0;
      nativeMiss = 0;
      fallbackTried = 0;
      exifToolHit = 0;
      exifToolMiss = 0;
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
          exifToolHit++;
          return m;
        } else {
          exifToolMiss++;
        }
      }
      return null;
    }

    if (supportedNativeExifMimeTypes.contains(mimeType)) {
      final sw = Stopwatch()..start();
      final m = await _nativeExif_readerGPSExtractor(file);
      nativeDur += sw.elapsed;

      if (m != null) {
        nativeHit++;
        return m;
      } else {
        nativeMiss++;
        if (globalConfig.exifToolInstalled) {
          fallbackTried++;
          final sw2 = Stopwatch()..start();
          final n = await _exifToolGPSExtractor(file);
          exiftoolDur += sw2.elapsed;
          if (n != null) {
            exifToolHit++;
            return n;
          } else {
            exifToolMiss++;
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
        exifToolHit++;
        return m;
      } else {
        exifToolMiss++;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _nativeExif_readerGPSExtractor(
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
