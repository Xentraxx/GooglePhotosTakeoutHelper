import 'package:gpth/gpth-lib.dart';

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

  /// Speeds up by avoiding costly ExifTool fallback when native claims support.
  bool fallbackToExifToolOnNativeMiss = false;

  /// Speeds up Step 5: skip the "already has date?" pre-check for non-JPEGs.
  /// If you need strict "skip if already has date", leave false.
  bool skipPrecheckForNonJpegInWriter = false;

  // Seppeds up Step 5 by sending files by batches to ExifTool on evey ExifTool call
  bool enableBatching = true; // Disable this if you observe any abnormal dates in your output files.

  /// DatesDictionary passed as argument (if ussed flag --fileDates)
  Map<String, Map<String, dynamic>>? fileDatesDictionary;

  // ───────────────────────────────────────────────────────────────────────────
  // NEW: Unsupported-format handling policy for Step 5 (Write EXIF)
  // These flags let you temporarily disable pre-skip logic and/or silence warnings.
  // - forceProcessUnsupportedFormats: If true, do NOT pre-skip AVI/MPG/MPEG/BMP.
  //   Let ExifTool decide (and fail silently if it cannot write).
  // - silenceUnsupportedWarnings: If true, do not log "Skipping …" warnings when
  //   the pre-skip is active.
  // - maxExifImageBatchSize / maxExifVideoBatchSize: hard caps for ExifTool batch
  //   sizes to avoid catastrophic batch failures (can be overridden via config).
  bool forceProcessUnsupportedFormats = false;
  bool silenceUnsupportedWarnings = true;
  int maxExifImageBatchSize = 1000;
  int maxExifVideoBatchSize = 24;

  // ───────────────────────────────────────────────────────────────────────────
  // Initialization / lifecycle
  // ───────────────────────────────────────────────────────────────────────────

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
    fallbackToExifToolOnNativeMiss = false;
    skipPrecheckForNonJpegInWriter = false;
    enableBatching = true;
    fileDatesDictionary = null;

    // NEW: reset unsupported-policy and batch caps
    forceProcessUnsupportedFormats = false;
    silenceUnsupportedWarnings = true;
    maxExifImageBatchSize = 500;
    maxExifVideoBatchSize = 24;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Optional helpers for integration
  // ───────────────────────────────────────────────────────────────────────────

  /// NEW: Update only a subset of fields from a loose map (e.g., CLI/JSON overrides).
  /// Unknown keys are ignored. Values are validated and coerced when safe.
  void applyOverrides(final Map<String, dynamic> overrides) {
    // Booleans
    if (overrides.containsKey('isVerbose')) isVerbose = _asBool(overrides['isVerbose'], isVerbose);
    if (overrides.containsKey('enforceMaxFileSize')) enforceMaxFileSize = _asBool(overrides['enforceMaxFileSize'], enforceMaxFileSize);
    if (overrides.containsKey('exifToolInstalled')) exifToolInstalled = _asBool(overrides['exifToolInstalled'], exifToolInstalled);
    if (overrides.containsKey('fallbackToExifToolOnNativeMiss')) fallbackToExifToolOnNativeMiss = _asBool(overrides['fallbackToExifToolOnNativeMiss'], fallbackToExifToolOnNativeMiss);
    if (overrides.containsKey('skipPrecheckForNonJpegInWriter')) skipPrecheckForNonJpegInWriter = _asBool(overrides['skipPrecheckForNonJpegInWriter'], skipPrecheckForNonJpegInWriter);
    if (overrides.containsKey('enableBatching')) enableBatching = _asBool(overrides['enableBatching'], enableBatching);

    // NEW flags
    if (overrides.containsKey('forceProcessUnsupportedFormats')) {
      forceProcessUnsupportedFormats = _asBool(overrides['forceProcessUnsupportedFormats'], forceProcessUnsupportedFormats);
    }
    if (overrides.containsKey('silenceUnsupportedWarnings')) {
      silenceUnsupportedWarnings = _asBool(overrides['silenceUnsupportedWarnings'], silenceUnsupportedWarnings);
    }

    // Ints
    if (overrides.containsKey('maxExifImageBatchSize')) {
      maxExifImageBatchSize = _asInt(overrides['maxExifImageBatchSize'], maxExifImageBatchSize);
    }
    if (overrides.containsKey('maxExifVideoBatchSize')) {
      maxExifVideoBatchSize = _asInt(overrides['maxExifVideoBatchSize'], maxExifVideoBatchSize);
    }

    // Dates dictionary (allow pass-through if structure matches)
    if (overrides.containsKey('fileDatesDictionary')) {
      final v = overrides['fileDatesDictionary'];
      if (v is Map<String, dynamic>) {
        // Best-effort cast; the writer only reads the expected shape.
        fileDatesDictionary = v.map((k, val) => MapEntry(k, (val is Map<String, dynamic>) ? val : <String, dynamic>{}));
      }
    }
  }

  /// NEW: Expose as a plain JSON-like map so other modules can read flags
  /// without tight coupling (used by Step 5 _resolveInt/_resolveUnsupportedPolicy).
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'isVerbose': isVerbose,
      'enforceMaxFileSize': enforceMaxFileSize,
      'exifToolInstalled': exifToolInstalled,
      'fallbackToExifToolOnNativeMiss': fallbackToExifToolOnNativeMiss,
      'skipPrecheckForNonJpegInWriter': skipPrecheckForNonJpegInWriter,
      'enableBatching': enableBatching,
      'forceProcessUnsupportedFormats': forceProcessUnsupportedFormats,
      'silenceUnsupportedWarnings': silenceUnsupportedWarnings,
      'maxExifImageBatchSize': maxExifImageBatchSize,
      'maxExifVideoBatchSize': maxExifVideoBatchSize,
      // NOTE: fileDatesDictionary can be very large; usually not needed here.
    };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ───────────────────────────────────────────────────────────────────────────

  bool _asBool(dynamic v, bool fallback) {
    if (v is bool) return v;
    if (v is String) {
      final s = v.toLowerCase().trim();
      if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
      if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
    }
    return fallback;
  }

  int _asInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is String) {
      final parsed = int.tryParse(v.trim());
      if (parsed != null) return parsed;
    }
    return fallback;
  }
}
