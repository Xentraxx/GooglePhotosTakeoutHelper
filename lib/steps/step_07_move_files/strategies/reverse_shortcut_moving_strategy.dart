import 'dart:io';
import 'package:gpth/gpth-lib.dart';

/// Reverse shortcut moving strategy implementation
///
/// This strategy moves files to album folders and creates shortcuts in ALL_PHOTOS.
/// Files remain in their album context, with shortcuts providing chronological access.
class ReverseShortcutMovingStrategy extends MediaEntityMovingStrategy {
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
  Stream<MediaEntityMovingResult> processMediaEntity(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
    final results = <MediaEntityMovingResult>[];
    final primaryFile = entity.primaryFile;

    // If entity has album associations, move to first album and create shortcuts elsewhere
    if (entity.albumNames.isNotEmpty) {
      // Step 1: Move file to first album folder
      final primaryAlbum = entity.albumNames.first;
      final primaryAlbumDir = _pathService.generateTargetDirectory(
        primaryAlbum,
        entity.dateTaken,
        context,
        isPartnerShared: entity.partnershared,
      );
      final stopwatch = Stopwatch()..start();
      try {
        final movedFile = await _fileService.moveFile(
          primaryFile,
          primaryAlbumDir,
          dateTaken: entity.dateTaken,
        );

        stopwatch.stop();
        final primaryResult = MediaEntityMovingResult.success(
          operation: MediaEntityMovingOperation(
            sourceFile: primaryFile,
            targetDirectory: primaryAlbumDir,
            operationType: MediaEntityOperationType.move,
            mediaEntity: entity,
            albumKey: primaryAlbum,
          ),
          resultFile: movedFile,
          duration: stopwatch.elapsed,
        );
        results.add(primaryResult);
        yield primaryResult;

        // Step 2: Create shortcut in ALL_PHOTOS (or PARTNER_SHARED)
        final allPhotosDir = _pathService.generateTargetDirectory(
          null, // null = ALL_PHOTOS or PARTNER_SHARED
          entity.dateTaken,
          context,
          isPartnerShared: entity.partnershared,
        );

        final shortcutStopwatch = Stopwatch()..start();
        try {
          final shortcutFile = await _symlinkService.createSymlink(
            allPhotosDir,
            movedFile,
          );

          shortcutStopwatch.stop();
          final shortcutResult = MediaEntityMovingResult.success(
            operation: MediaEntityMovingOperation(
              sourceFile: movedFile,
              targetDirectory: allPhotosDir,
              operationType: MediaEntityOperationType.createReverseSymlink,
              mediaEntity: entity,
            ),
            resultFile: shortcutFile,
            duration: shortcutStopwatch.elapsed,
          );
          results.add(shortcutResult);
          yield shortcutResult;
        } catch (e) {
          shortcutStopwatch.stop();
          final errorResult = MediaEntityMovingResult.failure(
            operation: MediaEntityMovingOperation(
              sourceFile: movedFile,
              targetDirectory: allPhotosDir,
              operationType: MediaEntityOperationType.createReverseSymlink,
              mediaEntity: entity,
            ),
            errorMessage: 'Failed to create reverse shortcut: $e',
            duration: shortcutStopwatch.elapsed,
          );
          results.add(errorResult);
          yield errorResult;
        }

        // Step 3: Create shortcuts in other album folders
        for (int i = 1; i < entity.albumNames.length; i++) {
          final albumName = entity.albumNames.elementAt(i);
          final albumDir = _pathService.generateTargetDirectory(
            albumName,
            entity.dateTaken,
            context,
            isPartnerShared: entity.partnershared,
          );

          final albumShortcutStopwatch = Stopwatch()..start();
          try {
            final albumShortcutFile = await _symlinkService.createSymlink(
              albumDir,
              movedFile,
            );

            albumShortcutStopwatch.stop();
            final albumShortcutResult = MediaEntityMovingResult.success(
              operation: MediaEntityMovingOperation(
                sourceFile: movedFile,
                targetDirectory: albumDir,
                operationType: MediaEntityOperationType.createSymlink,
                mediaEntity: entity,
                albumKey: albumName,
              ),
              resultFile: albumShortcutFile,
              duration: albumShortcutStopwatch.elapsed,
            );
            results.add(albumShortcutResult);
            yield albumShortcutResult;
          } catch (e) {
            albumShortcutStopwatch.stop();
            final errorResult = MediaEntityMovingResult.failure(
              operation: MediaEntityMovingOperation(
                sourceFile: movedFile,
                targetDirectory: albumDir,
                operationType: MediaEntityOperationType.createSymlink,
                mediaEntity: entity,
                albumKey: albumName,
              ),
              errorMessage: 'Failed to create album shortcut: $e',
              duration: albumShortcutStopwatch.elapsed,
            );
            results.add(errorResult);
            yield errorResult;
          }
        }
      } catch (e) {
        stopwatch.stop();
        final errorResult = MediaEntityMovingResult.failure(
          operation: MediaEntityMovingOperation(
            sourceFile: primaryFile,
            targetDirectory: primaryAlbumDir,
            operationType: MediaEntityOperationType.move,
            mediaEntity: entity,
            albumKey: primaryAlbum,
          ),
          errorMessage: 'Failed to move to album folder: $e',
          duration: stopwatch.elapsed,
        );
        results.add(errorResult);
        yield errorResult;
      }
    } else {
      // No album associations, move to ALL_PHOTOS (or PARTNER_SHARED)
      final allPhotosDir = _pathService.generateTargetDirectory(
        null,
        entity.dateTaken,
        context,
        isPartnerShared: entity.partnershared,
      );

      final stopwatch = Stopwatch()..start();
      try {
        final movedFile = await _fileService.moveFile(
          primaryFile,
          allPhotosDir,
          dateTaken: entity.dateTaken,
        );

        stopwatch.stop();
        final primaryResult = MediaEntityMovingResult.success(
          operation: MediaEntityMovingOperation(
            sourceFile: primaryFile,
            targetDirectory: allPhotosDir,
            operationType: MediaEntityOperationType.move,
            mediaEntity: entity,
          ),
          resultFile: movedFile,
          duration: stopwatch.elapsed,
        );
        results.add(primaryResult);
        yield primaryResult;
      } catch (e) {
        stopwatch.stop();
        final errorResult = MediaEntityMovingResult.failure(
          operation: MediaEntityMovingOperation(
            sourceFile: primaryFile,
            targetDirectory: allPhotosDir,
            operationType: MediaEntityOperationType.move,
            mediaEntity: entity,
          ),
          errorMessage: 'Failed to move to ALL_PHOTOS: $e',
          duration: stopwatch.elapsed,
        );
        results.add(errorResult);
        yield errorResult;
      }
    }

    // Move non-primary physical files to _Duplicates, preserving structure
    yield* _moveNonPrimaryFilesToDuplicates(entity, context);
  }

