import 'dart:io';
import 'package:gpth/gpth-lib.dart';

/// Nothing moving strategy implementation
///
/// This strategy ignores albums entirely and creates only ALL_PHOTOS with all files
/// organized chronologically. All files are moved to ALL_PHOTOS regardless of their
/// source location (year folders or albums) to ensure no data loss.
class NothingMovingStrategy extends MediaEntityMovingStrategy {
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
  Stream<MediaEntityMovingResult> processMediaEntity(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
    // Move ALL files to ALL_PHOTOS, regardless of their source location
    // This ensures no data loss in move mode and provides transparent behavior

    // Move file to ALL_PHOTOS (or PARTNER_SHARED)
    final primaryFile = entity.primaryFile;
    final allPhotosDir = _pathService.generateTargetDirectory(
      null, // null = ALL_PHOTOS or PARTNER_SHARED
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
      yield MediaEntityMovingResult.success(
        operation: MediaEntityMovingOperation(
          sourceFile: primaryFile,
          targetDirectory: allPhotosDir,
          operationType: MediaEntityOperationType.move,
          mediaEntity: entity,
        ),
        resultFile: movedFile,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      yield MediaEntityMovingResult.failure(
        operation: MediaEntityMovingOperation(
          sourceFile: primaryFile,
          targetDirectory: allPhotosDir,
          operationType: MediaEntityOperationType.move,
          mediaEntity: entity,
        ),
        errorMessage: 'Failed to move file: $e',
        duration: stopwatch.elapsed,
      );
    }

    // Move non-primary physical files to _Duplicates, preserving structure
    yield* _moveNonPrimaryFilesToDuplicates(entity, context);
  }

  @override
  void validateContext(final MovingContext context) {
    // No special validation needed for nothing mode
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
