/// # Invalid Extensions Test Suite
library;

import 'dart:io';

import 'package:gpth/exiftoolInterface.dart';
import 'package:gpth/utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import './test_setup.dart';

void main() {
  group('Invalid extensions', () {
    late TestFixture fixture;

    setUpAll(() async {
      await initExiftool();
    });

    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    test('fix invalid .jpg extension', () async {
      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      final imgFile1 = fixture.createFile('actual-png.jpg', pngHeader);

      final albumDir = fixture.createDirectory('extensions-tests');
      final albumFile1 = File('${albumDir.path}/${p.basename(imgFile1.path)}');
      imgFile1.renameSync(albumFile1.path);

      await fixIncorrectExtensions(albumDir, null);

      final fixedFile = File(
        '${albumDir.path}/${p.basename(imgFile1.path)}.png',
      );
      expect(fixedFile.existsSync(), isTrue);
    });

    test('skip invalid JPEG files', () async {
      final jpegHeader = [0xFF, 0xD8];
      final imgFile1 = fixture.createFile('actual-jpeg.png', jpegHeader);

      final albumDir = fixture.createDirectory('extensions-tests');
      final albumFile1 = File('${albumDir.path}/${p.basename(imgFile1.path)}');
      imgFile1.renameSync(albumFile1.path);

      await fixIncorrectExtensions(albumDir, true); // non-jpeg mode

      final fixedFile = File(
        '${albumDir.path}/${p.basename(imgFile1.path)}.jpg',
      );
      expect(fixedFile.existsSync(), isFalse);
    });

    test('skip TIFF-based RAW files', () async {
      final cr2Header = [
        0x49,
        0x49,
        0x2A,
        0x00,
        0x10,
        0x00,
        0x00,
        0x00,
        0x43,
        0x52,
        0x02,
      ];
      final imgFile1 = fixture.createFile('actual-raw.CR2', cr2Header);

      final albumDir = fixture.createDirectory('extensions-tests');
      final albumFile1 = File('${albumDir.path}/${p.basename(imgFile1.path)}');
      imgFile1.renameSync(albumFile1.path);

      await fixIncorrectExtensions(albumDir, false);

      final fixedFile = File(
        '${albumDir.path}/${p.basename(imgFile1.path)}.tiff',
      );
      expect(fixedFile.existsSync(), isFalse);
    });
  });
}
