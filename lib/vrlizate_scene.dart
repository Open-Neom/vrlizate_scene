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

export 'src/quality_preset.dart';
export 'src/stereo_head_rig.dart';
export 'src/stereo_scene_view.dart';
export 'src/vr_look.dart';
export 'src/vr_spatial_audio.dart';
export 'src/vr_thermal_governor.dart';
export 'package:vrlizate/vrlizate.dart'
    show
        VrInputArbiter,
        VrInputPriority,
        VrInputSource,
        VrInputType,
        VrInputDriver,
        VrInputSink,
        VrGamepadDriver,
        VrGamepadButton,
        VrGamepadStick;

// 3D widgets live in their own module; re-exported here so existing
// vrlizate_scene consumers (demos) keep working with a single import.
export 'package:vrlizate_widgets/vrlizate_widgets.dart'
    show
        VrControl,
        VrControlRegistry,
        VrButton3D,
        VrToggle3D,
        VrDropdown3D,
        VrPanel3D,
        VrWidget,
        VrStatelessWidget,
        VrStatefulWidget,
        VrWidgetState,
        VrSpatial,
        VrDragController,
        VrSlider3D,
        controlMaterial,
        VrControlMeshBuilder;
