import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' show Scene;

import 'vr_world_navigation_scope.dart';

/// Mounts GPU-dependent children only after shared shaders are actually ready.
///
/// flutter_scene may catch initialization errors and complete its Future
/// normally. Therefore successful completion alone is not sufficient: the
/// readiness flag must also be true. A timeout/failure stays visible until an
/// explicit retry; rebuilding this widget never launches an automatic loop.
///
/// Pass a lazy [builder], not an already constructed GPU-dependent subtree,
/// when using this gate above a demo's Scene/geometry constructors.
class VrGpuResourceGate extends StatefulWidget {
  const VrGpuResourceGate({
    super.key,
    required this.builder,
    this.onBack,
    this.initialize,
    this.isReady,
    this.timeout = const Duration(seconds: 12),
  });

  final WidgetBuilder builder;
  final VoidCallback? onBack;

  /// Injectable resource operations for CPU-only tests or another backend.
  final Future<void> Function()? initialize;
  final bool Function()? isReady;
  final Duration timeout;

  @override
  State<VrGpuResourceGate> createState() => _VrGpuResourceGateState();
}

class _VrGpuResourceGateState extends State<VrGpuResourceGate> {
  bool _loading = true;
  bool _ready = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final attempt = ++_attempt;
    try {
      await Future<void>.sync(
        widget.initialize ?? Scene.initializeStaticResources,
      ).timeout(widget.timeout);
      final ready = (widget.isReady ?? () => Scene.isReadyToRender)();
      if (!ready) {
        throw StateError('GPU initialization completed without ready shaders.');
      }
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _ready = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || attempt != _attempt) return;
      debugPrint('VR GPU resources unavailable: $error');
      setState(() {
        _ready = false;
        _loading = false;
      });
    }
  }

  void _retry() {
    if (_loading) return;
    setState(() {
      _ready = false;
      _loading = true;
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _attempt++; // invalidate late completions, including timed-out attempts
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.builder(context);
    final navigation = VrWorldNavigationScope.maybeOf(context);
    final navigator = Navigator.maybeOf(context);
    final back =
        widget.onBack ??
        navigation?.onHome ??
        (navigator?.canPop() == true
            ? () {
                navigator!.maybePop();
              }
            : null);

    // A GPU failure cannot display its own recovery controls in 3D. This is
    // deliberately an ordinary Flutter screen, usable after removing a visor.
    return Material(
      color: const Color(0xFF101821),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading) ...[
                    const CircularProgressIndicator(
                      semanticsLabel: 'Cargando gráficos / Loading graphics',
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Preparando gráficos 3D…\nPreparing 3D graphics…',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 20),
                    ),
                  ] else ...[
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFFFD166),
                      size: 42,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No se pudieron cargar los gráficos 3D.\n'
                      'Could not load 3D graphics.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Los shaders o recursos GPU no están listos.\n'
                      'GPU shaders or resources are unavailable.\n\n'
                      'Retira el visor para usar estos controles.\n'
                      'Remove the headset to use these controls.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFD1D9E2), fontSize: 15),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (back != null)
                        FilledButton.tonal(
                          key: const ValueKey('vr_gpu_back'),
                          onPressed: back,
                          child: const Text('Volver / Back'),
                        ),
                      if (!_loading)
                        FilledButton(
                          key: const ValueKey('vr_gpu_retry'),
                          onPressed: _retry,
                          child: const Text('Reintentar / Retry'),
                        ),
                    ],
                  ),
                  if (!_loading && back == null) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'También puedes cerrar esta vista desde la app.\n'
                      'You can also close this view from the app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFD1D9E2)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
