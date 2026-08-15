/// vrlizate_scene — flutter_scene (Flutter GPU) adapter for the vrlizate
/// VR engine.
///
/// Optional module: the vrlizate core stays renderer-agnostic. Add this
/// package when you want real-time PBR 3D scenes (glTF, shadows, IBL)
/// rendered stereoscopically with vrlizate head tracking and gaze input.
///
/// Requires Flutter master channel (Flutter GPU) and
/// `flutter config --enable-dart-data-assets`.
library;

export 'src/stereo_head_rig.dart';
export 'src/stereo_scene_view.dart';
