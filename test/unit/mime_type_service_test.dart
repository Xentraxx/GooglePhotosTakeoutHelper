/// Test suite for MimeTypeService
///
/// Tests the MIME type mapping and extension functionality.
library;

import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

void main() {
  group('MimeTypeService', () {
    late MimeTypeService service;

    setUp(() {
      service = const MimeTypeService();
    });

    group('getPreferredExtension', () {
      test('returns correct extension for common image types', () {
        expect(service.getPreferredExtension('image/jpeg'), equals('jpg'));
        expect(service.getPreferredExtension('image/png'), equals('png'));
        expect(service.getPreferredExtension('image/gif'), equals('gif'));
        expect(service.getPreferredExtension('image/webp'), equals('webp'));
        expect(service.getPreferredExtension('image/heic'), equals('heic'));
        expect(service.getPreferredExtension('image/bmp'), equals('bmp'));
      });

      test('returns correct extension for common video types', () {
        expect(service.getPreferredExtension('video/mp4'), equals('mp4'));
        expect(service.getPreferredExtension('video/avi'), equals('avi'));
        expect(service.getPreferredExtension('video/mov'), equals('mov'));
        expect(service.getPreferredExtension('video/quicktime'), equals('mov'));
        expect(service.getPreferredExtension('video/webm'), equals('webm'));
        expect(
          service.getPreferredExtension('video/x-matroska'),
          equals('mkv'),
        );
      });

      test('returns null for unknown MIME types', () {
        expect(service.getPreferredExtension('unknown/type'), isNull);
        expect(service.getPreferredExtension('application/unknown'), isNull);
        expect(service.getPreferredExtension(''), isNull);
      });

      test('is case sensitive for MIME types', () {
        expect(service.getPreferredExtension('IMAGE/JPEG'), isNull);
        expect(service.getPreferredExtension('Video/MP4'), isNull);
      });
    });

    group('getSupportedMimeTypes', () {
      test('returns non-empty set of supported types', () {
        final supportedTypes = service.getSupportedMimeTypes();

        expect(supportedTypes, isNotEmpty);
        expect(supportedTypes, contains('image/jpeg'));
        expect(supportedTypes, contains('video/mp4'));
      });

      test('includes both image and video types', () {
        final supportedTypes = service.getSupportedMimeTypes();

        final imageTypes = supportedTypes
            .where((final t) => t.startsWith('image/'))
            .toList();
        final videoTypes = supportedTypes
            .where((final t) => t.startsWith('video/'))
            .toList();

        expect(imageTypes, isNotEmpty);
        expect(videoTypes, isNotEmpty);
      });
    });

    group('isSupportedMimeType', () {
      test('returns true for supported image types', () {
        expect(service.isSupportedMimeType('image/jpeg'), isTrue);
        expect(service.isSupportedMimeType('image/png'), isTrue);
        expect(service.isSupportedMimeType('image/gif'), isTrue);
      });

      test('returns true for supported video types', () {
        expect(service.isSupportedMimeType('video/mp4'), isTrue);
        expect(service.isSupportedMimeType('video/avi'), isTrue);
        expect(service.isSupportedMimeType('video/mov'), isTrue);
      });

      test('returns false for unsupported types', () {
        expect(service.isSupportedMimeType('unknown/type'), isFalse);
        expect(service.isSupportedMimeType('application/pdf'), isFalse);
        expect(service.isSupportedMimeType('text/plain'), isFalse);
        expect(service.isSupportedMimeType(''), isFalse);
      });
    });

    group('getImageExtension', () {
      test('returns extension for image MIME types', () {
        expect(service.getImageExtension('image/jpeg'), equals('jpg'));
        expect(service.getImageExtension('image/png'), equals('png'));
        expect(service.getImageExtension('image/gif'), equals('gif'));
        expect(service.getImageExtension('image/webp'), equals('webp'));
      });

      test('returns null for non-image MIME types', () {
        expect(service.getImageExtension('video/mp4'), isNull);
        expect(service.getImageExtension('application/pdf'), isNull);
        expect(service.getImageExtension('text/plain'), isNull);
      });

      test('returns null for unknown image types', () {
        expect(service.getImageExtension('image/unknown'), isNull);
      });
    });

    group('getVideoExtension', () {
      test('returns extension for video MIME types', () {
        expect(service.getVideoExtension('video/mp4'), equals('mp4'));
        expect(service.getVideoExtension('video/avi'), equals('avi'));
        expect(service.getVideoExtension('video/mov'), equals('mov'));
        expect(service.getVideoExtension('video/webm'), equals('webm'));
      });

      test('returns null for non-video MIME types', () {
        expect(service.getVideoExtension('image/jpeg'), isNull);
        expect(service.getVideoExtension('application/pdf'), isNull);
        expect(service.getVideoExtension('text/plain'), isNull);
      });

      test('returns null for unknown video types', () {
        expect(service.getVideoExtension('video/unknown'), isNull);
      });
    });

    group('MIME type mappings', () {
      test('handles video/quicktime correctly', () {
        expect(service.getPreferredExtension('video/quicktime'), equals('mov'));
        expect(service.getPreferredExtension('video/mov'), equals('mov'));
      });

      test('handles x-prefixed types correctly', () {
        expect(service.getPreferredExtension('video/x-msvideo'), equals('avi'));
        expect(
          service.getPreferredExtension('video/x-matroska'),
          equals('mkv'),
        );
        expect(service.getPreferredExtension('video/x-flv'), equals('flv'));
      });

      test('handles XML-based types correctly', () {
        expect(service.getPreferredExtension('image/svg+xml'), equals('svg'));
      });

      test('covers common modern formats', () {
        expect(service.getPreferredExtension('image/avif'), equals('avif'));
        expect(service.getPreferredExtension('image/heic'), equals('heic'));
        expect(service.getPreferredExtension('video/webm'), equals('webm'));
      });
    });
  });
}
