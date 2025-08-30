import 'package:gpth/gpth-lib.dart';

/// Step 6: Find and merge album relationships
///
/// This sophisticated step analyzes the media collection to identify files that represent
/// the same photo/video across different albums and locations, then merges them into
/// unified Media objects. This is crucial for Google Photos exports where the same file
/// appears in both year folders and multiple album folders.
///
/// ## Album Relationship Detection
///
/// ### Content-Based Matching
/// - **Hash Comparison**: Uses SHA-256 hashing to identify identical file content
/// - **Size Verification**: Pre-filters by file size before expensive hash calculations
/// - **Binary Comparison**: Ensures exact content matches for reliable identification
/// - **Performance Optimization**: Groups by size first to minimize hash operations
///
/// ### File Location Analysis
/// - **Year Folder Files**: Primary files from "Photos from YYYY" directories
/// - **Album Folder Files**: Duplicate copies in named album directories
/// - **Cross-Reference Mapping**: Identifies which albums contain each photo
/// - **Relationship Preservation**: Maintains all album associations for each file
///
/// ### Multi-Album Detection
/// Files appearing in multiple albums are properly handled:
/// - **Album List Consolidation**: Merges all album names into single Media object
/// - **File Path Preservation**: Keeps references to all file locations
/// - **Metadata Reconciliation**: Chooses best metadata from available sources
/// - **Duplicate Elimination**: Removes redundant Media objects after merging
///
/// ## Merging Logic
///
/// ### Data Consolidation Strategy
/// When multiple Media objects represent the same file:
/// 1. **Date Accuracy Priority**: Chooses the Media with best date accuracy
/// 2. **Album Information Merge**: Combines all album associations
/// 3. **File Reference Consolidation**: Preserves all file location references
/// 4. **Metadata Selection**: Uses most reliable metadata source
/// 5. **Original Cleanup**: Removes now-redundant Media objects
///
/// ### Best Source Selection
/// The algorithm prioritizes:
/// - **Higher date accuracy** (lower accuracy number = better)
/// - **Shorter filename length** (often indicates original vs processed)
/// - **Year folder over album folder** (primary source preference)
/// - **Earlier discovery order** (first found = canonical)
///
/// ### Album Association Management
/// - **Null Key Preservation**: Maintains year folder association (null key)
/// - **Named Album Keys**: Preserves all album folder associations
/// - **Album Name Cleanup**: Handles special characters and emoji in album names
/// - **Hierarchy Respect**: Maintains Google Photos album organization structure
///
/// ## Processing Performance
///
/// ### Optimization Strategies
/// - **Size-Based Grouping**: Groups files by size before hash comparison
/// - **Incremental Processing**: Processes files in batches for memory efficiency
/// - **Hash Caching**: Avoids recalculating hashes for the same files
/// - **Early Termination**: Skips further processing when no matches possible
///
/// ### Scalability Features
/// - **Large Collection Support**: Efficiently handles thousands of photos
/// - **Memory Management**: Processes groups incrementally to control memory usage
/// - **Progress Reporting**: Provides feedback for long-running operations
/// - **Interruption Handling**: Can be safely interrupted and resumed
///
/// ## Album Behavior Preparation
///
/// This step prepares the media collection for various album handling modes:
///
/// ### Shortcut Mode Preparation
/// - **Primary File Identification**: Designates main file for each photo
/// - **Album Reference Setup**: Prepares album folder references for linking
///
/// ### Duplicate-Copy Mode Preparation
/// - **Multi-Location Tracking**: Maintains all file location information
/// - **Copy Source Identification**: Identifies which files need album copies
/// - **Album Structure Mapping**: Maps album organization for file duplication
///
/// ### JSON Mode Preparation
/// - **Album Membership Tracking**: Records which albums contain each file
/// - **Metadata Consolidation**: Prepares album information for JSON export
/// - **File-Album Associations**: Creates mapping for JSON output generation
///
/// ## Error Handling and Edge Cases
///
/// ### File Access Issues
/// - **Permission Errors**: Gracefully handles inaccessible files
/// - **Corrupted Files**: Skips files that cannot be hashed
/// - **Missing Files**: Handles broken file references
/// - **Network Storage**: Manages timeouts and connection issues
///
/// ### Data Integrity Protection
/// - **Hash Verification**: Ensures content matching is accurate
/// - **Metadata Validation**: Verifies merged metadata consistency
/// - **Rollback Capability**: Can undo merging if issues detected
/// - **Audit Logging**: Tracks all merge operations for debugging
///
/// ### Special Cases
/// - **Identical Filenames**: Handles files with same name but different content
/// - **Modified Timestamps**: Manages files with different modification times
/// - **Size Variations**: Handles minor size differences due to metadata changes
/// - **Encoding Differences**: Manages files with different character encodings
///
/// ## Integration and Dependencies
///
/// ### Prerequisites
/// - **Media Discovery**: Requires fully populated MediaCollection
/// - **Date Extraction**: Benefits from date information for conflict resolution
/// - **Duplicate Removal**: Should run after basic duplicate detection
///
/// ### Output Usage
/// - **File Moving**: Provides unified Media objects for organization
/// - **Album Creation**: Enables proper album folder structure generation
/// - **Symlink Creation**: Supports linking strategies for album modes
/// - **Statistics Generation**: Provides data for final processing reports
///
/// ### Configuration Dependencies
/// - **Album Behavior**: Different merging strategies for different output modes
/// - **Verbose Mode**: Controls detailed progress and statistics reporting
/// - **Performance Settings**: May use different algorithms for large collections
class FindAlbumsStep extends ProcessingStep with LoggerMixin {
  FindAlbumsStep() : super('Find Albums');

