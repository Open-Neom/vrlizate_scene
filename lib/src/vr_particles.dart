import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'quality_preset.dart';
import 'vr_glow.dart';

/// Ready-made particle effects for the native demos, on the engine's
/// `ParticleSystem` (fixed-step, prewarmed, stepped once per frame by the
/// scene itself).
///
/// Every factory returns a [Node] carrying a `ParticleEmitterComponent`;
/// place it with `localTransform` and add it to the scene. Effects simulate
/// in the node's local space, so a torch's smoke rises along the torch's
/// +Y. Emitters use the shared soft-disc texture ([VrGlow.radialTexture])
/// and so need GPU resources: callers await `Scene.initializeStaticResources`
/// (the `dress` flows already do) or use [VrParticles.attach].
///
/// [VrParticleBudget] scales particle counts by quality tier so a low-end
/// viewer keeps the effect but not the overdraw.
abstract final class VrParticles {
  /// Creates and adds an effect only once the GPU is ready, guarded by
  /// [isCurrent] like the texture loaders. Returns the node or null.
  static Future<Node?> attach(
    Scene scene,
    Node Function() build, {
    required bool Function() isCurrent,
    vm.Matrix4? transform,
  }) async {
    await Scene.initializeStaticResources();
    if (!isCurrent() || !Scene.isReadyToRender) return null;
    final node = build();
    if (transform != null) node.localTransform = transform;
    scene.add(node);
    return node;
  }

  static SpriteMaterial _sprite(SpriteBlendMode blend) =>
      SpriteMaterial(colorTexture: VrGlow.radialTexture())..blendMode = blend;

  static Node _node(
    String name,
    ParticleSystem system,
    SpriteBlendMode blend, {
    BillboardFacing facing = BillboardFacing.spherical,
    double velocityStretch = 0.0,
  }) => Node(name: name)
    ..raycastable = false
    ..addComponent(
      ParticleEmitterComponent(system: system, material: _sprite(blend))
        ..facing = facing
        ..velocityStretch = velocityStretch,
    );

  /// Thin grey smoke rising and thinning from a torch or chimney.
  static Node torchSmoke(VrParticleBudget budget, {int seed = 1}) {
    final count = budget.scale(40);
    return _node(
      'smoke',
      ParticleSystem(
        maxParticles: count,
        shape: const ConeEmitterShape(angle: 0.25, radius: 0.03),
        spawner: Spawner(rate: count / 2.2),
        lifetime: const UniformFloat(1.6, 2.4),
        startSpeed: const UniformFloat(0.35, 0.55),
        startSize: const UniformFloat(0.10, 0.16),
        startColor: ConstantColor(vm.Vector4(0.35, 0.33, 0.30, 0.28)),
        modules: [
          SizeOverLifeModule(
            CurveFloat(
              ParticleCurve(const [
                ParticleKeyframe(0, 0.5),
                ParticleKeyframe(1, 2.6),
              ]),
            ),
          ),
          ColorOverLifeModule(
            GradientColor(
              ColorGradient([
                ColorStop(0, vm.Vector4(0.4, 0.36, 0.32, 0)),
                ColorStop(0.15, vm.Vector4(0.4, 0.36, 0.32, 0.3)),
                ColorStop(1, vm.Vector4(0.3, 0.3, 0.3, 0)),
              ]),
            ),
          ),
          TurbulenceModule(strength: 0.25, frequency: 1.4, seed: seed),
          LinearDragModule(0.6),
        ],
        prewarm: 2.0,
        seed: seed,
      ),
      SpriteBlendMode.alpha,
    );
  }

