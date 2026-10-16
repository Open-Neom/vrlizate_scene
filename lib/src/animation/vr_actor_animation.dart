import 'package:flutter_scene/scene.dart' as fs;

/// Semantic actions independent of the names authored in a glTF asset.
enum VrActorAction { idle, walk, wave }

/// Owns three real Flutter Scene clips on an imported actor's root.
///
/// Scene advances clip time and evaluates the blended pose in its pre-pass.
/// Call [tick] once per application frame to advance only the transition
/// weights; do not also call `AnimationClip.advance` or `scenePrePass` yourself.
/// Pausing freezes both clip time and transition progress.
///
/// The actor must expose all three named animations in `parsedAnimations`.
/// This controller exclusively owns those clip names on that actor; unrelated
/// clips are left registered, but can still affect Scene's weight normalization.
/// Place/scale the model under a separate parent to keep authored animation
/// channels independent of world placement.
final class VrActorAnimation {
  factory VrActorAnimation({
    required fs.Node actor,
    Map<VrActorAction, String> clipNames = defaultClipNames,
    double transitionSeconds = .25,
    bool autoplay = true,
    void Function(VrActorAction action)? onActionChanged,
  }) {
    _validateDuration(transitionSeconds);
    final animations = <VrActorAction, fs.Animation>{};
    final names = <String>{};
    // Validate the complete mapping before registering any clips on the actor.
    for (final action in VrActorAction.values) {
      final name = clipNames[action];
      if (name == null || name.isEmpty || !names.add(name)) {
        throw ArgumentError.value(
          clipNames,
          'clipNames',
          'Every action requires a distinct, nonempty clip name.',
        );
      }
      final animation = actor.findAnimationByName(name);
      if (animation == null ||
          !animation.endTime.isFinite ||
          animation.endTime <= 0) {
        throw ArgumentError.value(
          name,
          'clipNames',
          'Actor requires a nonempty animation named "$name".',
        );
      }
      animations[action] = animation;
    }
    final clips = <VrActorAction, fs.AnimationClip>{};
    try {
      for (final action in VrActorAction.values) {
        clips[action] = actor.createAnimationClip(animations[action]!)
          ..loop = action != VrActorAction.wave
          ..weight = action == VrActorAction.idle ? 1 : 0;
      }
    } catch (_) {
      for (final clip in clips.values) {
        actor.removeAnimationClip(clip);
      }
      rethrow;
    }
    return VrActorAnimation._(
      actor,
      clips,
      Map.unmodifiable({
        for (final entry in animations.entries) entry.key: entry.value.endTime,
      }),
      transitionSeconds,
      !autoplay,
      onActionChanged,
    ).._syncPlayback();
  }

  VrActorAnimation._(
    this._actor,
    this._clips,
    this._durations,
    this.transitionSeconds,
    this._paused,
    this.onActionChanged,
  );

  static const defaultClipNames = <VrActorAction, String>{
    VrActorAction.idle: 'Idle',
    VrActorAction.walk: 'Walking',
    VrActorAction.wave: 'Wave',
  };

  final fs.Node _actor;
  final Map<VrActorAction, fs.AnimationClip> _clips;
  final Map<VrActorAction, double> _durations;
  final List<double> _blendStart = List.filled(VrActorAction.values.length, 0);

  /// Default fade duration, in seconds. Zero switches clips immediately.
  final double transitionSeconds;

  /// Called only when the requested action changes, including wave -> idle.
  /// There are no per-frame notifications or reactive state dependencies.
  final void Function(VrActorAction action)? onActionChanged;

  VrActorAction _action = VrActorAction.idle;
  bool _paused;
  bool _disposed = false;
  double _blendElapsed = 0;
  double _blendDuration = 0;

  VrActorAction get action => _action;
  bool get isPaused => _paused;
  bool get isDisposed => _disposed;
  bool get isTransitioning => _blendElapsed < _blendDuration;
  double get playbackTime => _clips[_action]!.playbackTime;
  double get duration => _durations[_action]!;

