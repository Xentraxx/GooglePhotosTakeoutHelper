// ignore_for_file: unintended_html_in_doc_comment

import 'dart:convert';
import 'dart:io';
import 'package:gpth/gpth_lib_exports.dart';
import 'package:path/path.dart' as path;

/// Ignore-Albums strategy:
/// - Move only CANONICAL files (primary + secondaries that are canonical) to ALL_PHOTOS (date-structured if needed).
/// - Delete all NON-CANONICAL files from source (they will not appear in Output in any form).
/// - After each operation: update fe.targetPath (for moved), fe.isShortcut=false, fe.isMoved=true on moves,
///   and fe.isDeleted=true on deletions.
/// - Uses a snapshot of primary and secondaries to avoid in-loop modifications side effects.
class IgnoreAlbumsMovingStrategy extends MoveMediaEntityStrategy {
  const IgnoreAlbumsMovingStrategy(this._fileService, this._pathService);

  final FileOperationService _fileService;
  final PathGeneratorService _pathService;

  @override
  String get name => 'Ignore Albums';

  @override
  bool get createsShortcuts => false;

  @override
  bool get createsDuplicates => false;

  @override
  Stream<MoveMediaEntityResult> processMediaEntity(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
    final Directory allPhotosDir = MovingStrategyUtils.allPhotosDir(
      _pathService,
      entity,
      context,
    );

    // Snapshot of the files to respect the "immutable getters" idea
    final List<FileEntity> files = <FileEntity>[
      entity.primaryFile,
      ...entity.secondaryFiles,
    ];

    // Common special folders handling (moved to utils): move to output/Special Folders and exclude from further logic
    final (
      Set<FileEntity> specialHandled,
      List<MoveMediaEntityResult> sfResults,
    ) = await MovingStrategyUtils.handleSpecialFoldersForEntity(
      _fileService,
      context,
      entity,
    );
    for (final r in sfResults) {
      yield r;
    }

    for (final fe in files) {
      if (specialHandled.contains(fe)) {
        continue; // skip already handled as Special Folder
      }
      if (fe.isCanonical == true) {
        final sw = Stopwatch()..start();
        final File src = fe.asFile();
        try {
          final moved = await _fileService.moveFile(
            src,
            allPhotosDir,
            dateTaken: entity.dateTaken,
          );
          sw.stop();

          fe.targetPath = moved.path;
          fe.isShortcut = false;
          fe.isMoved = true;

          yield MoveMediaEntityResult.success(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: allPhotosDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
            ),
            resultFile: moved,
            duration: sw.elapsed,
          );
        } catch (e) {
          final elapsed = sw.elapsed;
          yield MoveMediaEntityResult.failure(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: allPhotosDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
            ),
            errorMessage: 'Failed to move canonical file: $e',
            duration: elapsed,
          );
        }
      } else {
        // Non-canonical → delete from source
        final dsw = Stopwatch()..start();
        final File src = fe.asFile();
        try {
          // If you have a delete method on _fileService, replace with that.
          await src.delete();
          dsw.stop();

          fe.isDeleted = true;
          fe.isShortcut = false;
          fe.targetPath = null;

          yield MoveMediaEntityResult.success(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: Directory(MovingStrategyUtils.dirOf(src.path)),
              operationType: MediaEntityOperationType.delete,
              mediaEntity: entity,
            ),
            resultFile: src,
            duration: dsw.elapsed,
          );
        } catch (e) {
          final elapsed = dsw.elapsed;
          yield MoveMediaEntityResult.failure(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: Directory(MovingStrategyUtils.dirOf(src.path)),
              operationType: MediaEntityOperationType.delete,
              mediaEntity: entity,
            ),
            errorMessage: 'Failed to delete non-canonical file: $e',
            duration: elapsed,
          );
        }
      }
    }
  }

  @override
  void validateContext(final MovingContext context) {}
}

/// Nothing strategy:
/// - Move **primary** to ALL_PHOTOS (date-structured if needed).
/// - Delete **all secondaries** from source (they will not appear in Output).
/// - After each operation: update fe.targetPath and flags (isShortcut=false; isMoved=true for moved; isDeleted=true for deleted).
class NothingMovingStrategy extends MoveMediaEntityStrategy {
  const NothingMovingStrategy(this._fileService, this._pathService);

  final FileOperationService _fileService;
  final PathGeneratorService _pathService;

  @override
  String get name => 'Nothing';

  @override
  bool get createsShortcuts => false;

  @override
  bool get createsDuplicates => false;

  @override
  Stream<MoveMediaEntityResult> processMediaEntity(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
    final Directory allPhotosDir = MovingStrategyUtils.allPhotosDir(
      _pathService,
      entity,
      context,
    );

    // Snapshot to avoid in-loop mutations
    final FileEntity primary = entity.primaryFile;
    final List<FileEntity> secondaries = <FileEntity>[...entity.secondaryFiles];

    // Common special folders handling: move to Special Folders and exclude from further logic
    final (
      Set<FileEntity> specialHandled,
      List<MoveMediaEntityResult> sfResults,
    ) = await MovingStrategyUtils.handleSpecialFoldersForEntity(
      _fileService,
      context,
      entity,
    );
    for (final r in sfResults) {
      yield r;
    }

    // Move primary
    if (!specialHandled.contains(primary)) {
      {
        final sw = Stopwatch()..start();
        final File src = primary.asFile();
        try {
          final moved = await _fileService.moveFile(
            src,
            allPhotosDir,
            dateTaken: entity.dateTaken,
          );
          sw.stop();

          primary.targetPath = moved.path;
          primary.isShortcut = false;
          primary.isMoved = true;

          yield MoveMediaEntityResult.success(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: allPhotosDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
            ),
            resultFile: moved,
            duration: sw.elapsed,
          );
        } catch (e) {
          final elapsed = sw.elapsed;
          yield MoveMediaEntityResult.failure(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: allPhotosDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
            ),
            errorMessage: 'Failed to move primary: $e',
            duration: elapsed,
          );
        }
      }
    }

    // Delete all secondaries
    for (final sec in secondaries) {
      if (specialHandled.contains(sec)) {
        continue; // skip already moved to Special Folders
      }
      final dsw = Stopwatch()..start();
      final File src = sec.asFile();
      try {
        await src.delete();
        dsw.stop();

        sec.isDeleted = true;
        sec.isShortcut = false;
        sec.targetPath = null;

        yield MoveMediaEntityResult.success(
          operation: MoveMediaEntityOperation(
            sourceFile: src,
            targetDirectory: Directory(MovingStrategyUtils.dirOf(src.path)),
            operationType: MediaEntityOperationType.delete,
            mediaEntity: entity,
          ),
          resultFile: src,
          duration: dsw.elapsed,
        );
      } catch (e) {
        final elapsed = dsw.elapsed;
        yield MoveMediaEntityResult.failure(
          operation: MoveMediaEntityOperation(
            sourceFile: src,
            targetDirectory: Directory(MovingStrategyUtils.dirOf(src.path)),
            operationType: MediaEntityOperationType.delete,
            mediaEntity: entity,
          ),
          errorMessage: 'Failed to delete secondary: $e',
          duration: elapsed,
        );
      }
    }
  }

  @override
  void validateContext(final MovingContext context) {}
}