  /// Hot embers popping up from a flame and fading out (additive).
  static Node embers(
    VrParticleBudget budget, {
    int seed = 2,
    vm.Vector3? color,
  }) {
    final count = budget.scale(24);
    final c = color ?? vm.Vector3(1.0, 0.55, 0.15);
    return _node(
      'embers',
      ParticleSystem(
        maxParticles: count,
        shape: const ConeEmitterShape(angle: 0.55, radius: 0.04),
        spawner: Spawner(rate: count / 1.1),
        lifetime: const UniformFloat(0.6, 1.2),
        startSpeed: const UniformFloat(0.6, 1.3),
        startSize: const UniformFloat(0.02, 0.045),
        startColor: ConstantColor(vm.Vector4(c.x, c.y, c.z, 1)),
        gravity: vm.Vector3(0, -1.2, 0),
        modules: [
          ColorOverLifeModule(
            GradientColor(
              ColorGradient([
                ColorStop(0, vm.Vector4(c.x * 1.5, c.y * 1.5, c.z * 1.5, 1)),
                ColorStop(0.6, vm.Vector4(c.x, c.y * 0.6, c.z * 0.3, 0.8)),
                ColorStop(1, vm.Vector4(0.3, 0.05, 0.0, 0)),
              ]),
            ),
          ),
          TurbulenceModule(strength: 0.8, frequency: 2.5, seed: seed),
        ],
        prewarm: 1.0,
        seed: seed,
      ),
      SpriteBlendMode.additive,
    );
  }

  /// One burst of dust and grit (a collapse, an impact). Non-looping: the
  /// node can be removed after [seconds].
  static Node dustBurst(
    VrParticleBudget budget, {
    int seed = 3,
    double radius = 0.8,
    double seconds = 2.5,
    vm.Vector3? color,
  }) {
    final count = budget.scale(90);
    final c = color ?? vm.Vector3(0.55, 0.50, 0.42);
    return _node(
      'dust',
      ParticleSystem(
        maxParticles: count,
        shape: SphereEmitterShape(radius: radius * 0.5, hemisphere: true),
        spawner: Spawner(bursts: [ParticleBurst(time: 0, count: count)]),
        lifetime: UniformFloat(seconds * 0.5, seconds),
        startSpeed: const UniformFloat(1.2, 3.0),
        startSize: UniformFloat(radius * 0.25, radius * 0.5),
        startColor: ConstantColor(vm.Vector4(c.x, c.y, c.z, 0.55)),
        gravity: vm.Vector3(0, -0.8, 0),
        looping: false,
        duration: seconds,
        modules: [
          SizeOverLifeModule(
            CurveFloat(
              ParticleCurve(const [
                ParticleKeyframe(0, 0.6),
                ParticleKeyframe(1, 2.2),
              ]),
            ),
          ),
          ColorOverLifeModule(
            GradientColor(
              ColorGradient([
                ColorStop(0, vm.Vector4(c.x, c.y, c.z, 0.6)),
                ColorStop(1, vm.Vector4(c.x, c.y, c.z, 0)),
              ]),
            ),
          ),
          LinearDragModule(2.2),
        ],
        seed: seed,
      ),
      SpriteBlendMode.alpha,
    );
  }

  /// A short spray of sparks (additive, velocity-stretched).
  static Node sparks(
    VrParticleBudget budget, {
    int seed = 4,
    vm.Vector3? color,
    double seconds = 0.9,
  }) {
    final count = budget.scale(40);
    final c = color ?? vm.Vector3(1.0, 0.8, 0.4);
    return _node(
      'sparks',
      ParticleSystem(
        maxParticles: count,
        shape: const SphereEmitterShape(radius: 0.05, surfaceOnly: true),
        spawner: Spawner(bursts: [ParticleBurst(time: 0, count: count)]),
        lifetime: UniformFloat(seconds * 0.4, seconds),
        startSpeed: const UniformFloat(2.5, 6.0),
        startSize: const UniformFloat(0.02, 0.04),
        startColor: ConstantColor(vm.Vector4(c.x, c.y, c.z, 1)),
        gravity: vm.Vector3(0, -6, 0),
        looping: false,
        duration: seconds,
        modules: [
          ColorOverLifeModule(
            GradientColor(
              ColorGradient([
                ColorStop(0, vm.Vector4(c.x * 2, c.y * 2, c.z * 2, 1)),
                ColorStop(1, vm.Vector4(c.x, c.y * 0.4, 0, 0)),
              ]),
            ),
          ),
          LinearDragModule(0.8),
        ],
        seed: seed,
      ),
      SpriteBlendMode.additive,
      facing: BillboardFacing.velocityStretched,
      velocityStretch: 0.08,
    );
  }

