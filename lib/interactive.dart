/// This file contains code for interacting with user when launched without
/// arguments => probably with double-click
///
/// Such "interactive mode" was created because people are too dumb to use cmd
/// And I'm too lazy to create GUI <- this line is by Copilot and is true
///
/// Rules for this file functions do...:
/// - ...use sleep() to make thing live and give time to read text
/// - ...decide for themselves how much sleep() they want and where
/// - ...start and end without any extra \n, but can have \n inside
///    - extra \n are added in main file
/// - ...detect when something is wrong (f.e. disk space) and quit whole program
/// - ...are as single-job as it's appropriate - main file calls them one by one
library;

import 'dart:async';
import 'dart:io';

// @Deprecated('Interactive unzipping is suspended for now!')
// import 'package:archive/archive_io.dart';
import 'package:file_picker_desktop/file_picker_desktop.dart';
import 'package:path/path.dart' as p;

import 'utils.dart';

const Map<String, String> albumOptions = <String, String>{
  'shortcut':
      '[Recommended] Album folders with shortcuts/symlinks to \n'
      'original photos. \nRecommended as it will take the least space, but \n'
      'may not be portable when moving across systems/computes/phones etc\n',
  'duplicate-copy':
      'Album folders with photos copied into them. \n'
      'This will work across all systems, but may take wayyy more space!!\n',
  'json':
      'Put ALL photos in one folder and \n'
      'make a .json file with info about albums. \n'
      "Use if you're a programmer, or just want to get everything, \n"
      'ignoring lack of year-folders etc.\n',
  'nothing':
      'Ignore album associations and put all unique photos into one folder. \n'
      'All photos including album-only photos are processed. \n'
      'NOTE: Special folders (Archive/Trash) are handled separately.\n',
  'reverse-shortcut':
      'Album folders with ORIGINAL photos. "ALL_PHOTOS" folder \n'
      'with shortcuts/symlinks to albums. If a photo is not in an album, \n'
      'the original is saved. CAUTION: If a photo is in multiple albums, it will \n'
      'be duplicated in the other albums, and the shortcuts/symlinks in \n'
      '"ALL_PHOTOS" will point only to one album.\n',
};

/// Whether we are, indeed, running interactive (or not)
bool indeed = false;

/// Pauses execution for specified number of seconds
///
/// [seconds] Number of seconds to sleep (can be fractional)
Future<void> sleep(final num seconds) =>
    Future<void>.delayed(Duration(milliseconds: (seconds * 1000).toInt()));

/// Displays a prompt and waits for user to press enter
void pressEnterToContinue() {
  print('[press enter to continue]');
  stdin.readLineSync();
}

/// Reads user input and normalizes it (removes brackets, lowercase, trim)
///
/// Returns the normalized input string
Future<String> askForInt() async => stdin
    .readLineSync()!
    .replaceAll('[', '')
    .replaceAll(']', '')
    .toLowerCase()
    .trim();

/// Displays greeting message and introduction to the tool
Future<void> greet() async {
  print('GooglePhotosTakeoutHelper v$version');
  await sleep(1);
  print(
    'Hi there! This tool will help you to get all of your photos from '
    'Google Takeout to one nice tidy folder\n',
  );
  await sleep(3);
  print(
    '(If any part confuses you, read the guide on:\n'
    'https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper )',
  );
  await sleep(3);
}

/// does not quit explicitly - do it yourself
Future<void> nothingFoundMessage() async {
  print('...oh :(');
  print('...');
  print("8 I couldn't find any D: reasons for this may be:");
  if (indeed) {
    print(
      "  - you've already ran gpth and it moved all photos to output -\n"
      '    delete the input folder and re-extract the zip',
    );
  }
  print(
    "  - your Takeout doesn't have any \"year folders\" -\n"
    '    visit https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper\n'
    '    again and request new, correct Takeout',
  );
  print('After fixing this, go ahead and try again :)');
}

/// Prompts user to select input directory using file picker dialog
///
/// Returns the selected Directory
/// Throws if dialog fails or user cancels
Future<Directory> getInputDir() async {
  print('Select the directory where you unzipped all your takeout zips');
  print('(Make sure they are merged => there is only one "Takeout" folder!)');
  await sleep(1);
  pressEnterToContinue();
  final String? dir = await getDirectoryPath(
    dialogTitle: 'Select unzipped folder:',
  );
  await sleep(1);
  if (dir == null) {
    error('Duh, something went wrong with selecting - try again!');
    return getOutput();
  }
  print('Cool!');
  await sleep(1);
  return Directory(dir);
}

