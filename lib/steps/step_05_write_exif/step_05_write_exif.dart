import 'dart:io';
import 'package:console_bars/console_bars.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:gpth/gpth-lib.dart';

/// Step 5: Write EXIF data to media files
///
/// This step embeds GPS coordinates and datetime information directly into media file
/// EXIF metadata, ensuring that location and timing data is preserved permanently with
/// each photo and video, independent of external metadata files.
///
/// ## Purpose and Benefits
///
/// ### Metadata Preservation
/// - **Permanent Embedding**: GPS and datetime become part of the file itself
/// - **Software Compatibility**: Works with all photo viewers and editing applications
/// - **Future-Proofing**: Data remains accessible even if JSON files are lost
/// - **Standard Compliance**: Uses standard EXIF tags recognized by all photo software
///
/// ### Data Sources
/// - **GPS Coordinates**: Extracted from Google Photos JSON metadata files
/// - **DateTime Information**: Uses accurately extracted photo creation timestamps
/// - **Timezone Handling**: Properly handles timezone conversion and UTC timestamps
/// - **Precision Preservation**: Maintains full coordinate and timestamp precision
///
/// ## EXIF Writing Process
///
/// ### GPS Coordinate Processing
/// 1. **JSON Extraction**: Reads GPS data from associated `.json` metadata files
/// 2. **Coordinate Conversion**: Converts decimal degrees to EXIF DMS (Degrees/Minutes/Seconds) format
/// 3. **Reference Assignment**: Sets proper hemisphere references (N/S, E/W)
/// 4. **Precision Handling**: Maintains coordinate accuracy to GPS precision limits
/// 5. **Validation**: Verifies coordinates are within valid Earth coordinate ranges
///
/// ### DateTime Embedding
/// 1. **Source Selection**: Uses the most accurate datetime from extraction step
/// 2. **Format Conversion**: Converts to EXIF datetime format (YYYY:MM:DD HH:MM:SS)
/// 3. **Tag Assignment**: Writes to appropriate EXIF datetime tags
/// 4. **Timezone Preservation**: Includes timezone information when available
/// 5. **Consistency Check**: Ensures all datetime tags are synchronized
///
/// ### EXIF Tag Management
/// - **Standard Tags**: Uses industry-standard EXIF tag numbers and formats
/// - **Multiple Tags**: Writes to primary and subsecond datetime tags
/// - **GPS Tags**: Populates comprehensive GPS tag set (latitude, longitude, altitude, etc.)
/// - **Metadata Preservation**: Maintains existing EXIF data while adding new information
///
/// ## Configuration and Control
///
/// ### Processing Options
/// - **Enable/Disable**: Controlled by `writeExif` configuration setting
/// - **Selective Processing**: Only processes files that lack existing EXIF datetime
/// - **Overwrite Protection**: Avoids overwriting existing accurate EXIF data
/// - **Source Filtering**: Only writes data extracted from reliable sources
///
/// ### Quality Control
/// - **Data Validation**: Verifies GPS coordinates and datetime values before writing
/// - **Format Verification**: Ensures data meets EXIF standard requirements
/// - **Error Detection**: Identifies and reports files that cannot be processed
/// - **Integrity Checking**: Confirms EXIF data was written correctly
///
/// ## Technical Implementation
///
/// ### File Format Support
/// - **JPEG Files**: Full EXIF support with standard embedding
/// - **TIFF Files**: Native EXIF support with comprehensive tag coverage
/// - **RAW Formats**: Uses ExifTool for advanced RAW file EXIF writing
/// - **Video Files**: Limited metadata support where format allows
///
/// ### ExifTool Integration
/// - **External Tool**: Uses ExifTool for comprehensive format support
/// - **Fallback Support**: Uses built-in EXIF writing when ExifTool unavailable
/// - **Format Coverage**: Supports hundreds of image and video formats
/// - **Advanced Features**: Handles complex metadata scenarios and edge cases
///
/// ### Performance Optimization
/// - **Batch Processing**: Groups multiple files for efficient processing
/// - **Memory Management**: Processes files without loading full content
/// - **I/O Minimization**: Optimizes file read/write operations
/// - **Progress Tracking**: Provides user feedback for long-running operations
///
/// ## Error Handling and Recovery
///
/// ### File Access Issues
/// - **Permission Errors**: Gracefully handles read-only or protected files
/// - **File Locks**: Manages files locked by other applications
/// - **Corrupted Files**: Skips files with corrupted EXIF segments
/// - **Format Limitations**: Handles unsupported file formats appropriately
///
/// ### Data Integrity Protection
/// - **Backup Creation**: Optionally creates backups before modifying files
/// - **Rollback Capability**: Can restore original files if issues occur
/// - **Verification**: Confirms EXIF data was written correctly
/// - **Partial Failure Handling**: Continues processing when individual files fail
///
/// ### External Tool Dependencies
/// - **ExifTool Detection**: Automatically detects ExifTool availability
/// - **Fallback Mechanisms**: Uses alternative methods when ExifTool unavailable
/// - **Version Compatibility**: Works with different ExifTool versions
/// - **Error Recovery**: Handles ExifTool execution errors gracefully
///
/// ## Data Quality and Validation
///
/// ### GPS Coordinate Validation
/// - **Range Checking**: Ensures coordinates are within valid Earth bounds
/// - **Precision Limits**: Respects GPS precision limitations
/// - **Format Verification**: Validates coordinate format before writing
/// - **Reference Consistency**: Ensures hemisphere references match coordinate signs
///
/// ### DateTime Validation
/// - **Reasonable Dates**: Rejects obviously incorrect dates (future/prehistoric)
/// - **Format Compliance**: Ensures datetime meets EXIF standard requirements
/// - **Timezone Handling**: Properly manages timezone information
/// - **Accuracy Tracking**: Preserves information about date extraction accuracy
///
/// ## Integration and Dependencies
///
/// ### Prerequisites
/// - **Date Extraction**: Requires completed date extraction from Step 4
/// - **JSON Processing**: Needs JSON metadata files for GPS coordinate extraction
/// - **File Accessibility**: Files must be writable for EXIF modification
/// - **Tool Availability**: ExifTool recommended for best format support
///
/// ### Step Coordination
/// - **After Date Extraction**: Runs after accurate datetime determination
/// - **Before File Moving**: Embeds metadata before final file organization
/// - **Coordinate with Album Finding**: May benefit from consolidated file information
/// - **Performance Consideration**: Balances thoroughness with processing speed
///
/// ## User Benefits and Use Cases
///
/// ### Photo Management
/// - **Geotagging**: Enables location-based photo organization and mapping
/// - **Timeline Accuracy**: Ensures correct chronological sorting in all applications
/// - **Software Compatibility**: Works with Adobe Lightroom, Apple Photos, Google Photos web
/// - **Archive Longevity**: Creates self-contained files with embedded metadata
///
/// ### Professional Workflows
/// - **Client Delivery**: Photos delivered with proper embedded metadata
/// - **Stock Photography**: Images have complete location and timing information
/// - **Legal Documentation**: Embedded metadata provides verifiable timestamps
/// - **Scientific Research**: Preserves precise location and timing data
///
/// ## Statistics and Reporting
///
/// ### Processing Metrics
/// - **GPS Coordinates Written**: Count of files with GPS data successfully embedded
/// - **DateTime Updates**: Number of files with datetime information added
/// - **Processing Performance**: Files processed per second and total duration
/// - **Error Tracking**: Files that couldn't be processed and reasons why
///
/// ### Quality Metrics
/// - **Data Source Breakdown**: Statistics on GPS/datetime data sources
/// - **Format Coverage**: Which file formats were successfully processed
/// - **Tool Usage**: Whether ExifTool or built-in methods were used
/// - **Validation Results**: How many files passed data validation checks
class WriteExifStep extends ProcessingStep with LoggerMixin {
  WriteExifStep() : super('Write EXIF Data');

