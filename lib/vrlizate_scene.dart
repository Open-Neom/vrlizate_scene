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

export 'domain/models/vr_detected_spatial_object.dart';
export 'domain/models/vr_spatial_contour_segment.dart';
export 'domain/models/vr_spatial_sonar_pulse.dart';
export 'domain/services/vr_multi_camera_space_mapper.dart';
export 'domain/services/vr_scene_transition_controller.dart';
export 'src/avatar/vr_avatar_node.dart';
export 'src/animation/vr_actor_animation.dart';
export 'src/animation/vr_exploded_scene_rig.dart';
export 'src/animation/vr_limb_kinematics.dart';
export 'src/assets/vr_glb_template_cache.dart';
export 'src/quality_preset.dart';
export 'ui/vr_spatial_passthrough_overlay.dart';
export 'ui/vr_spatial_wireframe_painter.dart';
export 'utils/constants/vr_scene_constants.dart';
export 'utils/enums/vr_lighting_preset.dart';
export 'utils/enums/vr_passthrough_mode.dart';
export 'utils/enums/vr_scene_transition_style.dart';
export 'utils/enums/vr_spatial_object_category.dart';
export 'src/vr_device_performance.dart';
export 'src/vr_frame_metrics.dart';
export 'src/vr_headset_profile.dart';
export 'src/vr_fixed_foveation.dart';
export 'src/stereo_head_rig.dart';
export 'src/stereo_hud_overlay.dart';
export 'src/vr_demo_exit_overlay.dart';
export 'src/vr_spatial_tracking.dart';
export 'src/vr_stick_look.dart';
export 'src/vr_viewer_profile.dart';
export 'src/vr_gpu_resource_gate.dart';
export 'src/stereo_scene_view.dart';
export 'src/retained_scene_adapter.dart';
export 'src/retained_desktop_input.dart';
export 'src/retained_demo_scene_view.dart';
export 'src/lathe_geometry.dart';
export 'src/vr_glow.dart';
export 'src/vr_particles.dart';
export 'src/vr_sky.dart';
export 'src/pbr_texture_synth.dart';
export 'src/pbr_texture_library.dart';
export 'src/vr_look.dart';
export 'src/vr_spatial_audio.dart';
export 'src/vr_thermal_governor.dart';
export 'src/vr_world_navigation_scope.dart';
export 'src/vr_input_session_scope.dart';
export 'src/vr_controller_feedback.dart';
export 'src/vr_zenith_recenter.dart';
export 'src/streaming/vr_scene_region.dart';
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
        VrWidgetSurface3D,
        VrWorldTextSpec,
        VrWorldTextNodeBuilder,
        VrWordsphereConstants,
        VrWordspherePlane,
        VrWordsphereSessionController,
        controlMaterial,
        VrControlMeshBuilder;