/// JSON strategy:
/// - Move **primary** to ALL_PHOTOS.
/// - For each album:
///   - If the primary was originally NON-CANONICAL and belonged to that album, add a JSON entry for it.
///   - For each NON-CANONICAL secondary that belonged to that album, add a JSON entry.
/// - After JSON recording:
///   - Delete **all secondaries** from source (CANONICAL secondaries are deleted without JSON entry).
/// - JSON fields (all relative paths use forward slashes):
///   {
///     "albums": {
///       "<albumName>": [
///         {
///           "albumName": "<album>",
///           "albumPath": "Albums/<Album>",                 // relative to output
///           "fileName": "<originalBaseName>",
///           "filePath": "Albums/<Album>/<originalBase>",   // relative to output (intended album path for original name)
///           "targetPath": "All Photos/.../<movedPrimary>"  // relative to output, final target of moved primary
///         },
///         ...
///       ]
///     },
///     "metadata": { ... }
///   }
class JsonMovingStrategy extends MoveMediaEntityStrategy {
  JsonMovingStrategy(this._fileService, this._pathService);

  final FileOperationService _fileService;
  final PathGeneratorService _pathService;

  // albumName -> list of entries
  final Map<String, List<Map<String, String>>> _albumInfo = {};

  @override
  String get name => 'JSON';

  @override
  bool get createsShortcuts => false;

  @override
  bool get createsDuplicates => false;

  @override
  Stream<MoveMediaEntityResult> processMediaEntity(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
    final Directory outDir = context.outputDirectory;
    final Directory allPhotosDir = MovingStrategyUtils.allPhotosDir(
      _pathService,
      entity,
      context,
    );

    // Snapshot
    final FileEntity primary = entity.primaryFile;
    final List<FileEntity> secondaries = <FileEntity>[...entity.secondaryFiles];

    final bool primaryWasCanonical = primary.isCanonical == true;

    // Common special folders handling: move to Special Folders and exclude from JSON logic
    final (
      Set<FileEntity> specialHandled,
      List<MoveMediaEntityResult> sfResults,
    ) = await MovingStrategyUtils.handleSpecialFoldersForEntity(
      _fileService,
      context,
      entity,
    );
    for (final r in sfResults) {
      yield r;
    }

    // Move primary to ALL_PHOTOS
    if (!specialHandled.contains(primary)) {
      final sw = Stopwatch()..start();
      final File src = primary.asFile();
      File movedPrimary;
      try {
        movedPrimary = await _fileService.moveFile(
          src,
          allPhotosDir,
          dateTaken: entity.dateTaken,
        );
        sw.stop();

        primary.targetPath = movedPrimary.path;
        primary.isShortcut = false;
        primary.isMoved = true;

        yield MoveMediaEntityResult.success(
          operation: MoveMediaEntityOperation(
            sourceFile: src,
            targetDirectory: allPhotosDir,
            operationType: MediaEntityOperationType.move,
            mediaEntity: entity,
          ),
          resultFile: movedPrimary,
          duration: sw.elapsed,
        );
      } catch (e) {
        final elapsed = sw.elapsed;
        yield MoveMediaEntityResult.failure(
          operation: MoveMediaEntityOperation(
            sourceFile: src,
            targetDirectory: allPhotosDir,
            operationType: MediaEntityOperationType.move,
            mediaEntity: entity,
          ),
          errorMessage: 'Failed to move primary: $e',
          duration: elapsed,
        );
        return;
      }

      final String primaryRel = path
          .relative(movedPrimary.path, from: outDir.path)
          .replaceAll('\\', '/');

      // Build JSON entries per album
      for (final albumName in entity.albumNames) {
        final Directory albumDir =
            MovingStrategyUtils.albumDirConsideringUntitled(
              _pathService,
              albumName,
              entity,
              context,
            );
        final String albumRel = path
            .relative(albumDir.path, from: outDir.path)
            .replaceAll('\\', '/');

        // Primary entry if it was originally non-canonical and belonged to this album
        if (!primaryWasCanonical &&
            MovingStrategyUtils.fileBelongsToAlbum(
              entity,
              primary,
              albumName,
            )) {
          final String originalBase = path.basename(primary.sourcePath);
          final String albumPathWithFile = '$albumRel/$originalBase';
          (_albumInfo[albumName] ??= <Map<String, String>>[]).add({
            'albumName': albumName,
            'albumPath': albumRel,
            'fileName': originalBase,
            'filePath': albumPathWithFile,
            'targetPath': primaryRel,
          });
        }

        // Secondary entries: only NON-CANONICAL that belonged to this album
        for (final sec in secondaries) {
          if (specialHandled.contains(sec)) {
            continue; // do not include Special Folder files
          }
          if (sec.isCanonical == true) continue;
          if (!MovingStrategyUtils.fileBelongsToAlbum(entity, sec, albumName)) {
            continue;
          }
          final String secBase = path.basename(sec.sourcePath);
          final String albumPathWithFile = '$albumRel/$secBase';
          (_albumInfo[albumName] ??= <Map<String, String>>[]).add({
            'albumName': albumName,
            'albumPath': albumRel,
            'fileName': secBase,
            'filePath': albumPathWithFile,
            'targetPath': primaryRel,
          });
        }
      }
    }

    // Delete all secondaries from source (CANONICAL: no JSON entry; NON-CANONICAL: entry already recorded above)
    for (final sec in secondaries) {
      if (specialHandled.contains(sec)) {
        continue; // already moved to Special Folders
      }
      final dsw = Stopwatch()..start();
      final File srcSec = sec.asFile();
      try {
        await srcSec.delete();
        dsw.stop();

        sec.isDeleted = true;
        sec.isShortcut = false;
        sec.targetPath = null;

        yield MoveMediaEntityResult.success(
          operation: MoveMediaEntityOperation(
            sourceFile: srcSec,
            targetDirectory: Directory(MovingStrategyUtils.dirOf(srcSec.path)),
            operationType: MediaEntityOperationType.delete,
            mediaEntity: entity,
          ),
          resultFile: srcSec,
          duration: dsw.elapsed,
        );
      } catch (e) {
        final elapsed = dsw.elapsed;
        yield MoveMediaEntityResult.failure(
          operation: MoveMediaEntityOperation(
            sourceFile: srcSec,
            targetDirectory: Directory(MovingStrategyUtils.dirOf(srcSec.path)),
            operationType: MediaEntityOperationType.delete,
            mediaEntity: entity,
          ),
          errorMessage: 'Failed to delete secondary after JSON: $e',
          duration: elapsed,
        );
      }
    }
  }

