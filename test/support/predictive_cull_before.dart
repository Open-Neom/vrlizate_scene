// Frozen GFX063 BEFORE builder; replay oracle, never imported by production.
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:vector_math/vector_math.dart' as vm;

List<vm.Plane> buildBeforePredictivePlanes({
  required vm.Vector3 eyePosition,
  required vm.Vector3 forward,
  required vm.Vector3 screenRight,
  required vm.Vector3 up,
  required double fovRadiansY,
  required double fullEyeAspectRatio,
  required ui.Rect normalizedCropRect,
  double horizontalClipShift = 0.0,
  double safetyMarginRadians = 0.085,
  double? dynamicFarCullMeters,
}) {
  if (fovRadiansY <= 0.05 ||
      !fovRadiansY.isFinite ||
      fullEyeAspectRatio <= 0.05 ||
      !fullEyeAspectRatio.isFinite) {
    return const [];
  }
  final planes = <vm.Plane>[];
  final tanHalfY = math.tan(fovRadiansY * 0.5);
  final tanHalfX = tanHalfY * fullEyeAspectRatio;
  final guardX = math.tan(safetyMarginRadians) + horizontalClipShift.abs();
  final guardY = math.tan(safetyMarginRadians);

  // Map normalized crop [0..1] (top-left origin) into tangent bounds:
  // u=0 -> -tanHalfX, u=1 -> +tanHalfX; v=0 -> +tanHalfY (top), v=1 -> -tanHalfY (bottom).
  final leftClip = normalizedCropRect.left * 2.0 - 1.0;
  final rightClip = normalizedCropRect.right * 2.0 - 1.0;
  final topClip = 1.0 - normalizedCropRect.top * 2.0;
  final bottomClip = 1.0 - normalizedCropRect.bottom * 2.0;

  final tauLeft = leftClip * tanHalfX - guardX;
  final tauRight = rightClip * tanHalfX + guardX;
  final tauBottom = bottomClip * tanHalfY - guardY;
  final tauTop = topClip * tanHalfY + guardY;

  vm.Plane makeConePlane(vm.Vector3 rawNormal) {
    final n = rawNormal.normalized();
    return vm.Plane.components(n.x, n.y, n.z, -n.dot(eyePosition));
  }

  // Only emit side planes when tighter than the uncropped eye frustum,
  // avoiding duplicate plane tests when full 1.0 x 1.0 viewport is active.
  if (normalizedCropRect.left > 0.01) {
    planes.add(makeConePlane(screenRight - forward * tauLeft));
  }
  if (normalizedCropRect.right < 0.99) {
    planes.add(makeConePlane(-screenRight + forward * tauRight));
  }
  if (normalizedCropRect.bottom < 0.99) {
    planes.add(makeConePlane(up - forward * tauBottom));
  }
  if (normalizedCropRect.top > 0.01) {
    planes.add(makeConePlane(-up + forward * tauTop));
  }

  if (dynamicFarCullMeters != null &&
      dynamicFarCullMeters.isFinite &&
      dynamicFarCullMeters > 4.0) {
    final f = forward.normalized();
    planes.add(
      vm.Plane.components(
        -f.x,
        -f.y,
        -f.z,
        f.dot(eyePosition) + dynamicFarCullMeters,
      ),
    );
  }
  return planes;
}
