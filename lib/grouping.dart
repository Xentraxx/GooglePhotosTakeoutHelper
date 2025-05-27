/// This files contains functions for removing duplicates and detecting albums
///
/// That's because their logic looks very similar and they share code
library;

import 'dart:io';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'media.dart' show Media;
import 'media.dart';
import 'utils.dart';

extension Group on Iterable<Media> {
  /// This groups your media into map where key is something that they share
  /// and value is the List of those media are the same
  ///
  /// Key may be "245820998bytes", where there was no other file same size
  /// (no need to calculate hash), or hash.toSting'ed where hash was calculated
  ///
  /// Groups may be 1-lenght, where element was unique, or n-lenght where there
  /// were duplicates
  Map<String, List<Media>> groupIdentical() {
    final Map<String, List<Media>> output = <String, List<Media>>{};
    // group files by size - can't have same hash with diff size
    // ignore: unnecessary_this
    for (final MapEntry<int, List<Media>> sameSize in groupListsBy(
      (final Media e) => e.size,
    ).entries) {
      // just add with "...bytes" key if just one
      if (sameSize.value.length <= 1) {
        output['${sameSize.key}bytes'] = sameSize.value;
      } else {
        // ...calculate their full hashes and group by them
        output.addAll(
          sameSize.value.groupListsBy((final Media e) => e.hash.toString()),
        );
      }
    }
    return output;
  }
}

/// Removes duplicate media from list of media
///
/// This is meant to be used *early*, and it's aware of un-merged albums.
/// Meaning, it will leave duplicated files if they have different
/// [Media.albums] value
///
/// Uses file size, then sha256 hash to distinct
///
/// Returns count of removed
int removeDuplicates(final List<Media> media) {
  int count = 0;

  final Iterable<Iterable<List<Media>>> byAlbum = media
      // group by albums as we will merge those later
      // (to *not* compare hashes between albums)
      .groupListsBy((final Media e) => e.files.keys.first)
      .values
      // group by hash
      .map(
        (final List<Media> albumGroup) => albumGroup.groupIdentical().values,
      );
  // we don't care about album organization now - flatten
  final Iterable<List<Media>> hashGroups = byAlbum.flattened;

  for (final List<Media> group in hashGroups) {
    // sort by best date extraction, then file name length
    // using strings to sort by two values is a sneaky trick i learned at
    // https://stackoverflow.com/questions/55920677/how-to-sort-a-list-based-on-two-values

    // note: we are comparing accuracy here tho we do know that *all*
    // of them have it null - i'm leaving this just for sake
    group.sort(
      (
        final Media a,
        final Media b,
      ) => '${a.dateTakenAccuracy ?? 999}${p.basename(a.firstFile.path).length}'
          .compareTo(
            '${b.dateTakenAccuracy ?? 999}${p.basename(b.firstFile.path).length}',
          ),
    );
    // get list of all except first
    for (final Media e in group.sublist(1)) {
      // remove them from media
      media.remove(e);
      log('[Step 3/8] Skipping duplicate: ${e.firstFile.path}');
      count++;
    }
  }
  return count;
}

String albumName(final Directory albumDir) =>
    p.basename(p.normalize(albumDir.path));

/// This will analyze [allMedia], find which files are hash-same, and merge
/// all of them into single [Media] object with all album names they had
void findAlbums(final List<Media> allMedia) {
  for (final List<Media> group in allMedia.groupIdentical().values) {
    if (group.length <= 1) continue; // then this isn't a group
    // now, we have [group] list that contains actual sauce:

    final Map<String?, File> allFiles = group.fold(
      <String?, File>{},
      (final Map<String?, File> allFiles, final Media e) =>
          allFiles..addAll(e.files),
    );
    // sort by best date extraction
    group.sort(
      (final Media a, final Media b) =>
          (a.dateTakenAccuracy ?? 999).compareTo(b.dateTakenAccuracy ?? 999),
    );
    // remove original dirty ones
    allMedia.removeWhere(group.contains);
    // set the first (best) one complete album list
    group.first.files = allFiles;
    // add our one, precious ✨perfect✨ one
    allMedia.add(group.first);
  }
}