  /// Snow drifting down through a box [halfExtents] around the node.
  static Node snow(
    VrParticleBudget budget, {
    int seed = 5,
    vm.Vector3? halfExtents,
  }) {
    final count = budget.scale(320);
    final ext = halfExtents ?? vm.Vector3(14, 4, 14);
    return _node(
      'snow',
      ParticleSystem(
        maxParticles: count,
        shape: BoxEmitterShape(
          halfExtents: ext,
          direction: vm.Vector3(0, -1, 0),
        ),
        spawner: Spawner(rate: count / 7.0),
        lifetime: const UniformFloat(6.0, 8.0),
        startSpeed: const UniformFloat(0.5, 0.9),
        startSize: const UniformFloat(0.025, 0.05),
        startColor: ConstantColor(vm.Vector4(0.95, 0.97, 1.0, 0.85)),
        modules: [
          TurbulenceModule(strength: 0.45, frequency: 0.6, seed: seed),
          ColorOverLifeModule(
            GradientColor(
              ColorGradient([
                ColorStop(0, vm.Vector4(0.95, 0.97, 1.0, 0)),
                ColorStop(0.1, vm.Vector4(0.95, 0.97, 1.0, 0.85)),
                ColorStop(0.9, vm.Vector4(0.95, 0.97, 1.0, 0.85)),
                ColorStop(1, vm.Vector4(0.95, 0.97, 1.0, 0)),
              ]),
            ),
          ),
        ],
        prewarm: 8.0,
        seed: seed,
      ),
      SpriteBlendMode.alpha,
    );
  }

  /// Wind-blown sand or dust streaming sideways through a box.
  static Node windBlownSand(
    VrParticleBudget budget, {
    int seed = 6,
    vm.Vector3? halfExtents,
    vm.Vector3? wind,
    vm.Vector3? color,
  }) {
    final count = budget.scale(220);
    final ext = halfExtents ?? vm.Vector3(14, 1.2, 14);
    final w = wind ?? vm.Vector3(1, 0.05, 0.3);
    final c = color ?? vm.Vector3(0.78, 0.66, 0.44);
    return _node(
      'sand',
      ParticleSystem(
        maxParticles: count,
        shape: BoxEmitterShape(halfExtents: ext, direction: w),
        spawner: Spawner(rate: count / 3.0),
        lifetime: const UniformFloat(2.5, 3.5),
        startSpeed: const UniformFloat(2.5, 4.0),
        startSize: const UniformFloat(0.03, 0.07),
        startColor: ConstantColor(vm.Vector4(c.x, c.y, c.z, 0.35)),
        modules: [
          TurbulenceModule(strength: 0.6, frequency: 0.9, seed: seed),
          ColorOverLifeModule(
            GradientColor(
              ColorGradient([
                ColorStop(0, vm.Vector4(c.x, c.y, c.z, 0)),
                ColorStop(0.15, vm.Vector4(c.x, c.y, c.z, 0.35)),
                ColorStop(0.85, vm.Vector4(c.x, c.y, c.z, 0.35)),
                ColorStop(1, vm.Vector4(c.x, c.y, c.z, 0)),
              ]),
            ),
          ),
        ],
        prewarm: 4.0,
        seed: seed,
      ),
      SpriteBlendMode.alpha,
      facing: BillboardFacing.velocityStretched,
      velocityStretch: 0.03,
    );
  }

  /// Slow motes hanging in the air of a hall (lit by the beams).
  static Node dustMotes(
    VrParticleBudget budget, {
    int seed = 7,
    vm.Vector3? halfExtents,
  }) {
    final count = budget.scale(80);
    final ext = halfExtents ?? vm.Vector3(4, 1.5, 3);
    return _node(
      'motes',
      ParticleSystem(
        maxParticles: count,
        shape: BoxEmitterShape(halfExtents: ext),
        spawner: Spawner(rate: count / 6.0),
        lifetime: const UniformFloat(5.0, 7.0),
        startSpeed: const UniformFloat(0.0, 0.05),
        startSize: const UniformFloat(0.012, 0.028),
        startColor: ConstantColor(vm.Vector4(1, 0.95, 0.85, 0.5)),
        modules: [
          TurbulenceModule(strength: 0.12, frequency: 0.5, seed: seed),
          ColorOverLifeModule(
            GradientColor(
              ColorGradient([
                ColorStop(0, vm.Vector4(1, 0.95, 0.85, 0)),
                ColorStop(0.2, vm.Vector4(1, 0.95, 0.85, 0.5)),
                ColorStop(0.8, vm.Vector4(1, 0.95, 0.85, 0.5)),
                ColorStop(1, vm.Vector4(1, 0.95, 0.85, 0)),
              ]),
            ),
          ),
        ],
        prewarm: 7.0,
        seed: seed,
      ),
      SpriteBlendMode.additive,
    );
  }

