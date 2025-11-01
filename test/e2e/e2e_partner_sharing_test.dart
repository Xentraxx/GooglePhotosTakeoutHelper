/// E2E tests for Partner Sharing functionality
///
/// This test file specifically focuses on:
/// 1. Partner sharing separation to PARTNER_SHARED folder
/// 2. Date division integration with partner sharing
/// 3. Disabled partner sharing preserving original behavior

// ignore_for_file: avoid_redundant_argument_values

library;

import 'dart:convert';
import 'dart:io';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('Partner Sharing E2E Tests', () {
    late TestFixture fixture;
    late ProcessingPipeline pipeline;
    late Directory inputDir;
    late Directory outputDir;

    setUpAll(() async {
      await ServiceContainer.instance.initialize();
    });

    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();
      pipeline = const ProcessingPipeline();

      inputDir = Directory(path.join(fixture.basePath, 'input'));
      outputDir = Directory(path.join(fixture.basePath, 'output'));
      await inputDir.create();
      await outputDir.create();
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    tearDownAll(() async {
      await ServiceContainer.instance.dispose();
      await ServiceContainer.reset();
    });

    test('end-to-end partner sharing separation', () async {
      // Create proper Takeout folder structure
      final takeoutDir = Directory(path.join(inputDir.path, 'Takeout'));
      final googlePhotosDir = Directory(
        path.join(takeoutDir.path, 'Google Photos'),
      );
      await googlePhotosDir.create(recursive: true);

      // Create a partner shared photo with JSON metadata
      final partnerPhoto = File(
        path.join(googlePhotosDir.path, 'partner_photo.jpg'),
      );
      // Use proper JPEG data from test setup
      await partnerPhoto.writeAsBytes(
        base64.decode(greenImgBase64.replaceAll('\n', '')),
      );

      final partnerJson = File(
        path.join(googlePhotosDir.path, 'partner_photo.jpg.json'),
      );
      await partnerJson.writeAsString(
        jsonEncode({
          'title': 'Partner Shared Photo',
          'photoTakenTime': {
            'timestamp': '1609459200', // 2021-01-01
            'formatted': '01.01.2021, 00:00:00 UTC',
          },
          'googlePhotosOrigin': {'fromPartnerSharing': {}},
          'url': 'https://photos.google.com/photo/partner_shared_photo',
        }),
      );

      // Create a personal photo with JSON metadata
      final personalPhoto = File(
        path.join(googlePhotosDir.path, 'personal_photo.jpg'),
      );
      await personalPhoto.writeAsBytes(
        base64.decode(greenImgNoMetaDataBase64.replaceAll('\n', '')),
      );

      final personalJson = File(
        path.join(googlePhotosDir.path, 'personal_photo.jpg.json'),
      );
      await personalJson.writeAsString(
        jsonEncode({
          'title': 'Personal Photo',
          'photoTakenTime': {
            'timestamp': '1609459200', // 2021-01-01
            'formatted': '01.01.2021, 00:00:00 UTC',
          },
          'googlePhotosOrigin': {
            'mobileUpload': {
              'deviceFolder': {'localFolderName': ''},
              'deviceType': 'ANDROID_PHONE',
            },
          },
          'url': 'https://photos.google.com/photo/personal_photo',
        }),
      );

      // Create processing configuration with partner sharing enabled
      final config = ProcessingConfig(
        inputPath: takeoutDir.path, // Use takeout folder as input
        outputPath: outputDir.path,
        albumBehavior: AlbumBehavior.nothing, // Simple mode for testing
        dateDivision: DateDivisionLevel.none,
        dividePartnerShared: true,
        verbose: false,
      );

      // Run the main pipeline
      final result = await pipeline.execute(
        config: config,
        inputDirectory: Directory(takeoutDir.path),
        outputDirectory: outputDir,
      );

      // Verify the pipeline completed successfully
      expect(
        result.isSuccess,
        isTrue,
        reason: 'Pipeline should complete successfully',
      );

      // Verify partner shared photo went to PARTNER_SHARED folder
      final partnerSharedDir = Directory(
        path.join(outputDir.path, 'PARTNER_SHARED'),
      );
      expect(
        partnerSharedDir.existsSync(),
        isTrue,
        reason: 'PARTNER_SHARED folder should exist',
      );

      final partnerSharedPhoto = File(
        path.join(partnerSharedDir.path, 'partner_photo.jpg'),
      );
      expect(
        partnerSharedPhoto.existsSync(),
        isTrue,
        reason: 'Partner shared photo should be in PARTNER_SHARED folder',
      );

      // Verify personal photo went to ALL_PHOTOS folder
      final allPhotosDir = Directory(path.join(outputDir.path, 'ALL_PHOTOS'));
      expect(
        allPhotosDir.existsSync(),
        isTrue,
        reason: 'ALL_PHOTOS folder should exist',
      );

      final personalPhotoMoved = File(
        path.join(allPhotosDir.path, 'personal_photo.jpg'),
      );
      expect(
        personalPhotoMoved.existsSync(),
        isTrue,
        reason: 'Personal photo should be in ALL_PHOTOS folder',
      );

      // Verify original files were moved (not copied)
      expect(
        partnerPhoto.existsSync(),
        isFalse,
        reason: 'Original partner photo should be moved, not copied',
      );
      expect(
        personalPhoto.existsSync(),
        isFalse,
        reason: 'Original personal photo should be moved, not copied',
      );
    });

    test('end-to-end partner sharing with date division', () async {
      // Create proper Takeout folder structure
      final takeoutDir = Directory(path.join(inputDir.path, 'Takeout'));
      final googlePhotosDir = Directory(
        path.join(takeoutDir.path, 'Google Photos'),
      );
      await googlePhotosDir.create(recursive: true);

      // Create a partner shared photo
      final partnerPhoto = File(
        path.join(googlePhotosDir.path, 'partner_2023.jpg'),
      );
      await partnerPhoto.writeAsBytes(
        base64.decode(greenImgBase64.replaceAll('\n', '')),
      );

      final partnerJson = File(
        path.join(googlePhotosDir.path, 'partner_2023.jpg.json'),
      );
      await partnerJson.writeAsString(
        jsonEncode({
          'title': 'Partner Shared 2023',
          'photoTakenTime': {
            'timestamp': '1672531200', // 2023-01-01
            'formatted': '01.01.2023, 00:00:00 UTC',
          },
          'googlePhotosOrigin': {'fromPartnerSharing': {}},
          'url': 'https://photos.google.com/photo/partner_2023',
        }),
      );

      // Create configuration with date division enabled
      final config = ProcessingConfig(
        inputPath: takeoutDir.path, // Use takeout folder as input
        outputPath: outputDir.path,
        albumBehavior: AlbumBehavior.nothing,
        dateDivision: DateDivisionLevel.year,
        dividePartnerShared: true,
        verbose: false,
      );

      // Run pipeline
      final result = await pipeline.execute(
        config: config,
        inputDirectory: Directory(takeoutDir.path),
        outputDirectory: outputDir,
      );

      expect(result.isSuccess, isTrue);

      // Verify partner shared photo went to PARTNER_SHARED/2023/
      final partnerSharedPhotoPath = path.join(
        outputDir.path,
        'PARTNER_SHARED',
        '2023',
        'partner_2023.jpg',
      );
      final partnerSharedPhoto = File(partnerSharedPhotoPath);
      expect(
        partnerSharedPhoto.existsSync(),
        isTrue,
        reason: 'Partner shared photo should be in PARTNER_SHARED/2023/ folder',
      );
    });

    test('partner sharing disabled preserves original behavior', () async {
      // Create proper Takeout folder structure
      final takeoutDir = Directory(path.join(inputDir.path, 'Takeout'));
      final googlePhotosDir = Directory(
        path.join(takeoutDir.path, 'Google Photos'),
      );
      await googlePhotosDir.create(recursive: true);

      // Create a partner shared photo
      final partnerPhoto = File(
        path.join(googlePhotosDir.path, 'partner_photo.jpg'),
      );
      await partnerPhoto.writeAsBytes(
        base64.decode(greenImgBase64.replaceAll('\n', '')),
      );

      final partnerJson = File(
        path.join(googlePhotosDir.path, 'partner_photo.jpg.json'),
      );
      await partnerJson.writeAsString(
        jsonEncode({
          'title': 'Partner Shared Photo',
          'photoTakenTime': {
            'timestamp': '1609459200',
            'formatted': '01.01.2021, 00:00:00 UTC',
          },
          'googlePhotosOrigin': {'fromPartnerSharing': {}},
          'url': 'https://photos.google.com/photo/partner_shared_photo',
        }),
      );

      // Create configuration with partner sharing disabled
      final config = ProcessingConfig(
        inputPath: takeoutDir.path, // Use takeout folder as input
        outputPath: outputDir.path,
        albumBehavior: AlbumBehavior.nothing,
        dateDivision: DateDivisionLevel.none,
        dividePartnerShared: false, // Disabled
        verbose: false,
      );

      // Run pipeline
      final result = await pipeline.execute(
        config: config,
        inputDirectory: Directory(takeoutDir.path),
        outputDirectory: outputDir,
      );

      expect(result.isSuccess, isTrue);

      // Verify partner shared photo went to ALL_PHOTOS (not PARTNER_SHARED)
      final allPhotosPhoto = File(
        path.join(outputDir.path, 'ALL_PHOTOS', 'partner_photo.jpg'),
      );
      expect(
        allPhotosPhoto.existsSync(),
        isTrue,
        reason:
            'Partner shared photo should go to ALL_PHOTOS when feature is disabled',
      );

      // Verify PARTNER_SHARED folder was not created
      final partnerSharedDir = Directory(
        path.join(outputDir.path, 'PARTNER_SHARED'),
      );
      expect(
        partnerSharedDir.existsSync(),
        isFalse,
        reason:
            'PARTNER_SHARED folder should not exist when feature is disabled',
      );
    });
  });
}