  @override
  Future<List<MoveMediaEntityResult>> finalize(
    final MovingContext context,
    final List<MediaEntity> processedEntities,
  ) async {
    final String jsonPath = _pathService.generateAlbumsInfoJsonPath(
      context.outputDirectory,
    );
    final File jsonFile = File(jsonPath);

    final sw = Stopwatch()..start();
    try {
      final payload = {
        'albums': _albumInfo,
        'metadata': {
          'generated': DateTime.now().toIso8601String(),
          'total_albums': _albumInfo.length,
          'total_entities': processedEntities.length,
          'strategy': 'json',
        },
      };
      await jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      sw.stop();

      if (processedEntities.isEmpty) return const <MoveMediaEntityResult>[];

      return [
        MoveMediaEntityResult.success(
          operation: MoveMediaEntityOperation(
            sourceFile: jsonFile,
            targetDirectory: context.outputDirectory,
            operationType: MediaEntityOperationType.createJsonReference,
            mediaEntity: processedEntities.first,
          ),
          resultFile: jsonFile,
          duration: sw.elapsed,
        ),
      ];
    } catch (e) {
      sw.stop();
      if (processedEntities.isEmpty) return const <MoveMediaEntityResult>[];
      return [
        MoveMediaEntityResult.failure(
          operation: MoveMediaEntityOperation(
            sourceFile: jsonFile,
            targetDirectory: context.outputDirectory,
            operationType: MediaEntityOperationType.createJsonReference,
            mediaEntity: processedEntities.first,
          ),
          errorMessage: 'Failed to create albums-info.json: $e',
          duration: sw.elapsed,
        ),
      ];
    }
  }

  @override
  void validateContext(final MovingContext context) {}
}

/// Shortcut strategy:
/// - Choose the file to move to ALL_PHOTOS:
///   - If there is any CANONICAL among primary+secondaries, choose the best-ranked CANONICAL.
///   - Otherwise, use the current primary.
/// - Move the chosen file to ALL_PHOTOS.
/// - For each album:
///   - If primary (originally NON-CANONICAL) belonged to it → create shortcut named with original primary basename.
///   - For each NON-CANONICAL secondary that belonged to it → create shortcut named with its original basename.
///   - After creating a shortcut that represents a NON-CANONICAL source file, delete the original source
///     (the representation in Output is the link), and mark that FileEntity or its synthetic clone accordingly.
/// - Flags:
///   - Moved file: isMoved=true, isShortcut=false.
///   - For represented NON-CANONICAL files by a shortcut: original deleted → isDeleted=true; shortcut entries use isShortcut=true.
class ShortcutMovingStrategy extends MoveMediaEntityStrategy {
  const ShortcutMovingStrategy(
    this._fileService,
    this._pathService,
    this._symlinkService,
  );

  final FileOperationService _fileService;
  final PathGeneratorService _pathService;
  final SymlinkService _symlinkService;

  @override
  String get name => 'Shortcut';

  @override
  bool get createsShortcuts => true;

  @override
  bool get createsDuplicates => false;

