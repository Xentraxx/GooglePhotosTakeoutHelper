import 'dart:io';
import 'dart:typed_data';
import 'package:coordinate_converter/coordinate_converter.dart';
import 'package:image/image.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'date_extractors/exif_extractor.dart';
import 'exiftoolInterface.dart';
import 'utils.dart';

Future<bool> writeDateTimeToExif(
  final DateTime dateTime,
  final File file,
) async {
  final List<int> headerBytes = await File(file.path).openRead(0, 128).first;
  final String? mimeTypeFromHeader = lookupMimeType(
    file.path,
    headerBytes: headerBytes,
  );
  final String? mimeTypeFromExtension = lookupMimeType(file.path);

  //Check if the file already has a dateTime in its EXIF data. If function returns a DateTime, there is no need to write it again. Skip.
  if (await exifDateTimeExtractor(file) != null) {
    return false;
  }

  if (exifToolInstalled) {
    //Even if exifTool is installed, try to use native way for speed first and if it works keep going. If not, use exiftool.
    if (mimeTypeFromHeader == 'image/jpeg' &&
        await _noExifToolDateTimeWriter(file, dateTime, mimeTypeFromHeader)) {
      return true; //If native way was able to write exif data: exit. If not, try exifTool.
    }

    if (mimeTypeFromExtension != mimeTypeFromHeader &&
        mimeTypeFromHeader != 'image/tiff') {
      log(
        "DateWriter - File has a wrong extension indicating '$mimeTypeFromExtension' but actually it is '$mimeTypeFromHeader'.\n"
            'Exiftool would fail, skipping. You may want to run GPTH with --fix-extensions.\n ${file.path}',
        level: 'error',
        forcePrint: true,
      );
      return false;
    }

    final exifFormat = DateFormat('yyyy:MM:dd HH:mm:ss');
    final String dt = exifFormat.format(dateTime);
    final success = await exiftool!.writeExifBatch(file, {
      'DateTimeOriginal': '"$dt"',
      'DateTimeDigitized': '"$dt"',
      'DateTime': '"$dt"',
    });
    if (success) {
      log(
        '[Step 5/8] New DateTime $dt written to EXIF (exiftool): ${file.path}',
      );
      return true;
    } else {
      log(
        '[Step 5/8] DateTime $dt could not be written to EXIF: ${file.path}',
        level: 'error',
      );
      return false;
    }
  } else {
    //When exiftool is not installed
    return _noExifToolDateTimeWriter(file, dateTime, mimeTypeFromHeader);
  }
}

Future<bool> writeGpsToExif(
  final DMSCoordinates coordinates,
  final File file,
) async {
  final List<int> headerBytes = await File(file.path).openRead(0, 128).first;
  final String? mimeTypeFromHeader = lookupMimeType(
    file.path,
    headerBytes: headerBytes,
  );

  if (exifToolInstalled) {
    final String? mimeTypeFromExtension = lookupMimeType(file.path);
    //Even if exifTool is installed, try to use native way for speed first and if it works keep going. If not, use exiftool.
    if (mimeTypeFromHeader == 'image/jpeg' &&
        await _noExifGPSWriter(file, coordinates, mimeTypeFromHeader)) {
      return true;
    }

    if (mimeTypeFromExtension != mimeTypeFromHeader) {
      log(
        "GPSWriter - File has a wrong extension indicating '$mimeTypeFromExtension' but actually it is '$mimeTypeFromHeader'.\n"
            'Exiftool would fail, skipping. You may want to run GPTH with --fix-extensions.\n ${file.path}',
        level: 'error',
        forcePrint: true,
      );
      return false;
    }

    //Check if the file already has EXIF data and if yes, skip.
    final Map coordinatesMap = await exiftool!.readExifBatch(file, [
      'GPSLatitude',
      'GPSLongitude',
    ]);
    final bool filehasExifCoordinates = coordinatesMap.values.isNotEmpty;
    if (!filehasExifCoordinates) {
      log(
        '[Step 5/8] Found coordinates ${coordinates.toString()} in json, but missing in EXIF for file: ${file.path}',
      );

      final success = await exiftool!.writeExifBatch(file, {
        'GPSLatitude': coordinates.toDD().latitude.toString(),
        'GPSLongitude': coordinates.toDD().longitude.toString(),
        'GPSLatitudeRef': coordinates.latDirection.abbreviation.toString(),
        'GPSLongitudeRef': coordinates.longDirection.abbreviation.toString(),
      });
      if (success) {
        log('[Step 5/8] New coordinates written to EXIF: ${file.path}');
        return true;
      } else {
        log(
          '[Step 5/8] Coordinates ${coordinates.toString()} could not be written to EXIF: ${file.path}',
          level: 'error',
          forcePrint: true,
        );
        return false;
      }
    }
    //Found coords in json but already present in exif. Skip.
    return false;
  } else {
    //If exiftool is not installed
    return _noExifGPSWriter(file, coordinates, mimeTypeFromHeader);
  }
}

