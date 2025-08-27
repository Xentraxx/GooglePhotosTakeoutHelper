import 'dart:convert';
import 'dart:io';

import '../../../../entities/media_entity.dart';
import '../file_operation_service.dart';
import '../moving_context_model.dart';
import '../path_generator_service.dart';
import 'media_entity_moving_strategy.dart';

/// JSON moving strategy implementation
///
/// This strategy creates a single ALL_PHOTOS folder with all files and generates
/// an albums-info.json file containing metadata about album associations.
class JsonMovingStrategy extends MediaEntityMovingStrategy {
  JsonMovingStrategy(this._fileService, this._pathService);

  final FileOperationService _fileService;
  final PathGeneratorService _pathService;

  // Track album information for JSON generation
  final Map<String, List<String>> _albumInfo = {};

  @override
  String get name => 'JSON';

  @override
  bool get createsShortcuts => false;

  @override
  bool get createsDuplicates => false;

  @override
  Stream<MediaEntityMovingResult> processMediaEntity(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
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

      // Track album associations for JSON file
      final fileName = movedFile.uri.pathSegments.last;
      for (final albumName in entity.albumNames) {
        _albumInfo.putIfAbsent(albumName, () => []).add(fileName);
      }

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
        errorMessage: 'Failed to move file: $e',
        duration: stopwatch.elapsed,
      );
      yield errorResult;
    }

    // NEW: move non-primary physical files to _Duplicates preserving source structure
    yield* _moveNonPrimaryFilesToDuplicates(entity, context);
  }

  @override
  Future<List<MediaEntityMovingResult>> finalize(
    final MovingContext context,
    final List<MediaEntity> processedEntities,
  ) async {
    // Generate albums-info.json file
    final jsonPath = _pathService.generateAlbumsInfoJsonPath(
      context.outputDirectory,
    );
    final jsonFile = File(jsonPath);

    final stopwatch = Stopwatch()..start();
    try {
      final albumData = {
        'albums': _albumInfo,
        'metadata': {
          'generated': DateTime.now().toIso8601String(),
          'total_albums': _albumInfo.length,
          'total_files': processedEntities.length,
          'strategy': 'json',
        },
      };

      await jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(albumData),
      );

      stopwatch.stop();
      return [
        MediaEntityMovingResult.success(
          operation: MediaEntityMovingOperation(
            sourceFile: jsonFile, // Placeholder for JSON generation
            targetDirectory: context.outputDirectory,
            operationType: MediaEntityOperationType.createJsonReference,
            mediaEntity: processedEntities.isNotEmpty
                ? processedEntities.first
                : MediaEntity.single(file: jsonFile), // Fallback
          ),
          resultFile: jsonFile,
          duration: stopwatch.elapsed,
        ),
      ];
    } catch (e) {
      stopwatch.stop();
      return [
        MediaEntityMovingResult.failure(
          operation: MediaEntityMovingOperation(
            sourceFile: jsonFile,
            targetDirectory: context.outputDirectory,
            operationType: MediaEntityOperationType.createJsonReference,
            mediaEntity: processedEntities.isNotEmpty
                ? processedEntities.first
                : MediaEntity.single(file: jsonFile), // Fallback
          ),
          errorMessage: 'Failed to create albums-info.json: $e',
          duration: stopwatch.elapsed,
        ),
      ];
    }
  }

  @override
  void validateContext(final MovingContext context) {
    // No special validation needed for JSON mode
  }

  // --- NEW helper: move all non-primary physical files to _Duplicates, preserving structure ---
  Stream<MediaEntityMovingResult> _moveNonPrimaryFilesToDuplicates(
    final MediaEntity entity,
    final MovingContext context,
  ) async* {
    final duplicatesRoot = Directory(
      '${context.outputDirectory.path}/_Duplicates',
    );
    final primaryPath = entity.primaryFile.path;
    final allSources = entity.files.files.values
        .map((final f) => f.path)
        .toSet();

    for (final srcPath in allSources) {
      if (srcPath == primaryPath) continue;

      final sourceFile = File(srcPath);
      final relInfo = _computeDuplicatesRelativeInfo(srcPath);
      final targetDir = Directory(
        '${duplicatesRoot.path}/${relInfo.relativeDir}',
      );
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
          errorMessage:
              'Failed to move non-primary file to _Duplicates: $e (hint: ${relInfo.hint})',
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
      final relDir = rel.contains('/')
          ? rel.substring(0, rel.lastIndexOf('/'))
          : '';
      return _RelInfo(
        relativeDir: relDir.isEmpty ? '.' : relDir,
        hint: 'anchored by /Takeout/',
      );
    }

    for (final anchor in const ['/google fotos/', '/google photos/']) {
      final idx = lower.indexOf(anchor);
      if (idx >= 0) {
        final rel = normalized.substring(idx + anchor.length);
        final relDir = rel.contains('/')
            ? rel.substring(0, rel.lastIndexOf('/'))
            : '';
        return _RelInfo(
          relativeDir: relDir.isEmpty ? '.' : relDir,
          hint: 'anchored by $anchor',
        );
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