/// Asks user for zip files with ui dialogs
@Deprecated('Interactive unzipping is suspended for now!')
Future<List<File>> getZips() async {
  print(
    'First, select all .zips from Google Takeout '
    '(use Ctrl to select multiple)',
  );
  await sleep(2);
  pressEnterToContinue();
  final FilePickerResult? files = await pickFiles(
    dialogTitle: 'Select all Takeout zips:',
    type: FileType.custom,
    allowedExtensions: <String>['zip', 'tgz'],
    allowMultiple: true,
  );
  await sleep(1);
  if (files == null) {
    error('Duh, something went wrong with selecting - try again!');
    quit(69);
  }
  if (files.count == 0) {
    error('No files selected - try again :/');
    quit(6969);
  }
  if (files.count == 1) {
    print(
      "You selected only one zip - if that's only one you have, it's cool, "
      'but if you have multiple, Ctrl-C to exit gpth, and select them '
      '*all* again (with Ctrl)',
    );
    await sleep(5);
    pressEnterToContinue();
  }
  if (!files.files.every(
    (final PlatformFile e) =>
        File(e.path!).statSync().type == FileSystemEntityType.file &&
        RegExp(r'\.(zip|tgz)$').hasMatch(e.path!),
  )) {
    print(
      'Files: [${files.files.map((final PlatformFile e) => p.basename(e.path!)).join(', ')}]',
    );
    error('Not all files you selected are zips :/ please do this again');
    quit(6969);
  }
  // potentially shows user they selected too little ?
  print(
    'Cool! Selected ${files.count} zips => '
    '${filesize(files.files.map((final PlatformFile e) => File(e.path!).statSync().size).reduce((final int a, final int b) => a + b))}',
  );
  await sleep(1);
  return files.files.map((final PlatformFile e) => File(e.path!)).toList();
}

/// Prompts user to select output directory using file picker dialog
///
/// Returns the selected Directory
/// Recursively asks again if dialog fails
Future<Directory> getOutput() async {
  print(
    'Now, select output folder - all photos will be moved there\n'
    '(note: GPTH will *move* your photos - no extra space will be taken ;)',
  );
  await sleep(1);
  pressEnterToContinue();
  final String? dir = await getDirectoryPath(
    dialogTitle: 'Select output folder:',
  );
  await sleep(1);
  if (dir == null) {
    error('Duh, something went wrong with selecting - try again!');
    return getOutput();
  }
  print('Cool!');
  await sleep(1);
  return Directory(dir);
}

/// Asks user how to organize photos by date folders
///
/// Returns:
/// - 0: One big folder
/// - 1: Year folders
/// - 2: Year/month folders
/// - 3: Year/month/day folders
Future<num> askDivideDates() async {
  print(
    'Do you want your photos in one big chronological folder, '
    'or divided to folders by year/month?',
  );
  print('[1] (default) - one big folder');
  print('[2] - year folders');
  print('[3] - year/month folders');
  print('[3] - year/month/day folders');
  print('(Type a number or press enter for default):');
  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print('Selected one big folder');
      return 0;
    case '2':
      print('Will divide by year');
      return 1;
    case '3':
      print('Will divide by year and month');
      return 2;
    case '4':
      print('Will divide by year, month, and day');
      return 3;
    default:
      error('Invalid answer - try again');
      return askDivideDates();
  }
}

/// Asks user whether to remove "supplemental-metadata" suffix from JSON files
///
/// Returns true if suffix should be removed
Future<bool> askModifyJson() async {
  print(
    'Check if your .json files of your photos contains "supplemental-metadata" '
    'between the original extension and .json. If this suffix is present, '
    'the script will not be able to map a media file with the corresponding JSON file.'
    'Note that this mode will alter your original json files, regardless of the "copy" mode.',
  );
  print('For example: myImageName.jpg.supplemental-metadata.json');
  print(
    '[1] (Erase suffix) - Yes, the json files have the suffix "supplemental-metadata" (default)',
  );
  print('[2] (Dont Erease suffix) - No');
  print('(Type a number or press enter for default):');
  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print('Will erease the suffix "supplemental-metadata"');
      return true;
    case '2':
      print('Will not erease the suffix');
      return false;
    default:
      error('Invalid answer - try again');
      return askModifyJson();
  }
}

