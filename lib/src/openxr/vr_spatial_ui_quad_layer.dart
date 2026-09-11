import 'package:vector_math/vector_math.dart' as vm;

/// Decoupled spatial 2D UI composition layer corresponding to OpenXR's `XrCompositionLayerQuad`.
///
/// Instead of rasterizing Flutter 2D widgets into the 3D scene every frame
/// (which triggers full-screen scene repaints and causes blurry, filtered text),
/// UI subtrees are rasterized to an offscreen texture once and submitted directly
/// to the OpenXR compositor as a standalone spatial quad layer.
///
/// When the UI is static ([isDirty] is false), it costs **0 ms** of rendering work
/// in the 3D stereo render loop.
class VrSpatialUiQuadLayer {
  final String layerId;
  final int pixelWidth;
  final int pixelHeight;
  final double widthMeters;
  final double heightMeters;

  vm.Vector3 position;
  vm.Quaternion orientation;

  int? textureId;
  bool _isDirty = true;

  VrSpatialUiQuadLayer({
    required this.layerId,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.widthMeters,
    required this.heightMeters,
    vm.Vector3? position,
    vm.Quaternion? orientation,
    this.textureId,
  })  : position = position ?? vm.Vector3(0, 0, -1.5),
        orientation = orientation ?? vm.Quaternion.identity(),
        assert(pixelWidth > 0, 'pixelWidth must be positive'),
        assert(pixelHeight > 0, 'pixelHeight must be positive'),
        assert(widthMeters > 0, 'widthMeters must be positive'),
        assert(heightMeters > 0, 'heightMeters must be positive');

  bool get isDirty => _isDirty;

  /// Marks this UI quad layer as needing a rasterization repaint.
  void markDirty() {
    _isDirty = true;
  }

  /// Marks this UI layer as clean after rasterization into [textureId] finishes.
  void markClean({int? updatedTextureId}) {
    _isDirty = false;
    if (updatedTextureId != null) {
      textureId = updatedTextureId;
    }
  }

  /// Updates the 3D spatial pose of the quad in world space.
  void setPose({required vm.Vector3 newPosition, required vm.Quaternion newOrientation}) {
    position.setFrom(newPosition);
    orientation.setFrom(newOrientation);
  }

  /// Computes a model transform matrix placing this quad in 3D world space.
  vm.Matrix4 computeTransformMatrix() {
    final rot = vm.Matrix4.identity();
    rot.setRotation(orientation.asRotationMatrix());

    final scale = vm.Matrix4.diagonal3Values(widthMeters, heightMeters, 1.0);
    final trans = vm.Matrix4.translation(position);

    return trans * rot * scale;
  }

  Map<String, Object?> toOpenXrQuadDescriptor() => <String, Object?>{
        'layerId': layerId,
        'textureId': textureId,
        'pixelWidth': pixelWidth,
        'pixelHeight': pixelHeight,
        'widthMeters': widthMeters,
        'heightMeters': heightMeters,
        'pose': <String, Object?>{
          'position': <double>[position.x, position.y, position.z],
          'orientation': <double>[
            orientation.x,
            orientation.y,
            orientation.z,
            orientation.w,
          ],
        },
        'isDirty': _isDirty,
      };

  @override
  String toString() =>
      'VrSpatialUiQuadLayer($layerId, ${pixelWidth}x$pixelHeight px, '
      '${widthMeters.toStringAsFixed(2)}x${heightMeters.toStringAsFixed(2)}m, '
      'dirty: $_isDirty, tex: $textureId)';
}
