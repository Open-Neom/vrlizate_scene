import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../domain/models/vr_spatial_contour_segment.dart';
import '../utils/constants/vr_scene_constants.dart';

/// Projects 3D AI-identified object contours ([VrSpatialContourSegment]) into a
/// single eye's perspective viewport with stereoscopic eye offset (`eyeOffsetMeters`).
class VrSpatialWireframePainter extends CustomPainter {
  VrSpatialWireframePainter({
    required this.segments,
    required this.viewerPosition,
    required this.viewerOrientation,
    this.eyeOffsetMeters = 0.0,
    this.verticalFovRadians =
        VrSceneConstants.defaultEyeViewportVerticalFovRadians,
    this.opacity = 1.0,
  });

  final List<VrSpatialContourSegment> segments;
  final vm.Vector3 viewerPosition;
  final vm.Quaternion viewerOrientation;

  /// Signed interpupillary offset (`-ipd/2` for left eye, `+ipd/2` for right eye).
  final double eyeOffsetMeters;
  final double verticalFovRadians;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final clampedOpacity = opacity.clamp(0.0, 1.0);
    if (clampedOpacity <= VrSceneConstants.minRenderableWireframeOpacity ||
        segments.isEmpty ||
        size.isEmpty) {
      return;
    }

    final aspect = size.width / math.max(1.0, size.height);
    final focalY = 1.0 / math.tan(verticalFovRadians * 0.5);
    final focalX = focalY / aspect;

    // Eye world position shifted along the head's local +X right vector
    final rightAxis = _rotateQuaternion(
      viewerOrientation,
      vm.Vector3(1.0, 0.0, 0.0),
    );
    final eyeWorld = viewerPosition + rightAxis * eyeOffsetMeters;
    final invOrientation = viewerOrientation.conjugated();

    // Avoid MaskFilter.blur per segment: on Impeller Vulkan (EnableFlutterGPU),
    // per-line Gaussian blur allocates two offscreen render target passes per
    // segment, exhausting GPU memory across stereo viewports. A translucent
    // wide stroke produces the neon halo at zero offscreen allocation cost.
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth =
          VrSceneConstants.defaultContourStrokeWidth *
          VrSceneConstants.wireframeGlowWidthMultiplier;

    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = VrSceneConstants.defaultContourStrokeWidth;

    for (final segment in segments) {
      final p0Cam = _rotateQuaternion(
        invOrientation,
        segment.startWorld - eyeWorld,
      );
      final p1Cam = _rotateQuaternion(
        invOrientation,
        segment.endWorld - eyeWorld,
      );

      // Both endpoints must be in front of the near clip plane (z < -0.08)
      if (p0Cam.z >= VrSceneConstants.wireframeNearClipPlaneZ ||
          p1Cam.z >= VrSceneConstants.wireframeNearClipPlaneZ) {
        continue;
      }

      final s0 = _projectToScreen(p0Cam, size, focalX, focalY);
      final s1 = _projectToScreen(p1Cam, size, focalX, focalY);

      final baseColor = Color(segment.colorArgb);
      final alpha =
          (clampedOpacity *
                  segment.confidence.clamp(
                    VrSceneConstants.minSegmentConfidenceAlpha,
                    1.0,
                  ))
              .clamp(0.0, 1.0);
      glowPaint.color = baseColor.withValues(
        alpha: alpha * VrSceneConstants.wireframeGlowAlphaMultiplier,
      );
      corePaint.color = baseColor.withValues(alpha: alpha);

      canvas.drawLine(s0, s1, glowPaint);
      canvas.drawLine(s0, s1, corePaint);
    }
  }

  /// Projects a 3D world point into 2D screen coordinates for the given eye
  /// pose and FOV, or returns `null` if behind the near clip plane (`z >= -0.08`).
  static Offset? projectPointToEye({
    required vm.Vector3 worldPoint,
    required vm.Vector3 viewerPosition,
    required vm.Quaternion viewerOrientation,
    required Size viewportSize,
    double eyeOffsetMeters = 0.0,
    double verticalFovRadians =
        VrSceneConstants.defaultEyeViewportVerticalFovRadians,
  }) {
    if (viewportSize.isEmpty) return null;
    final aspect = viewportSize.width / math.max(1.0, viewportSize.height);
    final focalY = 1.0 / math.tan(verticalFovRadians * 0.5);
    final focalX = focalY / aspect;
    final rightAxis = _rotateQuaternion(
      viewerOrientation,
      vm.Vector3(1.0, 0.0, 0.0),
    );
    final eyeWorld = viewerPosition + rightAxis * eyeOffsetMeters;
    final invOrientation = viewerOrientation.conjugated();
    final pCam = _rotateQuaternion(invOrientation, worldPoint - eyeWorld);
    if (pCam.z >= VrSceneConstants.wireframeNearClipPlaneZ) return null;
    return _projectToScreen(pCam, viewportSize, focalX, focalY);
  }

  static Offset _projectToScreen(
    vm.Vector3 camPoint,
    Size size,
    double focalX,
    double focalY,
  ) {
    final invZ = -1.0 / camPoint.z;
    final ndcX = camPoint.x * invZ * focalX;
    final ndcY = camPoint.y * invZ * focalY;
    final px = (ndcX * 0.5 + 0.5) * size.width;
    final py = (0.5 - ndcY * 0.5) * size.height;
    return Offset(px, py);
  }

  static vm.Vector3 _rotateQuaternion(vm.Quaternion q, vm.Vector3 v) {
    final u = vm.Vector3(q.x, q.y, q.z);
    final w = q.w;
    final uvCross = u.cross(v);
    final uuvCross = u.cross(uvCross);
    return v + uvCross * (2.0 * w) + uuvCross * 2.0;
  }

  @override
  bool shouldRepaint(covariant VrSpatialWireframePainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.viewerPosition != viewerPosition ||
        oldDelegate.viewerOrientation != viewerOrientation ||
        oldDelegate.eyeOffsetMeters != eyeOffsetMeters ||
        oldDelegate.opacity != opacity;
  }
}
