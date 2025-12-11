/// **INPUT/OUTPUT PATH DATA MODEL**
///
/// Domain model for holding resolved and validated input and output directory paths.
/// This provides type safety and clarity for path handling throughout the
/// argument parsing and validation process.
///
/// **PURPOSE:**
/// - Encapsulates the two required paths in a single domain object
/// - Provides type safety for path passing between functions
/// - Makes function signatures clearer and more maintainable
/// - Enables future extension with additional path-related metadata
///   (e.g., a flag indicating whether the input was extracted from ZIPs)
/// - Follows clean architecture principles by keeping data models in domain layer
///
/// **USAGE:**
/// Used by path resolution services and configuration builders to return validated
/// input and output directory paths from either CLI arguments or interactive mode prompts.
class InputOutputPaths {
  const InputOutputPaths({
    required this.inputPath,
    required this.outputPath,
    this.extractedFromZip =
        false, // NEW: set to true when the input was produced by ZIP extraction
    final String?
    userInputRoot, // NEW: original user-provided root (before resolveGooglePhotosPath)
  }) : userInputRoot = userInputRoot ?? inputPath;

  /// Path to the directory containing Google Photos Takeout media files.
  /// This path is normalized to point to the actual Google Photos folder
  /// containing "Photos from YYYY" directories and album folders.
  final String inputPath;

  /// Path to the directory where organized photos will be written.
  /// This directory will be created if it doesn't exist.
  final String outputPath;

  /// Whether the input directory was produced by an internal ZIP extraction step.
  /// When true, upstream logic can skip cloning (--keep-input) because the input
  /// is already a temporary/extracted location.
  final bool extractedFromZip;

  /// Original user-selected/CLI-provided folder (before resolving to the Google Photos subfolder).
  /// This is the folder to clone if --keep-input is active.
  final String userInputRoot;

  @override
  String toString() =>
      'InputOutputPaths(input: $inputPath, output: $outputPath, extractedFromZip: $extractedFromZip, userInputRoot: $userInputRoot)';

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      (other is InputOutputPaths &&
          runtimeType == other.runtimeType &&
          inputPath == other.inputPath &&
          outputPath == other.outputPath &&
          extractedFromZip == other.extractedFromZip &&
          userInputRoot == other.userInputRoot);

  @override
  int get hashCode =>
      inputPath.hashCode ^
      outputPath.hashCode ^
      extractedFromZip.hashCode ^
      userInputRoot.hashCode;
}