  @override
  Stream<MoveMediaEntityResult> processMediaEntity(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
    // Snapshot
    final FileEntity primary = entity.primaryFile;
    final List<FileEntity> secondaries = <FileEntity>[...entity.secondaryFiles];
    final List<FileEntity> allFiles = <FileEntity>[primary, ...secondaries];

    // Snapshot flag: primary canonicity BEFORE any move
    final bool primaryWasCanonical = primary.isCanonical == true;

    // Common special folders handling: move to Special Folders and exclude from shortcut logic
    final (
      Set<FileEntity> specialHandled,
      List<MoveMediaEntityResult> sfResults,
    ) = await MovingStrategyUtils.handleSpecialFoldersForEntity(
      _fileService,
      context,
      entity,
    );
    for (final r in sfResults) {
      yield r;
    }

    // Decide which file to move to ALL_PHOTOS (prefer best canonical if exists)
    final List<FileEntity> canonicals = allFiles
        .where(
          (final f) => f.isCanonical == true && !specialHandled.contains(f),
        )
        .toList();
    final FileEntity chosen = canonicals.isNotEmpty
        ? _chooseBestRanked(canonicals)
        : primary;

    // Move chosen file to ALL_PHOTOS
    if (!specialHandled.contains(chosen)) {
      final Directory allPhotosDir = MovingStrategyUtils.allPhotosDir(
        _pathService,
        entity,
        context,
      );

      final sw = Stopwatch()..start();
      final File src = chosen.asFile();
      File movedPrimary;
      try {
        movedPrimary = await _fileService.moveFile(
          src,
          allPhotosDir,
          dateTaken: entity.dateTaken,
        );
        sw.stop();

        chosen.targetPath = movedPrimary.path;
        chosen.isShortcut = false;
        chosen.isMoved = true;

        yield MoveMediaEntityResult.success(
          operation: MoveMediaEntityOperation(
            sourceFile: src,
            targetDirectory: allPhotosDir,
            operationType: MediaEntityOperationType.move,
            mediaEntity: entity,
          ),
          resultFile: movedPrimary,
          duration: sw.elapsed,
        );
      } catch (e) {
        final elapsed = sw.elapsed;
        yield MoveMediaEntityResult.failure(
          operation: MoveMediaEntityOperation(
            sourceFile: src,
            targetDirectory: allPhotosDir,
            operationType: MediaEntityOperationType.move,
            mediaEntity: entity,
          ),
          errorMessage: 'Failed to move primary file: $e',
          duration: elapsed,
        );
        return;
      }

      // Collect synthetic shortcut secondaries after loops
      final List<FileEntity> pendingShortcutSecondaries = <FileEntity>[];

      // Per-entity, per-album registry of basenames already materialized as shortcuts
      // This avoids creating "(1)" when multiple originals share the same name.
      final Map<String, Set<String>> usedBasenamesPerAlbum =
          <String, Set<String>>{};

      // Iterate unique album names to avoid duplicate passes on the same album
      for (final albumName in {...entity.albumNames}) {
        final Directory albumDir =
            MovingStrategyUtils.albumDirConsideringUntitled(
              _pathService,
              albumName,
              entity,
              context,
            );
        final Set<String> usedHere = usedBasenamesPerAlbum.putIfAbsent(
          albumName,
          () => <String>{},
        );

        // Helper to reuse existing shortcut if a basename already exists in this album
        Future<File?> reuseIfExists(final String desiredName) async {
          final String candidate = path.join(albumDir.path, desiredName);
          // Reuse if something already exists with this name (file/link/dir), or we already created it in this entity.
          if (usedHere.contains(desiredName) ||
              MovingStrategyUtils._existsAny(candidate)) {
            return File(candidate);
          }
          return null;
        }

        // Primary shortcut if originally non-canonical and belonged to this album
        if (!primaryWasCanonical &&
            !specialHandled.contains(primary) &&
            MovingStrategyUtils.fileBelongsToAlbum(
              entity,
              primary,
              albumName,
            )) {
          final String desiredName = path.basename(primary.sourcePath);
          final ssw = Stopwatch()..start();
          try {
            // 1) Try reuse if the same basename already exists in album
            final File? existing = await reuseIfExists(desiredName);
            if (existing != null) {
              ssw.stop();

              // Represent primary's original using the already-present shortcut
              pendingShortcutSecondaries.add(
                _buildShortcutClone(primary, existing.path),
              );

              // Delete the original NON-CANONICAL primary source
              try {
                await File(primary.sourcePath).delete();
                primary.isDeleted = true;
              } catch (_) {}

              // Mark basename as used for this entity/album
              usedHere.add(desiredName);

              yield MoveMediaEntityResult.success(
                operation: MoveMediaEntityOperation(
                  sourceFile: movedPrimary,
                  targetDirectory: albumDir,
                  operationType: MediaEntityOperationType.createSymlink,
                  mediaEntity: entity,
                  albumKey: albumName,
                ),
                resultFile: existing,
                duration: ssw.elapsed,
              );
            } else {
              // 2) Create the symlink and try to rename to desiredName (will ensure uniqueness on disk)
              final File shortcut =
                  await MovingStrategyUtils.createSymlinkWithPreferredName(
                    _symlinkService,
                    albumDir,
                    movedPrimary,
                    desiredName,
                  );
              ssw.stop();

              pendingShortcutSecondaries.add(
                _buildShortcutClone(primary, shortcut.path),
              );

              // Delete the original NON-CANONICAL primary source
              try {
                await File(primary.sourcePath).delete();
                primary.isDeleted = true;
              } catch (_) {}

              // Record the basename actually used (after rename)
              usedHere.add(path.basename(shortcut.path));

              yield MoveMediaEntityResult.success(
                operation: MoveMediaEntityOperation(
                  sourceFile: movedPrimary,
                  targetDirectory: albumDir,
                  operationType: MediaEntityOperationType.createSymlink,
                  mediaEntity: entity,
                  albumKey: albumName,
                ),
                resultFile: shortcut,
                duration: ssw.elapsed,
              );
            }
          } catch (e) {
            final elapsed = ssw.elapsed;
            yield MoveMediaEntityResult.failure(
              operation: MoveMediaEntityOperation(
                sourceFile: movedPrimary,
                targetDirectory: albumDir,
                operationType: MediaEntityOperationType.createSymlink,
                mediaEntity: entity,
                albumKey: albumName,
              ),
              errorMessage:
                  'Failed to create album shortcut for non-canonical primary: $e',
              duration: elapsed,
            );
          }
        }

        // Shortcuts for NON-CANONICAL secondaries that belonged to this album
        for (final sec in secondaries) {
          if (specialHandled.contains(sec)) continue; // skip Special Folders
          if (sec.isCanonical == true) continue;
          if (!MovingStrategyUtils.fileBelongsToAlbum(entity, sec, albumName)) {
            continue;
          }
          final String desiredName = path.basename(sec.sourcePath);
          final ssw = Stopwatch()..start();
          try {
            // First, reuse if an identical basename already exists here
            final File? existing = await reuseIfExists(desiredName);
            if (existing != null) {
              ssw.stop();

              if (sec.targetPath == null) {
                sec.targetPath = existing.path;
                sec.isShortcut = true;
              } else {
                pendingShortcutSecondaries.add(
                  _buildShortcutClone(sec, existing.path),
                );
              }

              // Delete the original NON-CANONICAL secondary source
              try {
                await File(sec.sourcePath).delete();
                sec.isDeleted = true;
              } catch (_) {}

              usedHere.add(desiredName);

              yield MoveMediaEntityResult.success(
                operation: MoveMediaEntityOperation(
                  sourceFile: movedPrimary,
                  targetDirectory: albumDir,
                  operationType: MediaEntityOperationType.createSymlink,
                  mediaEntity: entity,
                  albumKey: albumName,
                ),
                resultFile: existing,
                duration: ssw.elapsed,
              );
            } else {
              // Otherwise, create a new symlink with the preferred name
              final File shortcut =
                  await MovingStrategyUtils.createSymlinkWithPreferredName(
                    _symlinkService,
                    albumDir,
                    movedPrimary,
                    desiredName,
                  );
              ssw.stop();

              if (sec.targetPath == null) {
                sec.targetPath = shortcut.path;
                sec.isShortcut = true;
              } else {
                pendingShortcutSecondaries.add(
                  _buildShortcutClone(sec, shortcut.path),
                );
              }

              // Delete the original NON-CANONICAL secondary source
              try {
                await File(sec.sourcePath).delete();
                sec.isDeleted = true;
              } catch (_) {}

              usedHere.add(path.basename(shortcut.path));

              yield MoveMediaEntityResult.success(
                operation: MoveMediaEntityOperation(
                  sourceFile: movedPrimary,
                  targetDirectory: albumDir,
                  operationType: MediaEntityOperationType.createSymlink,
                  mediaEntity: entity,
                  albumKey: albumName,
                ),
                resultFile: shortcut,
                duration: ssw.elapsed,
              );
            }
          } catch (e) {
            final elapsed = ssw.elapsed;
            yield MoveMediaEntityResult.failure(
              operation: MoveMediaEntityOperation(
                sourceFile: movedPrimary,
                targetDirectory: albumDir,
                operationType: MediaEntityOperationType.createSymlink,
                mediaEntity: entity,
                albumKey: albumName,
              ),
              errorMessage: 'Failed to create secondary shortcut: $e',
              duration: elapsed,
            );
          }
        }
      }

      if (pendingShortcutSecondaries.isNotEmpty) {
        entity.secondaryFiles.addAll(pendingShortcutSecondaries);
      }
    }
  }

  @override
  void validateContext(final MovingContext context) {}

  FileEntity _buildShortcutClone(
    final FileEntity src,
    final String shortcutPath,
  ) => FileEntity(
    sourcePath: src.sourcePath,
    targetPath: shortcutPath,
    isShortcut: true,
    dateAccuracy: src.dateAccuracy,
    ranking: src.ranking,
  );

  FileEntity _chooseBestRanked(final List<FileEntity> files) {
    files.sort((final a, final b) {
      final ra = a.ranking;
      final rb = b.ranking;
      final cmp = ra.compareTo(rb); // lower is better
      if (cmp != 0) return cmp;

      final ba = path.basename(a.path).length;
      final bb = path.basename(b.path).length;
      if (ba != bb) return ba.compareTo(bb);

      return a.path.length.compareTo(b.path.length);
    });
    return files.first;
  }
}

/// Reverse-Shortcut strategy:
/// - Move all NON-CANONICAL files (primary and secondaries) physically into Albums/<Album>.
/// - Choose the best-ranked NON-CANONICAL (among the moved ones) as the "anchor".
/// - For each CANONICAL file (including canonical primary if any), create a shortcut in ALL_PHOTOS pointing to the anchor,
///   then delete the original canonical source (its representation in Output becomes the shortcut).
/// - If there are NO NON-CANONICAL files at all, move the canonical primary to ALL_PHOTOS (fallback).
/// - Flags are updated as: moved.isMoved=true; represented-by-shortcut.isShortcut=true and originals deleted (isDeleted=true).
class ReverseShortcutMovingStrategy extends MoveMediaEntityStrategy {
  const ReverseShortcutMovingStrategy(
    this._fileService,
    this._pathService,
    this._symlinkService,
  );

  final FileOperationService _fileService;
  final PathGeneratorService _pathService;
  final SymlinkService _symlinkService;

  @override
  String get name => 'Reverse Shortcut';

  @override
  bool get createsShortcuts => true;

  @override
  bool get createsDuplicates => false;