  double weightFor(VrActorAction action) => _clips[action]!.weight;
  double durationFor(VrActorAction action) => _durations[action]!;

  /// Blends toward [action] without dropping the current mixed pose.
  ///
  /// Repeated requests for the current action do nothing unless [restart] is
  /// true. A newly entered wave starts at zero and returns to idle after its
  /// one-shot ends. Looping clips already contributing to a blend keep their
  /// playback position when an interrupted transition returns to them.
  void play(
    VrActorAction action, {
    bool restart = false,
    double? transitionSeconds,
  }) {
    _checkAlive();
    final fade = transitionSeconds ?? this.transitionSeconds;
    _validateDuration(fade);
    if (action == _action && !restart) return;
    final changed = action != _action;
    final target = _clips[action]!;
    if (restart || action == VrActorAction.wave || target.weight == 0) {
      target.seek(0);
    }
    for (final item in VrActorAction.values) {
      _blendStart[item.index] = _clips[item]!.weight;
    }
    _action = action;
    _blendElapsed = 0;
    _blendDuration = fade;
    if (fade == 0) _writeBlend(1);
    _syncPlayback();
    if (changed) onActionChanged?.call(action);
  }

  /// Advances only blend weights and checks Scene's real one-shot progress.
  /// Invalid deltas and ticks after disposal are ignored.
  void tick(double dt) {
    if (_disposed || _paused || !dt.isFinite || dt < 0) return;
    if (_action == VrActorAction.wave && playbackTime >= duration) {
      play(VrActorAction.idle);
      // A host callback may pause or dispose the controller on state change.
      if (_disposed || _paused) return;
    }
    if (!isTransitioning || dt == 0) return;
    _blendElapsed = (_blendElapsed + dt).clamp(0, _blendDuration);
    final t = _blendElapsed / _blendDuration;
    _writeBlend(t * t * (3 - 2 * t));
    if (!isTransitioning) _syncPlayback();
  }

  void _writeBlend(double t) {
    for (final action in VrActorAction.values) {
      final start = _blendStart[action.index];
      final target = action == _action ? 1.0 : 0.0;
      _clips[action]!.weight = start + (target - start) * t;
    }
  }

  void _syncPlayback() {
    for (final action in VrActorAction.values) {
      final clip = _clips[action]!;
      final contributes = action == _action || clip.weight > 0;
      final finished =
          action == VrActorAction.wave &&
          clip.playbackTime >= _durations[action]!;
      if (!_paused && contributes && !finished) {
        clip.play();
      } else {
        clip.pause();
      }
    }
  }

  /// Keeps the visible pose and fade progress at their current positions.
  void pause() {
    if (_disposed || _paused) return;
    _paused = true;
    _syncPlayback();
  }

  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    _syncPlayback();
  }

  /// Seeks the current action only, clamped to its duration. The outgoing
  /// clip and current blend weights are unchanged. A paused seek stays paused;
  /// Scene applies that pose on its next pre-pass even while clips are paused.
  void seek(double seconds) {
    _checkAlive();
    if (!seconds.isFinite) {
      throw ArgumentError.value(seconds, 'seconds', 'Must be finite.');
    }
    _clips[_action]!.seek(seconds);
    _syncPlayback();
  }

  /// Stops and unregisters only this controller's clips; idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _paused = true;
    _blendElapsed = _blendDuration = 0;
    for (final clip in _clips.values) {
      clip.pause();
      clip.weight = 0;
      _actor.removeAnimationClip(clip);
    }
  }

  void _checkAlive() {
    if (_disposed) throw StateError('Actor animation has been disposed.');
  }

  static void _validateDuration(double seconds) {
    if (!seconds.isFinite || seconds < 0) {
      throw ArgumentError.value(
        seconds,
        'transitionSeconds',
        'Must be finite and nonnegative.',
      );
    }
  }
}
