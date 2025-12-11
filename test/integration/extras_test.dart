import 'package:gpth/gpth_lib_exports.dart';
import 'package:test/test.dart';

void main() {
  const extrasService = EditedVersionDetectorService();

  group('removePartialExtraFormats', () {
    test('should return original filename when no partial suffixes found', () {
      expect(
        extrasService.removePartialExtraFormats('photo.jpg'),
        equals('photo.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('video.mp4'),
        equals('video.mp4'),
      );
      expect(
        extrasService.removePartialExtraFormats('image-normal.png'),
        equals('image-normal.png'),
      );
    });

    test('should remove partial "-ed" suffix (from "-edited")', () {
      expect(
        extrasService.removePartialExtraFormats('photo-ed.jpg'),
        equals('photo.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('image-ed.png'),
        equals('image.png'),
      );
      expect(
        extrasService.removePartialExtraFormats('video-ed.mp4'),
        equals('video.mp4'),
      );
    });

    test('should remove partial "-edi" suffix (from "-edited")', () {
      expect(
        extrasService.removePartialExtraFormats('photo-edi.jpg'),
        equals('photo.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('image-edi.png'),
        equals('image.png'),
      );
    });

    test('should remove partial "-edit" suffix (from "-edited")', () {
      expect(
        extrasService.removePartialExtraFormats('photo-edit.jpg'),
        equals('photo.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('image-edit.png'),
        equals('image.png'),
      );
    });

    test('should remove partial "-edite" suffix (from "-edited")', () {
      expect(
        extrasService.removePartialExtraFormats('photo-edite.jpg'),
        equals('photo.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('image-edite.png'),
        equals('image.png'),
      );
    });

    test('should remove full "-edited" suffix', () {
      expect(
        extrasService.removePartialExtraFormats('photo-edited.jpg'),
        equals('photo.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('image-edited.png'),
        equals('image.png'),
      );
    });

    test('should remove partial German "-be" suffix (from "-bearbeitet")', () {
      expect(
        extrasService.removePartialExtraFormats('foto-be.jpg'),
        equals('foto.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('bild-be.png'),
        equals('bild.png'),
      );
    });

    test(
      'should remove partial German "-bear" suffix (from "-bearbeitet")',
      () {
        expect(
          extrasService.removePartialExtraFormats('foto-bear.jpg'),
          equals('foto.jpg'),
        );
        expect(
          extrasService.removePartialExtraFormats('bild-bear.png'),
          equals('bild.png'),
        );
      },
    );

    test('should remove partial French "-mo" suffix (from "-modifié")', () {
      expect(
        extrasService.removePartialExtraFormats('photo-mo.jpg'),
        equals('photo.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('image-mo.png'),
        equals('image.png'),
      );
    });

    test('should remove partial French "-modif" suffix (from "-modifié")', () {
      expect(
        extrasService.removePartialExtraFormats('photo-modif.jpg'),
        equals('photo.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('image-modif.png'),
        equals('image.png'),
      );
    });

    test('should handle suffixes with digit patterns like "(1)"', () {
      expect(
        extrasService.removePartialExtraFormats('photo-ed(1).jpg'),
        equals('photo.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('image-edit(2).png'),
        equals('image.png'),
      );
      expect(
        extrasService.removePartialExtraFormats('video-bear(3).mp4'),
        equals('video.mp4'),
      );
    });

    test('should be case insensitive', () {
      expect(
        extrasService.removePartialExtraFormats('photo-ED.jpg'),
        equals('photo.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('image-Edit.png'),
        equals('image.png'),
      );
      expect(
        extrasService.removePartialExtraFormats('video-BEAR.mp4'),
        equals('video.mp4'),
      );
    });

    test('should handle files without extensions', () {
      expect(
        extrasService.removePartialExtraFormats('photo-ed'),
        equals('photo'),
      );
      expect(
        extrasService.removePartialExtraFormats('image-edit'),
        equals('image'),
      );
      expect(
        extrasService.removePartialExtraFormats('video-bear'),
        equals('video'),
      );
    });

    test('should handle complex filenames', () {
      expect(
        extrasService.removePartialExtraFormats('IMG_20230101_123456-ed.jpg'),
        equals('IMG_20230101_123456.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats(
          'vacation_beach_sunset-modif.png',
        ),
        equals('vacation_beach_sunset.png'),
      );
      expect(
        extrasService.removePartialExtraFormats(
          'family_photo_2023-bear(1).jpg',
        ),
        equals('family_photo_2023.jpg'),
      );
    });

    test(
      'should remove partial suffix which is short (less than 2 characters)',
      () {
        expect(
          extrasService.removePartialExtraFormats('photo.jpg'),
          equals('photo.jpg'),
        );
        expect(
          extrasService.removePartialExtraFormats('image.png'),
          equals('image.png'),
        );
        expect(
          extrasService.removePartialExtraFormats('video.mp4'),
          equals('video.mp4'),
        );
      },
    );

    test(
      'should not remove if suffix does not match any known extra formats',
      () {
        expect(
          extrasService.removePartialExtraFormats('photo-xyz.jpg'),
          equals('photo-xyz.jpg'),
        );
        expect(
          extrasService.removePartialExtraFormats('image-abc.png'),
          equals('image-abc.png'),
        );
        expect(
          extrasService.removePartialExtraFormats('video-test.mp4'),
          equals('video-test.mp4'),
        );
      },
    );

    test('should handle multiple partial suffixes', () {
      // This tests the behavior when multiple partial suffixes could match
      expect(
        extrasService.removePartialExtraFormats('photo-be-ed.jpg'),
        equals('photo-be.jpg'),
      );
    });

    test('should handle Unicode characters in filenames', () {
      expect(
        extrasService.removePartialExtraFormats('phöto-ed.jpg'),
        equals('phöto.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('imagé-edit.png'),
        equals('imagé.png'),
      );
    });

    test('should handle Polish partial suffixes', () {
      expect(
        extrasService.removePartialExtraFormats('zdjęcie-ed.jpg'),
        equals('zdjęcie.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('obraz-edyt.png'),
        equals('obraz.png'),
      );
    });

    test('should handle Japanese partial suffixes', () {
      expect(
        extrasService.removePartialExtraFormats('写真-編.jpg'),
        equals('写真.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('画像-編集.png'),
        equals('画像.png'),
      );
    });

    test('should handle Italian partial suffixes', () {
      expect(
        extrasService.removePartialExtraFormats('foto-mo.jpg'),
        equals('foto.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('immagine-modif.png'),
        equals('immagine.png'),
      );
    });

    test('should handle Spanish partial suffixes', () {
      expect(
        extrasService.removePartialExtraFormats('foto-ha.jpg'),
        equals('foto.jpg'),
      );
      expect(
        extrasService.removePartialExtraFormats('Yoli_001-ha ed.JPG'),
        equals('Yoli_001.JPG'),
      );
    });
  });
}