  @override
  Stream<MoveMediaEntityResult> processMediaEntity(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
    final FileEntity primary = entity.primaryFile;
    final List<FileEntity> secondaries = <FileEntity>[...entity.secondaryFiles];
    final List<FileEntity> allFiles = <FileEntity>[primary, ...secondaries];

    // Snapshot canonicity BEFORE any move
    final Map<FileEntity, bool> wasCanonical = {
      for (final f in allFiles) f: f.isCanonical == true,
    };

    final List<FileEntity> nonCanonicals = allFiles
        .where((final f) => f.isCanonical != true)
        .toList();

    // Common special folders handling: move to Special Folders and exclude from further logic
    final (
      Set<FileEntity> specialHandled,
      List<MoveMediaEntityResult> sfResults,
    ) = await MovingStrategyUtils.handleSpecialFoldersForEntity(
      _fileService,
      context,
      entity,
    );
    for (final r in sfResults) {
      yield r;
    }

    final List<FileEntity> nonCanonicalsUsable = nonCanonicals
        .where((final f) => !specialHandled.contains(f))
        .toList();

    if (nonCanonicalsUsable.isNotEmpty) {
      // Move every NON-CANONICAL to its album (deterministic choice per file)
      final Map<FileEntity, File> movedMap = <FileEntity, File>{};

      for (final fe in nonCanonicalsUsable) {
        final List<String> albumsForThisFile =
            MovingStrategyUtils.albumsForFile(entity, fe);
        final String primaryAlbum = albumsForThisFile.isNotEmpty
            ? albumsForThisFile.first
            : (entity.albumNames.isNotEmpty
                  ? entity.albumNames.first
                  : 'Unknown Album');

        final Directory albumDir =
            MovingStrategyUtils.albumDirConsideringUntitled(
              _pathService,
              primaryAlbum,
              entity,
              context,
            );

        final sw = Stopwatch()..start();
        final File src = fe.asFile();
        try {
          final File m = await _fileService.moveFile(
            src,
            albumDir,
            dateTaken: entity.dateTaken,
          );
          sw.stop();

          fe.targetPath = m.path;
          fe.isShortcut = false;
          fe.isMoved = true;

          movedMap[fe] = m;

          yield MoveMediaEntityResult.success(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: albumDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
              albumKey: primaryAlbum,
            ),
            resultFile: m,
            duration: sw.elapsed,
          );
        } catch (e) {
          final elapsed = sw.elapsed;
          yield MoveMediaEntityResult.failure(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: albumDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
              albumKey: primaryAlbum,
            ),
            errorMessage: 'Failed to move non-canonical file: $e',
            duration: elapsed,
          );
        }
      }

      // Choose anchor: best-ranked among NON-CANONICAL moved
      final FileEntity anchor = _chooseBestRanked(nonCanonicalsUsable);
      final File? anchorMoved = movedMap[anchor];
      if (anchorMoved == null) {
        // Fallback: if nothing moved, do nothing more
        return;
      }

      // For each CANONICAL (pre-move), create shortcut in ALL_PHOTOS pointing to anchor and delete original
      final Directory allPhotosDir = MovingStrategyUtils.allPhotosDir(
        _pathService,
        entity,
        context,
      );

      // Per-entity registry of basenames already materialized in ALL_PHOTOS
      // This prevents producing "(1)" when multiple canonical files map to the same desired name.
      final Set<String> usedBasenamesAllPhotos = <String>{};

      for (final fe in allFiles) {
        if (specialHandled.contains(fe)) continue; // skip Special Folders
        if (wasCanonical[fe] != true) continue;

        final String desiredName = path.basename(fe.sourcePath);
        final String desiredPath = path.join(allPhotosDir.path, desiredName);

        final ssw = Stopwatch()..start();
        try {
          // Try reuse if a link/file with the desired basename already exists in ALL_PHOTOS
          if (usedBasenamesAllPhotos.contains(desiredName) ||
              MovingStrategyUtils._existsAny(desiredPath)) {
            ssw.stop();

            // Represent this canonical via the existing shortcut (synthetic entry)
            entity.secondaryFiles.add(
              FileEntity(
                sourcePath: fe.sourcePath,
                targetPath: desiredPath,
                isShortcut: true,
                dateAccuracy: fe.dateAccuracy,
                ranking: fe.ranking,
              ),
            );

            // Delete original canonical source
            try {
              await File(fe.sourcePath).delete();
              fe.isDeleted = true;
            } catch (_) {}

            usedBasenamesAllPhotos.add(desiredName);

            yield MoveMediaEntityResult.success(
              operation: MoveMediaEntityOperation(
                sourceFile: anchorMoved,
                targetDirectory: allPhotosDir,
                operationType: MediaEntityOperationType.createReverseSymlink,
                mediaEntity: entity,
              ),
              resultFile: File(desiredPath),
              duration: ssw.elapsed,
            );
          } else {
            // Otherwise create a symlink and try to rename it to the preferred basename
            final File shortcut =
                await MovingStrategyUtils.createSymlinkWithPreferredName(
                  _symlinkService,
                  allPhotosDir,
                  anchorMoved,
                  desiredName,
                );
            ssw.stop();

            entity.secondaryFiles.add(
              FileEntity(
                sourcePath: fe.sourcePath,
                targetPath: shortcut.path,
                isShortcut: true,
                dateAccuracy: fe.dateAccuracy,
                ranking: fe.ranking,
              ),
            );

            // Delete original canonical source
            try {
              await File(fe.sourcePath).delete();
              fe.isDeleted = true;
            } catch (_) {}

            usedBasenamesAllPhotos.add(path.basename(shortcut.path));

            yield MoveMediaEntityResult.success(
              operation: MoveMediaEntityOperation(
                sourceFile: anchorMoved,
                targetDirectory: allPhotosDir,
                operationType: MediaEntityOperationType.createReverseSymlink,
                mediaEntity: entity,
              ),
              resultFile: shortcut,
              duration: ssw.elapsed,
            );
          }
        } catch (e) {
          final elapsed = ssw.elapsed;
          yield MoveMediaEntityResult.failure(
            operation: MoveMediaEntityOperation(
              sourceFile: anchorMoved,
              targetDirectory: allPhotosDir,
              operationType: MediaEntityOperationType.createReverseSymlink,
              mediaEntity: entity,
            ),
            errorMessage: 'Failed to create reverse shortcut: $e',
            duration: elapsed,
          );
        }
      }
    } else {
      // No NON-CANONICALS → move canonical primary to ALL_PHOTOS
      if (!MovingStrategyUtils.isInSpecialFolder(primary.sourcePath)) {
        final Directory allPhotosDir = MovingStrategyUtils.allPhotosDir(
          _pathService,
          entity,
          context,
        );

        final sw = Stopwatch()..start();
        final File src = primary.asFile();
        try {
          final moved = await _fileService.moveFile(
            src,
            allPhotosDir,
            dateTaken: entity.dateTaken,
          );
          sw.stop();

          primary.targetPath = moved.path;
          primary.isShortcut = false;
          primary.isMoved = true;

          yield MoveMediaEntityResult.success(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: allPhotosDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
            ),
            resultFile: moved,
            duration: sw.elapsed,
          );
        } catch (e) {
          final elapsed = sw.elapsed;
          yield MoveMediaEntityResult.failure(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: allPhotosDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
            ),
            errorMessage: 'Failed to move canonical primary: $e',
            duration: elapsed,
          );
        }
      }
      // else: primary was already handled as Special Folder
    }
  }

  @override
  void validateContext(final MovingContext context) {}

  FileEntity _chooseBestRanked(final List<FileEntity> files) {
    files.sort((final a, final b) {
      final ra = a.ranking;
      final rb = b.ranking;
      final cmp = ra.compareTo(rb); // lower is better
      if (cmp != 0) return cmp;

      final ba = path.basename(a.path).length;
      final bb = path.basename(b.path).length;
      if (ba != bb) return ba.compareTo(bb);

      return a.path.length.compareTo(b.path.length);
    });
    return files.first;
  }
}

