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
  final _overlayKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
  }

  // Some steps target content inside a scrollable screen (e.g. the
  // Evidence Board's "Suspects" section can sit below the fold) -- bring
  // it into view before the spotlight tries to circle it. A no-op if the
  // target's already on screen or isn't inside a Scrollable.
  Future<void> _ensureVisible() async {
    final ctx = widget.steps[_index].targetKey.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 200), alignment: 0.5);
    if (mounted) setState(() {});
  }

  // This overlay is a Positioned.fill inside whatever Stack the host
  // screen wraps it in. That Stack doesn't always start at the true
  // screen origin (e.g. Evidence Board's Stack sits inside a TabBarView,
  // below the case briefing header) -- so the target's *global* position
  // has to be converted into coordinates *local to this overlay* before
  // the CustomPaint canvas (which only knows its own local space) can
  // draw the cutout in the right place.
  RenderBox? get _overlayBox => _overlayKey.currentContext?.findRenderObject() as RenderBox?;

  Rect? _targetRect() {
    final renderObject = widget.steps[_index].targetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final globalRect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final overlayBox = _overlayBox;
    if (overlayBox == null || !overlayBox.hasSize) return globalRect;
    return (overlayBox.globalToLocal(globalRect.topLeft) & globalRect.size);
  }

  void _next() {
    if (_index >= widget.steps.length - 1) {
      widget.onFinished();
    } else {
      setState(() => _index++);
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
    }
  }

  @override
  Widget build(BuildContext context) {
    final rect = _targetRect();
    final step = widget.steps[_index];
    final screenSize = _overlayBox?.hasSize == true ? _overlayBox!.size : MediaQuery.sizeOf(context);
    final isLast = _index == widget.steps.length - 1;
    final showBubbleAbove = rect != null && rect.center.dy > screenSize.height / 2;

    return Positioned.fill(
      child: GestureDetector(
        key: _overlayKey,
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
