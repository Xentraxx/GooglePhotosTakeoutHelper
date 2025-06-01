import 'dart:io';
import 'package:gpth/folder_classify.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  // Create a test directory structure similar to what GPTH creates
  final testOutputDir = Directory('/tmp/gpth_debug_test');
  if (await testOutputDir.exists()) {
    await testOutputDir.delete(recursive: true);
  }
  await testOutputDir.create(recursive: true);

  // Create ALL_PHOTOS directory
  final allPhotosDir = Directory(p.join(testOutputDir.path, 'ALL_PHOTOS'));
  await allPhotosDir.create();

  // Create a test photo in ALL_PHOTOS
  final testPhoto = File(p.join(allPhotosDir.path, 'test_photo.jpg'));
  await testPhoto.writeAsBytes([1, 2, 3, 4, 5]);

  // Create album directories
  final albums = ['Vacation 2023', 'Family Photos 👨‍👩‍👧‍👦', 'Holiday Memories', 'Wedding Photos 💒', 'Travel Adventures'];
  
  for (final albumName in albums) {
    final albumDir = Directory(p.join(testOutputDir.path, albumName));
    await albumDir.create();
    
    // Create a test photo in the album
    final albumPhoto = File(p.join(albumDir.path, 'album_photo.jpg'));
    await albumPhoto.writeAsBytes([1, 2, 3, 4, 5]);
  }

  print('Created test directory structure:');
  await for (final entity in testOutputDir.list()) {
    if (entity is Directory) {
      print('  Directory: ${p.basename(entity.path)}');
      await for (final file in entity.list()) {
        print('    File: ${p.basename(file.path)}');
      }
    }
  }

  print('\nTesting isAlbumFolder on each directory:');
  await for (final entity in testOutputDir.list()) {
    if (entity is Directory) {
      final dirName = p.basename(entity.path);
      if (dirName != 'ALL_PHOTOS') {
        final isAlbum = await isAlbumFolder(entity);
        print('  $dirName: isAlbumFolder = $isAlbum');
      }
    }
  }

  // Cleanup
  await testOutputDir.delete(recursive: true);
}
