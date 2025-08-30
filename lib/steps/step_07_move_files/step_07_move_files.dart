import 'dart:io';
import 'package:console_bars/console_bars.dart';
import 'package:gpth/gpth-lib.dart';

/// Step 7: Move files to output directory
///
/// After moving the primary file of each entity to ALL_PHOTOS (date structure),
/// this step restores album membership **from the entity metadata** but
/// **always using the single primary file as source**, according to the chosen strategy:
///
/// - Shortcut Mode: create symlinks/hardlinks in each album to the primary's final path.
/// - Duplicate-Copy Mode: copy the primary into each album folder.
/// - Reverse Shortcut Mode: move the primary physically to one canonical album
///   and create shortcuts from ALL_PHOTOS (and the other albums) pointing to that file.
/// - JSON Mode / Nothing Mode: no album folders.
class MoveFilesStep extends ProcessingStep {
  const MoveFilesStep() : super('Move Files');

  @override
  Future<StepResult> execute(final ProcessingContext context) async {
    print('');
    final stopwatch = Stopwatch()..start();

    try {
      print(
        '\n[Step 7/8] Moving files to Outputt folder (this may take a while)...',
      );
      // Optional Pixel MP/MV transformation
      int transformedCount = 0;
      if (context.config.transformPixelMp) {
        transformedCount = await _transformPixelFiles(context);
        if (context.config.verbose) {
          print('Transformed $transformedCount Pixel .MP/.MV files to .mp4');
        }
      }

      // Progress bar aligned with "primary files moved" (one per entity)
      final progressBar = FillingBar(
        desc: 'Moving primary files',
        total: context.mediaCollection.length,
        width: 50,
      );

      // Moving context
      final movingContext = MovingContext(
        outputDirectory: context.outputDirectory,
        dateDivision: context.config.dateDivision,
        albumBehavior: context.config.albumBehavior,
      );

      // Moving service
      final movingService = MediaEntityMovingService();

      // Collect source files (pre-run)
      final originalSourceFiles = <File>[];
      for (final mediaEntity in context.mediaCollection.media) {
        for (final entry in mediaEntity.files.files.entries) {
          originalSourceFiles.add(entry.value);
        }
      }

      int entitiesProcessed = 0;
      await for (final _ in movingService.moveMediaEntities(
        context.mediaCollection,
        movingContext,
      )) {
        entitiesProcessed++;
        progressBar.update(entitiesProcessed);
      }

      // Counters from moving phase
      int primaryMovedCount = 0;
      int duplicatesMovedCount = 0;
      int symlinksCreated = 0;

      String norm(final String p) => p.replaceAll('\\', '/').toLowerCase();

      // Count operations (but do NOT read any "destination" from results)
      for (final r in movingService.lastResults) {
        if (!r.success) continue;
        switch (r.operation.operationType) {
          case MediaEntityOperationType.move:
            final srcNorm = norm(r.operation.sourceFile.path);
            final primNorm = norm(r.operation.mediaEntity.primaryFile.path);
            if (srcNorm == primNorm) {
              primaryMovedCount++;
            } else {
              duplicatesMovedCount++;
            }
            break;
          case MediaEntityOperationType.createSymlink:
          case MediaEntityOperationType.createReverseSymlink:
            symlinksCreated++;
            break;
          case MediaEntityOperationType.copy:
          case MediaEntityOperationType.createJsonReference:
            // not counted in headline
            break;
        }
      }

      // === Restore album membership from entity (using ONLY the primary as source) ===
      // Compare by string value to avoid depending on enum type here.
      final String albumBehaviorValue = context.config.albumBehavior.value;

      final bool buildAlbumFolders =
          albumBehaviorValue == 'shortcut' ||
          albumBehaviorValue == 'duplicate-copy' ||
          albumBehaviorValue == 'reverse-shortcut';

      if (buildAlbumFolders) {
        final Directory albumsRoot = Directory(
          _join(context.outputDirectory.path, 'ALBUMS'),
        );
        final Directory allPhotosRoot = Directory(
          _join(context.outputDirectory.path, 'ALL_PHOTOS'),
        );

        if (!albumsRoot.existsSync()) {
          albumsRoot.createSync(recursive: true);
        }
        if (!allPhotosRoot.existsSync()) {
          allPhotosRoot.createSync(recursive: true);
        }

        for (final entity in context.mediaCollection.media) {
          // Albums where the entity belonged (keys on files map where key != null)
          final List<String> albumNames =
              entity.files.files.keys
                  .where((final k) => k != null && k.trim().isNotEmpty)
                  .map((final k) => k!.trim())
                  .toSet()
                  .toList()
                ..sort(
                  (final a, final b) =>
                      a.toLowerCase().compareTo(b.toLowerCase()),
                );

          if (albumNames.isEmpty) continue;

          // AFTER moving, the entity.primaryFile should point to the FINAL path.
          final File primaryDest = entity.primaryFile;
          if (!primaryDest.existsSync()) {
            if (context.config.verbose) {
              print(
                'Warning: Primary destination not found on disk for ${entity.primaryFile.path}. Skipping album restore.',
              );
            }
            continue;
          }

          // Reverse Shortcut: select canonical album (first alphabetically)
          String? canonicalAlbum;
          if (albumBehaviorValue == 'reverse-shortcut') {
            canonicalAlbum = albumNames.first;
          }

          // Prepare canonical physical target path when needed
          File? canonicalPhysical;
          if (albumBehaviorValue == 'reverse-shortcut') {
            final Directory canonicalDir = Directory(
              _join(albumsRoot.path, _sanitizeAlbum(canonicalAlbum!)),
            );
            if (!canonicalDir.existsSync()) {
              canonicalDir.createSync(recursive: true);
            }

            final String targetName = _sanitizeFileName(
              primaryDest.uri.pathSegments.isNotEmpty
                  ? primaryDest.uri.pathSegments.last
                  : primaryDest.path.split(Platform.pathSeparator).last,
            );
            final File newPhysical = File(_join(canonicalDir.path, targetName));

            if (norm(primaryDest.path) != norm(newPhysical.path)) {
              try {
                _ensureParentDir(newPhysical);
                if (newPhysical.existsSync()) {
                  final File unique = _uniquePath(newPhysical);
                  primaryDest.renameSync(unique.path);
                  canonicalPhysical = unique;
                } else {
                  primaryDest.renameSync(newPhysical.path);
                  canonicalPhysical = newPhysical;
                }
              } catch (e) {
                // If moving fails, keep original and fallback to shortcuts from ALL_PHOTOS
                canonicalPhysical = primaryDest;
                if (context.config.verbose) {
                  print(
                    'Warning: Reverse move failed (${primaryDest.path} -> ${newPhysical.path}): $e',
                  );
                }
              }
            } else {
              canonicalPhysical = primaryDest;
            }

            // Create shortcut in ALL_PHOTOS pointing back to canonicalPhysical
            try {
              final String linkName = canonicalPhysical.uri.pathSegments.last;
              final File linkAtAllPhotos = File(
                _join(allPhotosRoot.path, linkName),
              );
              final created = await _createShortcutOrLink(
                target: canonicalPhysical,
                link: linkAtAllPhotos,
                verbose: context.config.verbose,
              );
              if (created) symlinksCreated++;
            } catch (e) {
              if (context.config.verbose) {
                print(
                  'Warning: Failed to create ALL_PHOTOS reverse shortcut: $e',
                );
              }
            }
          }

          // For each album, create either shortcut/hardlink or copy
          for (final rawAlbum in albumNames) {
            final String albumName = _sanitizeAlbum(rawAlbum);
            final Directory albumDir = Directory(
              _join(albumsRoot.path, albumName),
            );
            if (!albumDir.existsSync()) {
              albumDir.createSync(recursive: true);
            }

            final File sourceFile = (albumBehaviorValue == 'reverse-shortcut')
                ? (canonicalPhysical ?? primaryDest)
                : primaryDest;

            final File albumTarget = File(
              _join(albumDir.path, sourceFile.uri.pathSegments.last),
            );

            switch (albumBehaviorValue) {
              case 'shortcut':
                {
                  final bool created = await _createShortcutOrLink(
                    target: sourceFile,
                    link: albumTarget,
                    verbose: context.config.verbose,
                  );
                  if (created) symlinksCreated++;
                  break;
                }
              case 'duplicate-copy':
                {
                  try {
                    _ensureParentDir(albumTarget);
                    if (!albumTarget.existsSync()) {
                      sourceFile.copySync(albumTarget.path);
                      duplicatesMovedCount++;
                    }
                  } catch (e) {
                    print(
                      'Warning: Failed to copy primary to album "$albumName": $e',
                    );
                  }
                  break;
                }
              case 'reverse-shortcut':
                {
                  if (albumName.toLowerCase() !=
                      _sanitizeAlbum(canonicalAlbum!).toLowerCase()) {
                    final bool created = await _createShortcutOrLink(
                      target: canonicalPhysical ?? sourceFile,
                      link: albumTarget,
                      verbose: context.config.verbose,
                    );
                    if (created) symlinksCreated++;
                  }
                  break;
                }
              default:
                // JSON / Nothing do not place anything in album folders here.
                break;
            }
          }
        }
      }

      // Post-run verification
      _diagnoseLeftovers(
        originalSourceFiles: originalSourceFiles,
        results: movingService.lastResults,
        verbose: context.config.verbose,
      );

      stopwatch.stop();
      return StepResult.success(
        stepName: name,
        duration: stopwatch.elapsed,
        data: {
          'entitiesProcessed': entitiesProcessed,
          'transformedCount': transformedCount,
          'albumBehavior': context.config.albumBehavior.value,
          'primaryMovedCount': primaryMovedCount,
          'duplicatesMovedCount': duplicatesMovedCount,
          'symlinksCreated': symlinksCreated,
        },
        message:
            'Moved $primaryMovedCount primary files, $duplicatesMovedCount duplicates, '
            'and created $symlinksCreated symlinks'
            '${transformedCount > 0 ? ', transformed $transformedCount Pixel files to .mp4' : ''}',
      );
    } catch (e) {
      stopwatch.stop();
      return StepResult.failure(
        stepName: name,
        duration: stopwatch.elapsed,
        error: e is Exception ? e : Exception(e.toString()),
        message: 'Failed to move files: $e',
      );
    }
  }