/// Prompts user to choose album handling behavior
///
/// Returns one of the album option keys from [albumOptions]
///
/// Available album modes:
///
/// - **shortcut**: Creates shortcuts/symlinks from album folders to the main file in ALL_PHOTOS.
///   The original file is moved to ALL_PHOTOS, and shortcuts are created in album folders.
///   This saves space while maintaining album organization.
///
/// - **duplicate-copy**: Creates actual copies of files in both ALL_PHOTOS and album folders.
///   Each file appears in ALL_PHOTOS and in every album it belongs to as separate physical files.
///   Uses more disk space but provides complete independence between folders.
///
/// - **reverse-shortcut**: The opposite of shortcut mode. Files remain in album folders,
///   and shortcuts are created in ALL_PHOTOS pointing to the album locations.
///   Maintains files in their album context while providing access via ALL_PHOTOS.
///
/// - **json**: Creates a single ALL_PHOTOS folder with all files, plus an albums-info.json
///   file that contains metadata about which albums each file belonged to.
///   Most space-efficient option with programmatic album information.
///   Note: Special folder handling is controlled separately.
///
/// - **nothing**: Ignores album associations entirely. Creates only ALL_PHOTOS folder with all
///   unique photos including album-only photos. Album metadata is discarded.
///   Simplest option for users who don't care about album organization.
///   Note: Special folders (Archive, Trash, etc.) are handled separately.
Future<String> askAlbums() async {
  print('What should be done with albums?');
  int i = 0;
  for (final MapEntry<String, String> entry in albumOptions.entries) {
    print('[${i++}] ${entry.key}: ${entry.value}');
  }
  final int? answer = int.tryParse(await askForInt());
  if (answer == null || answer < 0 || answer >= albumOptions.length) {
    error('Invalid answer - try again');
    return askAlbums();
  }
  final String choice = albumOptions.keys.elementAt(answer);
  print('Okay, doing: $choice');
  return choice;
}

/// Prompts user to choose special folder handling behavior
///
/// Returns one of: 'auto', 'skip', 'include', 'albums'
///
/// Available special folder modes:
///
/// - **auto**: Automatic handling based on album mode (default behavior)
/// - **skip**: Skip special folders entirely (Archive, Trash, etc. are ignored)
/// - **include**: Include special folder files in ALL_PHOTOS (no album structure)
/// - **albums**: Treat special folders as album folders (maintains folder structure)
Future<String> askSpecialFolders() async {
  print(
    '\nHow should special folders (Archive, Trash, Screenshots, Camera) be handled?',
  );
  print('[0] auto: Automatic handling based on album mode (default)');
  print('[1] skip: Skip special folders entirely');
  print('[2] include: Include special folder files in ALL_PHOTOS');
  print('[3] albums: Treat special folders as album folders');
  print('(Type a number or press enter for default):');
  final String answer = await askForInt();
  switch (answer) {
    case '0':
    case '':
      print('Selected automatic handling');
      return 'auto';
    case '1':
      print('Will skip special folders');
      return 'skip';
    case '2':
      print('Will include special folders in ALL_PHOTOS');
      return 'include';
    case '3':
      print('Will treat special folders as albums');
      return 'albums';
    default:
      error('Invalid answer - try again');
      return askSpecialFolders();
  }
}

// this is used in cli mode as well
Future<bool> askForCleanOutput() async {
  print('Output folder IS NOT EMPTY! What to do? Type either:');
  print('[1] - delete *all* files inside output folder and continue');
  print('[2] - continue as usual - put output files alongside existing');
  print('[3] - exit program to examine situation yourself');
  final String answer = stdin
      .readLineSync()!
      .replaceAll('[', '')
      .replaceAll(']', '')
      .toLowerCase()
      .trim();
  switch (answer) {
    case '1':
      print('Okay, deleting all files inside output folder...');
      return true;
    case '2':
      print('Okay, continuing as usual...');
      return false;
    case '3':
      print('Okay, exiting...');
      quit(0);
    default:
      error('Invalid answer - try again');
      return askForCleanOutput();
  }
}

/// Asks user whether to transform Pixel Motion Photo extensions to .mp4
///
/// Returns true if .MP/.MV files should be renamed to .mp4
Future<bool> askTransformPixelMP() async {
  print(
    'Pixel Motion Pictures are saved with the .MP or .MV '
    'extensions. Do you want to change them to .mp4 '
    'for better compatibility?',
  );
  print('[1] (default) - no, keep original extension');
  print('[2] - yes, change extension to .mp4');
  print('(Type 1 or 2 or press enter for default):');
  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print('Okay, will keep original extension');
      return false;
    case '2':
      print('Okay, will change to mp4!');
      return true;
    default:
      error('Invalid answer - try again');
      return askTransformPixelMP();
  }
}

/// Asks user whether to update creation times on Windows
///
/// Returns true if creation times should be synced with modified times
Future<bool> askChangeCreationTime() async {
  print(
    'This program fixes file "modified times". '
    'Due to language limitations, creation times remain unchanged. '
    'Would you like to run a separate script at the end to sync '
    'creation times with modified times?'
    '\nNote: ONLY ON WINDOWS',
  );
  print('[1] (Default) - No, don\'t update creation time');
  print('[2] - Yes, update creation time to match modified time');
  print('(Type 1 or 2, or press enter for default):');
  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print('Okay, will not change creation time');
      return false;
    case '2':
      print('Okay, will update creation time at the end of the prorgam!');
      return true;
    default:
      error('Invalid answer - try again');
      return askChangeCreationTime();
  }
}

