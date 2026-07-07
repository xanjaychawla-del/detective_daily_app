import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Shown full-screen the moment a case is opened, before the suspects/
/// evidence/accuse UI is usable. Tapping anywhere animates the title and
/// briefing text up into the compact header position (where they land,
/// already expanded, in CaseBriefingHeader) while the game UI underneath
/// fades into view.
class CaseIntroOverlay extends StatefulWidget {
  final String title;
  final String briefing;
  final VoidCallback onDismissed;

  const CaseIntroOverlay({
    super.key,
    required this.title,
    required this.briefing,
    required this.onDismissed,
  });

  @override
  State<CaseIntroOverlay> createState() => _CaseIntroOverlayState();
}

class _CaseIntroOverlayState extends State<CaseIntroOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _dismissing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissing) return;
    setState(() => _dismissing = true);
    _controller.forward().whenComplete(widget.onDismissed);
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value;
        return IgnorePointer(
          ignoring: t >= 1,
          child: Opacity(
            opacity: 1 - t,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismiss,
              child: Container(
                color: kSurfaceBackground,
                width: double.infinity,
                height: double.infinity,
                alignment: Alignment.lerp(Alignment.center, Alignment.topCenter, t),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
                child: Transform.scale(
                  scale: 1 - (t * 0.3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.briefing,
                        style: const TextStyle(fontSize: 16, color: Colors.white70, height: 1.4),
                      ),
                      const SizedBox(height: 40),
                      if (!_dismissing)
                        const Align(
                          alignment: Alignment.center,
                          child: Text(
                            'Tap anywhere to begin',
                            style: TextStyle(color: Colors.white38, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