  @override
  bool shouldSkip(final ProcessingContext context) =>
      context.mediaCollection.isEmpty;

  /// Transform Pixel .MP/.MV files to .mp4 extension (in-place rename).
  Future<int> _transformPixelFiles(final ProcessingContext context) async {
    int transformedCount = 0;
    final updatedEntities = <MediaEntity>[];

    for (final mediaEntity in context.mediaCollection.media) {
      var hasChanges = false;
      final updatedFiles = <String?, File>{};

      for (final entry in mediaEntity.files.files.entries) {
        final albumName = entry.key;
        final file = entry.value;
        final String currentPath = file.path;
        final String extension = currentPath.toLowerCase();

        if (extension.endsWith('.mp') || extension.endsWith('.mv')) {
          final String newPath =
              '${currentPath.substring(0, currentPath.lastIndexOf('.'))}.mp4';
          try {
            await file.rename(newPath);
            updatedFiles[albumName] = File(newPath);
            hasChanges = true;
            transformedCount++;
          } catch (e) {
            updatedFiles[albumName] = file;
            print('Warning: Failed to transform ${file.path}: $e');
          }
        } else {
          updatedFiles[albumName] = file;
        }
      }

      if (hasChanges) {
        final newFilesCollection = MediaFilesCollection.fromMap(updatedFiles);
        final updatedEntity = MediaEntity(
          files: newFilesCollection,
          dateTaken: mediaEntity.dateTaken,
          dateAccuracy: mediaEntity.dateAccuracy,
          dateTimeExtractionMethod: mediaEntity.dateTimeExtractionMethod,
          partnershared: mediaEntity.partnershared,
        );
        updatedEntities.add(updatedEntity);
      } else {
        updatedEntities.add(mediaEntity);
      }
    }

    context.mediaCollection.clear();
    context.mediaCollection.addAll(updatedEntities);
    return transformedCount;
  }

