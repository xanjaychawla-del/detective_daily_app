import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../case_repository/case_repository_providers.dart';
import '../conversation_engine/conversation_engine.dart';
import '../game_engine/game_state.dart';
import '../onboarding/coachmark_overlay.dart';
import '../onboarding/onboarding_prefs.dart';
import '../truth_engine/models.dart';

class InterrogationScreen extends ConsumerStatefulWidget {
  final String suspectId;
  const InterrogationScreen({super.key, required this.suspectId});

  @override
  ConsumerState<InterrogationScreen> createState() => _InterrogationScreenState();
}

class _InterrogationScreenState extends ConsumerState<InterrogationScreen> {
  final ScrollController _scroll = ScrollController();
  final AudioPlayer _player = AudioPlayer();
  final _categoriesKey = GlobalKey();
  final _presentEvidenceKey = GlobalKey();
  bool _loading = false;
  bool _showTutorial = false;

  Suspect get _suspect => ref.read(caseProvider)!.suspectById(widget.suspectId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInterview());
    OnboardingPrefs.hasSeen(kInterrogationTutorialKey).then((seen) {
      if (seen || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showTutorial = true);
      });
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _player.dispose();
    super.dispose();
  }

  void _dismissTutorial() {
    setState(() => _showTutorial = false);
    OnboardingPrefs.markSeen(kInterrogationTutorialKey);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _appendLine(TranscriptLine line) {
    ref.read(gameStateProvider.notifier).appendTranscriptLine(widget.suspectId, line);
    _scrollToBottom();
  }

  Future<void> _openInterview() async {
    // Re-opening a suspect already interviewed shows their existing
    // transcript (persisted in GameState) rather than starting blank --
    // jump straight to the bottom of it.
    final alreadyHadLines =
        (ref.read(gameStateProvider).transcripts[widget.suspectId] ?? const []).isNotEmpty;
    final fact = ref.read(conversationEngineProvider).openInterview(widget.suspectId);
    if (fact != null) {
      await _sayFact(fact, category: 'introduction');
    } else if (alreadyHadLines) {
      _scrollToBottom();
    }
  }

  Future<void> _sayFact(Fact fact, {required String category}) async {
    setState(() => _loading = true);
    String text = fact.text;
    String? audioUrl;
    try {
      final narration = await ref.read(caseRepositoryServiceProvider).fetchFactNarration(
            caseId: ref.read(caseProvider)!.id,
            suspect: _suspect,
            factId: fact.id,
            factText: fact.text,
            category: category,
          );
      text = narration.phrasedText;
      audioUrl = narration.audioUrl;
    } catch (_) {
      // Narration is a nice-to-have, never a blocker -- fall back to the
      // raw fact text if phrasing/narration fails for any reason.
    }
    if (!mounted) return;
    setState(() => _loading = false);
    _appendLine(TranscriptLine(speaker: _suspect.name, text: text, audioUrl: audioUrl));
    if (audioUrl != null) await _playAudioUrl(audioUrl);
  }

  Future<void> _playAudioUrl(String url) async {
    try {
      await _player.setUrl(url);
      await _player.play();
    } catch (_) {
      // Silent fallback -- the text is already shown either way.
    }
  }

  Future<void> _ask(FactCategory category) async {
    if (_loading) return;
    final fact = ref.read(conversationEngineProvider).askCategory(widget.suspectId, category);
    if (fact == null) {
      _appendLine(const TranscriptLine(text: "They've said everything they're going to on that."));
      return;
    }
    await _sayFact(fact, category: category.name);
  }

  Future<void> _presentEvidence(Evidence evidence) async {
    if (_loading) return;
    _appendLine(TranscriptLine(text: 'You present: ${evidence.label}.'));
    final reaction = ref.read(conversationEngineProvider).presentEvidence(widget.suspectId, evidence.id);
    if (reaction == null) {
      _appendLine(const TranscriptLine(text: "They don't have much to say about that."));
      return;
    }
    await _sayFact(Fact(id: reaction.id, text: reaction.text, isLie: reaction.isLie), category: 'evidence');
  }

  void _openEvidenceSheet() {
    final unlocked = ref.read(gameStateProvider).unlockedEvidenceIds;
    final items = ref.read(caseProvider)!.evidence.where((e) => unlocked.contains(e.id)).toList();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: items.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No evidence unlocked yet. Unlock evidence from the Evidence Board tab.'),
              )
            : ListView(
                shrinkWrap: true,
                children: items
                    .map((e) => ListTile(
                          title: Text(e.label),
                          subtitle: Text(e.description),
                          trailing: const Icon(Icons.front_hand),
                          onTap: () {
                            Navigator.pop(ctx);
                            _presentEvidence(e);
                          },
                        ))
                    .toList(),
              ),
      ),
    );
  }

  String _categoryLabel(FactCategory category) => switch (category) {
        FactCategory.timeline => 'Timeline',
        FactCategory.motive => 'Motive',
        FactCategory.relationships => 'Relationships',
        FactCategory.alibi => 'Alibi',
      };

  @override
  Widget build(BuildContext context) {
    final engine = ref.read(conversationEngineProvider);
    final gameState = ref.watch(gameStateProvider); // rebuild when focus/progress/evidence/transcript changes
    final lines = gameState.transcripts[widget.suspectId] ?? const <TranscriptLine>[];

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_suspect.name, overflow: TextOverflow.ellipsis),
            Text(
              _suspect.role,
              style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.normal),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: lines.length,
              itemBuilder: (context, i) {
                final line = lines[i];
                final isSystem = line.speaker == null;
                if (isSystem) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: Text(
                        line.text,
                        style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(child: Text(line.text)),
                        if (line.audioUrl != null) ...[
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => _playAudioUrl(line.audioUrl!),
                            borderRadius: BorderRadius.circular(16),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.replay_circle_filled, size: 20, color: Colors.white54),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Wrap(
                    key: _categoriesKey,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final category in FactCategory.values)
                        ActionChip(
                          label: Text(_categoryLabel(category)),
                          onPressed: !_loading && engine.hasMoreInCategory(widget.suspectId, category)
                              ? () => _ask(category)
                              : null,
                        ),
                    ],
                  ),
                  ActionChip(
                    key: _presentEvidenceKey,
                    avatar: const Icon(Icons.fact_check, size: 18),
                    label: const Text('Present Evidence'),
                    onPressed: _loading ? null : _openEvidenceSheet,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Stack(
      children: [
        scaffold,
        if (_showTutorial)
          CoachmarkOverlay(
            steps: [
              CoachmarkStep(
                targetKey: _categoriesKey,
                title: 'Ask Questions',
                description: 'Tap a category to ask about it -- Timeline, Motive, Relationships, or Alibi.',
              ),
              CoachmarkStep(
                targetKey: _presentEvidenceKey,
                title: 'Present Evidence',
                description: "Once you've unlocked evidence on the Evidence Board, present it here to catch a contradiction.",
              ),
            ],
            onFinished: _dismissTutorial,
          ),
      ],
    );
  }
}
