import 'dart:collection';

import 'package:flutter_scene/scene.dart' as fs;

/// Loads an unmounted, unanimated GLB template owned exclusively by the cache.
typedef VrGlbTemplateLoader =
    Future<fs.Node> Function(String assetPath, {int? maxTextureSize});

/// Bounded LRU cache of imported GLB templates, with independent actor instances.
///
/// Concurrent requests for a retained key share its import. Each request gets
/// its own node tree, skin bindings, morph weights and animation playback;
/// geometry, parsed animation curves, textures and materials remain shared.
/// Treat those shared resources as immutable. To customize an avatar, replace
/// its material slots with instance-owned materials instead of mutating the
/// template's material. Register animation clips only on the returned clone.
///
/// [maxEntries] limits retained templates, including pending imports, not live
/// instances or GPU bytes. Eviction drops the cache's reference; existing
/// instances keep their resources. This cache belongs to a world/session and
/// should be disposed with it, rather than retained globally without a limit.
final class VrGlbTemplateCache {
  VrGlbTemplateCache({this.maxEntries = 4, VrGlbTemplateLoader? loader})
    : _loader = loader ?? fs.Node.fromGlbAsset {
    if (maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be positive.');
    }
  }

  final int maxEntries;
  final VrGlbTemplateLoader _loader;
  final _templates =
      LinkedHashMap<
        ({String assetPath, int? maxTextureSize}),
        Future<fs.Node>
      >();
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Includes pending imports still retained by the LRU.
  int get retainedTemplateCount => _templates.length;

  Future<fs.Node> instantiate(String assetPath, {int? maxTextureSize}) async {
    _checkAlive();
    if (assetPath.trim().isEmpty) {
      throw ArgumentError.value(assetPath, 'assetPath', 'Must not be empty.');
    }
    if (maxTextureSize != null && maxTextureSize < 1) {
      throw ArgumentError.value(
        maxTextureSize,
        'maxTextureSize',
        'Must be positive when provided.',
      );
    }
    final key = (assetPath: assetPath, maxTextureSize: maxTextureSize);
    // Moving a retained entry to the end makes request order the LRU order.
    final pending =
        _templates.remove(key) ??
        Future<fs.Node>.sync(
          () => _loader(assetPath, maxTextureSize: maxTextureSize),
        );
    _templates[key] = pending;
    while (_templates.length > maxEntries) {
      _templates.remove(_templates.keys.first);
    }
    late final fs.Node template;
    try {
      template = await pending;
    } catch (_) {
      // An invalidated/replaced import must not remove a newer request.
      if (identical(_templates[key], pending)) _templates.remove(key);
      rethrow;
    }
    // Async completion cannot return a live actor after its owner disposed.
    _checkAlive();
    return template.clone();
  }

  /// Drops one retained import, allowing the next request to retry/reload.
  ///
  /// Outstanding callers can still receive their instance. Their completion
  /// never reinserts an invalidated template into this cache.
  void invalidate(String assetPath, {int? maxTextureSize}) {
    _templates.remove((assetPath: assetPath, maxTextureSize: maxTextureSize));
  }

  /// Drops all retained templates without invalidating already issued actors.
  /// Pending callers can finish, but cannot repopulate the cleared cache.
  void clear() => _templates.clear();

  /// Releases retained references. Pending imports cannot return an actor;
  /// successful late imports and future requests fail with StateError.
  /// Already returned instances remain usable; their owner must detach them.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clear();
  }

  void _checkAlive() {
    if (_disposed) throw StateError('GLB template cache has been disposed.');
  }
}
