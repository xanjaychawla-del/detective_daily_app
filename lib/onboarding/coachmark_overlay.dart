import 'package:flutter/material.dart';

import '../core/theme.dart';

/// One step of a coach-mark sequence: spotlights whatever is at [targetKey]
/// and shows a short title + one-line explanation next to it.
class CoachmarkStep {
  final GlobalKey targetKey;
  final String title;
  final String description;

  const CoachmarkStep({required this.targetKey, required this.title, required this.description});
}

/// A first-run-only overlay that spotlights one UI element at a time with a
/// brief explanation, advancing through [steps] on tap. Meant to be placed
/// in a Stack on top of the already-built screen, once that screen's first
/// frame has rendered (so target keys have valid layout to read).
class CoachmarkOverlay extends StatefulWidget {
  final List<CoachmarkStep> steps;
  final VoidCallback onFinished;

  const CoachmarkOverlay({super.key, required this.steps, required this.onFinished});

  @override
  State<CoachmarkOverlay> createState() => _CoachmarkOverlayState();
}

class _CoachmarkOverlayState extends State<CoachmarkOverlay> {
  int _index = 0;

  Rect? _targetRect() {
    final renderObject = widget.steps[_index].targetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  void _next() {
    if (_index >= widget.steps.length - 1) {
      widget.onFinished();
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rect = _targetRect();
    final step = widget.steps[_index];
    final screenSize = MediaQuery.sizeOf(context);
    final isLast = _index == widget.steps.length - 1;
    final showBubbleAbove = rect != null && rect.center.dy > screenSize.height / 2;

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _next,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SpotlightPainter(rect?.inflate(8)),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              top: rect == null || showBubbleAbove ? null : rect.bottom + 16,
              bottom: rect != null && showBubbleAbove ? screenSize.height - rect.top + 16 : null,
              child: rect == null
                  ? const SizedBox.shrink()
                  : Material(
                      color: kSurfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step.title,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 6),
                            Text(step.description, style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(onPressed: widget.onFinished, child: const Text('Skip')),
                                Text(
                                  '${_index + 1}/${widget.steps.length}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                                ),
                                FilledButton(onPressed: _next, child: Text(isLast ? 'Got it' : 'Next')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? spotlight;

  _SpotlightPainter(this.spotlight);

  @override
  void paint(Canvas canvas, Size size) {
    final scrimPaint = Paint()..color = Colors.black.withValues(alpha: 0.78);
    if (spotlight == null) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), scrimPaint);
      return;
    }
    final scrimPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holeRRect = RRect.fromRectAndRadius(spotlight!, const Radius.circular(12));
    final holePath = Path()..addRRect(holeRRect);
    canvas.drawPath(Path.combine(PathOperation.difference, scrimPath, holePath), scrimPaint);
    canvas.drawRRect(
      holeRRect,
      Paint()
        ..color = kAccentAmber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) => oldDelegate.spotlight != spotlight;
}
