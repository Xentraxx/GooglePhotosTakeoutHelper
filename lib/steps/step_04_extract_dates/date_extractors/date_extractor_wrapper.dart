import 'dart:io';

export 'exif_date_extractor.dart';
export 'filename_date_extractor.dart';
export 'folder_year_extractor.dart';
export 'json_date_extractor.dart';

/// Function that can take a file and potentially extract DateTime of it
typedef DateTimeExtractor = Future<DateTime?> Function(File);
