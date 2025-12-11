// lib/io/input_clone_service.dart

import 'dart:io';

import 'package:gpth/gpth_lib_exports.dart';
import 'package:path/path.dart' as p;

/// Service that creates an exact working copy of an input directory.
/// The copy is placed next to the original directory with a "_tmp" suffix
/// and is intended to be used as the input for the rest of the run.
///
/// Key points:
/// - Sibling folder named "originalName_tmp" (or _tmp2, _tmp3... if already exists).
/// - Recursively copies files and directories, best-effort preservation of timestamps.
/// - Skips re-copy if the destination path equals the source path.
/// - Recreates symlinks when possible; if not, falls back to copying the target contents (best-effort).
/// - Returns the created destination Directory.
class InputCloneService with LoggerMixin {
  /// Creates a sibling working copy of [src] and returns that directory.
  ///
  /// If "basename_tmp" already exists, this will try "basename_tmp2", "_tmp3", etc.
  /// The returned directory will be used as the effective input for the rest of the run.
  Future<Directory> cloneToSiblingTmp(
    final Directory src, {
    final String suffix = '_tmp',
  }) async {
    final Directory resolvedSrc = Directory(p.normalize(src.path));
    if (!await resolvedSrc.exists()) {
      throw StateError(
        'Source input directory does not exist: ${resolvedSrc.path}',
      );
    }

    // Compute destination path next to the original folder
    final String baseName = p.basename(resolvedSrc.path);
    final String parent = p.dirname(resolvedSrc.path);
    String candidate = p.join(parent, '$baseName$suffix');

    // Avoid copying into itself, and pick a unique destination
    int attempt = 1;
    while (p.equals(candidate, resolvedSrc.path) ||
        await Directory(candidate).exists()) {
      attempt++;
      candidate = p.join(parent, '$baseName$suffix$attempt');
    }
    final Directory dst = Directory(candidate);

    logPrint('Creating working copy of input at: ${dst.path}');
    await _copyDirectory(resolvedSrc, dst);
    logPrint('Working copy ready at: ${dst.path}');
    return dst;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Internals
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _copyDirectory(
    final Directory source,
    final Directory destination,
  ) async {
    // Create destination root if missing
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    // We copy breadth-first to ensure parent directories exist for files
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final String rel = p.relative(entity.path, from: source.path);
      final String targetPath = p.join(destination.path, rel);

      try {
        final FileSystemEntityType type = await entity.stat().then(
          (final s) => s.type,
        );

        if (type == FileSystemEntityType.directory) {
          final dir = Directory(targetPath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        } else if (type == FileSystemEntityType.file) {
          await _copyFile(entity as File, File(targetPath));
        } else if (type == FileSystemEntityType.link) {
          // Best-effort: recreate the link. If not supported, fall back to copying target contents.
          final link = Link(entity.path);
          try {
            final String target = await link.target();
            await Link(targetPath).create(target, recursive: true);
          } catch (_) {
            try {
              final real = await File(entity.path).resolveSymbolicLinks();
              await _copyFile(File(real), File(targetPath));
            } catch (e) {
              logWarning(
                'Failed to recreate/copy symlink $rel: $e',
                forcePrint: true,
              );
            }
          }
        } else {
          // Unknown entity type; skip with a warning
          logWarning('Skipping unknown entity type at $rel', forcePrint: true);
        }
      } catch (e) {
        logWarning('Failed to copy entry "$rel": $e', forcePrint: true);
      }
    }
  }

  Future<void> _copyFile(final File src, final File dst) async {
    try {
      // Ensure parent directory exists
      await dst.parent.create(recursive: true);

      // Stream copy to avoid high memory usage on large files
      final srcStream = src.openRead();
      final dstSink = dst.openWrite();
      await srcStream.pipe(dstSink);
      await dstSink.close();

      // Preserve timestamps (best-effort)
      try {
        final stat = await src.stat();
        try {
          await dst.setLastModified(stat.modified);
        } catch (_) {}
        try {
          await dst.setLastAccessed(stat.accessed);
        } catch (_) {}
      } catch (_) {}
    } catch (e) {
      logWarning(
        'Failed to copy file ${src.path} -> ${dst.path}: $e',
        forcePrint: true,
      );
    }
  }
}