/// Checks free space on disk and notifies user accordingly
@Deprecated('Interactive unzipping is suspended for now!')
Future<void> freeSpaceNotice(final int required, final Directory dir) async {
  final int? freeSpace = await getDiskFree(dir.path);
  if (freeSpace == null) {
    print(
      'Note: everything will take ~${filesize(required)} of disk space - '
      'make sure you have that available on ${dir.path} - otherwise, '
      'Ctrl-C to exit, and make some free space!\n'
      'Or: unzip manually, remove the zips and use gpth with cmd options',
    );
  } else if (freeSpace < required) {
    print(
      '!!! WARNING !!!\n'
      'Whole process requires ${filesize(required)} of space, but you '
      'only have ${filesize(freeSpace)} available on ${dir.path} - \n'
      'Go make some free space!\n'
      '(Or: unzip manually, remove the zips, and use gpth with cmd options)',
    );
    quit(69);
  } else {
    print(
      '(Note: everything will take ~${filesize(required)} of disk space - '
      'you have ${filesize(freeSpace)} free so should be fine :)',
    );
  }
  await sleep(3);
  pressEnterToContinue();
}

/// Unzips all zips to given folder (creates it if needed)
@Deprecated('Interactive unzipping is suspended for now!')
Future<void> unzip(final List<File> zips, final Directory dir) async {
  throw UnimplementedError();
  // if (await dir.exists()) await dir.delete(recursive: true);
  // await dir.create(recursive: true);
  // print('gpth will now unzip all of that, process it and put everything in '
  //     'the output folder :)');
  // await sleep(1);
  // for (final zip in zips) {
  //   print('Unzipping ${p.basename(zip.path)}...');
  //   try {
  //     await extractFileToDisk(zip.path, dir.path, asyncWrite: true);
  //   } on PathNotFoundException catch (e) {
  //     error('Error while unzipping $zip :(\n$e');
  //     error('');
  //     error('===== This is a known issue ! =====');
  //     error("Looks like unzipping doesn't want to work :(");
  //     error(
  //         "You will have to unzip manually - see 'Running manually' section in README");
  //     error('');
  //     error(
  //         'https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper#running-manually-with-cmd');
  //     error('');
  //     error('===== Sorry for inconvenience =====');
  //   } catch (e) {
  //     error('Error while unzipping $zip :(\n$e');
  //     quit(69);
  //   }
  // }
}

Future<bool> askIfWriteExif() async {
  if (exifToolInstalled) {
    print(
      'This mode will write Exif data (dates/times/coordinates) back to your files. '
      'To achieve the best results, download Exiftool and place it next to this executable or in your \$PATH.'
      'If you haven\'t done so yet, close this program and come back. '
      'creation times with modified times?'
      '\nNote: ONLY ON WINDOWS',
    );
  } else {
    print(
      'This mode will write Exif data (dates/times/coordinates) back to your files. '
      'We detected that ExifTool is NOT available! '
      'To achieve the best results, we strongly recomend to download Exiftool and place it next to this executable or in your \$PATH.'
      'You can download ExifTool here: https://exiftool.org '
      'Note that this mode will alter your original files, regardless of the "copy" mode.'
      'Do you want to continue with writing exif data enabled?',
    );
  }

  print('[1] (Default) - Yes, write exif');
  print('[2] - No, don\'t write to exif');
  print('(Type 1 or 2, or press enter for default):');
  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print('Okay, will write to exif');
      return true;
    case '2':
      print('Okay, will not touch the exif of your files!');
      return false;
    default:
      error('Invalid answer - try again');
      return askIfWriteExif();
  }
}

Future<bool> askIfLimitFileSize() async {
  print(
    'By default we will process all your files.'
    'However, if you have large video files and run this script on a low ram system (e.g. a NAS or your vacuum cleaning robot), you might want to '
    'limit the maximum file size to 64 MB not run out of memory. '
    'We recommend to only activate this if you run into problems.',
  );

  print('[1] (Default) - Don\'t limit me! Process everything!');
  print('[2] - I operate a Toaster. Limit supported media size to 64 MB');
  print('(Type 1 or 2, or press enter for default):');
  final String answer = await askForInt();
  switch (answer) {
    case '1':
    case '':
      print('Alrighty! Will process everything!');
      return false;
    case '2':
      print('Okay! Limiting files to a size of 64 MB');
      return true;
    default:
      error('Invalid answer - try again');
      return askIfLimitFileSize();
  }
}
