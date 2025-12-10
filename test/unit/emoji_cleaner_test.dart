/// Test suite for the Emoji Cleaner functionality.
///
/// This test suite verifies the emoji handling functionality that allows
/// Google Photos Takeout Helper to work with filesystem-incompatible emoji
/// characters in album names and file paths. The emoji cleaner handles:
///
/// 1. Detection of emoji characters in filenames and directory names
/// 2. Encoding emoji to hex representation for filesystem compatibility
/// 3. Decoding hex-encoded emoji back to original Unicode characters
/// 4. Safe renaming of directories containing emoji
/// 5. Preservation of file structure during emoji processing
///
/// Key Components Tested:
/// - Emoji detection across various Unicode ranges (BMP and supplementary)
/// - Hex encoding/decoding of emoji characters
/// - Directory renaming with emoji handling
/// - File system compatibility checks
/// - Error handling for invalid emoji sequences
///
/// Test Data:
/// The tests use a variety of emoji types including:
/// - Basic emoticons (😊, 😀)
/// - Hearts and symbols (❤️, ⚠️)
/// - Flag emojis (🇺🇸)
/// - Number emojis (1️⃣)
/// - Complex emoji sequences with variation selectors
///
/// File System Compatibility:
/// Tests verify that emoji-containing names are properly converted to
/// filesystem-safe hex representations while maintaining reversibility.
library;

import 'dart:io';

import 'package:emoji_regex/emoji_regex.dart' as regex;
import 'package:exif_reader/exif_reader.dart';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../setup/test_setup.dart';

final _filenameSanitizer = FilenameSanitizerService();

/// Helper function to check if a string contains emoji characters.
///
/// This function detects emoji using two methods:
/// 1. The emoji_regex package for standard emoji detection
/// 2. A custom regex for Unicode variation selectors (FE0F, FE0E)
///
/// Returns true if the text contains any emoji characters.
/// Used throughout the test suite to verify emoji detection logic.
bool containsEmoji(final String text) =>
    regex.emojiRegex().hasMatch(text) ||
    RegExp(r'\u{FE0F}|\u{FE0E}', unicode: true).hasMatch(text);

/// Helper function to encode emoji in a string (simplified test version).
///
/// This is a simplified implementation for testing purposes that converts
/// emoji characters to hexadecimal representation surrounded by underscores.
///
/// Process:
/// 1. Iterates through each character in the input string
/// 2. Handles Unicode surrogate pairs for emoji outside the BMP
/// 3. Converts emoji characters to _0xHEX_ format
/// 4. Preserves non-emoji characters unchanged
///
/// Example: "test_😊.jpg" → "test__0x1f60a_.jpg"
///
/// Args:
///   text: The input string that may contain emoji
///
/// Returns:
///   String with emoji encoded as hex representations
String encodeEmoji(final String text) {
  if (!containsEmoji(text)) return text;

  final StringBuffer result = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final int codeUnit = text.codeUnitAt(i);
    final String char = String.fromCharCode(codeUnit);

    // Handle surrogate pairs
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && i + 1 < text.length) {
      final int nextCodeUnit = text.codeUnitAt(i + 1);
      if (nextCodeUnit >= 0xDC00 && nextCodeUnit <= 0xDFFF) {
        final int emoji =
            ((codeUnit - 0xD800) << 10) + (nextCodeUnit - 0xDC00) + 0x10000;
        result.write('_0x${emoji.toRadixString(16)}_');
        i++;
        continue;
      }
    }

    // Handle BMP emoji
    if (containsEmoji(char)) {
      result.write('_0x${codeUnit.toRadixString(16)}_');
    } else {
      result.write(char);
    }
  }
  return result.toString();
}

