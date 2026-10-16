import 'package:flutter_scene/scene.dart' as fs;
// Build real CPU animation channels; no geometry, textures or GPU setup.
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart'
    show AnimationChannel, BindKey, PropertyResolver;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:vrlizate_scene/vrlizate_scene.dart';

fs.Animation _animation(String name, double x) => fs.Animation(
  name: name,
  channels: [
    AnimationChannel(
      bindTarget: BindKey(nodeName: 'joint'),
      resolver: PropertyResolver.makeTranslationTimeline(
        [0, 1],
        [vm.Vector3(x, 0, 0), vm.Vector3(x, 0, 0)],
      ),
    ),
  ],
);

fs.Node _actor({List<String> names = const ['Idle', 'Walking', 'Wave']}) {
  final actor = fs.Node(name: 'actor')..add(fs.Node(name: 'joint'));
  for (var i = 0; i < names.length; i++) {
    actor.addParsedAnimation(_animation(names[i], i * 10));
  }
  return actor;
}

double _pose(fs.Node actor) =>
    actor.getChildByName('joint')!.localTransform.getTranslation().x;

void main() {
  test('named mappings bind real clips and require all three actions', () {
    final actor = _actor(names: ['Rest', 'Move', 'Greet']);
    expect(() => VrActorAnimation(actor: actor), throwsArgumentError);
    expect(
      () => VrActorAnimation(
        actor: actor,
        clipNames: const {
          VrActorAction.idle: 'Rest',
          VrActorAction.walk: 'Rest',
          VrActorAction.wave: 'Greet',
        },
      ),
      throwsArgumentError,
    );
    final controller = VrActorAnimation(
      actor: actor,
      autoplay: false,
      clipNames: const {
        VrActorAction.idle: 'Rest',
        VrActorAction.walk: 'Move',
        VrActorAction.wave: 'Greet',
      },
    );
    addTearDown(controller.dispose);
    expect(controller.action, VrActorAction.idle);
    expect(controller.isPaused, isTrue);
    actor.scenePrePass(.5);
    expect(controller.playbackTime, 0);
    controller.play(VrActorAction.walk, transitionSeconds: 0);
    controller.resume();
    actor.scenePrePass(.2);
    expect(_pose(actor), closeTo(10, 1e-6));
    expect(controller.durationFor(VrActorAction.wave), 1);
  });

  test('fade blends the actual pose without advancing Scene time twice', () {
    final actor = _actor();
    final changes = <VrActorAction>[];
    final controller = VrActorAnimation(
      actor: actor,
      transitionSeconds: .4,
      onActionChanged: changes.add,
    );
    addTearDown(controller.dispose);
    controller.play(VrActorAction.walk);
    controller.tick(.2);
    expect(controller.playbackTime, 0, reason: 'Only Scene owns clip time.');
    actor.scenePrePass(.2);
    expect(controller.playbackTime, closeTo(.2, 1e-6));
    expect(_pose(actor), closeTo(5, 1e-6));
    controller.tick(.2);
    actor.scenePrePass(.2);
    expect(controller.isTransitioning, isFalse);
    expect(_pose(actor), closeTo(10, 1e-6));
    controller.play(VrActorAction.walk);
    expect(controller.playbackTime, closeTo(.4, 1e-6));
    expect(changes, [VrActorAction.walk], reason: 'No per-frame events.');
  });

  test('interrupting a fade preserves its current mixed pose', () {
    final actor = _actor();
    final controller = VrActorAnimation(actor: actor, transitionSeconds: .4);
    addTearDown(controller.dispose);
    controller.play(VrActorAction.walk);
    controller.tick(.1);
    actor.scenePrePass(.1);
    final before = _pose(actor);
    controller.play(VrActorAction.wave);
    actor.scenePrePass(0);
    expect(_pose(actor), closeTo(before, 1e-6));
    controller.tick(.2);
    actor.scenePrePass(.2);
    expect(_pose(actor), allOf(greaterThan(before), lessThan(20)));
    expect(
      VrActorAction.values.map(controller.weightFor).reduce((a, b) => a + b),
      closeTo(1, 1e-6),
    );
    controller.play(VrActorAction.walk);
    expect(
      controller.playbackTime,
      closeTo(.3, 1e-6),
      reason: 'An outgoing loop retains its phase when selected again.',
    );
  });

  test('pause freezes both clips and the in-flight transition', () {
    final actor = _actor();
    final controller = VrActorAnimation(actor: actor, transitionSeconds: .4);
    addTearDown(controller.dispose);
    controller.play(VrActorAction.walk);
    controller.tick(.1);
    actor.scenePrePass(.1);
    controller.pause();
    final weight = controller.weightFor(VrActorAction.walk);
    final pose = _pose(actor);
    controller.tick(5);
    actor.scenePrePass(5);
    expect(controller.playbackTime, closeTo(.1, 1e-6));
    expect(controller.weightFor(VrActorAction.walk), weight);
    expect(_pose(actor), closeTo(pose, 1e-6));
    controller.resume();
    controller.tick(.1);
    actor.scenePrePass(.1);
    expect(controller.playbackTime, closeTo(.2, 1e-6));
    expect(_pose(actor), greaterThan(pose));
  });

  test('one-shot completion returns to idle with an actual outgoing fade', () {
    final actor = _actor();
    final changes = <VrActorAction>[];
    final controller = VrActorAnimation(
      actor: actor,
      onActionChanged: changes.add,
    );
    addTearDown(controller.dispose);
    controller.play(VrActorAction.wave, transitionSeconds: 0);
    actor.scenePrePass(1.1);
    expect(controller.playbackTime, 1);
    controller.tick(0);
    expect(controller.action, VrActorAction.idle);
    expect(controller.isTransitioning, isTrue);
    actor.scenePrePass(0);
    expect(_pose(actor), closeTo(20, 1e-6));
    controller.tick(.25);
    actor.scenePrePass(.25);
    expect(_pose(actor), closeTo(0, 1e-6));
    expect(controller.weightFor(VrActorAction.wave), 0);
    expect(changes, [VrActorAction.wave, VrActorAction.idle]);
  });

  test('paused seek stays paused; ended waves resume into idle', () {
    final actor = _actor();
    final controller = VrActorAnimation(actor: actor);
    addTearDown(controller.dispose);
    controller.play(VrActorAction.wave, transitionSeconds: 0);
    controller.pause();
    controller.seek(99);
    controller.tick(1);
    actor.scenePrePass(1);
    expect(controller.playbackTime, 1);
    expect(controller.action, VrActorAction.wave);
    expect(controller.isPaused, isTrue);
    controller.resume();
    controller.tick(0);
    expect(controller.action, VrActorAction.idle);
    controller.play(VrActorAction.wave, restart: true, transitionSeconds: 0);
    expect(controller.playbackTime, 0);
    expect(() => controller.seek(double.nan), throwsArgumentError);
    controller.tick(double.infinity);
    expect(controller.playbackTime, 0);
  });

  test('dispose unregisters owned clips but preserves unrelated playback', () {
    final actor = _actor();
    final other = actor.createAnimationClip(_animation('Other', 3))
      ..loop = true
      ..play();
    final controller = VrActorAnimation(actor: actor);
    controller.play(VrActorAction.wave, transitionSeconds: 0);
    controller.dispose();
    controller.dispose();
    controller.tick(1);
    controller.resume();
    actor.scenePrePass(.2);
    expect(controller.isDisposed, isTrue);
    expect(controller.isTransitioning, isFalse);
    expect(_pose(actor), closeTo(3, 1e-6));
    expect(other.playbackTime, closeTo(.2, 1e-6));
    expect(() => controller.play(VrActorAction.idle), throwsStateError);
    expect(() => controller.seek(0), throwsStateError);
    actor.removeAnimationClip(other);
  });
}
