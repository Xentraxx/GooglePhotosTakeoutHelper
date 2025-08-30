import 'dart:io';
import 'package:gpth/gpth-lib.dart';

/// Duplicate-copy moving strategy implementation
///
/// This strategy creates actual file copies in both ALL_PHOTOS and album folders.
/// Files are moved to ALL_PHOTOS and copied to each album folder.
class DuplicateCopyMovingStrategy extends MediaEntityMovingStrategy {
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
  Stream<MediaEntityMovingResult> processMediaEntity(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
    // Step 1: Ensure we have (or create) the primary canonical file in ALL_PHOTOS (or PARTNER_SHARED)
    final originalPrimaryFile = entity.primaryFile;
    final allPhotosDir = _pathService.generateTargetDirectory(
      null, // null = ALL_PHOTOS or PARTNER_SHARED
      entity.dateTaken,
      context,
      isPartnerShared: entity.partnershared,
    );

    // If the original file physically resides inside one of the album folders that we will later populate,
    // we must MOVE it to the canonical ALL_PHOTOS folder instead of copying it, otherwise the original
    // remains and causes leftover files. Heuristic: if its path contains any of the album directory target paths.
    File canonicalFile = originalPrimaryFile;
    final stopwatch = Stopwatch()..start();
    try {
      if (entity.albumNames.isNotEmpty) {
        // Pre-generate album directories to test path containment cheaply
        final albumDirs = <String, Directory>{};
        for (final albumName in entity.albumNames) {
          final dir = _pathService.generateTargetDirectory(
            albumName,
            entity.dateTaken,
            context,
            isPartnerShared: entity.partnershared,
          );
          albumDirs[albumName] = dir;
        }

        final originalPathLower = originalPrimaryFile.path.toLowerCase();
        final isInsideAlbum = albumDirs.values.any(
          (final d) => originalPathLower.startsWith(d.path.toLowerCase()),
        );

        if (isInsideAlbum) {
          // Move the file out to canonical location
          canonicalFile = await _fileService.moveFile(
            originalPrimaryFile,
            allPhotosDir,
            dateTaken: entity.dateTaken,
          );
        } else {
          // Regular flow: move (rename) into ALL_PHOTOS (if already there rename handles uniqueness)
          canonicalFile = await _fileService.moveFile(
            originalPrimaryFile,
            allPhotosDir,
            dateTaken: entity.dateTaken,
          );
        }
      } else {
        // No albums: just move
        canonicalFile = await _fileService.moveFile(
          originalPrimaryFile,
          allPhotosDir,
          dateTaken: entity.dateTaken,
        );
      }

      stopwatch.stop();
      yield MediaEntityMovingResult.success(
        operation: MediaEntityMovingOperation(
          sourceFile: originalPrimaryFile,
          targetDirectory: allPhotosDir,
          operationType: MediaEntityOperationType.move,
          mediaEntity: entity,
        ),
        resultFile: canonicalFile,
        duration: stopwatch.elapsed,
      );

      // Step 2: For each album, ensure a copy exists (use canonicalFile as source)
      for (final albumName in entity.albumNames) {
        final albumDir = _pathService.generateTargetDirectory(
          albumName,
          entity.dateTaken,
          context,
          isPartnerShared: entity.partnershared,
        );

        final copyStopwatch = Stopwatch()..start();
        try {
          final copiedFile = await _fileService.copyFile(
            canonicalFile,
            albumDir,
            dateTaken: entity.dateTaken,
          );
          copyStopwatch.stop();
          yield MediaEntityMovingResult.success(
            operation: MediaEntityMovingOperation(
              sourceFile: canonicalFile,
              targetDirectory: albumDir,
              operationType: MediaEntityOperationType.copy,
              mediaEntity: entity,
              albumKey: albumName,
            ),
            resultFile: copiedFile,
            duration: copyStopwatch.elapsed,
          );
        } catch (e) {
          copyStopwatch.stop();
          yield MediaEntityMovingResult.failure(
            operation: MediaEntityMovingOperation(
              sourceFile: canonicalFile,
              targetDirectory: albumDir,
              operationType: MediaEntityOperationType.copy,
              mediaEntity: entity,
              albumKey: albumName,
            ),
            errorMessage: 'Failed to copy to album folder: $e',
            duration: copyStopwatch.elapsed,
          );
        }
      }
    } catch (e) {
      stopwatch.stop();
      yield MediaEntityMovingResult.failure(
        operation: MediaEntityMovingOperation(
          sourceFile: originalPrimaryFile,
          targetDirectory: allPhotosDir,
          operationType: MediaEntityOperationType.move,
          mediaEntity: entity,
        ),
        errorMessage: 'Failed to establish canonical file: $e',
        duration: stopwatch.elapsed,
      );
    }

    // Move non-primary physical files to _Duplicates preserving source structure
    yield* _moveNonPrimaryFilesToDuplicates(entity, context);
  }

  @override
  void validateContext(final MovingContext context) {
    // No special validation needed for duplicate-copy strategy
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

  // Calculate a relative directory inside _Duplicates that mirrors the source tree.
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
    final parent = normalized.substring(0, lastSlash >= 0 ? lastSlash : normalized.length);
    final leaf = parent.isEmpty ? 'Uncategorized' : parent.split('/').last;
    return _RelInfo(relativeDir: leaf, hint: 'fallback: no anchor found');
  }
}

class _RelInfo {
  const _RelInfo({required this.relativeDir, required this.hint});
  final String relativeDir;
  final String hint;
}
