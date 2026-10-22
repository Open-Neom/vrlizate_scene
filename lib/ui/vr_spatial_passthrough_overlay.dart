import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../domain/services/vr_multi_camera_space_mapper.dart';
import '../utils/constants/vr_scene_constants.dart';
import 'vr_spatial_wireframe_painter.dart';

/// Stereoscopic overlay widget that renders the Visor camera passthrough
/// background (`cameraPreviewBuilder`) and the 3D AI wireframe contours fused
/// by [VrMultiCameraSpaceMapper] across both left and right eye viewports.
class VrSpatialPassthroughOverlay extends StatelessWidget {
  const VrSpatialPassthroughOverlay({
    super.key,
    required this.mapper,
    required this.viewerPosition,
    required this.viewerOrientation,
    this.headPitchRadians = 0.0,
    this.ipdMeters = VrSceneConstants.defaultIpdMeters,
    this.stereoSplit = true,
    this.cameraPreview,
  });

  final VrMultiCameraSpaceMapper mapper;
  final vm.Vector3 viewerPosition;
  final vm.Quaternion viewerOrientation;
  final double headPitchRadians;
  final double ipdMeters;
  final bool stereoSplit;
  final Widget? cameraPreview;

  @override
  Widget build(BuildContext context) {
    final visibility = mapper.evaluateVisibility(
      viewerPosition: viewerPosition,
      headPitchRadians: headPitchRadians,
    );
    if (visibility.wireframeOpacity <=
            VrSceneConstants.minRenderableWireframeOpacity &&
        visibility.cameraFeedOpacity <=
            VrSceneConstants.minRenderableWireframeOpacity) {
      return const SizedBox.shrink();
    }

    final segments = mapper.allContourSegments;
    final feedAlpha = visibility.cameraFeedOpacity.clamp(0.0, 1.0);

    Widget buildEyeViewport(double eyeOffset) {
      return RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (feedAlpha > VrSceneConstants.minRenderableWireframeOpacity)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.98,
                    colors: [
                      Color.fromRGBO(6, 28, 44, feedAlpha * 0.72),
                      Color.fromRGBO(4, 12, 22, feedAlpha * 0.88),
                    ],
                  ),
                ),
                child: !stereoSplit ? cameraPreview : null,
              ),
            if (segments.isNotEmpty &&
                visibility.wireframeOpacity >
                    VrSceneConstants.minRenderableWireframeOpacity)
              CustomPaint(
                painter: VrSpatialWireframePainter(
                  segments: segments,
                  viewerPosition: viewerPosition,
                  viewerOrientation: viewerOrientation,
                  eyeOffsetMeters: eyeOffset,
                  opacity: visibility.wireframeOpacity,
                ),
              ),
          ],
        ),
      );
    }

    return IgnorePointer(
      child: stereoSplit
          ? Row(
              children: [
                Expanded(child: buildEyeViewport(-ipdMeters * 0.5)),
                Expanded(child: buildEyeViewport(ipdMeters * 0.5)),
              ],
            )
          : buildEyeViewport(0.0),
    );
  }
}
