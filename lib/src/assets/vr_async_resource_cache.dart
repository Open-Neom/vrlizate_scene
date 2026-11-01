import 'dart:collection';

/// Shares pending loads and bounds completed resources by least recent use.
///
/// Eviction releases only this cache's reference, never a live material's
/// resource. Clearing cannot cancel a load already issued to a caller, but its
/// completion cannot repopulate this cache or displace a newer request.
final class VrAsyncResourceCache<K, V extends Object> {
  VrAsyncResourceCache({required this.maxEntries}) {
    if (maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be positive.');
    }
  }

  final int maxEntries;
  final _ready = LinkedHashMap<K, V>();
  final _pending = <K, Future<V>>{};

  int get completedCount => _ready.length;

  Future<V> load(K key, Future<V> Function() loader) {
    final cached = _ready.remove(key);
    if (cached != null) {
      _ready[key] = cached;
      return Future.value(cached);
    }
    final existing = _pending[key];
    if (existing != null) return existing;
    late final Future<V> pending;
    // Defer even a Flutter SynchronousFuture until the pending entry exists.
    pending = Future<V>.microtask(loader).then(
      (value) {
        if (identical(_pending[key], pending)) {
          _pending.remove(key);
          _ready[key] = value;
          while (_ready.length > maxEntries) {
            _ready.remove(_ready.keys.first);
          }
        }
        return value;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_pending[key], pending)) _pending.remove(key);
        Error.throwWithStackTrace(error, stack);
      },
    );
    _pending[key] = pending;
    return pending;
  }

  void clear() {
    _pending.clear();
    _ready.clear();
  }
}
