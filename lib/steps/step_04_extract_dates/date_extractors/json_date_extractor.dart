import 'dart:convert';
import 'dart:io';
import 'package:coordinate_converter/coordinate_converter.dart';
import 'package:gpth/gpth_lib_exports.dart';

/// Finds corresponding json file with info from media file and gets 'photoTakenTime' from it
Future<DateTime?> jsonDateTimeExtractor(
  final File file, {
  final bool tryhard = false,
}) async {
  final File? jsonFile = await jsonForFile(file, tryhard: tryhard);
  if (jsonFile == null) return null;
  try {
    final dynamic data = jsonDecode(await jsonFile.readAsString());
    final int epoch = int.parse(data['photoTakenTime']['timestamp'].toString());
    return DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
  } on FormatException catch (_) {
    // this is when json is bad
    return null;
  } on FileSystemException catch (_) {
    // this happens for issue #143
    // "Failed to decode data using encoding 'utf-8'"
    // maybe this will self-fix when dart itself support more encodings
    return null;
  } on NoSuchMethodError catch (_) {
    // this is when tags like photoTakenTime aren't there
    return null;
  }
}

/// Attempts to find the corresponding JSON file for a media file
///
/// Delegates to JsonMetadataMatcherService service for the actual matching logic.
/// This function maintains backward compatibility with existing code.
///
/// [file] Media file to find JSON for
/// [tryhard] If true, uses more aggressive matching strategies
/// Returns the JSON file if found, null otherwise
Future<File?> jsonForFile(
  final File file, {
  required final bool tryhard,
}) async => JsonMetadataMatcherService.findJsonForFile(file, tryhard: tryhard);

/// This is to get coordinates from the json file. Expects media file and finds json.
Future<DMSCoordinates?> jsonCoordinatesExtractor(
  final File file, {
  final bool tryhard = false,
}) async {
  final File? jsonFile = await jsonForFile(file, tryhard: tryhard);
  if (jsonFile == null) return null;
  try {
    final Map<String, dynamic> data = jsonDecode(await jsonFile.readAsString());
    final double lat = data['geoData']['latitude'] as double;
    final double long = data['geoData']['longitude'] as double;
    //var alt = double.tryParse(data['geoData']['altitude']); //Info: Altitude is not used.
    if (lat == 0.0 && long == 0.0) {
      return null;
    } else {
      final DDCoordinates ddcoords = DDCoordinates(
        latitude: lat,
        longitude: long,
      );
      final DMSCoordinates dmscoords = DMSCoordinates.fromDD(ddcoords);
      return dmscoords;
    }
  } on FormatException catch (_) {
    // this is when json is bad
    return null;
  } on FileSystemException catch (_) {
    // this happens for issue #143
    // "Failed to decode data using encoding 'utf-8'"
    // maybe this will self-fix when dart itself support more encodings
    return null;
  } on NoSuchMethodError catch (_) {
    // this is when tags like photoTakenTime aren't there
    return null;
  }
}

/// Extracts partner sharing information from the JSON file
///
/// Returns true if the media was shared by a partner (has googlePhotosOrigin.fromPartnerSharing),
/// false otherwise (including for personal uploads with mobileUpload or other origins)
Future<bool> jsonPartnerSharingExtractor(
  final File file, {
  final bool tryhard = false,
}) async {
  final File? jsonFile = await jsonForFile(file, tryhard: tryhard);
  if (jsonFile == null) return false;
  try {
    final dynamic data = jsonDecode(await jsonFile.readAsString());

    // Check if googlePhotosOrigin exists and has fromPartnerSharing
    final dynamic googlePhotosOrigin = data['googlePhotosOrigin'];
    if (googlePhotosOrigin != null &&
        googlePhotosOrigin is Map<String, dynamic>) {
      return googlePhotosOrigin.containsKey('fromPartnerSharing');
    }

    return false;
  } on FormatException catch (_) {
    // this is when json is bad
    return false;
  } on FileSystemException catch (_) {
    // this happens for issue #143
    // "Failed to decode data using encoding 'utf-8'"
    // maybe this will self-fix when dart itself support more encodings
    return false;
  } on NoSuchMethodError catch (_) {
    // this is when tags like googlePhotosOrigin aren't there
    return false;
  }
}
