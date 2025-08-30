import 'dart:convert';
import 'dart:io';
import 'package:gpth/gpth-lib.dart';
import 'package:test/test.dart';

import '../setup/test_setup.dart';

void main() {
  group('Partner Sharing Detection', () {
    late TestFixture fixture;

    setUp(() async {
      fixture = TestFixture();
      await fixture.setUp();
    });

    tearDown(() async {
      await fixture.tearDown();
    });

    group('JSON Partner Sharing Extractor', () {
      test('detects partner shared media from JSON', () async {
        final imageFile = fixture.createImageWithoutExif('partner_shared.jpg');
        final jsonFile = File('${imageFile.path}.json');

        await jsonFile.writeAsString(
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

        final isPartnerShared = await jsonPartnerSharingExtractor(imageFile);

        expect(isPartnerShared, isTrue);

        await jsonFile.delete();
      });

      test('detects personal uploads (not partner shared)', () async {
        final imageFile = fixture.createImageWithoutExif('personal_upload.jpg');
        final jsonFile = File('${imageFile.path}.json');

        await jsonFile.writeAsString(
          jsonEncode({
            'title': 'Personal Upload',
            'photoTakenTime': {
              'timestamp': '1609459200',
              'formatted': '01.01.2021, 00:00:00 UTC',
            },
            'googlePhotosOrigin': {
              'mobileUpload': {
                'deviceFolder': {'localFolderName': ''},
                'deviceType': 'ANDROID_PHONE',
              },
            },
            'url': 'https://photos.google.com/photo/personal_upload',
          }),
        );

        final isPartnerShared = await jsonPartnerSharingExtractor(imageFile);

        expect(isPartnerShared, isFalse);

        await jsonFile.delete();
      });

      test('returns false when no JSON file exists', () async {
        final imageFile = fixture.createImageWithoutExif('no_json.jpg');

        final isPartnerShared = await jsonPartnerSharingExtractor(imageFile);

        expect(isPartnerShared, isFalse);
      });

      test('returns false when JSON has no googlePhotosOrigin', () async {
        final imageFile = fixture.createImageWithoutExif('no_origin.jpg');
        final jsonFile = File('${imageFile.path}.json');

        await jsonFile.writeAsString(
          jsonEncode({
            'title': 'Photo without origin info',
            'photoTakenTime': {
              'timestamp': '1609459200',
              'formatted': '01.01.2021, 00:00:00 UTC',
            },
          }),
        );

        final isPartnerShared = await jsonPartnerSharingExtractor(imageFile);

        expect(isPartnerShared, isFalse);

        await jsonFile.delete();
      });

      test('handles malformed JSON gracefully', () async {
        final imageFile = fixture.createImageWithoutExif('bad_json.jpg');
        final jsonFile = File('${imageFile.path}.json');

        await jsonFile.writeAsString('{ invalid json content }');

        final isPartnerShared = await jsonPartnerSharingExtractor(imageFile);

        expect(isPartnerShared, isFalse);

        await jsonFile.delete();
      });
    });

    group('MediaEntity Partner Sharing', () {
      test('creates MediaEntity with partner sharing flag', () {
        final file = fixture.createFile('test.jpg', [1, 2, 3]);

        final partnerSharedEntity = MediaEntity.single(
          file: file,
          partnershared: true,
        );

        final personalEntity = MediaEntity.single(file: file);

        expect(partnerSharedEntity.partnershared, isTrue);
        expect(personalEntity.partnershared, isFalse);
      });

      test('preserves partner sharing in withFile method', () {
        final file1 = fixture.createFile('test1.jpg', [1, 2, 3]);
        final file2 = fixture.createFile('test2.jpg', [4, 5, 6]);

        final entity = MediaEntity.single(file: file1, partnershared: true);

        final entityWithNewFile = entity.withFile('Album', file2);

        expect(entityWithNewFile.partnershared, isTrue);
      });

      test('preserves partner sharing in withDate method', () {
        final file = fixture.createFile('test.jpg', [1, 2, 3]);

        final entity = MediaEntity.single(file: file, partnershared: true);

        final entityWithDate = entity.withDate(dateTaken: DateTime.now());

        expect(entityWithDate.partnershared, isTrue);
      });

      test('merges partner sharing correctly (OR logic)', () {
        final file1 = fixture.createFile('test1.jpg', [1, 2, 3]);
        final file2 = fixture.createFile('test2.jpg', [4, 5, 6]);

        final partnerSharedEntity = MediaEntity.single(
          file: file1,
          partnershared: true,
        );

        final personalEntity = MediaEntity.single(file: file2);

        // Partner shared + personal = partner shared
        final merged1 = partnerSharedEntity.mergeWith(personalEntity);
        expect(merged1.partnershared, isTrue);

        // Personal + partner shared = partner shared
        final merged2 = personalEntity.mergeWith(partnerSharedEntity);
        expect(merged2.partnershared, isTrue);

        // Personal + personal = personal
        final merged3 = personalEntity.mergeWith(personalEntity);
        expect(merged3.partnershared, isFalse);
      });

      test('includes partner sharing in equality comparison', () {
        final file = fixture.createFile('test.jpg', [1, 2, 3]);

        final entity1 = MediaEntity.single(file: file, partnershared: true);

        final entity2 = MediaEntity.single(file: file);

        final entity3 = MediaEntity.single(file: file, partnershared: true);

        expect(entity1 == entity2, isFalse);
        expect(entity1 == entity3, isTrue);
      });

      test('includes partner sharing in hashCode', () {
        final file = fixture.createFile('test.jpg', [1, 2, 3]);

        final entity1 = MediaEntity.single(file: file, partnershared: true);

        final entity2 = MediaEntity.single(file: file);

        expect(entity1.hashCode == entity2.hashCode, isFalse);
      });

      test('includes partner sharing in toString', () {
        final file = fixture.createFile('test.jpg', [1, 2, 3]);

        final partnerSharedEntity = MediaEntity.single(
          file: file,
          partnershared: true,
        );

        final personalEntity = MediaEntity.single(file: file);

        expect(partnerSharedEntity.toString(), contains('partnershared: true'));
        expect(personalEntity.toString(), isNot(contains('partnershared')));
      });
    });
  });
}
