import '../../models/processing_config_model.dart';

/// Service for managing global application configuration and state
///
/// Replaces global variables with a proper service that can be injected
/// and tested. Provides thread-safe access to configuration values.
class GlobalConfigService {
  /// Constructor for dependency injection
  GlobalConfigService();

  /// Whether verbose logging is enabled
  bool isVerbose = false;

  /// Whether file size limits should be enforced
  bool enforceMaxFileSize = false;

  /// Whether ExifTool is available and installed
  bool exifToolInstalled = false;

  /// Initializes configuration from processing config
  void initializeFrom(final ProcessingConfig config) {
    isVerbose = config.verbose;
    enforceMaxFileSize = config.limitFileSize;
    // exifToolInstalled is set separately by ExifTool detection
  }

  /// Resets all configuration to defaults
  void reset() {
    isVerbose = false;
    enforceMaxFileSize = false;
    exifToolInstalled = false;
  }
}