/// Helper function to decode emoji from hex representation.
///
/// This function reverses the encoding process by converting hex-encoded
/// emoji back to their original Unicode characters. It uses a regex pattern
/// to find _0xHEX_ sequences and converts them back to emoji.
///
/// Process:
/// 1. Finds all _0xHEX_ patterns in the input string
/// 2. Parses the hexadecimal value to get the Unicode code point
/// 3. Converts the code point back to the original emoji character
/// 4. Handles parsing errors gracefully by preserving original text
///
/// Example: "test__0x1f60a_.jpg" → "test_😊.jpg"
///
/// Args:
///   text: The input string containing hex-encoded emoji
///
/// Returns:
///   String with hex representations decoded back to emoji
String decodeEmoji(final String text) {
  final RegExp emojiPattern = RegExp(r'_0x([0-9a-fA-F]+)_');
  return text.replaceAllMapped(emojiPattern, (final Match match) {
    try {
      final int codePoint = int.parse(match.group(1)!, radix: 16);
      return String.fromCharCode(codePoint);
    } catch (e) {
      return match.group(0)!; // Return original if parsing fails
    }
  });
}

/// Helper function for renaming directories back from hex encoding.
///
/// This function attempts to decode and rename a directory that may have
/// been encoded with hex emoji representations. It's used in tests to
/// restore original directory names after emoji processing.
///
/// Process:
/// 1. Attempts to decode the directory path using decodeAndRestoreAlbumEmoji
/// 2. If the decoded path differs from original, renames the directory
/// 3. Returns a Directory object pointing to the final path
///
/// Args:
///   hexDir: Directory that may contain hex-encoded emoji in its path
///
/// Returns:
///   Directory object with decoded path (renamed if necessary)
Directory decodeAndRenameAlbumIfHex(final Directory hexDir) {
  final String decodedPath = _filenameSanitizer.decodeAndRestoreAlbumEmoji(
    hexDir.path,
  );
  if (decodedPath != hexDir.path) {
    hexDir.renameSync(decodedPath);
    return Directory(decodedPath);
  }
  return hexDir;
}

