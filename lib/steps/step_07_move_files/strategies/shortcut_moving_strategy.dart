import 'dart:io';
import 'package:gpth/gpth-lib.dart';

/// Shortcut moving strategy implementation
///
/// This strategy creates shortcuts/symlinks from album folders to files in ALL_PHOTOS.
/// Files are moved to ALL_PHOTOS organized by date, and shortcuts are created in album folders.
class ShortcutMovingStrategy extends MediaEntityMovingStrategy {
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
  Stream<MediaEntityMovingResult> processMediaEntity(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
    final results = <MediaEntityMovingResult>[];

    // Step 1: Move primary file to ALL_PHOTOS (or PARTNER_SHARED)
    final primaryFile = entity.primaryFile;
    final allPhotosDir = _pathService.generateTargetDirectory(
      null, // null = ALL_PHOTOS (or PARTNER_SHARED if partner shared)
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

      // Step 2: Create shortcuts for each album association (use primary as source)
      for (final albumName in entity.albumNames) {
        final albumDir = _pathService.generateTargetDirectory(
          albumName,
          entity.dateTaken,
          context,
          isPartnerShared: entity.partnershared,
        );
        final shortcutStopwatch = Stopwatch()..start();
        try {
          final shortcutFile = await _symlinkService.createSymlink(
            albumDir,
            movedFile,
          );

          shortcutStopwatch.stop();
          final shortcutResult = MediaEntityMovingResult.success(
            operation: MediaEntityMovingOperation(
              sourceFile: movedFile,
              targetDirectory: albumDir,
              operationType: MediaEntityOperationType.createSymlink,
              mediaEntity: entity,
              albumKey: albumName,
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
              targetDirectory: albumDir,
              operationType: MediaEntityOperationType.createSymlink,
              mediaEntity: entity,
              albumKey: albumName,
            ),
            errorMessage: 'Failed to create shortcut: $e',
            duration: shortcutStopwatch.elapsed,
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
          targetDirectory: allPhotosDir,
          operationType: MediaEntityOperationType.move,
          mediaEntity: entity,
        ),
        errorMessage: 'Failed to move primary file: $e',
        duration: stopwatch.elapsed,
      );
      results.add(errorResult);
      yield errorResult;
    }

    // Move non-primary physical files to _Duplicates, preserving structure
    yield* _moveNonPrimaryFilesToDuplicates(entity, context);
  }

  @override
  void validateContext(final MovingContext context) {
    // No special validation needed for shortcut mode
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
