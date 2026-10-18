import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Glow that works on every quality tier.
///
/// `VrLook` only enables bloom on the ultra preset, so an emissive sphere is
/// a flat colored ball for most viewers. A [VrHalo] is a camera-facing
/// additive sprite with a soft radial falloff: torches, suns, gems, portals
/// and holograms read as light sources without post-processing, at the cost
/// of one translucent quad each. Halos never write depth and never cast
/// shadows.
abstract final class VrGlow {
  static Texture2D? _radial;

  /// The shared 64² soft-disc texture (RGB and alpha both fall off, so the
  /// same map serves additive and alpha sprites). Requires GPU resources.
  static Texture2D radialTexture() {
    final existing = _radial;
    if (existing != null) return existing;
    const size = 64;
    final px = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final dx = (x + 0.5) / size - 0.5;
        final dy = (y + 0.5) / size - 0.5;
        final r = math.sqrt(dx * dx + dy * dy) * 2; // 0 centre .. 1 edge
        // Bright core, long soft tail, zero at the edge (no square outline).
        final core = math.exp(-r * r * 9);
        final tail = math.pow((1 - r).clamp(0.0, 1.0), 2.2) * 0.35;
        final v = ((core + tail) * (r < 1 ? 1 : 0)).clamp(0.0, 1.0);
        final b = (v * 255).round();
        final o = (y * size + x) * 4;
        px[o] = b;
        px[o + 1] = b;
        px[o + 2] = b;
        px[o + 3] = b;
      }
    }
    return _radial = Texture2D.fromPixels(
      px,
      size,
      size,
      content: TextureContent.color,
    );
  }

  /// Creates a halo of [color] (linear, may exceed 1 for a hot core) and
  /// [size] meters across, positioned at [position]. Returns null, adding
  /// nothing, when [isCurrent] reports the caller is gone or the GPU is not
  /// ready.
  static Future<VrHalo?> halo({
    required bool Function() isCurrent,
    required vm.Vector3 color,
    double size = 0.6,
    double intensity = 1.0,
    vm.Vector3? position,
    String? name,
  }) async {
    await Scene.initializeStaticResources();
    if (!isCurrent() || !Scene.isReadyToRender) return null;
    final sprite = Sprite(
      texture: radialTexture(),
      width: size,
      height: size,
      blendMode: SpriteBlendMode.additive,
    );
    final node = Node(name: name ?? 'halo', mesh: sprite.mesh)
      ..raycastable = false;
    if (position != null) {
      node.localTransform = vm.Matrix4.translation(position);
    }
    final halo = VrHalo._(node, sprite, color);
    halo.intensity = intensity;
    return halo;
  }

  /// Flame-like flicker in [0.7, 1.3]: three incommensurate sines plus a
  /// slow drift, deterministic per [seed] so torches never flicker in sync.
  static double flicker(double t, int seed) {
    final p = seed * 1.618;
    return 1.0 +
        0.12 * math.sin(t * 11.3 + p) +
        0.09 * math.sin(t * 17.9 + p * 2.1) +
        0.06 * math.sin(t * 29.7 + p * 3.7) +
        0.03 * math.sin(t * 1.7 + p);
  }

  @visibleForTesting
  static void resetTexture() => _radial = null;
}

/// A placed halo whose brightness can be driven per frame.
class VrHalo {
  VrHalo._(this.node, this.sprite, vm.Vector3 color) : _color = color.clone();

  final Node node;
  final Sprite sprite;
  final vm.Vector3 _color;
  double _intensity = 1.0;

  double get intensity => _intensity;

  /// Scales the halo color; additive sprites brighten, they never clip to a
  /// square, so values above 1 are safe.
  set intensity(double value) {
    _intensity = value;
    sprite.color = vm.Vector4(
      _color.x * value,
      _color.y * value,
      _color.z * value,
      value.clamp(0.0, 1.0),
    );
  }

  /// Uniform scale of the quad (pulsing portals, breathing gems).
  set size(double meters) {
    sprite
      ..width = meters
      ..height = meters;
  }

  void setPosition(vm.Vector3 position) {
    node.localTransform = vm.Matrix4.translation(position);
  }
}
