import '../constants/vr_scene_constants.dart';

/// Semantic categories for real-world objects and boundaries identified by AI
/// across the Visor and Joystick cameras.
enum VrSpatialObjectCategory {
  floorBoundary,
  wall,
  table,
  chair,
  person,
  pet,
  doorway,
  obstacle,
  handController;

  /// Default high-contrast neon wireframe color (ARGB) for rendering this
  /// category's 3D contour lines in VR.
  int get defaultWireframeColorArgb => switch (this) {
    VrSpatialObjectCategory.floorBoundary ||
    VrSpatialObjectCategory.doorway =>
      VrSceneConstants.contourColorFloorBoundaryArgb,
    VrSpatialObjectCategory.wall => VrSceneConstants.contourColorWallArgb,
    VrSpatialObjectCategory.table ||
    VrSpatialObjectCategory.chair => VrSceneConstants.contourColorFurnitureArgb,
    VrSpatialObjectCategory.person ||
    VrSpatialObjectCategory.pet => VrSceneConstants.contourColorPersonPetArgb,
    VrSpatialObjectCategory.obstacle =>
      VrSceneConstants.contourColorObstacleAlertArgb,
    VrSpatialObjectCategory.handController =>
      VrSceneConstants.contourColorHandControllerArgb,
  };
}