/// Duplicate-Copy strategy:
/// - If there is ANY CANONICAL file in the entity:
///   - Move CANONICAL files to ALL_PHOTOS (no album copies for canonicals).
///   - Move NON-CANONICAL files to one album they belonged to; copy to other albums they belonged to.
///   - Do NOT create copies in ALL_PHOTOS for NON-CANONICAL files.
/// - If there are NO CANONICAL files in the entity:
///   - Choose the best-ranked NON-CANONICAL and create ONE duplicate copy in ALL_PHOTOS
///     as a new synthetic secondary with `isDuplicateCopy=true` and `isMoved=false`.
///   - Move originals to their primary album and copy to other albums they belonged to.
/// - Always update targetPath and flags accordingly.
class DuplicateCopyMovingStrategy extends MoveMediaEntityStrategy {
  const DuplicateCopyMovingStrategy(this._fileService, this._pathService);

  final FileOperationService _fileService;
  final PathGeneratorService _pathService;

  @override
  String get name => 'Duplicate Copy';

  @override
  bool get createsShortcuts => false;

  @override
  bool get createsDuplicates => true;

  @override
  Stream<MoveMediaEntityResult> processMediaEntity(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
    final Directory allPhotosDir = MovingStrategyUtils.allPhotosDir(
      _pathService,
      entity,
      context,
    );
    final FileEntity primary = entity.primaryFile;
    final List<FileEntity> secondaries = <FileEntity>[...entity.secondaryFiles];
    final List<FileEntity> allFiles = <FileEntity>[primary, ...secondaries];

    final bool hasCanonical = allFiles.any((final f) => f.isCanonical == true);

    // Common special folders handling: move to Special Folders and exclude from copies/duplicates logic
    final (
      Set<FileEntity> specialHandled,
      List<MoveMediaEntityResult> sfResults,
    ) = await MovingStrategyUtils.handleSpecialFoldersForEntity(
      _fileService,
      context,
      entity,
    );
    for (final r in sfResults) {
      yield r;
    }

    // Helper: move a file to a target dir
    Future<(File?, Duration)> moveWithTiming(
      final File src,
      final Directory dest,
    ) async {
      final sw = Stopwatch()..start();
      try {
        final moved = await _fileService.moveFile(
          src,
          dest,
          dateTaken: entity.dateTaken,
        );
        sw.stop();
        return (moved, sw.elapsed);
      } catch (_) {
        final elapsed = sw.elapsed;
        return (null, elapsed);
      }
    }

    // Helper: copy a file to a target dir
    Future<(File?, Duration)> copyWithTiming(
      final File src,
      final Directory dest,
    ) async {
      final sw = Stopwatch()..start();
      try {
        final copied = await _fileService.copyFile(
          src,
          dest,
          dateTaken: entity.dateTaken,
        );
        sw.stop();
        return (copied, sw.elapsed);
      } catch (_) {
        final elapsed = sw.elapsed;
        return (null, elapsed);
      }
    }

    // Case A: There is at least one canonical in the entity
    if (hasCanonical) {
      // Move canonicals to ALL_PHOTOS
      for (final fe in allFiles.where((final f) => f.isCanonical == true)) {
        if (specialHandled.contains(fe)) continue; // skip Special Folders
        final File src = fe.asFile();
        final (File? moved, Duration elapsed) = await moveWithTiming(
          src,
          allPhotosDir,
        );
        if (moved != null) {
          fe.targetPath = moved.path;
          fe.isShortcut = false;
          fe.isMoved = true;

          yield MoveMediaEntityResult.success(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: allPhotosDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
            ),
            resultFile: moved,
            duration: elapsed,
          );
        } else {
          yield MoveMediaEntityResult.failure(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: allPhotosDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
            ),
            errorMessage: 'Failed to move canonical file',
            duration: elapsed,
          );
        }
      }

      // For NON-CANONICALS: move to primary album and copy to the rest
      for (final fe in allFiles.where((final f) => f.isCanonical != true)) {
        if (specialHandled.contains(fe)) continue; // skip Special Folders
        final List<String> albumsForThisFile =
            MovingStrategyUtils.albumsForFile(entity, fe);
        final String primaryAlbum = albumsForThisFile.isNotEmpty
            ? albumsForThisFile.first
            : (entity.albumNames.isNotEmpty
                  ? entity.albumNames.first
                  : 'Unknown Album');

        // Move original to primary album
        final Directory primaryAlbumDir =
            MovingStrategyUtils.albumDirConsideringUntitled(
              _pathService,
              primaryAlbum,
              entity,
              context,
            );
        final File srcMove = fe.asFile();
        final (File? movedToAlbum, Duration moveElapsed) = await moveWithTiming(
          srcMove,
          primaryAlbumDir,
        );
        if (movedToAlbum != null) {
          fe.targetPath = movedToAlbum.path;
          fe.isShortcut = false;
          fe.isMoved = true;

          yield MoveMediaEntityResult.success(
            operation: MoveMediaEntityOperation(
              sourceFile: srcMove,
              targetDirectory: primaryAlbumDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
              albumKey: primaryAlbum,
            ),
            resultFile: movedToAlbum,
            duration: moveElapsed,
          );
        } else {
          yield MoveMediaEntityResult.failure(
            operation: MoveMediaEntityOperation(
              sourceFile: srcMove,
              targetDirectory: primaryAlbumDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
              albumKey: primaryAlbum,
            ),
            errorMessage: 'Failed to move non-canonical file to album',
            duration: moveElapsed,
          );
          continue;
        }

        // Copy to remaining albums
        for (final albumName in albumsForThisFile.skip(1)) {
          final Directory albumDir =
              MovingStrategyUtils.albumDirConsideringUntitled(
                _pathService,
                albumName,
                entity,
                context,
              );
          final (File? copied, Duration copyElapsed) = await copyWithTiming(
            movedToAlbum,
            albumDir,
          );
          if (copied != null) {
            yield MoveMediaEntityResult.success(
              operation: MoveMediaEntityOperation(
                sourceFile: movedToAlbum,
                targetDirectory: albumDir,
                operationType: MediaEntityOperationType.copy,
                mediaEntity: entity,
                albumKey: albumName,
              ),
              resultFile: copied,
              duration: copyElapsed,
            );
          } else {
            yield MoveMediaEntityResult.failure(
              operation: MoveMediaEntityOperation(
                sourceFile: movedToAlbum,
                targetDirectory: albumDir,
                operationType: MediaEntityOperationType.copy,
                mediaEntity: entity,
                albumKey: albumName,
              ),
              errorMessage: 'Failed to copy non-canonical file to album',
              duration: copyElapsed,
            );
          }
        }
      }

