import 'dart:io';
import 'package:args/args.dart';
import 'package:console_bars/console_bars.dart';
import 'package:coordinate_converter/src/models/dms_coordinates_model.dart';
import 'package:gpth/date_extractors/date_extractor.dart';
import 'package:gpth/emojicleaner.dart';
import 'package:gpth/exif_writer.dart';
import 'package:gpth/exiftoolInterface.dart';
import 'package:gpth/extras.dart';
import 'package:gpth/folder_classify.dart';
import 'package:gpth/grouping.dart';
import 'package:gpth/interactive.dart' as interactive;
import 'package:gpth/media.dart';
import 'package:gpth/moving.dart';
import 'package:gpth/utils.dart';
import 'package:path/path.dart' as p;

/// ############################### READ ME #############################
// Okay, time to explain the structure of things here
// We create a list of Media objects, and fill it with everything we find
// in "year folders". Then, we play *mutably* with this list - fill Media's
// with guess DateTime's, remove duplicates from this list.
//
// No shitheads, you did not overhear - we *mutate* the whole list and objects
// inside it. This is not Flutter-ish, but it's not Flutter - it's a small
// simple script, and this the best solution 😎💯

// Okay, more details on what will happen here:
// 1. We find *all* media in either year folders or album folders.
//    Every single file will be a separate [Media] object.
//    If given [Media] was found in album folder, it will have it noted
// 2. We [removeDuplicates] - if two files in same/null album have same hash,
//    one will be removed. Note that there are still duplicates from different
//    albums left. This is intentional
// 3. We guess their dates. Functions in [dateExtractors] are used in order
//    from most to least accurate
// 4. Now we [findAlbums]. This will analyze [Media] that have same hashes,
//    and leave just one with all [albums] filled.
//    final exampleMedia = [
//      Media('lonePhoto.jpg'),
//      Media('photo1.jpg, albums=null),
//      Media('photo1.jpg, albums={Vacation}),
//      Media('photo1.jpg, albums={Friends}),
//    ];
//    findAlbums(exampleMedia);
//    exampleMedia == [
//      Media('lonePhoto.jpg'),
//      Media('photo1.jpg, albums={Vacation, Friends}),
//    ];
//
//    Steps for all the major functionality have been added. You should always add to the output the step it originated from.
//    This is done to make it easier to debug and understand the flow of the program.
//    To find your way around search for "Step X" in the code.

/// ##############################################################
/// This is the help text that will be shown when user runs gpth --help

const String helpText =
    '''GooglePhotosTakeoutHelper v$version - The Dart successor

gpth is ment to help you with exporting your photos from Google Photos.

First, go to https://takeout.google.com/ , deselect all and select only Photos.
When ready, download all .zips, and extract them into *one* folder.
To read and write exif data, you have to install exiftool (e.g. from here https://exiftool.org)
for your OS and make sure the executable is in a folder in the \$PATH.

Then, run: gpth --input "folder/with/all/takeouts" --output "your/output/folder"
...and gpth will parse and organize all photos into one big chronological folder
''';

/// ##############################################################
/// This is the main function that will be run when user runs gpth

