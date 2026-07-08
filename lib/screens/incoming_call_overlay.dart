import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:just_audio/just_audio.dart';

import '../case_repository/case_repository_providers.dart';
import '../core/theme.dart';

const _kInspectorNames = [
  'Reyes',
  'Okafor',
  'Chen',
  'Whitfield',
  'Alvarez',
  'Novak',
  'Sato',
  'Bianchi',
  'Kowalski',
  'Adebayo',
];

// A plain char-code sum, not Dart's String.hashCode -- this must match
// supabase/functions/generate-briefing-audio/index.ts's pickInspectorName
// exactly so the name shown on screen always matches the name spoken in
// the cached audio for the same case id.
String _pickInspectorName(String caseId) {
  var sum = 0;
  for (final unit in caseId.codeUnits) {
    sum += unit;
  }
  return _kInspectorNames[sum % _kInspectorNames.length];
}

enum _CallPhase { ringing, briefing, dismissing }

/// Replaces the plain tap-to-dismiss case intro with a simulated incoming
/// call from "Inspector `<name>`". Answering plays the case briefing aloud
/// via a cached Google Cloud TTS narration (generated once per case,
/// reused by every player -- see generate-briefing-audio). Ringtone
/// playback uses the platform's real system ringtone on Android; iOS has
/// no public API for a user's actual ringtone, so it falls back to a
/// generic bundled ring sound there -- a platform limitation, not a bug.
class IncomingCallOverlay extends ConsumerStatefulWidget {
  final String caseId;
  final String title;
  final String briefing;
  final VoidCallback onFinished;

  const IncomingCallOverlay({
    super.key,
    required this.caseId,
    required this.title,
    required this.briefing,
    required this.onFinished,
  });

  @override
  ConsumerState<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends ConsumerState<IncomingCallOverlay> with SingleTickerProviderStateMixin {
  late final String _inspectorName = _pickInspectorName(widget.caseId);
  final AudioPlayer _player = AudioPlayer();
  _CallPhase _phase = _CallPhase.ringing;
  bool _loadingAudio = false;
  late final AnimationController _dismissController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void initState() {
    super.initState();
    FlutterRingtonePlayer().playRingtone();
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) _finish();
    });
  }

  @override
  void dispose() {
    FlutterRingtonePlayer().stop();
    _player.dispose();
    _dismissController.dispose();
    super.dispose();
  }

  Future<void> _answer() async {
    FlutterRingtonePlayer().stop();
    setState(() {
      _phase = _CallPhase.briefing;
      _loadingAudio = true;
    });
    try {
      final audioUrl = await ref.read(caseRepositoryServiceProvider).fetchBriefingAudioUrl(widget.caseId);
      if (!mounted) return;
      setState(() => _loadingAudio = false);
      await _player.setUrl(audioUrl);
      await _player.play();
    } catch (_) {
      _finish();
    }
  }

  // Declining isn't a way out of the case -- the inspector just calls back.
  // The ringtone pauses briefly then resumes; only Answer moves things
  // forward.
  Future<void> _decline() async {
    FlutterRingtonePlayer().stop();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || _phase != _CallPhase.ringing) return;
    FlutterRingtonePlayer().playRingtone();
  }

  void _finish() {
    if (_phase == _CallPhase.dismissing || !mounted) return;
    _player.stop();
    setState(() => _phase = _CallPhase.dismissing);
    _dismissController.forward().whenComplete(widget.onFinished);
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _CallPhase.dismissing) {
      return AnimatedBuilder(
        animation: _dismissController,
        builder: (context, child) {
          final t = CurvedAnimation(parent: _dismissController, curve: Curves.easeInOutCubic).value;
          return IgnorePointer(
            child: Opacity(opacity: 1 - t, child: Container(color: kSurfaceBackground)),
          );
        },
      );
    }

    final ringing = _phase == _CallPhase.ringing;
    return GestureDetector(
      // Absorbs taps on the empty areas of this screen so they can't fall
      // through to the suspect list underneath (a plain Container with no
      // gesture handler on a given point isn't hit-test opaque by default).
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              children: [
                const SizedBox(height: 24),
                CircleAvatar(
                  radius: 52,
                  backgroundColor: kSurfaceCard,
                  child: const Icon(Icons.local_police, size: 52, color: kAccentAmber),
                ),
                const SizedBox(height: 20),
                Text(
                  'Inspector $_inspectorName',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  ringing ? 'Incoming call...' : (_loadingAudio ? 'Connecting...' : 'On call'),
                  style: const TextStyle(color: Colors.white54, fontSize: 15),
                ),
                const Spacer(),
                if (!ringing)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.briefing,
                        style: const TextStyle(fontSize: 15, color: Colors.white70, height: 1.4),
                      ),
                    ],
                  ),
                const Spacer(),
                if (ringing)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallButton(icon: Icons.call_end, color: Colors.redAccent, label: 'Decline', onTap: _decline),
                      _CallButton(icon: Icons.call, color: Colors.greenAccent, label: 'Answer', onTap: _answer),
                    ],
                  )
                else
                  _CallButton(icon: Icons.call_end, color: Colors.redAccent, label: 'Hang up', onTap: _finish),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CallButton({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.black, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
