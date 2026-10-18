import 'package:flutter/material.dart';

import 'stereo_head_rig.dart' show vrHandheldConsoleMode;

/// Renders a 2D HUD / UI overlay duplicated across both eye viewports
/// (Left Eye: 0..0.5 width, Right Eye: 0.5..1.0 width) so it is correctly
/// positioned, visible, and comfortable to read through VR headsets / Cardboard.
/// In single-screen handheld console mode ([vrHandheldConsoleMode]), it renders
/// once across the centered viewport.
class StereoHudOverlay extends StatelessWidget {
  final Widget? child;
  final Widget Function(BuildContext context, int eyeIndex)? builder;
  final Alignment alignment;
  final EdgeInsetsGeometry padding;

  /// Horizontal pixel disparity between left and right eyes to place the HUD
  /// at a comfortable 3D depth plane (~1.8m) instead of flat at infinity.
  /// (Positive value moves Left eye rightwards, Right eye leftwards).
  final double depthDisparity;

  /// Proportional optical correction shared with [StereoHeadRig].
  ///
  /// `0.10` translates each HUD inward by 5% of its eye viewport so 2D
  /// overlays remain aligned with the corrected 3D projection on long phones.
  final double stereoImageInset;

  const StereoHudOverlay({
    super.key,
    this.child,
    this.builder,
    this.alignment = const Alignment(0.0, 0.45),
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    this.depthDisparity = 4.0,
    this.stereoImageInset = 0.10,
  }) : assert(
         child != null || builder != null,
         'Either child or builder must be provided',
       ),
       assert(
         stereoImageInset >= 0 && stereoImageInset <= 0.35,
         'stereoImageInset must be between 0 and 0.35',
       );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: vrHandheldConsoleMode,
      builder: (context, handheld, _) {
        if (handheld) {
          return Padding(
            padding: padding,
            child: Align(
              alignment: alignment,
              child: builder != null ? builder!(context, 0) : child!,
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final halfWidth = constraints.maxWidth / 2;
            final opticalShift = halfWidth * stereoImageInset / 2;
            return Stack(
              fit: StackFit.expand,
              children: [
                for (int eyeIndex = 0; eyeIndex < 2; eyeIndex++)
                  Positioned(
                    left: eyeIndex * halfWidth,
                    width: halfWidth,
                    top: 0,
                    bottom: 0,
                    child: ClipRect(
                      child: Transform.translate(
                        offset: Offset(
                          (eyeIndex == 0 ? 1 : -1) *
                              (opticalShift + depthDisparity / 2),
                          0,
                        ),
                        child: Padding(
                          padding: padding,
                          child: Align(
                            alignment: alignment,
                            child: builder != null
                                ? builder!(context, eyeIndex)
                                : child!,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
