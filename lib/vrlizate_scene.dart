/// vrlizate_scene — flutter_scene (Flutter GPU) adapter for the vrlizate
/// VR engine.
///
/// Optional module: the vrlizate core stays renderer-agnostic. Add this
/// package when you want PBR 3D scenes (glTF and image-based lighting)
/// rendered stereoscopically with vrlizate head tracking and gaze input.
///
/// Requires a Flutter GPU / flutter_scene compatible runtime. See the package
/// README for platform setup, profiling guidance, and rendering limitations.
library;

export 'src/quality_preset.dart';
export 'src/stereo_head_rig.dart';
export 'src/vr_viewer_profile.dart';
export 'src/vr_gpu_resource_gate.dart';
export 'src/stereo_scene_view.dart';
export 'src/retained_scene_adapter.dart';
export 'src/vr_look.dart';
export 'src/vr_spatial_audio.dart';
export 'src/vr_thermal_governor.dart';
export 'src/vr_world_navigation_scope.dart';
export 'src/vr_input_session_scope.dart';
export 'src/vr_controller_feedback.dart';
export 'src/openxr/vr_gpu_external_render_target.dart';
export 'src/openxr/vr_openxr_swapchain_bridge.dart';
export 'src/openxr/vr_openxr_native_bridge.dart';
export 'src/openxr/vr_decoupled_render_loop.dart';
export 'src/openxr/vr_spatial_ui_quad_layer.dart';
export 'package:vrlizate/vrlizate.dart'
    show
        VrInputArbiter,
        VrInputEvent,
        VrInputListener,
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
        VrSegmentedControl3D,
        VrProgressBar3D,
        VrStepper3D,
        VrTextBitmap,
        VrTextRaster,
        VrTextLabel,
        VrWorldPose,
        VrWorldAction,
        VrWorldActionPanel3D,
        VrWorldTextSpec,
        VrWorldTextNodeBuilder,
        controlMaterial,
        VrControlMeshBuilder;