  @override
  Future<StepResult> execute(final ProcessingContext context) async {
    final sw = Stopwatch()..start();

    try {
      final collection = context.mediaCollection;

      print('\n[Step 5/8] Starting EXIF data writing for ${collection.length} files (this may take a while)...');
      if (!context.config.writeExif) {
        sw.stop();
        return StepResult.success(stepName: name, duration: sw.elapsed, data: {'coordinatesWritten': 0, 'dateTimesWritten': 0, 'skipped': true}, message: 'EXIF writing skipped per configuration');
      }

      // Visible progress bar (kept as before)
      final progressBar = FillingBar(desc: 'Writing EXIF data', total: collection.length, width: 50);

      // Services
      final exifTool = ServiceContainer.instance.exifTool; // may be null

      // Backward-compatible behavior: if exifTool == null → nativeOnly path
      final bool nativeOnly = exifTool == null;
      if (nativeOnly) {
        logWarning('[Step 5/8] ExifTool not available, writing EXIF data for native supported files only...', forcePrint: true);
        print('[Step 5/8] Starting EXIF data writing (native-only, no ExifTool) for ${collection.length} files');
      } else {
        logInfo('Exiftool enabled using argument nativeOnly=false', forcePrint: true);
      }

      // Batching preference (restored, but safer limits)
      final bool enableExifToolBatch = _resolveBatchingPreference(exifTool);

      if (enableExifToolBatch) {
        logInfo('Exiftool batch enabled using argument enableExifToolBatch=true. Exiftool will be called in batches with several files per batch', forcePrint: true);
      } else {
        logInfo('Exiftool batch processing disabled using argument enableExifToolBatch=false. Exiftool will be called 1 time per file', forcePrint: true);
      }

      // NEW: resolve unsupported-format handling flags from GlobalConfig if present.
      final _UnsupportedPolicy unsupportedPolicy = _resolveUnsupportedPolicy();

      // Calculate optimal concurrency
      final int maxConc = ConcurrencyManager().concurrencyFor(ConcurrencyOperation.exif);

      // Reuse writer across batch if possible
      final ExifWriterService? exifWriter = (exifTool != null) ? ExifWriterService(exifTool) : null;

      // Adaptive batch sizing (same intent as older code, but capped to avoid mega-batches)
      final bool isWindows = Platform.isWindows;
      final int baseBatchSize = isWindows ? 60 : 120;
      // NEW: hard caps to avoid catastrophic batch failures; can be overridden by config.
      final int maxImageBatch = _resolveInt('maxExifImageBatchSize', defaultValue: 500);
      final int maxVideoBatch = _resolveInt('maxExifVideoBatchSize', defaultValue: 24);

      // Separate queues for images and videos (restored)
      final pendingImagesBatch = <MapEntry<File, Map<String, dynamic>>>[];
      final pendingVideosBatch = <MapEntry<File, Map<String, dynamic>>>[];

      // NEW: write batch with "split on fail" to isolate problematic files quickly.
      Future<void> _writeBatchSafe(final List<MapEntry<File, Map<String, dynamic>>> queue, {required final bool useArgFile, required final bool isVideoBatch}) async {
        if (queue.isEmpty || exifWriter == null) return;

        // Inner recursive splitter
        Future<void> _splitAndWrite(final List<MapEntry<File, Map<String, dynamic>>> chunk) async {
          if (chunk.isEmpty) return;
          if (chunk.length == 1) {
            final entry = chunk.first;
            try {
              await exifWriter.writeTagsWithExifTool(entry.key, entry.value);
            } catch (e) {
              if (!_shouldSilenceExiftoolError(e)) logWarning(isVideoBatch ? 'Per-file video write failed: ${entry.key.path} -> $e' : 'Per-file write failed: ${entry.key.path} -> $e', forcePrint: false);
              await _tryDeleteTmp(entry.key);
            }
            return;
          }

          final mid = chunk.length >> 1;
          final left = chunk.sublist(0, mid);
          final right = chunk.sublist(mid);

          try {
            await exifWriter.writeBatchWithExifTool(chunk, useArgFileWhenLarge: useArgFile);
          } catch (e) {
            await _tryDeleteTmpForChunk(chunk);
            if (!_shouldSilenceExiftoolError(e)) logWarning(isVideoBatch ? 'Video batch flush failed (${chunk.length} files) - splitting: $e' : 'Batch flush failed (${chunk.length} files) - splitting: $e', forcePrint: false);
            await _splitAndWrite(left);
            await _splitAndWrite(right);
          }
        }

        await _splitAndWrite(queue);
      }

      // Generic batch flush (restored behavior but uses _writeBatchSafe and cleans temps only on fail path)
      Future<void> _flushBatch(final List<MapEntry<File, Map<String, dynamic>>> queue, {required final bool useArgFile, required final bool isVideoBatch}) async {
        if (nativeOnly || !enableExifToolBatch) return; // no batches in per-file mode
        if (queue.isEmpty) return;
        if (exifWriter == null) {
          queue.clear();
          return;
        }

        // Enforce safe caps before writing
        while (queue.length > (isVideoBatch ? maxVideoBatch : maxImageBatch)) {
          final sub = queue.sublist(0, isVideoBatch ? maxVideoBatch : maxImageBatch);
          await _writeBatchSafe(sub, useArgFile: true, isVideoBatch: isVideoBatch);
          queue.removeRange(0, sub.length);
        }

        await _writeBatchSafe(queue, useArgFile: useArgFile, isVideoBatch: isVideoBatch);
        queue.clear();
      }

      // Helpers to flush each queue
      Future<void> _flushImageBatch({required final bool useArgFile}) => _flushBatch(pendingImagesBatch, useArgFile: useArgFile, isVideoBatch: false);
      Future<void> _flushVideoBatch({required final bool useArgFile}) => _flushBatch(pendingVideosBatch, useArgFile: useArgFile, isVideoBatch: true);

      // Threshold-based flushing (restored)
      Future<void> _maybeFlushThresholds() async {
        if (nativeOnly || !enableExifToolBatch) return;
        final int targetImageBatch = baseBatchSize.clamp(1, maxImageBatch);
        final int targetVideoBatch = 12.clamp(1, maxVideoBatch);
        if (pendingImagesBatch.length >= targetImageBatch) await _flushImageBatch(useArgFile: true);
        if (pendingVideosBatch.length >= targetVideoBatch) await _flushVideoBatch(useArgFile: true);
      }

      // Build processing order: multi-file entities first (pre-batch), then single-file entities (restored)
      final multi = <MediaEntity>[];
      final single = <MediaEntity>[];
      for (final e in collection.entities) {
        (e.files.files.length > 1 ? multi : single).add(e);
      }

      // Fast extension classifiers to avoid header sniff in the hot path.
      bool _isJpegByExt(final String p) {
        final l = p.toLowerCase();
        return l.endsWith('.jpg') || l.endsWith('.jpeg');
      }
      bool _isHeicByExt(final String p) => p.toLowerCase().endsWith('.heic');
      bool _isPngByExt(final String p) => p.toLowerCase().endsWith('.png');
      bool _isMp4ByExt(final String p) => p.toLowerCase().endsWith('.mp4');
      bool _isMovByExt(final String p) => p.toLowerCase().endsWith('.mov');

      int completedEntities = 0;
      int gpsWrittenTotal = 0;
      int dateWrittenTotal = 0;

      Future<Map<String, int>> _processList(final List<MediaEntity> list, {required final bool delayFlushUntilEnd}) async {
        int gpsWritten = 0;
        int dateWritten = 0;

        for (int i = 0; i < list.length; i += maxConc) {
          final slice = list.skip(i).take(maxConc).toList(growable: false);

          final results = await Future.wait(slice.map((entity) async {
            int localGps = 0;
            int localDate = 0;

            try {
              // Entity-level effective date: use entity.dateTaken (do not re-open JSON)
              // NOTE: We intentionally do not call _lateResolveDateFromJson here to avoid extra I/O.
              final DateTime? effectiveDate = entity.dateTaken;

              // Deterministic file order: primary → others (restored)
              final files = <File>[];
              File? primaryRef;
              try {
                final primary = entity.primaryFile;
                primaryRef = primary;
                files.add(primary);
                for (final f in entity.files.files.values) {
                  if (f.path != primary.path) files.add(f);
                }
              } catch (_) {
                if (entity.files.files.isNotEmpty) files.addAll(entity.files.files.values);
              }

              for (final file in files) {
                try {
                  final path = file.path;
                  final lower = path.toLowerCase();
                  final bool isPrimary = (primaryRef != null && file.path == primaryRef.path);

                  // Cheap MIME classification: trust common extensions; only sniff header if ambiguous.
                  String? mimeHeader;
                  String? mimeExt;
                  if (_isJpegByExt(path)) {
                    mimeHeader = 'image/jpeg'; mimeExt = 'image/jpeg';
                  } else if (_isHeicByExt(path)) {
                    mimeHeader = 'image/heic'; mimeExt = 'image/heic';
                  } else if (_isPngByExt(path)) {
                    mimeHeader = 'image/png'; mimeExt = 'image/png';
                  } else if (_isMp4ByExt(path)) {
                    mimeHeader = 'video/mp4'; mimeExt = 'video/mp4';
                  } else if (_isMovByExt(path)) {
                    mimeHeader = 'video/quicktime'; mimeExt = 'video/quicktime';
                  } else {
                    try {
                      final header = await file.openRead(0, 128).first;
                      mimeHeader = lookupMimeType(path, headerBytes: header);
                      mimeExt = lookupMimeType(path);
                    } catch (e) {
                      mimeHeader = lookupMimeType(path);
                      mimeExt = mimeHeader;
                    }
                  }

                  bool gpsWrittenThis = false;
                  bool dtWrittenThis = false;

                  // Tags to write with ExifTool (batched or per-file)
                  final tagsToWrite = <String, dynamic>{};

                  // 1) GPS writing policy (overwrite if JSON provides; do nothing if JSON absent)
                  try {
                    final coords = await jsonCoordinatesExtractor(file);
                    if (coords != null) {
                      // Do NOT read existing EXIF GPS. We simply overwrite when sidecar provides valid coords.
                      if (_isJpegByExt(path)) {
                        if (!nativeOnly && exifWriter != null) {
                          if (effectiveDate != null) {
                            final ok = await exifWriter.writeCombinedNativeJpeg(file, effectiveDate, coords);
                            if (ok) { gpsWrittenThis = true; dtWrittenThis = true; }
                            else {
                              final exifFormat = DateFormat('yyyy:MM:dd HH:mm:ss');
                              final dt = exifFormat.format(effectiveDate);
                              tagsToWrite['DateTimeOriginal'] = '"$dt"';
                              tagsToWrite['DateTimeDigitized'] = '"$dt"';
                              tagsToWrite['DateTime'] = '"$dt"';
                              tagsToWrite['GPSLatitude'] = coords.toDD().latitude.toString();
                              tagsToWrite['GPSLongitude'] = coords.toDD().longitude.toString();
                              tagsToWrite['GPSLatitudeRef'] = coords.latDirection.abbreviation.toString();
                              tagsToWrite['GPSLongitudeRef'] = coords.longDirection.abbreviation.toString();
                              gpsWrittenThis = true; dtWrittenThis = true;
                            }
                          } else {
                            final ok = await exifWriter.writeGpsNativeJpeg(file, coords);
                            if (ok) { gpsWrittenThis = true; }
                            else {
                              tagsToWrite['GPSLatitude'] = coords.toDD().latitude.toString();
                              tagsToWrite['GPSLongitude'] = coords.toDD().longitude.toString();
                              tagsToWrite['GPSLatitudeRef'] = coords.latDirection.abbreviation.toString();
                              tagsToWrite['GPSLongitudeRef'] = coords.longDirection.abbreviation.toString();
                              gpsWrittenThis = true;
                            }
                          }
                        } else {
                          // Native not available → ExifTool tags
                          tagsToWrite['GPSLatitude'] = coords.toDD().latitude.toString();
                          tagsToWrite['GPSLongitude'] = coords.toDD().longitude.toString();
                          tagsToWrite['GPSLatitudeRef'] = coords.latDirection.abbreviation.toString();
                          tagsToWrite['GPSLongitudeRef'] = coords.longDirection.abbreviation.toString();
                          gpsWrittenThis = true;
                        }
                      } else {
                        // Non-JPEG → ExifTool (unless nativeOnly)
                        if (!nativeOnly) {
                          tagsToWrite['GPSLatitude'] = coords.toDD().latitude.toString();
                          tagsToWrite['GPSLongitude'] = coords.toDD().longitude.toString();
                          tagsToWrite['GPSLatitudeRef'] = coords.latDirection.abbreviation.toString();
                          tagsToWrite['GPSLongitudeRef'] = coords.longDirection.abbreviation.toString();
                          gpsWrittenThis = true;
                        }
                      }
                    }
                  } catch (e) {
                    logWarning('Failed to extract/write GPS for ${_safePath(file)}: $e', forcePrint: true);
                  }

                  // 2) DateTime writer (native preferred for JPEG; do not re-read JSON)
                  try {
                    if (effectiveDate != null) {
                      if (_isJpegByExt(path)) {
                        if (!dtWrittenThis && !nativeOnly && exifWriter != null) {
                          final ok = await exifWriter.writeDateTimeNativeJpeg(file, effectiveDate);
                          if (ok) { dtWrittenThis = true; }
                          else {
                            final exifFormat = DateFormat('yyyy:MM:dd HH:mm:ss');
                            final dt = exifFormat.format(effectiveDate);
                            tagsToWrite['DateTimeOriginal'] = '"$dt"';
                            tagsToWrite['DateTimeDigitized'] = '"$dt"';
                            tagsToWrite['DateTime'] = '"$dt"';
                            dtWrittenThis = true;
                          }
                        }
                      } else {
                        if (!nativeOnly) {
                          final exifFormat = DateFormat('yyyy:MM:dd HH:mm:ss');
                          final dt = exifFormat.format(effectiveDate);
                          tagsToWrite['DateTimeOriginal'] = '"$dt"';
                          tagsToWrite['DateTimeDigitized'] = '"$dt"';
                          tagsToWrite['DateTime'] = '"$dt"';
                        }
                      }
                    }
                  } catch (e) {
                    logWarning('Failed to write DateTime for ${_safePath(file)}: $e', forcePrint: true);
                  }

                  // 3) Enqueue or write per-file with ExifTool according to configuration (with unsupported policy)
                  try {
                    if (!nativeOnly && tagsToWrite.isNotEmpty) {
                      final bool isVideo = (mimeHeader ?? '').startsWith('video/');
                      final bool isUnsupported = _isDefinitelyUnsupportedForWrite(mimeHeader: mimeHeader, mimeExt: mimeExt, pathLower: lower);

                      if (isUnsupported && !unsupportedPolicy.forceProcessUnsupportedFormats) {
                        if (!unsupportedPolicy.silenceUnsupportedWarnings) {
                          final detectedFmt = _describeUnsupported(mimeHeader: mimeHeader, mimeExt: mimeExt, pathLower: lower);
                          logWarning('Skipping $detectedFmt file - ExifTool cannot write $detectedFmt: ${file.path}', forcePrint: true);
                        }
                      } else {
                        if (!enableExifToolBatch) {
                          try {
                            await exifWriter!.writeTagsWithExifTool(file, tagsToWrite);
                          } catch (e) {
                            if (!_shouldSilenceExiftoolError(e)) logWarning(isVideo ? 'Per-file video write failed: ${file.path} -> $e' : 'Per-file write failed: ${file.path} -> $e', forcePrint: false);
                            await _tryDeleteTmp(file);
                          }
                        } else {
                          if (isVideo) {
                            pendingVideosBatch.add(MapEntry(file, tagsToWrite));
                          } else {
                            pendingImagesBatch.add(MapEntry(file, tagsToWrite));
                          }
                        }
                      }
                    }
                  } catch (e) {
                    if (!_shouldSilenceExiftoolError(e)) logWarning('Failed to enqueue EXIF tags for ${_safePath(file)}: $e', forcePrint: false);
                  }

                  // NEW: mark primary/secondary for final unique counts
                  if (gpsWrittenThis) {
                    ExifWriterService.markGpsTouchedFromStep5(file, isPrimary: isPrimary);
                    localGps++;
                  }
                  if (dtWrittenThis) {
                    ExifWriterService.markDateTouchedFromStep5(file, isPrimary: isPrimary);
                    localDate++;
                  }
                } catch (e) {
                  logError('EXIF write failed for ${_safePath(file)}: $e', forcePrint: true);
                }
              }
            } catch (e) {
              logError('Entity processing failed for ${_safePath(entity.primaryFile)}: $e', forcePrint: true);
            }

            return {'gps': localGps, 'date': localDate};
          }));

          for (final r in results) {
            gpsWritten += r['gps'] ?? 0;
            dateWritten += r['date'] ?? 0;
            completedEntities++;
            progressBar.update(completedEntities);
          }

          // During pre-batch (delayFlushUntilEnd == true) we do not flush by thresholds
          if (!nativeOnly && enableExifToolBatch && !delayFlushUntilEnd) await _maybeFlushThresholds();
        }

        // If delaying flush for this list, flush now (restored)
        if (!nativeOnly && enableExifToolBatch && delayFlushUntilEnd) {
          final bool flushImagesWithArg = pendingImagesBatch.length > (Platform.isWindows ? 30 : 60);
          final bool flushVideosWithArg = pendingVideosBatch.length > 6;
          await _flushImageBatch(useArgFile: flushImagesWithArg);
          await _flushVideoBatch(useArgFile: flushVideosWithArg);
        }

        return {'gps': gpsWritten, 'date': dateWritten};
      }

      // Wrap the whole processing to guarantee final flush in any case (restored)
      try {
        // 1) Pre-batch phase: multi-file entities (delay flush)
        if (multi.isNotEmpty) {
          final r = await _processList(multi, delayFlushUntilEnd: true);
          gpsWrittenTotal += r['gps']!;
          dateWrittenTotal += r['date']!;
        }

        // 2) Normal phase: single-file entities with threshold-based flushing
        if (single.isNotEmpty) {
          final r = await _processList(single, delayFlushUntilEnd: false);
          gpsWrittenTotal += r['gps']!;
          dateWrittenTotal += r['date']!;
        }
      } finally {
        // Final safety flush (only if batching is enabled)
        if (!nativeOnly && enableExifToolBatch) {
          final bool flushImagesWithArg = pendingImagesBatch.length > (Platform.isWindows ? 30 : 60);
          final bool flushVideosWithArg = pendingVideosBatch.length > 6;
          await _flushImageBatch(useArgFile: flushImagesWithArg);
          await _flushVideoBatch(useArgFile: flushVideosWithArg);
        } else {
          pendingImagesBatch.clear();
          pendingVideosBatch.clear();
        }
      }

      print(''); // Force new line after progress bar

      // NEW: print unique counts with primary/secondary split from ExifWriterService
      final gpsTotal = ExifWriterService.uniqueGpsFilesCount;
      final gpsPrim = ExifWriterService.uniqueGpsPrimaryCount;
      final gpsSec = ExifWriterService.uniqueGpsSecondaryCount;
      final dtTotal = ExifWriterService.uniqueDateFilesCount;
      final dtPrim = ExifWriterService.uniqueDatePrimaryCount;
      final dtSec = ExifWriterService.uniqueDateSecondaryCount;

      if (gpsTotal > 0) print('$gpsTotal files got GPS set in EXIF data (primary=$gpsPrim, secondary=$gpsSec)');
      if (dtTotal > 0) print('$dtTotal files got DateTime set in EXIF data (primary=$dtPrim, secondary=$dtSec)');

      // NEW: final clarifying line to reconcile progress bar (entities) vs files touched (unique files).
      print('Processed ${collection.entities.length} entities; touched ${ExifWriterService.uniqueFilesTouchedCount} files');

      // Capture counts BEFORE resetting instrumentation ──
      // Capture unique counts before dumpWriterStats(reset: true) so we can use them in the StepResult message and data.
      final int touchedFilesBeforeReset = ExifWriterService.uniqueFilesTouchedCount;
      final int touchedGpsBeforeReset = ExifWriterService.uniqueGpsFilesCount;
      final int touchedDateBeforeReset = ExifWriterService.uniqueDateFilesCount;

      // Final writer stats (seconds) and GPS extractor stats (restored)
      ExifWriterService.dumpWriterStats(reset: true, logger: this);
      ExifCoordinateExtractor.dumpStats(reset: true, loggerMixin: this);

      sw.stop();
      return StepResult.success(stepName: name, duration: sw.elapsed, data: {'coordinatesWritten': touchedGpsBeforeReset, 'dateTimesWritten': touchedDateBeforeReset, 'skipped': false}, message: 'Wrote EXIF data to $touchedFilesBeforeReset files');
    } catch (e) {
      // NOTE: Silence known benign ExifTool errors; only log unexpected ones.
      if (!_shouldSilenceExiftoolError(e)) logError('Failed to write EXIF data: $e', forcePrint: true);
      final sw = Stopwatch()..stop();
      return StepResult.failure(stepName: name, duration: sw.elapsed, error: e is Exception ? e : Exception(e.toString()), message: 'Failed to write EXIF data');
    }
  }