Future<void> main(final List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption(
      'fix',
      help:
          'Folder with any photos to fix dates. \n'
          'This skips whole "GoogleTakeout" procedure. \n'
          'It is here because gpth has some cool heuristics to determine date \n'
          'of a photo, and this can be handy in many situations :)\n',
    )
    ..addFlag(
      'interactive',
      help:
          'Use interactive mode. Type this in case auto-detection fails, \n'
          'or you *really* want to combine advanced options with prompts\n',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help:
          'Shows extensive output for debugging and analysis.\n'
          'This can help with troubleshooting\n',
    )
    ..addOption(
      'input',
      abbr: 'i',
      help:
          'Input folder with *all* takeouts *extracted*.\n'
          '(The folder your "Takeout" folder is within)\n',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Output folder where all photos will land\n',
    )
    ..addOption(
      'albums',
      help: 'What to do about albums?',
      allowed: interactive.albumOptions.keys,
      allowedHelp: interactive.albumOptions,
      defaultsTo: 'shortcut',
    )
    ..addOption(
      'divide-to-dates',
      help: 'Divide output to folders by nothing/year/month/day\n',
      allowed: <String>['0', '1', '2', '3'],
      defaultsTo: '0',
    )
    ..addFlag('skip-extras', help: 'Skip extra images (like -edited etc)\n')
    ..addFlag(
      'guess-from-name',
      help: 'Try to guess file dates from their names\n',
      defaultsTo: true,
    )
    ..addFlag(
      'copy',
      help:
          'Copy files instead of moving them.\n'
          'This is usually slower, and uses extra space, \n'
          "but doesn't break your input folder\n",
    )
    ..addFlag(
      'modify-json',
      help:
          'Delete the "supplemental-metadata" suffix from \n'
          '.json files to ensure that script works correctly\n',
      defaultsTo: true,
    )
    ..addFlag(
      'transform-pixel-mp',
      help: 'Transform Pixel .MP or .MV extensions to ".mp4"\n',
    )
    ..addFlag(
      'update-creation-time',
      help:
          'Set creation time equal to the last \n'
          'modification date at the end of the program. \n'
          'Only Windows supported\n',
    )
    ..addFlag(
      'write-exif',
      help:
          'Writes geodata from json files and the extracted DateTime to EXIF. \n'
          'It always writes to original data, even if combined with --copy! (default)',
      defaultsTo: true,
    )
    ..addFlag(
      'limit-filesize',
      help:
          'Enforces a maximum size of 64MB per file for systems with low RAM (e.g. NAS).\n '
          'DateTime will not be extracted from or written to larger files.',
    )
    ..addOption(
      'special-folders',
      help:
          'How to handle special folders (Archive, Trash, Screenshots, Camera)',
      allowed: <String>['auto', 'skip', 'include', 'albums'],
      allowedHelp: <String, String>{
        'auto': 'Automatic handling based on album mode (default)',
        'skip': 'Skip special folders entirely',
        'include': 'Include special folder files in ALL_PHOTOS',
        'albums': 'Treat special folders as album folders',
      },
      defaultsTo: 'auto',
    );
  final Map<String, dynamic> args = <String, dynamic>{};
  try {
    final ArgResults res = parser.parse(arguments);
    for (final String key in res.options) {
      args[key] = res[key];
    }
    interactive.indeed =
        args['interactive'] || (res.arguments.isEmpty && stdin.hasTerminal);
  } on FormatException catch (e) {
    // don't print big ass trace
    error('$e');
    quit(2);
  } catch (e) {
    // any other exceptions (args must not be null)
    error('$e');
    quit(100);
  }

  if (args['help']) {
    print(helpText);
    print(parser.usage);
    return;
  }

  // here we check if in debug profile or in verbose mode to activate logging.
  bool isDebugMode = false;
  // ignore: prefer_asserts_with_message
  assert(() {
    isDebugMode = true;
    return true;
  }());
  if (args['verbose'] || isDebugMode) {
    isVerbose = true;
    log('Verbose mode active!');
  }
  // set the enforceMaxFileSize variable through argument
  if (args['limit-filesize']) {
    enforceMaxFileSize = true;
  }

  //checking if Exiftool is installed
  if (await initExiftool()) {
    print(
      '[INFO] Exiftool was found! Continuing with support for reading and writing EXIF data...',
    );
  } else {
    print(
      '[INFO] Exiftool was not found! Continuing without support for reading and writing EXIF data...',
    );
  }
  sleep(const Duration(seconds: 3));

  /// ##############################################################
  /// Here the Script asks interactively to fill all arguments

  if (interactive.indeed) {
    // greet user
    await interactive.greet();
    print('');
    // @Deprecated('Interactive unzipping is suspended for now!')
    // final zips = await interactive.getZips();
    //TODO: Add functionality to unzip files again
    late Directory inDir;
    try {
      inDir = await interactive.getInputDir();
    } catch (e) {
      print(
        'Hmm, interactive selecting input dir crashed... \n'
        "it looks like you're running in headless/on Synology/NAS...\n"
        "If so, you have to use cli options - run 'gpth --help' to see them",
      );
      exit(69);
    }
    print('');
    final Directory out = await interactive.getOutput();
    print('');
    args['write-exif'] = await interactive.askIfWriteExif();
    print('');
    args['limit-filesize'] = await interactive.askIfLimitFileSize();
    print('');
    args['divide-to-dates'] = await interactive.askDivideDates();
    print('');
    args['modify-json'] = await interactive.askModifyJson();
    print('');
    args['albums'] = await interactive.askAlbums();
    print('');
    args['special-folders'] = await interactive.askSpecialFolders();
    print('');
    args['transform-pixel-mp'] = await interactive.askTransformPixelMP();
    print('');
    if (Platform.isWindows) {
      //Only in windows is going to ask
      args['update-creation-time'] = await interactive.askChangeCreationTime();
      print('');
    }

    // @Deprecated('Interactive unzipping is suspended for now!')
    // // calculate approx space required for everything
    // final cumZipsSize = zips.map((e) => e.lengthSync()).reduce((a, b) => a + b);
    // final requiredSpace = (cumZipsSize * 2) + 256 * 1024 * 1024;
    // await interactive.freeSpaceNotice(requiredSpace, out); // and notify this
    // print('');
    //
    // final unzipDir = Directory(p.join(out.path, '.gpth-unzipped'));
    // args['input'] = unzipDir.path;
    args['input'] = inDir.path;
    args['output'] = out.path;
    //
    // await interactive.unzip(zips, unzipDir);
    // print('');
  }

  // elastic list of extractors - can add/remove with cli flags
  // those are in order of reliability -
  // if one fails, only then later ones will be used
  final List<DateTimeExtractor> dateExtractors = <DateTimeExtractor>[
    jsonDateTimeExtractor,
    exifDateTimeExtractor,
    if (args['guess-from-name']) guessExtractor,
    // this is potentially *dangerous* - see:
    // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/175
    (final File f) => jsonDateTimeExtractor(f, tryhard: true),
  ];

  /// ##############################################################
  /// ######################## Occasional Fix mode #################
  /// This is a special mode that will go through all files in the given folder
  /// and try to set each file to correct lastModified value.
  /// This is useful for files that have been moved or copied and have lost their original lastModified value.
  /// This is not a part of the main functionality of the script, but it can be accessed by using the --fix flag.
  /// It is not recommended to use this mode unless you know what you are doing.

  if (args['fix'] != null) {
    // i was thing if not to move this to outside file, but let's leave for now
    print('========== FIX MODE ==========');
    print('I will go through all files in folder that you gave me');
    print('and try to set each file to correct lastModified value');
    final Directory dir = Directory(args['fix']);
    if (!await dir.exists()) {
      error("directory to fix doesn't exist :/");
      quit(11);
    }
    int set = 0;
    int notSet = 0;
    await for (final File file in dir.list(recursive: true).wherePhotoVideo()) {
      DateTime? date;
      for (final DateTimeExtractor extractor in dateExtractors) {
        date = await extractor(file);
        if (date != null) {
          await file.setLastModified(date);
          set++;
          break;
        }
      }
      if (date == null) notSet++;
    }
    print('FINISHED!');
    print('$set set✅');
    print('$notSet not set❌');
    return;
  }

  /// ################# Fix mode END ###############################
  /// ##############################################################
  /// ##### Parse all options and check if alright #################

  if (args['input'] == null) {
    error('No --input folder specified :/');
    quit(10);
  }
  if (args['output'] == null) {
    error('No --output folder specified :/');
    quit(10);
  }
  final Directory input = Directory(args['input']);
  final Directory output = Directory(args['output']);
  if (!await input.exists()) {
    error('Input folder does not exist :/');
    quit(11);
  }
  // all of this logic is to prevent user easily blowing output folder
  // by running command two times
  if (await output.exists() &&
      !await output
          .list()
          // allow input folder to be inside output
          .where(
            (final FileSystemEntity e) =>
                p.absolute(e.path) != p.absolute(args['input']),
          )
          .isEmpty) {
    if (await interactive.askForCleanOutput()) {
      await for (final FileSystemEntity file
          in output.list()
          // delete everything except input folder if there
          .where(
            (final FileSystemEntity e) =>
                p.absolute(e.path) != p.absolute(args['input']),
          )) {
        await file.delete(recursive: true);
      }
    }
  }
  await output.create(recursive: true);

  /// ##############################################################
  // ##### Really important global variables #######################

  // Big global media list that we'll work on
  final List<Media> media = <Media>[];

  // All "year folders" that we found
  final List<Directory> yearFolders = <Directory>[];

  // All album folders - that is, folders that were aside yearFolders and were
  // not matching "Photos from ...." name
  final List<Directory> albumFolders = <Directory>[];

  // All special folders - Google Photos system folders (Archive, Trash, etc.)
  final List<Directory> specialFolders = <Directory>[];

  /// ##############################################################
  /// #### Here we start the actual work ###########################
  /// ##############################################################
  /// ################# STEP 1 #####################################
  /// ##### Fixing JSON files (if needed) ##########################
  final Stopwatch sw1 = Stopwatch()
    ..start(); //Creation of our debugging stopwatch for each step.
  if (args['modify-json']) {
    print(
      '[Step 1/8] Fixing JSON files. Removing suffix... (this may take some time)',
    );
    await renameIncorrectJsonFiles(input);
  }
  sw1.stop();
  print(
    '[Step 1/8] Step 1 took ${sw1.elapsed.inMinutes} minutes or ${sw1.elapsed.inSeconds} seconds to complete.',
  );

  /// ##############################################################
  /// ################# STEP 2 #####################################
  /// ##### Find literally *all* photos/videos and add to list #####
  final Stopwatch sw2 = Stopwatch()
    ..start(); //Creation of our debugging stopwatch for each step.
  print('[Step 2/8] Searching for everything in input folder...');

  // recursive=true makes it find everything nicely even if user id dumb 😋
  await for (final Directory d
      in input.list(recursive: true).whereType<Directory>()) {
    if (isYearFolder(d)) {
      yearFolders.add(d);
    } else if (isSpecialFolder(d)) {
      specialFolders.add(d);
    } else if (await isAlbumFolder(d)) {
      albumFolders.add(d);
    }
  }
  for (final Directory f in yearFolders) {
    await for (final File file in f.list().wherePhotoVideo()) {
      media.add(Media(<String?, File>{null: file}));
    }
  }
  for (final Directory a in albumFolders) {
    final Directory cleanedAlbumDir = encodeAndRenameAlbumIfEmoji(
      a,
    ); //Here we check if there are emojis in the album names and if yes, we hex encode them so there are no problems later!
    await for (final File file in cleanedAlbumDir.list().wherePhotoVideo()) {
      media.add(Media(<String?, File>{albumName(cleanedAlbumDir): file}));
    }
  }

  // Process special folders based on album behavior and special-folders flag
  for (final Directory s in specialFolders) {
    final String folderName = albumName(s);
    await for (final File file in s.list().wherePhotoVideo()) {
      final String specialFoldersMode = args['special-folders'];

      // Determine how to handle special folders
      if (specialFoldersMode == 'skip') {
        // Skip special folders entirely
        continue;
      } else if (specialFoldersMode == 'include') {
        // Include special folder files in ALL_PHOTOS
        media.add(Media(<String?, File>{null: file}));
      } else if (specialFoldersMode == 'albums') {
        // Treat special folders as album folders
        media.add(Media(<String?, File>{folderName: file}));
      } else {
        // Auto mode - handle based on album behavior
        if (args['albums'] == 'nothing') {
          // In 'nothing' mode, skip special folders (they're not year folders)
          continue;
        } else if (args['albums'] == 'json') {
          // In 'json' mode, include ALL photos including special folders as regular files
          media.add(Media(<String?, File>{null: file}));
        } else {
          // In other modes (shortcut, duplicate-copy, reverse-shortcut), treat as special album folders
          media.add(Media(<String?, File>{folderName: file}));
        }
      }
    }
  }

  if (media.isEmpty) {
    await interactive.nothingFoundMessage();
    // @Deprecated('Interactive unzipping is suspended for now!')
    // if (interactive.indeed) {
    //   print('([interactive] removing unzipped folder...)');
    //   await input.delete(recursive: true);
    // }
    quit(13);
  }
  sw2.stop();
  print(
    '[Step 2/8] Step 2 took ${sw2.elapsed.inMinutes} minutes or ${sw2.elapsed.inSeconds} seconds to complete.',
  );

  /// ##############################################################
  /// ################# STEP 3 #####################################
  /// ##### Finding and removing duplicates ########################
  final Stopwatch sw3 = Stopwatch()
    ..start(); //Creation of our debugging stopwatch for each step.
  print('[Step 3/8] Finding duplicates... (This may take some time)');
  final int countDuplicates = removeDuplicates(media);

  /// ##############################################################

  /// ##### Potentially skip extras #####

  if (args['skip-extras']) {
    print('[Step 3/8] Finding "extra" photos (-edited etc)');
  }
  final int countExtras = args['skip-extras'] ? removeExtras(media) : 0;
  sw3.stop();
  print(
    '[Step 3/8] Step 3 took ${sw3.elapsed.inMinutes} minutes or ${sw3.elapsed.inSeconds} seconds to complete.',
  );

  /// ##############################################################
  /// ################# STEP 4 #####################################
  /// ##### Extracting DateTime through Extractors #################

  // NOTE FOR MYSELF/whatever:
  // I placed extracting dates *after* removing duplicates.
  // Today i thought to myself - shouldn't this be reversed?
  // Finding correct date is our *biggest* priority, and duplicate that we just
  // removed might have been the chosen one
  //
  // But on the other hand, duplicates must be hash-perfect, so they contain
  // same exifs, and we can just compare length of their names - in 9999% cases,
  // one with shorter name will have json and others will not 🤷
  // ...and we would potentially waste a lot of time searching for all of their
  //    jsons
  // ...so i'm leaving this like that 😎
  //
  // Ps. BUT i've put album merging *after* guess date - notes below

  /// ##### Extracting/predicting dates using given extractors #####

  final Stopwatch sw4 = Stopwatch()
    ..start(); //Creation of our debugging stopwatch for each step.

  final FillingBar barExtract = FillingBar(
    total: media.length,
    desc: '[Step 4/8] Extracting dates from files',
    width: defaultBarWidth,
  );

  // Collect statistics for reporting
  final Map<DateTimeExtractionMethod, int> extractionStats = {};

  for (int i = 0; i < media.length; i++) {
    int q = 0;
    DateTimeExtractionMethod? extractionMethod;
    for (final DateTimeExtractor extractor in dateExtractors) {
      final DateTime? date = await extractor(media[i].firstFile);
      if (date != null) {
        media[i].dateTaken = date;
        media[i].dateTakenAccuracy = q;
        extractionMethod = DateTimeExtractionMethod
            .values[q]; //This assigns to extractionMethod the enum value corresponding to the current extractor's index.
        barExtract.increment();
        break;
      }
      // increase this every time - indicate the extraction gets more shitty
      q++;
    }
    if (media[i].dateTaken == null) {
      extractionMethod = DateTimeExtractionMethod.none; //For statistics
      media[i].dateTimeExtractionMethod = DateTimeExtractionMethod
          .none; //Writing in media object that no extraction method worked. :(
      log(
        "[Step 4/8] Couldn't get date with any extractor on ${media[i].firstFile.path}",
        level: 'warning',
        forcePrint: true,
      );
    } else {
      media[i].dateTimeExtractionMethod =
          extractionMethod; //Writing used extraction method to this media object.
    }
    extractionStats[extractionMethod!] =
        (extractionStats[extractionMethod] ?? 0) + 1; //Update statistics.
  }
  print('');

  sw4.stop();
  print(
    '[Step 4/8] Step 4 took ${sw4.elapsed.inMinutes} minutes or ${sw4.elapsed.inSeconds} seconds to complete.',
  );

  /// ##############################################################
  /// ################# STEP 5 #####################################
  /// ##### Json Coordinates and extracted DateTime to EXIF ########

  // In this part, we will write coordinates and dates to EXIF data of the files.
  // This is done after the dates of files have been defined, because here we have to write the files to disk again and before
  // the files are moved to the output folder, to avoid shortcuts/symlinks problems.

  final Stopwatch sw5 = Stopwatch()
    ..start(); //Creation of our debugging stopwatch for each step.

  int exifccounter = 0; //Counter for coordinates set in EXIF
  int exifdtcounter = 0; //Counter for DateTime set in EXIF
  if (args['write-exif']) {
    final FillingBar barJsonToExifExtractor = FillingBar(
      total: media.length,
      desc: '[Step 5/8] Getting EXIF data from JSONs and applying it to media',
      width: defaultBarWidth,
    );

    for (int i = 0; i < media.length; i++) {
      final File currentFile = media[i].firstFile;

      final DMSCoordinates? coords = await jsonCoordinatesExtractor(
        currentFile,
      );
      if (coords != null) {
        //If coordinates were found in json, write them to exif
        if (await writeGpsToExif(coords, currentFile)) {
          exifccounter++;
        }
      }
      if (media[i].dateTimeExtractionMethod !=
              DateTimeExtractionMethod
                  .exif && //Already got it through ExifExtractor
          media[i].dateTimeExtractionMethod != DateTimeExtractionMethod.none) {
        //Has no dateTime at all, so nothing to write.
        //If date was found before through any extractor, except through exif extractor (cause then it's already in exif, duh!) write it to exif
        if (await writeDateTimeToExif(media[i].dateTaken!, currentFile)) {
          exifdtcounter++;
        }
      }

      barJsonToExifExtractor.increment();
    }
  } else {
    print('[Step 5/8] Skipping writing data to EXIF.');
  }
  sw5.stop();
  print(
    '\n[Step 5/8] Step 5 took ${sw5.elapsed.inMinutes} minutes or ${sw5.elapsed.inSeconds} seconds to complete.',
  );

  /// ##############################################################
  /// ################# STEP 6 #####################################
  /// ##### Find albums and rename .MP and .MV extensions ##########

  // I'm placing merging duplicate Media into albums after guessing date for
  // each one individually, because they are in different folder.
  // I wish that, thanks to this, we may find some jsons in albums that would
  // be broken in shithole of big-ass year folders
  final Stopwatch sw6 = Stopwatch()
    ..start(); //Creation of our debugging stopwatch for each step.
  print('[Step 6/8] Finding albums (this may take a while)');
  findAlbums(media);

  /// ##############################################################

  // Change Pixel Motion Photos extension to .mp4 using a list of Medias.
  // This is done after the dates of files have been defined, and before
  // the files are moved to the output folder, to avoid shortcuts/symlinks problems
  if (args['transform-pixel-mp']) {
    print(
      '[Step 6/8] Changing .MP or .MV extensions to .mp4... (this may take some time)',
    );
    await changeMPExtensions(media, '.mp4');
  } else {
    print('\n[Step 6/8] Skipped changing .MP or .MV extensions to .mp4');
  }

  /// ##############################################################

  // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/261
  // If a media is not in a year album (there is no null key) it establishes
  // one from an album as a null key to copy it to ALL_PHOTOS correctly.
  // This will move the album file to ALL_PHOTOS and create the shortcut to
  // the output album folder (if shortcut option is selected).
  // (The inverse will happen if the inverse-shortcut option is selected).
  // If album mode is set to *duplicate-copy* it will not proceed
  // to avoid moving the same file twice (which would throw an exception)
  if (args['albums'] != 'duplicate-copy') {
    for (final Media m in media) {
      final File? fileWithKey1 = m.files[null];
      if (fileWithKey1 == null) {
        m.files[null] = m.files.values.first;
      }
    }
  }

  sw6.stop();
  print(
    '[Step 6/8] Step 6 took ${sw6.elapsed.inMinutes} minutes or ${sw6.elapsed.inSeconds} seconds to complete.',
  );

  /// ##############################################################
  /// ################# STEP 7 #####################################
  /// ##### Copy/move files to actual output folder ################
  final Stopwatch sw7 = Stopwatch()
    ..start(); //Creation of our debugging stopwatch for each step.
  final FillingBar barCopy = FillingBar(
    total: outputFileCount(media, args['albums']),
    desc:
        "[Step 7/8] ${args['copy'] ? 'Copying' : 'Moving'} media to output folder",
    width: defaultBarWidth,
  );
  await moveFiles(
    media,
    output,
    copy: args['copy'],
    divideToDates: args['divide-to-dates'] is num
        ? args['divide-to-dates']
        : num.parse(args['divide-to-dates']),
    albumBehavior: args['albums'],
  ).listen((final _) => barCopy.increment()).asFuture();
  print('\n[Step 7/8] Done moving/copying media!');

  // @Deprecated('Interactive unzipping is suspended for now!')
  // // remove unzipped folder if was created
  // if (interactive.indeed) {
  //   print('Removing unzipped folder...');
  //   await input.delete(recursive: true);
  // }
  sw7.stop();
  print(
    '[Step 7/8] Step 7 took ${sw7.elapsed.inMinutes} minutes or ${sw7.elapsed.inSeconds} seconds to complete.',
  );

  /// ##############################################################
  /// ################# STEP 8 #####################################
  /// ##### Update creation time (Windows only) ####################
  final Stopwatch sw8 = Stopwatch()
    ..start(); //Creation of our debugging stopwatch for each step.
  int updatedCreationTimeCounter = 0;
  if (args['update-creation-time']) {
    print(
      '[Step 8/8] Updating creation time of media files to match their modified time in output folder ...',
    );
    updatedCreationTimeCounter = await updateCreationTimeRecursively(output);
    print('');
    print('=' * defaultBarWidth);
  } else {
    print('[Step 8/8] Skipping: Updating creation time (Windows only)');
  }
  sw8.stop();
  log(
    '\n[Step 8/8] Step 6 took ${sw8.elapsed.inMinutes} minutes or ${sw8.elapsed.inSeconds} seconds to complete.',
  );

  // After all processing steps, before program exit we encode the emojis in album paths again.
  final outputDirs = output.listSync(recursive: true).whereType<Directory>();
  if (outputDirs.isNotEmpty) {
    final FillingBar barEmojiEncode = FillingBar(
      total: outputDirs.length,
      desc:
          '[Step 8/8] Looking for folders with emojis and renaming them back.',
      width: defaultBarWidth,
    );
    for (final dir in outputDirs) {
      final String decodedPath = decodeAndRestoreAlbumEmoji(dir.path);

      barEmojiEncode.increment();

      if (decodedPath != dir.path) {
        dir.renameSync(decodedPath);
      }
      barEmojiEncode.increment();
    }
  }

  /// ##############################################################
  /// ################# END ########################################
  /// Now just the last message of the program, just displaying some stats so you have an overview of what happened.
  /// Also helps with testing because you can run a diverse and large dataset with the same options through a new version and expect the same (or better) stats.
  /// If they got worse, you did smth wrong.
  print('');
  print('=' * defaultBarWidth);
  print('DONE! FREEEEEDOOOOM!!!');
  print('Some statistics for the achievement hunters:');
  //This check will print an error if no stats are available.
  if (countDuplicates > 0 &&
      updatedCreationTimeCounter > 0 &&
      exifccounter > 0 &&
      exifdtcounter > 0 &&
      args['skip-extras']) {
    print('Error! No stats available (This is weird!)');
  }
  if (updatedCreationTimeCounter > 0) {
    print('$updatedCreationTimeCounter files had their CreationDate updated');
  }
  if (countDuplicates > 0) {
    print('$countDuplicates duplicates were found and skipped');
  }
  if (exifccounter > 0) {
    print(
      '$exifccounter files got their coordinates set in EXIF data (from json)',
    );
  }
  if (exifdtcounter > 0) {
    print('$exifdtcounter got their DateTime set in EXIF data');
  }
  if (args['skip-extras']) print('$countExtras extras were skipped');

  // Print datetime extraction method statistics
  print('DateTime extraction method statistics:');
  for (final entry in extractionStats.entries) {
    final String extractionMethodString = entry.key.name.toString();
    print('$extractionMethodString: ${entry.value} files');
  }
  print(
    'In total the script took ${(sw1.elapsed + sw2.elapsed + sw3.elapsed + sw4.elapsed + sw5.elapsed + sw6.elapsed + sw7.elapsed + sw8.elapsed).inMinutes} minutes to complete',
  );
  print(
    "Last thing - I've spent *a ton* of time on this script - \n"
    'if I saved your time and you want to say thanks, you can send me a tip:\n'
    'https://www.paypal.me/TheLastGimbus\n'
    'https://ko-fi.com/thelastgimbus\n'
    'Thank you ❤',
  );
  print('=' * defaultBarWidth);
  quit(0);
}
