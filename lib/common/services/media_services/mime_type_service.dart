/// Service for MIME type operations and file extension mapping
///
/// Provides utilities for working with MIME types and determining
/// appropriate file extensions based on content type.
class MimeTypeService {
  /// Creates a new MIME type service
  const MimeTypeService();

  /// Returns the preferred file extension for a given MIME type
  ///
  /// [mimeType] The MIME type to get extension for
  /// Returns the preferred extension without the dot, or null if unknown
  String? getPreferredExtension(final String mimeType) =>
      _mimeToExtensionMap[mimeType];

  /// Gets all supported MIME types
  Set<String> getSupportedMimeTypes() => _mimeToExtensionMap.keys.toSet();

  /// Checks if a MIME type is supported for extension mapping
  bool isSupportedMimeType(final String mimeType) =>
      _mimeToExtensionMap.containsKey(mimeType);

  /// Gets the extension for an image MIME type
  String? getImageExtension(final String mimeType) {
    if (!mimeType.startsWith('image/')) {
      return null;
    }
    return getPreferredExtension(mimeType);
  }

  /// Gets the extension for a video MIME type
  String? getVideoExtension(final String mimeType) {
    if (!mimeType.startsWith('video/')) {
      return null;
    }
    return getPreferredExtension(mimeType);
  }

  /// Maps MIME types to their preferred file extensions
  static const Map<String, String> _mimeToExtensionMap = {
    // Image formats
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/heic': 'heic',
    'image/avif': 'avif',
    'image/bmp': 'bmp',
    'image/svg+xml': 'svg',

    // Video formats
    'video/mp4': 'mp4',
    'video/avi': 'avi',
    'video/mov': 'mov',
    'video/quicktime': 'mov',
    'video/x-msvideo': 'avi',
    'video/webm': 'webm',
    'video/x-matroska': 'mkv',
    'video/3gpp': '3gp',
    'video/x-flv': 'flv',
  };
}
