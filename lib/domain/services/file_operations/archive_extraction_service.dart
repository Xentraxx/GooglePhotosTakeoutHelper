import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../../presentation/interactive_presenter.dart';
import '../core/logging_service.dart';

/// Service for handling ZIP file extraction using streaming
///
/// This service provides efficient ZIP extraction functionality using
/// streaming to handle files of any size without memory constraints.
class ZipExtractionService {
  /// Creates a new instance of ZipExtractionService
  ZipExtractionService({final InteractivePresenter? presenter})
    : _presenter = presenter ?? InteractivePresenter();

  final InteractivePresenter _presenter;
  final LoggingService _logger = LoggingService();

  /// Extracts all ZIP files to the specified directory using streaming
  ///
  /// Uses memory-efficient streaming extraction to handle files of any size.
  ///
  /// [zips] List of ZIP files to extract
  /// [dir] Target directory for extraction (will be created if needed)
  Future<void> extractAll(final List<File> zips, final Directory dir) async {
    // Clean up and create destination directory
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    await _presenter.showUnzipStartMessage();

    for (final File zip in zips) {
      await _presenter.showUnzipProgress(p.basename(zip.path));

      try {
        // Validate ZIP file exists
        if (!await zip.exists()) {
          throw FileSystemException('ZIP file not found', zip.path);
        }

        // Extract using streaming
        await extractFileToDisk(zip.path, dir.path);

        await _presenter.showUnzipSuccess(p.basename(zip.path));
      } catch (e) {
        _logger.warning('Failed to extract ${p.basename(zip.path)}: $e');
        _logger.warning('Continuing with remaining ZIP files...');
      }
    }

    await _presenter.showUnzipComplete();
  }
}