  /// Diagnose leftover source files after the move.
  void _diagnoseLeftovers({
    required final List<File> originalSourceFiles,
    required final List<MediaEntityMovingResult> results,
    required final bool verbose,
  }) {
    final movedOrCopiedSources = <String>{};
    final failuresBySource = <String, List<MediaEntityMovingResult>>{};

    for (final r in results) {
      final src = r.operation.sourceFile.path;
      if (r.success) {
        movedOrCopiedSources.add(src);
      } else {
        failuresBySource.putIfAbsent(src, () => []).add(r);
      }
    }

    final leftovers = <File>[];
    for (final f in originalSourceFiles) {
      final p = f.path;
      final isAccounted = movedOrCopiedSources.contains(p);
      final existsNow = f.existsSync();
      if (!isAccounted && existsNow) {
        leftovers.add(f);
      }
    }

    if (leftovers.isEmpty) {
      if (verbose) {
        print('\n[Verification] No leftover source files detected.');
      }
      return;
    }

    print(
      '\n[Verification] Leftovers diagnosis — files still present at source:',
    );
    for (final f in leftovers) {
      final p = f.path;
      final relatedFailures = failuresBySource[p] ?? const [];
      final hint = _buildHeuristicHintForPath(p);
      if (relatedFailures.isNotEmpty) {
        final first = relatedFailures.first;
        final op = first.operation.operationType.name.toUpperCase();
        final msg = first.errorMessage ?? 'Unknown error';
        print('  • $p');
        print('    - Last recorded operation: $op (FAILED): $msg');
        if (hint != null) {
          print('    - Heuristic hint: $hint');
        }
      } else {
        print('  • $p');
        print('    - No recorded operation for this source file.');
        if (hint != null) {
          print('    - Heuristic hint: $hint');
        }
      }
    }

    print('  Total leftovers: ${leftovers.length}\n');
  }

