import 'dart:io';

import 'package:args/args.dart';
import 'package:console_bars/console_bars.dart';
import 'package:gpth/date_extractor.dart';
import 'package:gpth/extras.dart';
import 'package:gpth/folder_classify.dart';
import 'package:gpth/grouping.dart';
import 'package:gpth/interactive.dart' as interactive;
import 'package:gpth/media.dart';
import 'package:gpth/moving.dart';
import 'package:gpth/utils.dart';
import 'package:path/path.dart' as p;
import 'package:gpth/date_extractors/json_extractor.dart' as json_extractor;

const helpText = """GooglePhotosTakeoutHelper v$version - The Dart successor

gpth is ment to help you with exporting your photos from Google Photos.

First, go to https://takeout.google.com/ , deselect all and select only Photos.
When ready, download all .zips, and extract them into *one* folder.
(Auto-extracting works only in interactive mode)

Then, run: gpth --input "folder/with/all/takeouts" --output "your/output/folder"
...and gpth will parse and organize all photos into one big chronological folder
""";
const barWidth = 40;

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption(
      'fix',
      help: 'Folder with any photos to fix dates. '
          'This skips whole "GoogleTakeout" procedure.'
          'It is here because gpth has some cool heuristics to determine date '
          'of a photo, and this can be handy in many situations :)',
    )
    ..addFlag('interactive',
        help: 'Use interactive mode. Type this in case auto-detection fails, '
            'or you *really* want to combine advanced options with prompts')
    ..addOption('input',
        abbr: 'i', help: 'Input folder with *all* takeouts *extracted*. ')
    ..addOption('output',
        abbr: 'o', help: 'Output folder where all photos will land')
    ..addOption(
      'albums',
      help: 'What to do about albums?',
      allowed: interactive.albumOptions.keys,
      allowedHelp: interactive.albumOptions,
      defaultsTo: 'shortcut',
    )
    ..addFlag('divide-to-dates', help: 'Divide output to folders by year/month')
    ..addFlag('skip-extras', help: 'Skip extra images (like -edited etc)')
    ..addFlag(
      'guess-from-name',
      help: 'Try to guess file dates from their names',
      defaultsTo: true,
    )
    ..addFlag(
      'copy',
      help: "Copy files instead of moving them.\n"
          "This is usually slower, and uses extra space, "
          "but doesn't break your input folder",
    );
  final args = <String, dynamic>{};
  try {
    final res = parser.parse(arguments);
    for (final key in res.options) {
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

  if (interactive.indeed) {
    // greet user
    await interactive.greet();
    print('');
    // ask for everything
    // @Deprecated('Interactive unzipping is suspended for now!')
    // final zips = await interactive.getZips();
    late Directory inDir;
    try {
      inDir = await interactive.getInputDir();
    } catch (e) {
      print("Hmm, interactive selecting input dir crashed... \n"
          "it looks like you're running in headless/on Synology/NAS...\n"
          "If so, you have to use cli options - run 'gpth --help' to see them");
      exit(69);
    }
    print('');
    final out = await interactive.getOutput();
    print('');
    args['divide-to-dates'] = await interactive.askDivideDates();
    print('');
    args['albums'] = await interactive.askAlbums();
    print('');

    args['input'] = inDir.path;
    args['output'] = out.path;
  }

  // elastic list of extractors - can add/remove with cli flags
  // those are in order of reliability -
  // if one fails, only then later ones will be used
  final dateExtractors = <DateTimeExtractor>[
    jsonExtractor,
    exifExtractor,
    if (args['guess-from-name']) guessExtractor,
    // this is potentially *dangerous* - see:
    // https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/issues/175
    (f) => jsonExtractor(f, tryhard: true),
  ];

  /// ##### Occasional Fix mode #####

  if (args['fix'] != null) {
    print('========== FIX MODE ==========');
    print('I will go through all files in folder that you gave me');
    print('and try to set each file to correct lastModified value');
    final dir = Directory(args['fix']);
    if (!await dir.exists()) {
      error("directory to fix doesn't exist :/");
      quit(11);
    }
    var set = 0;
    var notSet = 0;
    await for (final file in dir.list(recursive: true).wherePhotoVideo()) {
      DateTime? date;
      for (final extractor in dateExtractors) {
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

  /// ###############################

  /// ##### Parse all options and check if alright #####

  if (args['input'] == null) {
    error("No --input folder specified :/");
    quit(10);
  }
  if (args['output'] == null) {
    error("No --output folder specified :/");
    quit(10);
  }
  final input = Directory(args['input']);
  final output = Directory(args['output']);
  if (!await input.exists()) {
    error("Input folder does not exist :/");
    quit(11);
  }
  if (await output.exists() &&
      !await output
          .list()
          .where((e) => p.absolute(e.path) != p.absolute(args['input']))
          .isEmpty) {
    if (await interactive.askForCleanOutput()) {
      await for (final file in output
          .list()
          .where((e) => p.absolute(e.path) != p.absolute(args['input']))) {
        await file.delete(recursive: true);
      }
    }
  }
  await output.create(recursive: true);

  /// ##################################################

  /// Big global media list that we'll work on
  final media = <Media>[];

  /// All "year folders" that we found
  final yearFolders = <Directory>[];

  /// All album folders - that is, folders that were aside yearFolders and were
  /// not matching "Photos from ...." name
  final albumFolders = <Directory>[];

  /// ##### Find literally *all* photos/videos and add to list #####

  print('Okay, running... searching for everything in input folder...');

  await for (final d in input.list(recursive: true).whereType<Directory>()) {
    if (isYearFolder(d)) {
      yearFolders.add(d);
    } else if (await isAlbumFolder(d)) {
      albumFolders.add(d);
    }
  }
  for (final f in yearFolders) {
    await for (final file in f.list().wherePhotoVideo()) {
      media.add(Media({null: file}));
    }
  }
  for (final a in albumFolders) {
    await for (final file in a.list().wherePhotoVideo()) {
      media.add(Media({albumName(a): file}));
    }
  }

  if (media.isEmpty) {
    await interactive.nothingFoundMessage();
    quit(13);
  }

  /// NEW STEP: Detect partner-shared photos
  print('Detecting partner-shared photos...');
  final barPartner = FillingBar(
    total: media.length,
    desc: "Checking sharing source",
    width: barWidth,
  );
  for (final m in media) {
    m.isPartnerShared = await json_extractor.isPartnerShared(m.firstFile, tryhard: true);
    barPartner.increment();
  }
  print('');

  /// ##### Find duplicates #####

  print('Finding duplicates...');
  final countDuplicates = removeDuplicates(media);

  /// ###########################

  /// ##### Potentially skip extras #####

  if (args['skip-extras']) print('Finding "extra" photos (-edited etc)');
  final countExtras = args['skip-extras'] ? removeExtras(media) : 0;

  /// ###################################

  /// ##### Extracting/predicting dates using given extractors #####

  final barExtract = FillingBar(
    total: media.length,
    desc: "Guessing dates from files",
    width: barWidth,
  );
  for (var i = 0; i < media.length; i++) {
    var q = 0;
    for (final extractor in dateExtractors) {
      final date = await extractor(media[i].firstFile);
      if (date != null) {
        media[i].dateTaken = date;
        media[i].dateTakenAccuracy = q;
        barExtract.increment();
        break;
      }
      q++;
    }
    if (media[i].dateTaken == null) {
      print("\nCan't get date on ${media[i].firstFile.path}");
    }
  }
  print('');

  /// ##############################################################

  /// ##### Find albums #####

  print('Finding albums (this may take some time, dont worry :) ...');
  findAlbums(media);

  /// #######################

  /// ##### Copy/move files to actual output folder #####

  final barCopy = FillingBar(
    total: outputFileCount(media, args['albums']),
    desc: "${args['copy'] ? 'Coping' : 'Moving'} photos to output folder",
    width: barWidth,
  );
  await moveFiles(
    media,
    output,
    copy: args['copy'],
    divideToDates: args['divide-to-dates'],
    albumBehavior: args['albums'],
  ).listen((_) => barCopy.increment()).asFuture();
  print('');

  print('=' * barWidth);
  print('DONE! FREEEEEDOOOOM!!!');
  if (countDuplicates > 0) print('Skipped $countDuplicates duplicates');
  if (args['skip-extras']) print('Skipped $countExtras extras');
  final countPoop = media.where((e) => e.dateTaken == null).length;
  if (countPoop > 0) {
    print("Couldn't find date for $countPoop photos/videos :/");
  }
  print('');
  print(
    "Last thing - I've spent *a ton* of time on this script - \n"
    "if I saved your time and you want to say thanks, you can send me a tip:\n"
    "https://www.paypal.me/TheLastGimbus\n"
    "https://ko-fi.com/thelastgimbus\n"
    "Thank you ❤",
  );
  print('=' * barWidth);
  quit(0);
}