      return;
    }

    // Case B: No canonicals → create ONE duplicate copy in ALL_PHOTOS from the best-ranked NON-CANONICAL
    final List<FileEntity> nonCanonicals = allFiles
        .where(
          (final f) => f.isCanonical != true && !specialHandled.contains(f),
        )
        .toList();
    if (nonCanonicals.isEmpty) return;

    final FileEntity best = _chooseBestRanked(nonCanonicals);
    final File srcBest = best.asFile();
    final (File? copiedToAll, Duration copyElapsed) = await copyWithTiming(
      srcBest,
      allPhotosDir,
    );
    if (copiedToAll != null) {
      // Synthetic secondary representing the duplicate copy in ALL_PHOTOS
      entity.secondaryFiles.add(
        FileEntity(
          sourcePath: best.sourcePath,
          targetPath: copiedToAll.path,
          dateAccuracy: best.dateAccuracy,
          ranking: best.ranking,
        )..isDuplicateCopy = true, // mark duplicate copy
      );

      yield MoveMediaEntityResult.success(
        operation: MoveMediaEntityOperation(
          sourceFile: srcBest,
          targetDirectory: allPhotosDir,
          operationType: MediaEntityOperationType.copy,
          mediaEntity: entity,
        ),
        resultFile: copiedToAll,
        duration: copyElapsed,
      );
    } else {
      yield MoveMediaEntityResult.failure(
        operation: MoveMediaEntityOperation(
          sourceFile: srcBest,
          targetDirectory: allPhotosDir,
          operationType: MediaEntityOperationType.copy,
          mediaEntity: entity,
        ),
        errorMessage: 'Failed to create duplicate copy in ALL_PHOTOS',
        duration: copyElapsed,
      );
    }

    // Move each NON-CANONICAL original to its primary album and copy to other albums
    for (final fe in nonCanonicals) {
      final List<String> albumsForThisFile = MovingStrategyUtils.albumsForFile(
        entity,
        fe,
      );
      final String primaryAlbum = albumsForThisFile.isNotEmpty
          ? albumsForThisFile.first
          : (entity.albumNames.isNotEmpty
                ? entity.albumNames.first
                : 'Unknown Album');

      // Move original to primary album
      final Directory primaryAlbumDir =
          MovingStrategyUtils.albumDirConsideringUntitled(
            _pathService,
            primaryAlbum,
            entity,
            context,
          );
      final File srcMove = fe.asFile();
      final (File? movedToAlbum, Duration moveElapsed) = await moveWithTiming(
        srcMove,
        primaryAlbumDir,
      );
      if (movedToAlbum != null) {
        fe.targetPath = movedToAlbum.path;
        fe.isShortcut = false;
        fe.isMoved = true;

        yield MoveMediaEntityResult.success(
          operation: MoveMediaEntityOperation(
            sourceFile: srcMove,
            targetDirectory: primaryAlbumDir,
            operationType: MediaEntityOperationType.move,
            mediaEntity: entity,
            albumKey: primaryAlbum,
          ),
          resultFile: movedToAlbum,
          duration: moveElapsed,
        );
      } else {
        yield MoveMediaEntityResult.failure(
          operation: MoveMediaEntityOperation(
            sourceFile: srcMove,
            targetDirectory: primaryAlbumDir,
            operationType: MediaEntityOperationType.move,
            mediaEntity: entity,
            albumKey: primaryAlbum,
          ),
          errorMessage: 'Failed to move non-canonical file to album',
          duration: moveElapsed,
        );
        continue;
      }

      // Copy to remaining albums
      for (final albumName in albumsForThisFile.skip(1)) {
        final Directory albumDir =
            MovingStrategyUtils.albumDirConsideringUntitled(
              _pathService,
              albumName,
              entity,
              context,
            );
        final (File? copied, Duration copyElapsed2) = await copyWithTiming(
          movedToAlbum,
          albumDir,
        );
        if (copied != null) {
          yield MoveMediaEntityResult.success(
            operation: MoveMediaEntityOperation(
              sourceFile: movedToAlbum,
              targetDirectory: albumDir,
              operationType: MediaEntityOperationType.copy,
              mediaEntity: entity,
              albumKey: albumName,
            ),
            resultFile: copied,
            duration: copyElapsed2,
          );
        } else {
          yield MoveMediaEntityResult.failure(
            operation: MoveMediaEntityOperation(
              sourceFile: movedToAlbum,
              targetDirectory: albumDir,
              operationType: MediaEntityOperationType.copy,
              mediaEntity: entity,
              albumKey: albumName,
            ),
            errorMessage: 'Failed to copy non-canonical file to album',
            duration: copyElapsed2,
          );
        }
      }
    }
  }

  @override
  void validateContext(final MovingContext context) {}

  FileEntity _chooseBestRanked(final List<FileEntity> files) {
    files.sort((final a, final b) {
      final ra = a.ranking;
      final rb = b.ranking;
      final cmp = ra.compareTo(rb); // lower is better
      if (cmp != 0) return cmp;

      final ba = path.basename(a.path).length;
      final bb = path.basename(b.path).length;
      if (ba != bb) return ba.compareTo(bb);

      return a.path.length.compareTo(b.path.length);
    });
    return files.first;
  }
}

/// ─────────────────────────────────────────────────────────────────────────
/// Common helpers to avoid code duplication across strategies
/// (centralized in this service module so strategies can import and reuse them)
/// ─────────────────────────────────────────────────────────────────────────
class MovingStrategyUtils {
  const MovingStrategyUtils._();

  /// Generate ALL_PHOTOS target directory (date-structured if needed).
  static Directory allPhotosDir(
    final PathGeneratorService pathService,
    final MediaEntity entity,
    final MovingContext context,
  ) => pathService.generateTargetDirectory(
    null,
    entity.dateTaken,
    context,
    isPartnerShared: entity.partnerShared,
  );

  /// Generate Albums/<albumName> target directory (date-structured if needed).
  static Directory albumDir(
    final PathGeneratorService pathService,
    final String albumName,
    final MediaEntity entity,
    final MovingContext context,
  ) => pathService.generateTargetDirectory(
    albumName,
    entity.dateTaken,
    context,
    isPartnerShared: entity.partnerShared,
  );

  /// Generate album directory but reroute to "Untitled Albums" if albumName starts with any entry in untitledAlbums (case-insensitive).
  /// Note: keeps date-structured path produced by pathService; only swaps the top-level 'Albums' with 'Untitled Albums' when present.
  static Directory albumDirConsideringUntitled(
    final PathGeneratorService pathService,
    final String albumName,
    final MediaEntity entity,
    final MovingContext context,
  ) {
    final Directory base = albumDir(pathService, albumName, entity, context);

    // Fast check against untitled list (case-insensitive "startsWith")
    final String nameLower = albumName.toLowerCase();
    bool isUntitled = false;
    for (final u in untitledAlbums) {
      if (nameLower.startsWith(u.toLowerCase())) {
        isUntitled = true;
        break;
      }
    }
    if (!isUntitled) return base;

    // Build a sibling path under "<output>/Untitled Albums/..." preserving the relative structure after "Albums"
    final String outPath = context.outputDirectory.path;
    final String basePath = base.path;

    // Compute relative path to output and swap the first segment if it is "Albums"
    final String rel = path.relative(basePath, from: outPath);
    final List<String> parts = rel.replaceAll('\\', '/').split('/');
    if (parts.isNotEmpty && parts.first.toLowerCase() == 'albums') {
      parts[0] = 'Untitled Albums';
      final String newRel = parts.join('/');
      return Directory(path.join(outPath, newRel));
    }

    // Fallback: if we cannot detect the 'Albums' segment, place under "Untitled Albums/<albumName>"
    return Directory(path.join(outPath, 'Untitled Albums', albumName));
  }