  String? _buildHeuristicHintForPath(final String path) {
    final lower = path.toLowerCase();
    final hasTilde = path.contains('~');
    final hasYen = path.contains('¥');
    final looksLikeTakeout = lower.contains(r'takeout\google fotos');

    final hints = <String>[];
    if (hasYen) {
      hints.add(
        'Filename contains "¥" which often indicates codepage/zip encoding issues (mojibake of "Ñ"). Consider verifying unzip tool uses UTF-8.',
      );
    }
    if (hasTilde) {
      hints.add(
        'Filename contains "~" which can indicate 8.3 shortname artifacts. Collisions/normalization may cause mismatches.',
      );
    }
    if (looksLikeTakeout) {
      hints.add(
        'Source under Takeout; ensure the path normalization and unzip preserved Unicode (NFC) correctly.',
      );
    }
    if (hints.isEmpty) return null;
    return hints.join(' ');
  }

  // ───────────────────────────── Helpers (albums) ─────────────────────────────

  static String _join(final String a, final String b) =>
      a.endsWith(Platform.pathSeparator)
      ? '$a$b'
      : '$a${Platform.pathSeparator}$b';

  static void _ensureParentDir(final File f) {
    final dir = f.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  static String _sanitizeAlbum(final String s) {
    var out = s.trim();
    const illegal = r'<>:"/\|?*';
    for (final ch in illegal.split('')) {
      out = out.replaceAll(ch, '_');
    }
    if (out.isEmpty) out = 'Unknown_Album';
    return out;
  }

  static String _sanitizeFileName(final String s) {
    var out = s.trim();
    const illegal = r'<>:"/\|?*';
    for (final ch in illegal.split('')) {
      out = out.replaceAll(ch, '_');
    }
    if (out.isEmpty) out = 'unnamed';
    return out;
  }

  static File _uniquePath(final File desired) {
    if (!desired.existsSync()) return desired;
    final dir = desired.parent.path;
    final name = desired.uri.pathSegments.isNotEmpty
        ? desired.uri.pathSegments.last
        : desired.path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    int i = 1;
    while (true) {
      final candidate = File(_join(dir, '$base ($i)$ext'));
      if (!candidate.existsSync()) return candidate;
      i++;
    }
  }

  /// Create a shortcut/link file at [link] pointing to [target].
  /// - On Unix: create a symlink.
  /// - On Windows: try hardlink via `mklink /H`. If it fails, fallback to copying.
  static Future<bool> _createShortcutOrLink({
    required final File target,
    required final File link,
    required final bool verbose,
  }) async {
    try {
      _ensureParentDir(link);
      if (link.existsSync()) {
        return false;
      }

      if (Platform.isWindows) {
        final result = await Process.run('cmd', [
          '/c',
          'mklink',
          '/H',
          link.path,
          target.path,
        ], runInShell: true);
        if (result.exitCode == 0) {
          return true;
        } else {
          if (verbose) {
            print(
              'mklink /H failed (${result.exitCode}): ${result.stderr ?? result.stdout}',
            );
            print('Falling back to copy for Windows shortcut.');
          }
          target.copySync(link.path);
          return true;
        }
      } else {
        await Link(link.path).create(target.path, recursive: true);
        return true;
      }
    } catch (e) {
      if (verbose) {
        print(
          'Warning: Failed to create shortcut/link (${link.path} -> ${target.path}): $e',
        );
      }
      return false;
    }
  }
}
