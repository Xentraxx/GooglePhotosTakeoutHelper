// ignore_for_file: non_constant_identifier_names

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:exif_reader/exif_reader.dart';
import 'package:mime/mime.dart';

import '../../../../infrastructure/exiftool_service.dart';
import '../../../../shared/constants.dart';
import '../../core/global_config_service.dart';
import '../../core/logging_service.dart';

/// Service for extracting dates from EXIF data
class ExifDateExtractor with LoggerMixin {
  /// Creates a new instance of ExifDateExtractor
  ExifDateExtractor(this.exiftool);

  /// The ExifTool service instance (can be null if ExifTool is not available)
  final ExifToolService? exiftool;

  /// DateTime from exif data *potentially* hidden within a [file]
  ///
  /// You can try this with *any* file, it either works or not 🤷
  Future<DateTime?> exifDateTimeExtractor(
    final File file, {
    required final GlobalConfigService globalConfig,
  }) async {
    //If file is >maxFileSize - return null. https://github.com/brendan-duncan/image/issues/457#issue-1549020643
    if (await file.length() > defaultMaxFileSize &&
        globalConfig.enforceMaxFileSize) {
      logError(
        'The file is larger than the maximum supported file size of ${defaultMaxFileSize.toString()} bytes. File: ${file.path}',
      );
      return null;
    }

    //Let me give a high level overview of what is happening here:
    //1. Try to get mimetype with lookupMimeType(file.path) by
    //  1. checking is the magic number (refering to https://en.wikipedia.org/wiki/List_of_file_signatures and https://github.com/dart-lang/tools/blob/main/pkgs/mime/lib/src/magic_number.dart) is well known. We do this because google takeout sometimes changed the file extension (e.g. mimeType is HEIC but it exports a .png)
    // Now we do or don't have a mimeType. We continue with:
    // 1. If the mimeType is supported by exif_reader, we use the exif_reader library to read exif. If that fails, exiftool is still used as a fallback, cause it's worth a try.
    // 2. If the mimeType is not supported by exif_reader or null, we try exiftool and don't even attempt exif_reader, because it would be pointless.

    //We only read the first 128 bytes as that's sufficient for MIME type detection
    final List<int> headerBytes = await File(file.path).openRead(0, 128).first;

    //Getting mimeType.
    final String? mimeType = lookupMimeType(
      file.path,
      headerBytes: headerBytes,
    );
    //lookupMimeType might return null e.g. for raw files. Even if Exiftool would be installed, using it to read the mimeType just to then decide if we use exiftool to read exif data or not
    //would completely defeat the purpose and actually compromise speed as we'd have to do 2 reads in some situations. In others we would still just do one read but have the additional native read.

    //We use the native way for all supported mimeTypes of exif_reader for speed and performance. We trust the list at https://pub.dev/packages/exif_reader
    //We also know that the mimeTypes for RAW can never happen because the lookupMimeType() does not support them. However, leaving there in here for now cause they don't hurt.
    final supportedNativeMimeTypes = {
      'image/jpeg',
      'image/tiff',
      'image/heic',
      'image/png',
      'image/webp',
      'image/jxl',
      'image/x-sony-arw',
      'image/x-canon-cr2',
      'image/x-canon-cr3',
      'image/x-canon-crw',
      'image/x-nikon-nef',
      'image/x-nikon-nrw',
      'image/x-panasonic-rw2',
      'image/x-fuji-raf',
      'image/x-adobe-dng',
      'image/x-raw',
      'image/tiff-fx',
      'image/x-portable-anymap',
    };

    DateTime?
    result; //this variable should be filled. That's the goal from here on.

    // For video files, we should use exiftool directly
    if (mimeType?.startsWith('video/') == true) {
      if (globalConfig.exifToolInstalled) {
        result = await _exifToolExtractor(file);
        if (result != null) {
          return result;
        }
      }
      logWarning(
        'Reading exif from ${file.path} with mimeType $mimeType skipped. Reading from this kind of file is only supported with exiftool.',
      );
      return null;
    }

    if (supportedNativeMimeTypes.contains(mimeType)) {
      result = await _nativeExif_readerExtractor(file);
      if (result != null) {
        return result;
      } else {
        //If we end up here, we have a mimeType which should be supported by exif_reader, but the read failed regardless.
        //Most probably the file does not contain any DateTime in exif. So we return null.
        return null;
      }
    }
    //At this point either we didn't do anything because the mimeType is unknown (null) or not supported by the native method.
    //Anyway, there is nothing else to do than to try it with exiftool now. exiftool is the last resort *sing* in any case due to performance.  if ((mimeType == null || !supportedNativeMimeTypes.contains(mimeType)) &&
    if (globalConfig.exifToolInstalled) {
      result = await _exifToolExtractor(file);
      if (result != null) {
        return result; //We did get a DateTime from Exiftool and return it. It's being logged in _exifToolExtractor(). We are happy.
      }
    }

    //This logic below is only to give a tailored error message because if you get here, sorry, then result stayed empty and we just don't support the file type.
    if (mimeType == 'image/jpeg') {
      logWarning(
        '${file.path} has a mimeType of $mimeType. However, could not read it with exif_reader. This means, the file is probably corrupt',
      );
    } else if (globalConfig.exifToolInstalled) {
      logError(
        "$mimeType is a weird mime type! Please create an issue if you get this error message, as we currently can't handle it.",
      );
    } else {
      logWarning(
        'Reading exif from ${file.path} with mimeType $mimeType skipped. Reading from this kind of file is probably only supported with exiftool.',
      );
    }
    return result; //If we can't get mimeType, result will be null as there is probably no point in moving forward to read other metadata.
  }

