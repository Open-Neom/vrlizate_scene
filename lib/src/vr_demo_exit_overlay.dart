import 'package:flutter/material.dart';

import 'stereo_hud_overlay.dart';

/// Persistent stereoscopic exit affordance shared by every immersive demo.
class VrDemoExitOverlay extends StatelessWidget {
  const VrDemoExitOverlay({
    super.key,
    required this.demoTitle,
    required this.onExit,
  });

  final String demoTitle;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return StereoHudOverlay(
      alignment: const Alignment(-0.78, -0.78),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      depthDisparity: 7,
      builder: (_, eyeIndex) => Semantics(
        button: true,
        label: 'Salir de $demoTitle y volver al Home',
        child: Tooltip(
          message: 'Volver al Home',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onExit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xE6293150), Color(0xE6080816)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.75),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.north_west_rounded,
                    color: Color(0xFF67E8F9),
                    size: 16,
                  ),
                  SizedBox(width: 5),
                  Text(
                    'HOME',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
