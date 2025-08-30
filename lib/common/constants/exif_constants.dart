/// Constants related to EXIF processing
library;

/// MIME types supported by the native exif_reader library
///
/// This list represents formats that can be processed using the fast native
/// exif_reader library instead of the slower ExifTool external process.
/// Based on https://pub.dev/packages/exif_reader documentation.
const Set<String> supportedNativeExifMimeTypes = {
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