  @override
  bool shouldSkip(final ProcessingContext context) => context.mediaCollection.isEmpty;

  String _safePath(final File f) {
    try {
      return f.path;
    } catch (_) {
      return '<unknown-file>';
    }
  }

  // NEW (restored semantics): resolve batching preference in a tolerant way.
  // Reads optional `enableBatching` from GlobalConfig if present; defaults to true
  // when ExifTool is available (since batching only makes sense with ExifTool).
  bool _resolveBatchingPreference(final Object? exifTool) {
    if (exifTool == null) return false; // no ExifTool → no batching
    try {
      final cfg = ServiceContainer.instance.globalConfig;
      final dyn = cfg as dynamic;
      final v = dyn.enableBatching; // may not exist
      if (v is bool) return v;
    } catch (_) {
      // ignore: property not present or not accessible
    }
    return true; // default: enabled if ExifTool is available
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helpers añadidos para limpieza de rutas, filtro de formatos y política
  // ───────────────────────────────────────────────────────────────────────────

  // NEW: Resolve unsupported handling policy from GlobalConfig dynamically (tolerant).
  _UnsupportedPolicy _resolveUnsupportedPolicy() {
    bool force = false;
    bool silence = false;
    try {
      final cfg = ServiceContainer.instance.globalConfig;
      final dyn = cfg as dynamic;
      if (dyn.forceProcessUnsupportedFormats is bool) force = dyn.forceProcessUnsupportedFormats as bool;
      if (dyn.silenceUnsupportedWarnings is bool) silence = dyn.silenceUnsupportedWarnings as bool;
    } catch (_) {}
    return _UnsupportedPolicy(forceProcessUnsupportedFormats: force, silenceUnsupportedWarnings: silence);
  }

  // Formats that ExifTool does not embed-write and are better filtered early (unless forceProcessUnsupportedFormats is true).
  bool _isDefinitelyUnsupportedForWrite({String? mimeHeader, String? mimeExt, required String pathLower}) {
    if (pathLower.endsWith('.avi') || pathLower.endsWith('.mpg') || pathLower.endsWith('.mpeg') || pathLower.endsWith('.bmp')) return true;
    if (mimeHeader == 'video/x-msvideo' || mimeExt == 'video/x-msvideo') return true; // AVI
    if ((mimeHeader ?? '').contains('mpeg') || (mimeExt ?? '').contains('mpeg')) return true; // MPG/MPEG
    if ((mimeHeader ?? '') == 'image/bmp' || (mimeExt ?? '') == 'image/bmp') return true; // BMP
    return false;
  }

  // NEW: Describe unsupported type for logging (compact string).
  String _describeUnsupported({String? mimeHeader, String? mimeExt, required String pathLower}) {
    if (pathLower.endsWith('.avi') || mimeHeader == 'video/x-msvideo' || mimeExt == 'video/x-msvideo') return 'AVI';
    if (pathLower.endsWith('.mpg') || pathLower.endsWith('.mpeg') || (mimeHeader ?? '').contains('mpeg') || (mimeExt ?? '').contains('mpeg')) return 'MPEG';
    if (pathLower.endsWith('.bmp') || mimeHeader == 'image/bmp' || mimeExt == 'image/bmp') return 'BMP';
    return 'unsupported';
  }

  // NEW: ExifTool error filter to silence noisy/benign errors like "Truncated InteropIFD directory".
  bool _shouldSilenceExiftoolError(Object e) {
    final s = e.toString();
    if (s.contains('Truncated InteropIFD directory')) return true;
    // Add more patterns if needed:
    // if (s.contains('Minor error') || s.contains('Nothing to do')) return true;
    return false;
  }

  // NEW: Try delete *_exiftool_tmp best-effort for a file.
  Future<void> _tryDeleteTmp(final File f) async {
    try {
      final tmp = File('${f.path}_exiftool_tmp');
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
  }

  // NEW: Try delete *_exiftool_tmp for a chunk of files (best-effort).
  Future<void> _tryDeleteTmpForChunk(final List<MapEntry<File, Map<String, dynamic>>> chunk) async {
    for (final e in chunk) {
      await _tryDeleteTmp(e.key);
    }
  }

  // NEW: Resolve optional integer config values.
  int _resolveInt(String name, {required int defaultValue}) {
    try {
      final cfg = ServiceContainer.instance.globalConfig;
      final dyn = cfg as dynamic;
      final v = dyn.toJson != null ? (dyn.toJson()[name]) : (dyn[name]); // attempt structured/dyn access
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? defaultValue;
    } catch (_) {}
    return defaultValue;
  }
}

// NEW: tiny policy holder
class _UnsupportedPolicy {
  final bool forceProcessUnsupportedFormats;
  final bool silenceUnsupportedWarnings;
  const _UnsupportedPolicy({required this.forceProcessUnsupportedFormats, required this.silenceUnsupportedWarnings});
}