  /// Returns true if 'child' path equals or is a subpath of 'parent'.
  static bool isSubPath(final String child, final String parent) {
    final String c = child.replaceAll('\\', '/');
    final String p = parent.replaceAll('\\', '/');
    return c == p || c.startsWith('$p/');
  }

  /// Returns the directory (without trailing slash) of a path, handling both separators.
  static String dirOf(final String p) {
    final normalized = p.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx < 0 ? '' : normalized.substring(0, idx);
  }

  /// Infer album name for a given file source directory using albumsMap metadata.
  /// Returns null if no album matches.
  static String? inferAlbumForSourceDir(
    final MediaEntity entity,
    final String fileSourceDir,
  ) {
    for (final entry in entity.albumsMap.entries) {
      for (final src in entry.value.sourceDirectories) {
        if (isSubPath(fileSourceDir, src)) return entry.key;
      }
    }
    return entity.albumNames.isNotEmpty ? entity.albumNames.first : null;
  }

  /// Compute the list of album names a given file (by its source directory) belonged to.
  static List<String> albumsForFile(
    final MediaEntity entity,
    final FileEntity file,
  ) {
    final fileDir = dirOf(file.sourcePath);
    final List<String> result = <String>[];
    for (final entry in entity.albumsMap.entries) {
      for (final src in entry.value.sourceDirectories) {
        if (isSubPath(fileDir, src)) {
          result.add(entry.key);
          break;
        }
      }
    }
    return result;
  }

  /// Predicate: whether [file] belonged to the given [albumName] according to sourceDirectories.
  static bool fileBelongsToAlbum(
    final MediaEntity entity,
    final FileEntity file,
    final String albumName,
  ) {
    final albumInfo = entity.albumsMap[albumName];
    if (albumInfo == null || albumInfo.sourceDirectories.isEmpty) return false;
    final fileDir = dirOf(file.sourcePath);
    for (final src in albumInfo.sourceDirectories) {
      if (isSubPath(fileDir, src)) return true;
    }
    return false;
  }

  /// Create a symlink to [target] inside [dir] and try to rename it to [preferredBasename].
  /// On name collision, appends " (n)" before extension.
  static Future<File> createSymlinkWithPreferredName(
    final SymlinkService symlinkService,
    final Directory dir,
    final File target,
    final String preferredBasename,
  ) async {
    final File link = await symlinkService.createSymlink(dir, target);
    final String currentBase = link.uri.pathSegments.last;
    if (currentBase == preferredBasename) return link;

    final String finalBasename = _resolveUniqueBasename(dir, preferredBasename);
    final String desiredPath = path.join(dir.path, finalBasename);
    try {
      return await link.rename(desiredPath);
    } catch (_) {
      return link;
    }
  }

  static String _resolveUniqueBasename(final Directory dir, final String base) {
    final int dot = base.lastIndexOf('.');
    final String stem = dot > 0 ? base.substring(0, dot) : base;
    final String ext = dot > 0 ? base.substring(dot) : '';
    String candidate = base;
    int idx = 1;
    while (_existsAny(path.join(dir.path, candidate))) {
      candidate = '$stem ($idx)$ext';
      idx++;
    }
    return candidate;
  }

  static bool _existsAny(final String fullPath) {
    try {
      return File(fullPath).existsSync() ||
          Link(fullPath).existsSync() ||
          Directory(fullPath).existsSync();
    } catch (_) {
      return false;
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Special Folders helpers (centralized):
  // - Case-insensitive match of any path segment against the predefined list.
  // - Capitalization rule: first letter uppercase, rest lowercase.
  // - Target directory: <output>/Special Folders/<CapitalizedName>
  // - One common entry point: handleSpecialFoldersForEntity(...) to keep strategies short.
  // ───────────────────────────────────────────────────────────────────────

  static bool isInSpecialFolder(final String sourcePath) =>
      matchSpecialFolderInPath(sourcePath) != null;

  static String? matchSpecialFolderInPath(final String sourcePath) {
    final String norm = sourcePath.replaceAll('\\', '/');
    final List<String> segments = norm.split('/');
    for (final seg in segments) {
      final String segLower = seg.toLowerCase();
      for (final name in specialFolders) {
        // specialFolders are defined in constant.dart module
        if (segLower == name) {
          return _capitalizeFirst(name);
        }
      }
    }
    return null;
  }

  static Directory specialFolderDir(
    final Directory outputDir,
    final String specialCapName,
  ) => Directory(path.join(outputDir.path, 'Special Folders', specialCapName));

  static String _capitalizeFirst(final String s) {
    if (s.isEmpty) return s;
    final String lower = s.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  /// Moves any file from the entity that lives under a Special Folder directly to output/Special Folders/<CapName>/...
  /// Returns the set of handled FileEntity and the list of MoveMediaEntityResult to be yielded by the caller.
  static Future<(Set<FileEntity>, List<MoveMediaEntityResult>)>
  handleSpecialFoldersForEntity(
    final FileOperationService fileService,
    final MovingContext context,
    final MediaEntity entity,
  ) async {
    final Set<FileEntity> handled = <FileEntity>{};
    final List<MoveMediaEntityResult> results = <MoveMediaEntityResult>[];

    // Snapshot to avoid in-loop mutations
    final List<FileEntity> files = <FileEntity>[
      entity.primaryFile,
      ...entity.secondaryFiles,
    ];

    for (final fe in files) {
      final String? specialCap = matchSpecialFolderInPath(fe.sourcePath);
      if (specialCap == null) continue;

      final Directory specialDir = specialFolderDir(
        context.outputDirectory,
        specialCap,
      );
      final sw = Stopwatch()..start();
      final File src = fe.asFile();
      try {
        final File moved = await fileService.moveFile(
          src,
          specialDir,
          dateTaken: entity.dateTaken,
        );
        sw.stop();

        fe.targetPath = moved.path;
        fe.isShortcut = false;
        fe.isMoved = true;

        handled.add(fe);

        results.add(
          MoveMediaEntityResult.success(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: specialDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
            ),
            resultFile: moved,
            duration: sw.elapsed,
          ),
        );
      } catch (e) {
        final elapsed = sw.elapsed;
        results.add(
          MoveMediaEntityResult.failure(
            operation: MoveMediaEntityOperation(
              sourceFile: src,
              targetDirectory: specialDir,
              operationType: MediaEntityOperationType.move,
              mediaEntity: entity,
            ),
            errorMessage: 'Failed to move special-folder file: $e',
            duration: elapsed,
          ),
        );
      }
    }

    return (handled, results);
  }
}