  /// Extracts DateTime from file using ExifTool
  ///
  /// Reads various DateTime tags in order of reliability and attempts to
  /// parse them into a valid DateTime object. Handles date normalization
  /// and validates against edge cases.
  ///
  /// [file] File to extract DateTime from
  /// Returns parsed DateTime or null if extraction fails
  Future<DateTime?> _exifToolExtractor(final File file) async {
    // Return null if ExifTool is not available
    if (exiftool == null) {
      return null;
    }

    try {
      final tags = await exiftool!.readExifData(file);
      final dynamic datetimeValue =
          tags['DateTimeOriginal'] ??
          tags['MediaCreateDate'] ??
          tags['CreationDate'] ??
          tags['TrackCreateDate'] ??
          tags['CreateDate'] ??
          tags['DateTimeDigitized'] ??
          tags['GPSDateStamp'] ??
          tags['DateTime'];

      if (datetimeValue == null) {
        logWarning(
          "Exiftool was not able to extract an acceptable DateTime for ${file.path}.\n\tThose Tags are accepted: 'DateTimeOriginal', 'MediaCreateDate', 'CreationDate','TrackCreateDate','. The file has those Tags: ${tags.toString()}",
        );
        return null;
      }

      String datetime = datetimeValue.toString();
      // Normalize separators and parse
      datetime = datetime
          .replaceAll('-', ':')
          .replaceAll('/', ':')
          .replaceAll('.', ':')
          .replaceAll('\\', ':')
          .replaceAll(': ', ':0')
          .substring(0, math.min(datetime.length, 19))
          .replaceFirst(':', '-')
          .replaceFirst(':', '-');

      final DateTime? parsedDateTime = DateTime.tryParse(datetime);
      if (parsedDateTime == DateTime.parse('2036-01-01T23:59:59.000000Z')) {
        //we keep this for safety for this edge case: https://ffmpeg.org/pipermail/ffmpeg-user/2023-April/056265.html
        logWarning(
          'Extracted DateTime before January 1st 1970 from EXIF for ${file.path}. Therefore the DateTime from other extractors is not being changed.',
        );
        return null;
      } else {
        //Successfully extracted DateTime
        return parsedDateTime;
      }
    } catch (e) {
      logError('exiftool read failed: ${e.toString()}');
      return null;
    }
  }

  /// Extracts DateTime from file using native exif_reader library
  ///
  /// Faster than ExifTool but supports fewer file formats. Reads standard
  /// EXIF DateTime tags and normalizes the format for parsing using the native exif_reader library.
  ///
  /// [file] File to extract DateTime from
  /// Returns parsed DateTime or null if extraction fails
  Future<DateTime?> _nativeExif_readerExtractor(final File file) async {
    // Read only the first 64KB which should contain EXIF APP1/APP2 segments.
    const int exifScanWindow = 64 * 1024; // 64KB
    final int fileLength = await file.length();
    final int end = fileLength < exifScanWindow ? fileLength : exifScanWindow;
    final bytesBuilder = BytesBuilder(copy: false);
    // ignore: prefer_foreach
    await for (final chunk in file.openRead(0, end)) {
      bytesBuilder.add(chunk);
    }
    final tags = await readExifFromBytes(bytesBuilder.takeBytes());
    String? datetime;
    // try if any of these exists
    datetime ??= tags['Image DateTime']?.printable;
    datetime ??= tags['EXIF DateTimeOriginal']?.printable;
    datetime ??= tags['EXIF DateTimeDigitized']?.printable;
    if (datetime == null || datetime.isEmpty) return null;
    // Normalize separators and parse
    datetime = datetime
        .replaceAll('-', ':')
        .replaceAll('/', ':')
        .replaceAll('.', ':')
        .replaceAll('\\', ':')
        .replaceAll(': ', ':0')
        .substring(0, math.min(datetime.length, 19))
        .replaceFirst(':', '-')
        .replaceFirst(':', '-');

    final DateTime? parsedDateTime = DateTime.tryParse(datetime);
    if (parsedDateTime == DateTime.parse('2036-01-01T23:59:59.000000Z')) {
      //we keep this for safety for this edge case: https://ffmpeg.org/pipermail/ffmpeg-user/2023-April/056265.html
      logWarning(
        'Extracted DateTime before January 1st 1970 from EXIF for ${file.path}. Therefore the DateTime from other extractors is not being changed.',
      );
      return null;
    } else {
      //Successfully extracted DateTime
      return parsedDateTime;
    }
  }
}
