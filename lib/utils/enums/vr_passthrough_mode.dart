/// Selects how real-world camera feeds and AI-detected spatial object contours
/// are blended with the virtual 3D scene in VRlizate.
enum VrPassthroughMode {
  /// Pure virtual 3D rendering (`0%` camera passthrough).
  off,

  /// Live stereoscopic passthrough from the Visor's forward-facing world camera
  /// (with per-eye parallax compensation from `cameraToEyeTranslation`).
  visorCameraPassthrough,

  /// Renders glowing 3D wireframe / edge contour lines of real-world objects,
  /// walls, furniture, pets, and floor boundaries identified by AI across the
  /// Visor and Joystick cameras without hiding the virtual 3D world.
  aiWireframeContours,

  /// Context-aware Mixed Reality mode: fuses the 3 cameras (Visor front +
  /// Joystick front + Joystick rear) so AI wireframe contours appear when an
  /// obstacle enters the safety radius (`< 1.15 m`) and floor passthrough
  /// fades in automatically when the user glances downward (`pitch < -27.5°`).
  multiCameraHybridSpace,
}
