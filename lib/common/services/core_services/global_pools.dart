import 'package:gpth/gpth_lib_exports.dart';
import 'package:pool/pool.dart';

/// Central registry of shared Pool instances.
///
/// Creates one lazily-initialized [Pool] per [ConcurrencyOperation] so that
/// unrelated parts of the application coordinate throughput instead of spawning
/// many short‑lived pools whose limits compete unpredictably.
///
/// Rationale:
/// * Avoids repeated allocation of Pool objects for large batch operations.
/// * Provides a single choke point should future adaptive logic wish to resize.
/// * Keeps per-operation intent explicit via [ConcurrencyOperation].
class GlobalPools {
  GlobalPools._();

  static final Map<ConcurrencyOperation, Pool> _pools = {};

  /// Obtain (and lazily create) the pool for the given operation.
  static Pool poolFor(final ConcurrencyOperation op) =>
      _pools.putIfAbsent(op, () {
        final size = ConcurrencyManager().concurrencyFor(op).clamp(1, 512);
        return Pool(size);
      });

  /// Dispose and recreate a specific pool (e.g. after external config change).
  static Future<void> refresh(final ConcurrencyOperation op) async {
    final existing = _pools.remove(op);
    if (existing != null) {
      await existing.close();
    }
    poolFor(op); // recreate
  }

  /// Dispose all pools (primarily for tests).
  static Future<void> disposeAll() async {
    for (final pool in _pools.values) {
      await pool.close();
    }
    _pools.clear();
  }
}