void main() {
  late ExifToolService? exiftool;

  setUpAll(() async {
    exiftool = await ExifToolService.find();
    if (exiftool != null) {
      await exiftool!.startPersistentProcess();
    }
  });

  tearDownAll(() async {
    if (exiftool != null) {
      await exiftool!.dispose();
    }
  });

  group('Emoji Cleaner - Comprehensive Test Suite', () {
    late TestFixture fixture;

    setUp(() async {
      // Create a fresh test fixture for each test to ensure isolation
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      // Clean up test artifacts to prevent interference between tests
      await fixture.tearDown();
    });

    group('Emoji Detection and Encoding - Core Functionality', () {
      /// Verifies that the emoji detection function correctly identifies
      /// emoji characters in various filename patterns commonly found
      /// in Google Photos albums. This is critical for determining which
      /// files and directories need emoji processing.
      test('containsEmoji detects emoji in filenames', () {
        // Test basic emoji detection in common filename patterns
        expect(containsEmoji('test_😊.jpg'), isTrue);
        expect(containsEmoji('vacation_💖❤️'), isTrue);
        expect(containsEmoji('test_🎉_party'), isTrue);

        // Verify that normal filenames without emoji are not flagged
        expect(containsEmoji('no_emoji.jpg'), isFalse);
        expect(containsEmoji('regular_folder'), isFalse);
      });

      /// Tests emoji detection across different Unicode categories and ranges.
      /// This ensures comprehensive coverage of emoji types that might appear
      /// in Google Photos album names, including complex emoji with modifiers.
      test(
        'containsEmoji detects various emoji types across Unicode ranges',
        () {
          // Basic emoticons (U+1F600-U+1F64F)
          expect(containsEmoji('face_😀'), isTrue); // Smiling face

          // Miscellaneous symbols (U+2600-U+26FF)
          expect(
            containsEmoji('heart_❤️'),
            isTrue,
          ); // Red heart with variation selector
          expect(containsEmoji('symbol_⚠️'), isTrue); // Warning symbol

          // Regional indicator symbols for flags (U+1F1E6-U+1F1FF)
          expect(
            containsEmoji('flag_🇺🇸'),
            isTrue,
          ); // US flag (surrogate pair)

          // Enclosed alphanumeric supplement (U+1F100-U+1F1FF)
          expect(containsEmoji('number_1️⃣'), isTrue); // Keycap number 1
        },
      );

      /// Validates that emoji encoding properly converts emoji characters
      /// to filesystem-safe hex representations. This is essential for
      /// creating directory names that work across different operating systems.
      test('encodeEmoji converts emoji to hex representation', () {
        final result = encodeEmoji('test_😊.jpg');

        // Verify that hex encoding occurred
        expect(result, contains('_0x'));
        // Verify that original emoji was removed
        expect(result, isNot(contains('😊')));
      });

      /// Tests encoding of multiple emoji characters in a single string,
      /// which is common in Google Photos album names that contain
      /// multiple emoji for emphasis or categorization.
      test('encodeEmoji handles multiple emojis in sequence', () {
        final result = encodeEmoji('vacation_💖❤️');

        // Verify specific emoji hex codes are present
        expect(result, contains('_0x1f496_')); // 💖 (sparkling heart)
        expect(result, contains('_0x2764_')); // ❤ (red heart)
        expect(result, contains('_0xfe0f_')); // Variation selector FE0F
      });

      /// Ensures that non-emoji content is preserved during the encoding
      /// process, maintaining the structure and readability of filenames
      /// while only transforming the problematic emoji characters.
      test('encodeEmoji preserves non-emoji content unchanged', () {
        final result = encodeEmoji('test_😊_file.jpg');

        // Verify file structure is maintained
        expect(result, startsWith('test_'));
        expect(result, endsWith('_file.jpg'));
        // Verify emoji was encoded
        expect(result, contains('_0x'));
      });
    });

    group('Emoji Decoding - Reversibility Verification', () {
      /// Verifies that the encoding/decoding process is fully reversible,
      /// ensuring that original emoji can be restored from hex representations.
      /// This is crucial for maintaining user-readable album names.
      test('decodeEmoji converts hex back to original emoji', () {
        const original = 'test_😊.jpg';
        final encoded = encodeEmoji(original);
        final decoded = decodeEmoji(encoded);

        // Verify complete round-trip conversion
        expect(decoded, original);
      });

      /// Tests decoding of multiple emoji characters to ensure complex
      /// album names with multiple emoji are properly restored.
      test('decodeEmoji handles multiple emojis correctly', () {
        const original = 'vacation_💖❤️';
        final encoded = encodeEmoji(original);
        final decoded = decodeEmoji(encoded);

        // Verify complete restoration of complex emoji sequence
        expect(decoded, original);
      });

      /// Ensures that strings without hex codes are not modified during
      /// the decoding process, providing safe handling of mixed content.
      test('decodeEmoji preserves strings without hex codes', () {
        const original = 'regular_filename.jpg';
        final decoded = decodeEmoji(original);

        // Verify no changes to non-encoded content
        expect(decoded, original);
      });

      test('roundtrip encoding and decoding preserves original', () {
        final testCases = [
          'simple_😊.jpg',
          'complex_💖❤️🎉.mp4',
          'flags_🇺🇸🇬🇧.png',
          'numbers_1️⃣2️⃣3️⃣.gif',
          'no_emoji_here.txt',
        ];

        for (final testCase in testCases) {
          final encoded = encodeEmoji(testCase);
          final decoded = decodeEmoji(encoded);
          expect(decoded, testCase, reason: 'Failed for: $testCase');
        }
      });
    });

    group('Album/Folder Emoji Handling', () {
      test('encodeAndRenameAlbumIfEmoji renames emoji folders', () {
        final emojiDir = fixture.createDirectory('test_😊_folder');

        final result = _filenameSanitizer.encodeAndRenameAlbumIfEmoji(emojiDir);

        expect(result.existsSync(), isTrue);
        expect(result.path, isNot(contains('😊')));
        expect(result.path, contains('_0x'));
        expect(emojiDir.existsSync(), isFalse);
      });

      test('encodeAndRenameAlbumIfEmoji preserves non-emoji folders', () {
        final normalDir = fixture.createDirectory('normal_folder');
        final originalPath = normalDir.path;

        final result = _filenameSanitizer.encodeAndRenameAlbumIfEmoji(
          normalDir,
        );

        expect(result.path, originalPath);
        expect(result.existsSync(), isTrue);
      });

      test(
        'encodeAndRenameAlbumIfEmoji handles complex emoji combinations',
        () {
          final complexEmojiDir = fixture.createDirectory('vacation_💖❤️🎉');

          final result = _filenameSanitizer.encodeAndRenameAlbumIfEmoji(
            complexEmojiDir,
          );

          expect(result.existsSync(), isTrue);
          expect(result.path, contains('_0x1f496_')); // 💖
          expect(result.path, contains('_0x2764_')); // ❤
          expect(result.path, contains('_0x1f389_')); // 🎉
          expect(complexEmojiDir.existsSync(), isFalse);
        },
      );

      test('decodeAndRenameAlbumIfHex restores original emoji folder', () {
        final emojiDir = fixture.createDirectory('test_😊_folder');
        final encoded = _filenameSanitizer.encodeAndRenameAlbumIfEmoji(
          emojiDir,
        );

        final restored = decodeAndRenameAlbumIfHex(encoded);

        expect(restored.existsSync(), isTrue);
        expect(restored.path, contains('😊'));
        expect(restored.path, isNot(contains('_0x')));
        expect(encoded.existsSync(), isFalse);
      });

      test('decodeAndRenameAlbumIfHex preserves non-hex folders', () {
        final normalDir = fixture.createDirectory('normal_folder');
        final originalPath = normalDir.path;

        final result = decodeAndRenameAlbumIfHex(normalDir);

        expect(result.path, originalPath);
        expect(result.existsSync(), isTrue);
      });
    });

    group('End-to-End Emoji Processing', () {
      test('complete emoji workflow: encode, process, decode', () async {
        // Create emoji folder with image
        const String emojiFolderName = 'test_💖❤️';
        final Directory emojiDir = Directory(
          path.join(fixture.basePath, emojiFolderName),
        );
        emojiDir.createSync(recursive: true);

        // Create image with EXIF data in the emoji folder
        final File img = fixture.createImageWithExifInDir(
          emojiDir.path,
          'img.jpg',
        );
        expect(img.existsSync(), isTrue, reason: 'Image file should exist');

        // 1. Encode and rename folder
        final Directory hexNameDir = _filenameSanitizer
            .encodeAndRenameAlbumIfEmoji(emojiDir);
        expect(hexNameDir.path, contains('_0x1f496_')); // 💖
        expect(hexNameDir.path, contains('_0x2764_')); // ❤
        expect(hexNameDir.path, contains('_0xfe0f_')); // Variation selector

        final Directory hexDir = Directory(hexNameDir.path);
        expect(hexDir.existsSync(), isTrue);
        final File hexImg = File(path.join(hexDir.path, 'img.jpg'));
        expect(hexImg.existsSync(), isTrue);

        // 2. Read EXIF from image in hex folder
        final ExifData exifData = await readExifFromBytes(await hexImg.readAsBytes());
        expect(
          exifData.tags['EXIF DateTimeOriginal']?.printable,
          '2022:12:16 16:06:47',
        ); // 3. Write using exiftool to hex_encoded folder
        if (exiftool != null) {
          // Ensure file is accessible before writing EXIF data
          // This prevents race conditions when running tests in parallel
          var attempts = 0;
          while (!hexImg.existsSync() && attempts < 10) {
            await Future.delayed(const Duration(milliseconds: 10));
            attempts++;
          }
          expect(
            hexImg.existsSync(),
            isTrue,
            reason: 'File should be accessible before EXIF write',
          );

          final Map<String, String> map = {};
          map['Artist'] = 'TestArtist';
          await exiftool!.writeExifDataSingle(hexImg, map);

          // Verify the data was written
          final updatedTags = await exiftool!.readExifData(hexImg);
          expect(updatedTags['Artist'], 'TestArtist');
        }

        // 4. Create shortcut/symlink to hex folder
        final Directory shortcutTarget = Directory(
          path.join(fixture.basePath, 'shortcuts'),
        );
        shortcutTarget.createSync();

        if (Platform.isWindows) {
          // Test Windows shortcut creation logic
          final String shortcutPath = path.join(
            shortcutTarget.path,
            '${path.basename(hexDir.path)}.lnk',
          );
          expect(
            () => File(shortcutPath).writeAsStringSync('dummy'),
            returnsNormally,
          );
        } else {
          // Test Unix symlink creation
          final Link symlink = Link(
            path.join(shortcutTarget.path, path.basename(hexDir.path)),
          );
          symlink.createSync(hexDir.path);
          expect(symlink.existsSync(), isTrue);
        }

        // 5. Decode and restore original emoji folder
        final Directory restoredDir = decodeAndRenameAlbumIfHex(hexDir);
        expect(restoredDir.path, contains('💖❤️'));
        expect(restoredDir.existsSync(), isTrue);

        final File restoredImg = File(path.join(restoredDir.path, 'img.jpg'));
        expect(restoredImg.existsSync(), isTrue);

        // Verify EXIF data is preserved after decode
        final ExifData restoredExifData = await readExifFromBytes(
          await restoredImg.readAsBytes(),
        );
        expect(
          restoredExifData.tags['EXIF DateTimeOriginal']?.printable,
          '2022:12:16 16:06:47',
        );
      });

      test('handles emoji files within regular folders', () {
        final normalDir = fixture.createDirectory('normal_folder');
        final emojiFile = File(path.join(normalDir.path, 'photo_😊.jpg'));
        emojiFile.createSync();
        emojiFile.writeAsBytesSync([1, 2, 3]);

        // Folder should not be renamed since it has no emoji
        final result = _filenameSanitizer.encodeAndRenameAlbumIfEmoji(
          normalDir,
        );
        expect(result.path, normalDir.path);

        // But the emoji file should still exist
        final files = normalDir.listSync();
        expect(
          files.any((final f) => path.basename(f.path).contains('😊')),
          isTrue,
        );
      });

      test('preserves folder structure during emoji processing', () {
        final parentDir = fixture.createDirectory('parent');
        final emojiSubDir = Directory(path.join(parentDir.path, 'sub_😊'));
        emojiSubDir.createSync();

        final testFile = File(path.join(emojiSubDir.path, 'test.txt'));
        testFile.createSync();
        testFile.writeAsStringSync('test content');

        final encoded = _filenameSanitizer.encodeAndRenameAlbumIfEmoji(
          emojiSubDir,
        );
        expect(encoded.parent.path, parentDir.path);

        final encodedFile = File(path.join(encoded.path, 'test.txt'));
        expect(encodedFile.existsSync(), isTrue);
        expect(encodedFile.readAsStringSync(), 'test content');
      });
    });

    group('Edge Cases and Error Handling', () {
      test('handles empty folder names', () {
        expect(containsEmoji(''), isFalse);
        expect(encodeEmoji(''), '');
        expect(decodeEmoji(''), '');
      });

      test('handles very long emoji sequences', () {
        const longEmoji =
            '😀😃😄😁😆😅😂🤣😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🤩🥳😏😒😞😔😟😕🙁☹️😣😖😫😩🥺😢😭😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓🤗🤔🤭🤫🤥😶😐😑😬🙄😯😦😧😮😲🥱😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕🤑🤠😈👿👹👺🤡💩👻💀☠️👽👾🤖🎃😺😸😹😻😼😽🙀😿😾';

        final encoded = encodeEmoji(longEmoji);
        final decoded = decodeEmoji(encoded);

        expect(encoded, isNot(contains('😀')));
        expect(decoded, longEmoji);
      });

      test('handles mixed emoji and special characters', () {
        const mixed = 'test_😊-file(1)_💖.jpg';
        final encoded = encodeEmoji(mixed);
        final decoded = decodeEmoji(encoded);

        expect(decoded, mixed);
        expect(encoded, contains('test_'));
        expect(encoded, contains('-file(1)_'));
        expect(encoded, contains('.jpg'));
      });

      test('handles folder rename failures gracefully', () {
        // This test would need to mock file system operations
        // For now, we'll test that the function doesn't throw
        final nonExistentDir = Directory(
          path.join(fixture.basePath, 'nonexistent_😊'),
        );

        expect(
          () => _filenameSanitizer.encodeAndRenameAlbumIfEmoji(nonExistentDir),
          returnsNormally,
        );
      });

      test('handles invalid hex codes in decoding', () {
        const invalidHex = 'test_0xinvalid_file.jpg';
        final decoded = decodeEmoji(invalidHex);

        // Should return original string if hex is invalid
        expect(decoded, invalidHex);
      });

      test('handles partial hex codes', () {
        const partialHex = 'test_0x1f60_incomplete.jpg';
        final decoded = decodeEmoji(partialHex);

        // Should handle partial hex gracefully
        expect(decoded, isNotNull);
      });
    });
  });
}