  @override
  Future<StepResult> execute(final ProcessingContext context) async {
    final sw = Stopwatch()..start();

    try {
      print('\n[Step 6/8] Finding albums (this may take a while)...');

      final collection = context.mediaCollection;
      final initial = collection.length;

      final svc = ServiceContainer.instance.albumRelationshipService;

      // Work on a copy to avoid mid-iteration mutation issues
      final mediaCopy = collection.asList();
      List<MediaEntity> merged;
      try {
        merged = await svc.detectAndMergeAlbums(mediaCopy);
      } catch (e) {
        logWarning('Album detection failed: $e', forcePrint: true);
        merged = mediaCopy; // conservative: do not drop anything
      }

      collection.replaceAll(merged);

      final finalCount = collection.length;
      final mergedCount = initial - finalCount;

      // Diagnostics: how many media have album files
      final mediaWithAlbums = merged.where((m) => m.hasAlbumAssociations).length;
      print('[Step 6/8] Media with album associations: $mediaWithAlbums');

      // Diagnostics: how many distinct album keys/names
      final distinctAlbums = <String>{};
      for (final m in merged) {
        // albumNames already unions files.albumNames + belongToAlbums.keys
        for (final name in m.albumNames) {
          if (name.isNotEmpty) distinctAlbums.add(name);
        }
      }
      print('[Step 6/8] Distinct album folders detected: ${distinctAlbums.length}');

      sw.stop();
      return StepResult.success(
        stepName: name,
        duration: sw.elapsed,
        data: {
          'initialCount': initial,
          'finalCount': finalCount,
          'mergedCount': mergedCount,
          'mediaWithAlbums': mediaWithAlbums,
          'distinctAlbums': distinctAlbums.length,
        },
        message: 'Found ${distinctAlbums.length} different albums ($mergedCount albums were merged)',
      );
    } catch (e) {
      sw.stop();
      return StepResult.failure(
        stepName: name,
        duration: sw.elapsed,
        error: e is Exception ? e : Exception(e.toString()),
        message: 'Failed to find albums: $e',
      );
    }
  }

  @override
  bool shouldSkip(final ProcessingContext context) =>
      context.mediaCollection.isEmpty;
}
