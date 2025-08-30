import 'package:gpth/gpth-lib.dart';

/// Factory for creating MediaEntity moving strategies
///
/// This factory creates the appropriate strategy instance based on
/// the album behavior configuration, providing all necessary dependencies.
class MediaEntityMovingStrategyFactory {
  const MediaEntityMovingStrategyFactory(
    this._fileService,
    this._pathService,
    this._symlinkService,
  );
  // Dependencies for creating strategy implementations
  final FileOperationService _fileService;
  final PathGeneratorService _pathService;
  final SymlinkService _symlinkService;

  /// Creates the appropriate strategy for the given album behavior
  MediaEntityMovingStrategy createStrategy(final AlbumBehavior albumBehavior) {
    switch (albumBehavior) {
      case AlbumBehavior.shortcut:
        return ShortcutMovingStrategy(
          _fileService,
          _pathService,
          _symlinkService,
        );
      case AlbumBehavior.duplicateCopy:
        return DuplicateCopyMovingStrategy(_fileService, _pathService);
      case AlbumBehavior.reverseShortcut:
        return ReverseShortcutMovingStrategy(
          _fileService,
          _pathService,
          _symlinkService,
        );
      case AlbumBehavior.json:
        return JsonMovingStrategy(_fileService, _pathService);
      case AlbumBehavior.nothing:
        return NothingMovingStrategy(_fileService, _pathService);
    }
  }
}