  @override
  void validateContext(final MovingContext context) {
    // No special validation needed for reverse shortcut mode
  }

  // --- helper: move all non-primary physical files to _Duplicates, preserving structure ---
  Stream<MediaEntityMovingResult> _moveNonPrimaryFilesToDuplicates(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
    final duplicatesRoot = Directory('${context.outputDirectory.path}/_Duplicates');
    final primaryPath = entity.primaryFile.path;
    final allSources = entity.files.files.values.map((final f) => f.path).toSet();

    for (final srcPath in allSources) {
      if (srcPath == primaryPath) continue;

      final sourceFile = File(srcPath);
      final relInfo = _computeDuplicatesRelativeInfo(srcPath);
      final targetDir = Directory('${duplicatesRoot.path}/${relInfo.relativeDir}');
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }

      final sw = Stopwatch()..start();
      try {
        final moved = await _fileService.moveFile(
          sourceFile,
          targetDir,
          dateTaken: entity.dateTaken,
        );
        sw.stop();
        yield MediaEntityMovingResult.success(
          operation: MediaEntityMovingOperation(
            sourceFile: sourceFile,
            targetDirectory: targetDir,
            operationType: MediaEntityOperationType.move,
            mediaEntity: entity,
          ),
          resultFile: moved,
          duration: sw.elapsed,
        );
      } catch (e) {
        sw.stop();
        yield MediaEntityMovingResult.failure(
          operation: MediaEntityMovingOperation(
            sourceFile: sourceFile,
            targetDirectory: targetDir,
            operationType: MediaEntityOperationType.move,
            mediaEntity: entity,
          ),
          errorMessage: 'Failed to move non-primary file to _Duplicates: $e (hint: ${relInfo.hint})',
          duration: sw.elapsed,
        );
      }
    }
  }

  _RelInfo _computeDuplicatesRelativeInfo(final String sourcePath) {
    final normalized = sourcePath.replaceAll('\\', '/');
    final lower = normalized.toLowerCase();

    final idxTakeout = lower.indexOf('/takeout/');
    if (idxTakeout >= 0) {
      final rel = normalized.substring(idxTakeout + '/takeout/'.length);
      final relDir = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
      return _RelInfo(relativeDir: relDir.isEmpty ? '.' : relDir, hint: 'anchored by /Takeout/');
    }

    for (final anchor in const ['/google fotos/', '/google photos/']) {
      final idx = lower.indexOf(anchor);
      if (idx >= 0) {
        final rel = normalized.substring(idx + anchor.length);
        final relDir = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
        return _RelInfo(relativeDir: relDir.isEmpty ? '.' : relDir, hint: 'anchored by $anchor');
      }
    }

    final lastSlash = normalized.lastIndexOf('/');
    final parent = lastSlash >= 0 ? normalized.substring(0, lastSlash) : '';
    final leaf = parent.isEmpty ? 'Uncategorized' : parent.split('/').last;
    return _RelInfo(relativeDir: leaf, hint: 'fallback: no anchor found');
  }
}

class _RelInfo {
  const _RelInfo({required this.relativeDir, required this.hint});
  final String relativeDir;
  final String hint;
}
