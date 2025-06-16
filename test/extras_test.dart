import 'package:gpth/extras.dart';
import 'package:test/test.dart';

void main() {
  group('removePartialExtraFormats', () {
    test('should return original filename when no partial suffixes found', () {
      expect(removePartialExtraFormats('photo.jpg'), equals('photo.jpg'));
      expect(removePartialExtraFormats('video.mp4'), equals('video.mp4'));
      expect(
        removePartialExtraFormats('image-normal.png'),
        equals('image-normal.png'),
      );
    });

    test('should remove partial "-ed" suffix (from "-edited")', () {
      expect(removePartialExtraFormats('photo-ed.jpg'), equals('photo.jpg'));
      expect(removePartialExtraFormats('image-ed.png'), equals('image.png'));
      expect(removePartialExtraFormats('video-ed.mp4'), equals('video.mp4'));
    });

    test('should remove partial "-edi" suffix (from "-edited")', () {
      expect(removePartialExtraFormats('photo-edi.jpg'), equals('photo.jpg'));
      expect(removePartialExtraFormats('image-edi.png'), equals('image.png'));
    });

    test('should remove partial "-edit" suffix (from "-edited")', () {
      expect(removePartialExtraFormats('photo-edit.jpg'), equals('photo.jpg'));
      expect(removePartialExtraFormats('image-edit.png'), equals('image.png'));
    });

    test('should remove partial "-edite" suffix (from "-edited")', () {
      expect(removePartialExtraFormats('photo-edite.jpg'), equals('photo.jpg'));
      expect(removePartialExtraFormats('image-edite.png'), equals('image.png'));
    });

    test('should remove full "-edited" suffix', () {
      expect(
        removePartialExtraFormats('photo-edited.jpg'),
        equals('photo.jpg'),
      );
      expect(
        removePartialExtraFormats('image-edited.png'),
        equals('image.png'),
      );
    });

    test('should remove partial German "-be" suffix (from "-bearbeitet")', () {
      expect(removePartialExtraFormats('foto-be.jpg'), equals('foto.jpg'));
      expect(removePartialExtraFormats('bild-be.png'), equals('bild.png'));
    });

    test(
      'should remove partial German "-bear" suffix (from "-bearbeitet")',
      () {
        expect(removePartialExtraFormats('foto-bear.jpg'), equals('foto.jpg'));
        expect(removePartialExtraFormats('bild-bear.png'), equals('bild.png'));
      },
    );

    test('should remove partial French "-mo" suffix (from "-modifié")', () {
      expect(removePartialExtraFormats('photo-mo.jpg'), equals('photo.jpg'));
      expect(removePartialExtraFormats('image-mo.png'), equals('image.png'));
    });

    test('should remove partial French "-modif" suffix (from "-modifié")', () {
      expect(removePartialExtraFormats('photo-modif.jpg'), equals('photo.jpg'));
      expect(removePartialExtraFormats('image-modif.png'), equals('image.png'));
    });

    test('should handle suffixes with digit patterns like "(1)"', () {
      expect(removePartialExtraFormats('photo-ed(1).jpg'), equals('photo.jpg'));
      expect(
        removePartialExtraFormats('image-edit(2).png'),
        equals('image.png'),
      );
      expect(
        removePartialExtraFormats('video-bear(3).mp4'),
        equals('video.mp4'),
      );
    });

    test('should be case insensitive', () {
      expect(removePartialExtraFormats('photo-ED.jpg'), equals('photo.jpg'));
      expect(removePartialExtraFormats('image-Edit.png'), equals('image.png'));
      expect(removePartialExtraFormats('video-BEAR.mp4'), equals('video.mp4'));
    });

    test('should handle files without extensions', () {
      expect(removePartialExtraFormats('photo-ed'), equals('photo'));
      expect(removePartialExtraFormats('image-edit'), equals('image'));
      expect(removePartialExtraFormats('video-bear'), equals('video'));
    });

    test('should handle complex filenames', () {
      expect(
        removePartialExtraFormats('IMG_20230101_123456-ed.jpg'),
        equals('IMG_20230101_123456.jpg'),
      );
      expect(
        removePartialExtraFormats('vacation_beach_sunset-modif.png'),
        equals('vacation_beach_sunset.png'),
      );
      expect(
        removePartialExtraFormats('family_photo_2023-bear(1).jpg'),
        equals('family_photo_2023.jpg'),
      );
    });

    test(
      'should remove partial suffix which is short (less than 2 characters)',
      () {
        expect(removePartialExtraFormats('photo.jpg'), equals('photo.jpg'));
        expect(removePartialExtraFormats('image.png'), equals('image.png'));
        expect(removePartialExtraFormats('video.mp4'), equals('video.mp4'));
      },
    );

    test(
      'should not remove if suffix does not match any known extra formats',
      () {
        expect(
          removePartialExtraFormats('photo-xyz.jpg'),
          equals('photo-xyz.jpg'),
        );
        expect(
          removePartialExtraFormats('image-abc.png'),
          equals('image-abc.png'),
        );
        expect(
          removePartialExtraFormats('video-test.mp4'),
          equals('video-test.mp4'),
        );
      },
    );

    test('should handle multiple partial suffixes', () {
      // This tests the behavior when multiple partial suffixes could match
      expect(
        removePartialExtraFormats('photo-be-ed.jpg'),
        equals('photo-be.jpg'),
      );
    });

    test('should handle Unicode characters in filenames', () {
      expect(removePartialExtraFormats('phöto-ed.jpg'), equals('phöto.jpg'));
      expect(removePartialExtraFormats('imagé-edit.png'), equals('imagé.png'));
    });

    test('should handle Polish partial suffixes', () {
      expect(
        removePartialExtraFormats('zdjęcie-ed.jpg'),
        equals('zdjęcie.jpg'),
      );
      expect(removePartialExtraFormats('obraz-edyt.png'), equals('obraz.png'));
    });

    test('should handle Japanese partial suffixes', () {
      expect(removePartialExtraFormats('写真-編.jpg'), equals('写真.jpg'));
      expect(removePartialExtraFormats('画像-編集.png'), equals('画像.png'));
    });

    test('should handle Italian partial suffixes', () {
      expect(removePartialExtraFormats('foto-mo.jpg'), equals('foto.jpg'));
      expect(
        removePartialExtraFormats('immagine-modif.png'),
        equals('immagine.png'),
      );
    });

    test('should handle Spanish partial suffixes', () {
      expect(removePartialExtraFormats('foto-ha.jpg'), equals('foto.jpg'));
      expect(
        removePartialExtraFormats('Yoli_001-ha ed.JPG'),
        equals('Yoli_001.JPG'),
      );
    });
  });
}
