import 'package:flutter/services.dart';
import 'package:vrlizate/vrlizate.dart';

/// WASD emits held axes; StereoSceneView remains the sole movement integrator.
/// It never mutates a camera or listens to sensors. Keyboard-only actions such
/// as R/E/Space remain available to the demo's surrounding shortcuts.
class RetainedDesktopInput implements VrInputDriver {
  VrInputSink? _sink;
  final Set<LogicalKeyboardKey> _pressed = {};
  final Map<String, dynamic> _axes = {'stick': 'left', 'x': 0.0, 'y': 0.0};

  @override
  VrInputSource get source => VrInputSource.externalPeripheral;

  @override
  void attach(VrInputSink sink) {
    detach();
    _sink = sink;
  }

  @override
  void detach() {
    releaseAll();
    _sink = null;
  }

  bool handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (_sink == null ||
        (key != LogicalKeyboardKey.keyW &&
            key != LogicalKeyboardKey.keyA &&
            key != LogicalKeyboardKey.keyS &&
            key != LogicalKeyboardKey.keyD)) {
      return false;
    }
    if (event is KeyUpEvent) {
      _pressed.remove(key);
    } else if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _pressed.add(key);
    } else {
      return false;
    }
    _emit();
    return true;
  }

  void releaseAll() {
    if (_pressed.isEmpty) return;
    _pressed.clear();
    _emit();
  }

  void _emit() {
    final x =
        (_pressed.contains(LogicalKeyboardKey.keyD) ? 1.0 : 0.0) -
        (_pressed.contains(LogicalKeyboardKey.keyA) ? 1.0 : 0.0);
    final y =
        (_pressed.contains(LogicalKeyboardKey.keyW) ? 1.0 : 0.0) -
        (_pressed.contains(LogicalKeyboardKey.keyS) ? 1.0 : 0.0);
    _axes['x'] = x;
    _axes['y'] = y;
    _sink?.emit(
      type: VrInputType.navigate,
      data: _axes,
      active: x != 0 || y != 0,
    );
  }
}
