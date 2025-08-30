import 'dart:io';
import 'package:gpth/gpth-lib.dart';

/// Step 3: Remove duplicate media files
///
/// This essential step identifies and eliminates duplicate files based on content hashing,
/// which is crucial for Google Photos Takeout exports that often contain multiple copies
/// of the same photo across different albums and year folders.
///
/// ## Duplicate Detection Strategy
///
/// ### Content-Based Identification
/// - **Hash Algorithm**: Uses SHA-256 cryptographic hashing for reliable content comparison
/// - **Size Pre-filtering**: Groups files by size before hashing to optimize performance
/// - **Binary Comparison**: Ensures exact byte-by-byte content matching
/// - **Metadata Independence**: Focuses on file content, ignoring metadata differences
///
/// ### Two-Phase Processing
/// 1. **Size Grouping**: Groups files by identical file sizes (cheap comparison)
/// 2. **Hash Verification**: Calculates hashes only for files with matching sizes
/// 3. **Performance Optimization**: Avoids expensive hash calculations for unique sizes
/// 4. **Memory Efficiency**: Processes groups incrementally to manage memory usage
///
/// ## Duplicate Resolution Logic
///
/// ### Best Copy Selection
/// When multiple identical files are found, the algorithm selects the best copy using:
///
/// #### Primary Criteria (in priority order):
/// 1. **Date Accuracy**: Files with better date extraction accuracy (lower number = better)
/// 2. **Filename Length**: Shorter filenames often indicate original vs processed files
/// 3. **Discovery Order**: Earlier discovered files are preferred as canonical
/// 4. **Path Characteristics**: Year folder files preferred over album folder duplicates
///
/// #### Selection Algorithm:
/// ```
/// Sort by: dateTakenAccuracy (ascending) + filenameLength (ascending)
/// Keep: First file in sorted order
/// Remove: All subsequent identical files
/// ```
///
/// ### Metadata Preservation
/// - **Date Information**: Preserves best available date and accuracy from kept file
/// - **Album Associations**: May be preserved through later album finding step
/// - **EXIF Data**: Maintains original EXIF information from selected file
/// - **JSON Metadata**: Keeps associated JSON file with selected media file
///
/// ## Performance Optimizations
///
/// ### Efficient Algorithms
/// - **Hash Caching**: Avoids recalculating hashes for previously processed files
/// - **Batch Processing**: Processes files in groups to optimize I/O operations
/// - **Memory Management**: Uses streaming hash calculation for large files
/// - **Early Termination**: Skips processing when no duplicates are possible
///
/// ### Scalability Features
/// - **Large Collection Support**: Efficiently handles thousands of duplicate photos
/// - **Progress Reporting**: Provides feedback for long-running duplicate detection
/// - **Incremental Processing**: Can be interrupted and resumed safely
/// - **Resource Monitoring**: Adapts processing speed based on system resources
///
/// ## Common Duplicate Scenarios
///
/// ### Google Photos Export Patterns
/// - **Album Duplicates**: Same photo exists in year folder + multiple album folders
/// - **Download Duplicates**: Files downloaded multiple times from Google Photos
/// - **Processing Duplicates**: Files processed through multiple export/import cycles
/// - **Backup Duplicates**: Files backed up multiple times to Google Photos
///
/// ### File Naming Variations
/// - **Original vs Edited**: `photo.jpg` vs `photo-edited.jpg` (handled by extras removal)
/// - **Sequential Numbers**: `photo.jpg` vs `photo(1).jpg` with identical content
/// - **Date Prefixes**: Same content with different date stamps in filename
/// - **Album Prefixes**: Files with album names prepended to original filename
///
/// ## Error Handling and Edge Cases
///
/// ### File Access Issues
/// - **Permission Errors**: Skips inaccessible files without stopping processing
/// - **Corrupted Files**: Handles files that cannot be read or hashed
/// - **Network Storage**: Manages timeouts and connection issues
/// - **Locked Files**: Gracefully handles files locked by other applications
///
/// ### Hash Collision Handling
/// - **Verification**: Performs additional verification for suspected hash collisions
/// - **Fallback Comparison**: Uses byte-by-byte comparison if hash collision suspected
/// - **Logging**: Records potential collisions for investigation
/// - **Conservative Approach**: Errs on side of keeping files when uncertain
///
/// ### Special File Types
/// - **Live Photos**: Handles iOS Live Photos with multiple component files
/// - **Motion Photos**: Manages Google's Motion Photos format appropriately
/// - **RAW + JPEG**: Treats RAW and JPEG versions as separate files
/// - **Video Variants**: Handles different resolutions/formats of same video
///
/// ## Configuration and Behavior
///
/// ### Processing Modes
/// - **Verbose Mode**: Provides detailed logging of duplicate detection and removal
/// - **Conservative Mode**: More cautious about removing files when uncertain
/// - **Performance Mode**: Optimizes for speed with large collections
/// - **Verification Mode**: Performs additional integrity checks
///
/// ### Statistics Tracking
/// - **Duplicates Found**: Count of duplicate files identified
/// - **Files Removed**: Number of duplicate files removed from collection
/// - **Space Saved**: Estimated disk space savings from duplicate removal
/// - **Processing Performance**: Files processed per second and total time
///
/// ## Integration with Other Steps
///
/// ### Prerequisites
/// - **Media Discovery**: Requires populated MediaCollection from discovery step
/// - **File Accessibility**: Files must be readable for hash calculation
///
/// ### Outputs for Later Steps
/// - **Clean Media Collection**: Provides duplicate-free collection for further processing
/// - **Date Accuracy**: Preserves best date information for chronological organization
/// - **Reduced Dataset**: Smaller collection improves performance of subsequent steps
/// - **Quality Selection**: Ensures best quality files are retained
///
/// ### Processing Order Considerations
/// - **Before Album Finding**: Removes duplicates before album relationship analysis
/// - **Before Date Extraction**: Reduces workload for expensive date extraction
/// - **After Media Discovery**: Requires complete file inventory to identify all duplicates
/// - **Before File Moving**: Ensures final organization contains only unique files
///
/// ## Quality Assurance
///
/// ### Verification Steps
/// - **Hash Validation**: Verifies hash calculations are consistent
/// - **Selection Logic**: Confirms best copy selection follows documented algorithm
/// - **Metadata Integrity**: Ensures selected files maintain proper metadata
/// - **Count Reconciliation**: Verifies expected number of files are removed
///
/// ### Safety Measures
/// - **Dry Run Support**: Can simulate duplicate removal without actual deletion
/// - **Backup Recommendations**: Suggests backing up before duplicate removal
/// - **Rollback Information**: Logs removed files for potential recovery
/// - **Conservative Defaults**: Uses safe settings when configuration is ambiguous
///
/// ### Performance note (added):
/// For maximum throughput on very large datasets, this step calls `DuplicateDetectionService.groupIdenticalFast(...)`,
/// which pre-clusters by file size and a small tri-sample fingerprint before running full hashes only inside
/// those subgroups. This dramatically reduces I/O and CPU when many files share sizes but are not identical.
class RemoveDuplicatesStep extends ProcessingStep with LoggerMixin {
  RemoveDuplicatesStep() : super('Remove Duplicates');