  /// A thruster plume streaming out along the node's −Z (additive).
  static Node thruster(
    VrParticleBudget budget, {
    int seed = 8,
    vm.Vector3? color,
    double length = 0.8,
  }) {
    final count = budget.scale(36);
    final c = color ?? vm.Vector3(0.4, 0.8, 1.0);
    return _node(
      'thruster',
      ParticleSystem(
        maxParticles: count,
        shape: BoxEmitterShape(
          halfExtents: vm.Vector3(0.03, 0.03, 0.01),
          direction: vm.Vector3(0, 0, -1),
        ),
        spawner: Spawner(rate: count / 0.5),
        lifetime: ConstantFloat(0.5),
        startSpeed: UniformFloat(length * 1.6, length * 2.2),
        startSize: const UniformFloat(0.06, 0.10),
        startColor: ConstantColor(vm.Vector4(c.x, c.y, c.z, 1)),
        modules: [
          SizeOverLifeModule(
            CurveFloat(
              ParticleCurve(const [
                ParticleKeyframe(0, 1.0),
                ParticleKeyframe(1, 0.2),
              ]),
            ),
          ),
          ColorOverLifeModule(
            GradientColor(
              ColorGradient([
                ColorStop(0, vm.Vector4(c.x * 2, c.y * 2, c.z * 2, 1)),
                ColorStop(1, vm.Vector4(c.x * 0.3, c.y * 0.3, c.z * 0.6, 0)),
              ]),
            ),
          ),
        ],
        prewarm: 0.5,
        seed: seed,
      ),
      SpriteBlendMode.additive,
    );
  }

  /// Motes spiralling into a portal disc facing +Z (additive).
  static Node portalSwirl(
    VrParticleBudget budget, {
    int seed = 9,
    vm.Vector3? color,
    double radius = 0.9,
  }) {
    final count = budget.scale(60);
    final c = color ?? vm.Vector3(0.3, 0.9, 1.0);
    return _node(
      'swirl',
      ParticleSystem(
        maxParticles: count,
        shape: SphereEmitterShape(radius: radius, surfaceOnly: true),
        spawner: Spawner(rate: count / 1.6),
        lifetime: const UniformFloat(1.2, 1.8),
        // Emitted outward; the drag and reversed speed pull them inward.
        startSpeed: UniformFloat(-radius * 0.9, -radius * 0.6),
        startSize: const UniformFloat(0.03, 0.06),
        startColor: ConstantColor(vm.Vector4(c.x, c.y, c.z, 1)),
        modules: [
          TurbulenceModule(strength: 0.5, frequency: 2.0, seed: seed),
          ColorOverLifeModule(
            GradientColor(
              ColorGradient([
                ColorStop(0, vm.Vector4(c.x, c.y, c.z, 0)),
                ColorStop(0.3, vm.Vector4(c.x * 1.4, c.y * 1.4, c.z * 1.4, 1)),
                ColorStop(1, vm.Vector4(1, 1, 1, 0)),
              ]),
            ),
          ),
        ],
        prewarm: 2.0,
        seed: seed,
      ),
      SpriteBlendMode.additive,
    );
  }
}

/// Particle counts per quality tier: the effect survives on every device,
/// the overdraw does not.
class VrParticleBudget {
  const VrParticleBudget(this.factor);

  /// Multiplier applied to each effect's nominal count (1.0 = as designed).
  final double factor;

  static VrParticleBudget forPreset(VrQualityPreset preset) =>
      switch (preset.tier) {
        VrQualityTier.low => const VrParticleBudget(0.35),
        VrQualityTier.medium => const VrParticleBudget(0.7),
        VrQualityTier.high => const VrParticleBudget(1.0),
        VrQualityTier.ultra => const VrParticleBudget(1.4),
      };

  int scale(int nominal) => math.max(4, (nominal * factor).round());
}
