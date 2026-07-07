import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../game_engine/game_state.dart';
import '../onboarding/coachmark_overlay.dart';
import '../onboarding/onboarding_prefs.dart';
import '../truth_engine/models.dart';

/// Evidence and background checks are scoped per suspect (not one global
/// unlockable list), and background checks are locked until that suspect
/// has been interviewed at least once.
class EvidenceBoardScreen extends ConsumerStatefulWidget {
  const EvidenceBoardScreen({super.key});

  @override
  ConsumerState<EvidenceBoardScreen> createState() => _EvidenceBoardScreenState();
}

class _EvidenceBoardScreenState extends ConsumerState<EvidenceBoardScreen> {
  final FlutterTts _tts = FlutterTts();
  final _timelineKey = GlobalKey();
  final _suspectsKey = GlobalKey();
  bool _playingTimeline = false;
  bool _showTutorial = false;

  @override
  void initState() {
    super.initState();
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _playingTimeline = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _playingTimeline = false);
    });
    OnboardingPrefs.hasSeen(kEvidenceBoardTutorialKey).then((seen) {
      if (seen || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showTutorial = true);
      });
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  void _dismissTutorial() {
    setState(() => _showTutorial = false);
    OnboardingPrefs.markSeen(kEvidenceBoardTutorialKey);
  }

  // On-device TTS reading the timeline exactly as written -- no new AI
  // writing involved. See generate-timeline-audio for the cached-cloud
  // version, parked until there's enough traffic to justify it.
  String _buildTimelineScript(Case theCase) {
    final nameById = {for (final s in theCase.suspects) s.id: s.name};
    final lines = theCase.timeline.map((entry) {
      if (entry.type == TimelineEntryType.confirmed) return 'At ${entry.time}, ${entry.text}';
      final name = entry.suspectId != null ? nameById[entry.suspectId] : null;
      return 'At ${entry.time}, according to ${name ?? 'one witness'}, ${entry.text}';
    });
    return "Here's what we know about the timeline of events. ${lines.join(' ')} That's everything on record so far.";
  }

  Future<void> _toggleTimelineNarration(Case theCase) async {
    if (_playingTimeline) {
      await _tts.stop();
      setState(() => _playingTimeline = false);
      return;
    }
    setState(() => _playingTimeline = true);
    try {
      await _tts.setSpeechRate(0.46);
      await _tts.speak(_buildTimelineScript(theCase));
    } catch (err) {
      if (!mounted) return;
      setState(() => _playingTimeline = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play the timeline narration: $err')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theCase = ref.watch(caseProvider)!;
    final gameState = ref.watch(gameStateProvider);
    final notifier = ref.read(gameStateProvider.notifier);
    final hardMode = ref.watch(hardModeProvider);

    final list = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          key: _timelineKey,
          children: [
            Text('Case Timeline', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              onPressed: () => _toggleTimelineNarration(theCase),
              icon: Icon(_playingTimeline ? Icons.pause_circle : Icons.play_circle),
              tooltip: 'Play timeline narration',
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final entry in theCase.timeline) _TimelineTile(entry: entry),
        const SizedBox(height: 24),
        Text('Suspects', key: _suspectsKey, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final suspect in theCase.suspects)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              title: Text(suspect.name),
              subtitle: Text(suspect.role),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Evidence', style: Theme.of(context).textTheme.labelLarge),
                ),
                for (final evidence in theCase.evidenceForSuspect(suspect.id))
                  _EvidenceTile(evidence: evidence, gameState: gameState, notifier: notifier, hardMode: hardMode),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Background Check', style: Theme.of(context).textTheme.labelLarge),
                ),
                _BackgroundCheckTile(
                  suspect: suspect,
                  interviewed: gameState.interviewedSuspectIds.contains(suspect.id),
                  done: gameState.backgroundCheckDoneIds.contains(suspect.id),
                  cost: theCase.costs.backgroundCheck,
                  notifier: notifier,
                  hardMode: hardMode,
                ),
              ],
            ),
          ),
      ],
    );

    return Stack(
      children: [
        list,
        if (_showTutorial)
          CoachmarkOverlay(
            steps: [
              CoachmarkStep(
                targetKey: _timelineKey,
                title: 'Case Timeline',
                description: 'Confirmed events are solid facts; claimed events are what a suspect says happened -- '
                    "which may not be true. Tap play to hear it narrated.",
              ),
              CoachmarkStep(
                targetKey: _suspectsKey,
                title: 'Evidence & Background Checks',
                description: 'Each suspect has their own evidence to unlock and a background check you can run '
                    'once you\'ve interviewed them.',
              ),
            ],
            onFinished: _dismissTutorial,
          ),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final TimelineEntry entry;
  const _TimelineTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final confirmed = entry.type == TimelineEntryType.confirmed;
    final color = confirmed ? Colors.amber.shade300 : Colors.white54;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6, right: 8),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(
            width: 68,
            child: Text(entry.time, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              entry.text,
              style: TextStyle(color: confirmed ? null : Colors.white54, fontStyle: confirmed ? FontStyle.normal : FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  final Evidence evidence;
  final GameState gameState;
  final GameStateNotifier notifier;
  final bool hardMode;
  const _EvidenceTile({
    required this.evidence,
    required this.gameState,
    required this.notifier,
    required this.hardMode,
  });

  @override
  Widget build(BuildContext context) {
    final unlocked = gameState.unlockedEvidenceIds.contains(evidence.id);
    if (unlocked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle, size: 18, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(evidence.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(evidence.description),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final canAfford = notifier.canAffordEvidence(evidence.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.lock, size: 18, color: Colors.white38),
          const SizedBox(width: 8),
          Expanded(child: Text(evidence.label)),
          TextButton(
            onPressed: canAfford ? () => notifier.unlockEvidence(evidence.id) : null,
            child: Text(hardMode ? 'Unlock (${evidence.unlockCost} Focus)' : 'Unlock'),
          ),
        ],
      ),
    );
  }
}

class _BackgroundCheckTile extends StatelessWidget {
  final Suspect suspect;
  final bool interviewed;
  final bool done;
  final int cost;
  final GameStateNotifier notifier;
  final bool hardMode;
  const _BackgroundCheckTile({
    required this.suspect,
    required this.interviewed,
    required this.done,
    required this.cost,
    required this.notifier,
    required this.hardMode,
  });

  @override
  Widget build(BuildContext context) {
    if (!interviewed) {
      return Row(
        children: const [
          Icon(Icons.lock, size: 18, color: Colors.white38),
          SizedBox(width: 8),
          Expanded(child: Text('Interview this suspect first.', style: TextStyle(color: Colors.white38))),
        ],
      );
    }
    if (done) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle,
            size: 18,
            color: suspect.backgroundCheck.flagged ? Colors.deepOrange : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(suspect.backgroundCheck.text)),
        ],
      );
    }
    final canAfford = notifier.canAffordBackgroundCheck();
    return Row(
      children: [
        const Icon(Icons.search, size: 18),
        const SizedBox(width: 8),
        const Expanded(child: Text('Not yet checked.')),
        TextButton(
          onPressed: canAfford ? () => notifier.runBackgroundCheck(suspect.id) : null,
          child: Text(hardMode ? 'Run check ($cost Focus)' : 'Run check'),
        ),
      ],
    );
  }
}