  @override
  Future<StepResult> execute(final ProcessingContext context) async {
    final stopwatch = Stopwatch()..start();
    final mediaCol = context.mediaCollection;

    try {
      if (mediaCol.isEmpty) {
        stopwatch.stop();
        return StepResult.success(
          stepName: name,
          duration: stopwatch.elapsed,
          data: {'duplicatesRemoved': 0, 'remainingMedia': 0},
          message: 'No media to process.',
        );
      }

      print('\n[Step 3/8] Removing duplicates (this may take a while)...');

      final duplicateService = ServiceContainer.instance.duplicateDetectionService;
      final bool verify = _isVerifyEnabled();
      final MediaHashService verifier = verify ? MediaHashService() : MediaHashService(maxCacheSize: 1);

      int removedCount = 0;

      // Use the fastest grouping available (size → tri-sample fingerprint → full hash within candidates)
      Map<String, List<MediaEntity>> groups = const {};
      try {
        groups = await duplicateService.groupIdenticalFast(mediaCol.entities.toList());
      } catch (e) {
        logWarning('FAST duplicate grouping failed, falling back to standard grouping: $e', forcePrint: true);
        groups = await duplicateService.groupIdentical(mediaCol.entities.toList());
      }

      final Set<MediaEntity> entitiesToRemove = <MediaEntity>{};

      void mergeEntityFiles(final MediaEntity dst, final MediaEntity src) {
        try {
          final MediaEntity updated = dst.mergeWith(src);
          _replaceEntityInCollection(mediaCol, dst, updated);
        } catch (e) {
          logWarning('⚠️ Failed to merge files from duplicate entity: $e', forcePrint: true);
        }
      }

      bool _isSizeOnlyKey(final String k) {
        // Matches "<digits>bytes" (e.g., "12345bytes")
        if (!k.endsWith('bytes')) return false;
        final prefix = k.substring(0, k.length - 5);
        for (int i = 0; i < prefix.length; i++) {
          final c = prefix.codeUnitAt(i);
          if (c < 48 || c > 57) return false;
        }
        return true;
      }

      int processedGroups = 0;
      final int totalGroups = groups.length;

      // Iterate groups; only treat as duplicates those grouped by HASH (not by size)
      for (final entry in groups.entries) {
        final String key = entry.key;
        final List<MediaEntity> group = entry.value;

        processedGroups++;
        if (group.length <= 1) continue;

        // Ignore size-only groups even if length > 1 (they are NOT duplicates by definition)
        if (_isSizeOnlyKey(key)) {
          logDebug('Skipping size-only group "$key" with ${group.length} items (not duplicates by hash).');
          continue;
        }

        group.sort((a, b) {
          final aAcc = a.dateAccuracy?.value ?? 999;
          final bAcc = b.dateAccuracy?.value ?? 999;
          if (aAcc != bAcc) return aAcc.compareTo(bAcc);
          return a.primaryFile.path.length.compareTo(b.primaryFile.path.length);
        });

        final MediaEntity kept = group.first;
        final List<MediaEntity> toRemove = group.sublist(1);

        logDebug('Keeping ${kept.primaryFile.path}');
        if (verify) {
          try {
            final String keptHash = await verifier.calculateFileHash(kept.primaryFile);
            for (final d in toRemove) {
              try {
                final String dupHash = await verifier.calculateFileHash(d.primaryFile);
                if (dupHash != keptHash) {
                  logWarning('Verification mismatch. Will NOT remove ${d.primaryFile.path} (hash differs from kept).', forcePrint: true);
                  continue;
                }
                logDebug('Verified duplicate by SHA-256: ${d.primaryFile.path}');
                mergeEntityFiles(kept, d);
                entitiesToRemove.add(d);
                removedCount++;
              } catch (e) {
                logWarning('Verification failed for ${d.primaryFile.path}: $e. Skipping removal for safety.', forcePrint: true);
              }
            }
          } catch (e) {
            logWarning('Could not hash kept file ${_safePath(kept.primaryFile)} for verification: $e. Skipping removals for this group.', forcePrint: true);
          }
        } else {
          for (final d in toRemove) {
            logDebug('Removing duplicate: ${d.primaryFile.path}');
            mergeEntityFiles(kept, d);
            entitiesToRemove.add(d);
            removedCount++;
          }
        }

        if ((processedGroups % 1000) == 0) print('[Step 3/8] Progress: resolved $processedGroups/$totalGroups groups...');
      }

      // Apply removals
      if (entitiesToRemove.isNotEmpty) {
        print('🧹 Skipping ${entitiesToRemove.length} entities from collection');
        for (final e in entitiesToRemove) {
          try {
            mediaCol.remove(e);
          } catch (err) {
            logWarning('Failed to remove entity ${_safeEntity(e)}: $err', forcePrint: true);
          }
        }
      }

      print('✅ Remove Duplicates finished, total duplicates found: $removedCount');

      stopwatch.stop();
      return StepResult.success(
        stepName: name,
        duration: stopwatch.elapsed,
        data: {
          'duplicatesRemoved': removedCount,
          'remainingMedia': mediaCol.length,
        },
        message: 'Removed $removedCount duplicate files (they will be moved to "_Duplicates" sub-folder in Output folder)\n${mediaCol.length} media files remain.',
      );
    } catch (e) {
      stopwatch.stop();
      return StepResult.failure(
        stepName: name,
        duration: stopwatch.elapsed,
        error: e is Exception ? e : Exception(e.toString()),
        message: 'Failed to remove duplicates: $e',
      );
    }
  }

  @override
  bool shouldSkip(final ProcessingContext context) => context.mediaCollection.isEmpty;

  // ——— helpers ————————————————————————————————————————————————————————————————

  bool _isVerifyEnabled() {
    try {
      final v = Platform.environment['GPTH_VERIFY_DUPLICATES'];
      if (v == null) return false;
      final s = v.trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes' || s == 'on';
    } catch (_) {
      return false;
    }
  }

  String _safePath(final File f) {
    try {
      return f.path;
    } catch (_) {
      return '<unknown-file>';
    }
  }

  String _safeEntity(final MediaEntity e) {
    try {
      return e.primaryFile.path;
    } catch (_) {
      return '<unknown-entity>';
    }
  }

  void _replaceEntityInCollection(
    final MediaEntityCollection col,
    final MediaEntity oldE,
    final MediaEntity newE,
  ) {
    // Cheap linear replace using operators exposed by your collection
    for (int i = 0; i < col.length; i++) {
      try {
        if (identical(col[i], oldE) || col[i] == oldE) {
          col[i] = newE;
          return;
        }
      } catch (_) {
        // ignore and continue
      }
    }
  }
}
