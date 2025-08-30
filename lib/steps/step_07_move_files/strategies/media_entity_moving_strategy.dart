import 'dart:io';
import 'package:gpth/gpth-lib.dart';

/// Modern abstract base class for different album moving strategies using MediaEntity
///
/// This interface defines the contract for implementing different album
/// behaviors (shortcut, duplicate-copy, json, nothing, reverse-shortcut)
/// using immutable MediaEntity objects for better performance and safety.
abstract class MediaEntityMovingStrategy {
  const MediaEntityMovingStrategy();

  /// The name of this strategy for logging and debugging
  String get name;

  /// Whether this strategy creates shortcuts/symlinks
  bool get createsShortcuts;

  /// Whether this strategy creates duplicate files
  bool get createsDuplicates;

  /// Processes a single media entity according to this strategy
  ///
  /// [entity] The media entity to process
  /// [context] The moving context with configuration
  /// Returns a stream of MediaEntityMovingResult objects representing the operations performed
  Stream<MediaEntityMovingResult> processMediaEntity(
    final MediaEntity entity,
    final MovingContext context,
  );

  /// Performs any finalization steps after all media has been processed
  ///
  /// [context] The moving context
  /// [processedEntities] All media entities that were processed
  /// Returns any additional results from finalization
  Future<List<MediaEntityMovingResult>> finalize(
    final MovingContext context,
    final List<MediaEntity> processedEntities,
  ) async =>
      []; // Default: no finalization needed

  /// Validates that this strategy can be used with the given context
  ///
  /// [context] The moving context to validate
  /// Throws an exception if the context is invalid for this strategy
  void validateContext(final MovingContext context) {
    // Default: no validation needed
  }
}

/// Represents a single file moving operation for MediaEntity
class MediaEntityMovingOperation {
  const MediaEntityMovingOperation({
    required this.sourceFile,
    required this.targetDirectory,
    required this.operationType,
    required this.mediaEntity,
    this.albumKey,
  });

  final File sourceFile;
  final String? albumKey;
  final MediaEntity mediaEntity;
  final Directory targetDirectory;
  final MediaEntityOperationType operationType;

  /// Gets the target file for this operation
  File get targetFile =>
      File('${targetDirectory.path}/${sourceFile.uri.pathSegments.last}');

  /// Whether this operation is for an album file
  bool get isAlbumFile => albumKey != null;

  /// Whether this operation is for a main/year folder file
  bool get isMainFile => albumKey == null;
}

/// Types of moving operations for MediaEntity
enum MediaEntityOperationType {
  move,
  copy,
  createSymlink,
  createReverseSymlink,
  createJsonReference,
}

/// Result of a MediaEntity moving operation
class MediaEntityMovingResult {
  const MediaEntityMovingResult({
    required this.operation,
    required this.success,
    required this.duration,
    this.resultFile,
    this.errorMessage,
  });

  factory MediaEntityMovingResult.success({
    required final MediaEntityMovingOperation operation,
    required final File resultFile,
    required final Duration duration,
  }) =>
      MediaEntityMovingResult(
        operation: operation,
        resultFile: resultFile,
        success: true,
        duration: duration,
      );

  factory MediaEntityMovingResult.failure({
    required final MediaEntityMovingOperation operation,
    required final String errorMessage,
    required final Duration duration,
  }) =>
      MediaEntityMovingResult(
        operation: operation,
        success: false,
        errorMessage: errorMessage,
        duration: duration,
      );

  final MediaEntityMovingOperation operation;
  final File? resultFile;
  final bool success;
  final Duration duration;
  final String? errorMessage;

  /// Whether this result represents a successful operation
  bool get isSuccess => success;

  /// Whether this result represents a failed operation
  bool get isFailure => !success;
}
