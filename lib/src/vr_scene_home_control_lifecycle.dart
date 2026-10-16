/// Guards asynchronous HOME-label creation across visibility, scene and scope
/// changes. Old completions cannot attach nodes or release a newer attempt.
class VrSceneHomeControlLifecycle {
  VrSceneHomeControlLifecycle({bool enabled = true}) : _enabled = enabled;

  bool _enabled;
  int _generation = 0;
  int? _pending;

  bool get enabled => _enabled;
  bool get creating => _pending != null;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    invalidate();
  }

  int? begin() {
    if (!_enabled || creating) return null;
    return _pending = ++_generation;
  }

  bool accepts(int generation) =>
      _enabled && _generation == generation && _pending == generation;

  void finish(int generation) {
    if (_pending == generation) _pending = null;
  }

  void invalidate() {
    _generation++;
    _pending = null;
  }
}