/// Writes DateTime to EXIF using native Dart libraries (JPEG only)
///
/// Only supports JPEG files
/// using the 'image' package for EXIF manipulation.
///
/// [file] Image file to write to
/// [dateTime] DateTime to write to EXIF fields
/// [mimeTypeFromHeader] MIME type detected from file header
/// Returns true if write was successful
Future<bool> _noExifToolDateTimeWriter(
  final File file,
  final DateTime dateTime,
  final String? mimeTypeFromHeader,
) async {
  final exifFormat = DateFormat('yyyy:MM:dd HH:mm:ss');
  final String? mimeTypeFromExtension = lookupMimeType(file.path);
  if (mimeTypeFromHeader == 'image/jpeg') {
    if (mimeTypeFromHeader != mimeTypeFromExtension) {
      log(
        "DateWriter - File has a wrong extension indicating '$mimeTypeFromExtension'"
        " but actually it is '$mimeTypeFromHeader'. Will use native JPEG writer.\n ${file.path}",
        level: 'warning',
      );
    }
    //when it's a jpg and the image library can handle it
    ExifData? exifData;
    final Uint8List origbytes = file.readAsBytesSync();
    try {
      exifData = decodeJpgExif(origbytes); //Decode the exif data of the jpg.
    } catch (e) {
      log(
        '[Step 5/8] Found DateTime in json, but missing in EXIF for file: ${file.path}. Failed to write because of error during decoding: $e',
        level: 'error',
      );
      return false; // Ignoring errors during image decoding as it may not be a valid image file
    }
    if (exifData != null && !exifData.isEmpty) {
      exifData.imageIfd['DateTime'] = exifFormat.format(dateTime);
      exifData.exifIfd['DateTimeOriginal'] = exifFormat.format(dateTime);
      exifData.exifIfd['DateTimeDigitized'] = exifFormat.format(dateTime);
      final Uint8List? newbytes = injectJpgExif(
        origbytes,
        exifData,
      ); //This overwrites the original exif data of the image with the altered exif data.
      if (newbytes != null) {
        file.writeAsBytesSync(newbytes);
        log(
          '[Step 5/8] New DateTime ${dateTime.toString()} written to EXIF (natively): ${file.path}',
        );
        return true;
      }
    }
  }
  if (!exifToolInstalled) {
    log(
      '[Step 5/8] Found DateTime in json, but missing in EXIF. Writing to $mimeTypeFromHeader is not supported without exiftool.',
      level: 'warning',
      forcePrint: true,
    );
  }
  return false;
}

/// Writes GPS coordinates to EXIF using native Dart libraries (JPEG only)
///
/// Only supports JPEG files
/// using the 'image' package for EXIF manipulation.
///
/// [file] Image file to write to
/// [coordinates] GPS coordinates to write
/// [mimeTypeFromHeader] MIME type detected from file header
/// Returns true if write was successful
Future<bool> _noExifGPSWriter(
  final File file,
  final DMSCoordinates coordinates,
  final String? mimeTypeFromHeader,
) async {
  if (mimeTypeFromHeader == 'image/jpeg') {
    final String? mimeTypeFromExtension = lookupMimeType(file.path);
    if (mimeTypeFromHeader != mimeTypeFromExtension) {
      log(
        "GPSWriter - File has a wrong extension indicating '$mimeTypeFromExtension'"
        " but actually it is '$mimeTypeFromHeader'. Will use native JPEG writer. \n ${file.path}",
        level: 'warning',
      );
    }
    //when it's a jpg and the image library can handle it
    ExifData? exifData;
    final Uint8List origbytes = file.readAsBytesSync();
    try {
      exifData = decodeJpgExif(origbytes); //Decode only the exif data
    } catch (e) {
      log(
        '[Step 5/8] Found Coordinates in json, but missing in EXIF for file: ${file.path}. Failed to write because of error during decoding: $e',
        level: 'error',
      );
      return false; // Ignoring errors during image decoding as it may not be a valid image file
    }
    if (exifData != null) {
      exifData.gpsIfd.gpsLatitude = coordinates.toDD().latitude;
      exifData.gpsIfd.gpsLongitude = coordinates.toDD().longitude;
      exifData.gpsIfd.gpsLatitudeRef = coordinates.latDirection.abbreviation;
      exifData.gpsIfd.gpsLongitudeRef = coordinates.longDirection.abbreviation;
      final Uint8List? newbytes = injectJpgExif(
        origbytes,
        exifData,
      ); //This overwrites the original exif data of the image with the altered exif data.
      if (newbytes != null) {
        file.writeAsBytesSync(newbytes);
        log('[Step 5/8] New coordinates written to EXIF: ${file.path}');
        return true;
      }
    }
  }
  if (!exifToolInstalled) {
    if (isVerbose) {
      log(
        '[Step 5/8] Found Coordinates in json, but missing in EXIF. Writing to $mimeTypeFromHeader is not supported without exiftool.',
        level: 'warning',
      );
    } else {
      print(
        '[Step 5/8] [WARNING] Found Coordinates in json, but missing in EXIF. Writing to $mimeTypeFromHeader is not supported without exiftool.',
      );
    }
  }
  return false;
}
