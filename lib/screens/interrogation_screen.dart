import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai_adapter/ai_adapter_service.dart';
import '../conversation_engine/conversation_engine.dart';
import '../game_engine/game_state.dart';
import '../truth_engine/models.dart';

class _TranscriptLine {
  final String? speaker; // null = neutral/system line
  final String text;
  const _TranscriptLine({this.speaker, required this.text});
}

class InterrogationScreen extends ConsumerStatefulWidget {
  final String suspectId;
  const InterrogationScreen({super.key, required this.suspectId});

  @override
  ConsumerState<InterrogationScreen> createState() => _InterrogationScreenState();
}

class _InterrogationScreenState extends ConsumerState<InterrogationScreen> {
  final List<_TranscriptLine> _lines = [];
  final List<SpokenLine> _history = [];
  final ScrollController _scroll = ScrollController();
  bool _loading = false;

  Suspect get _suspect => ref.read(caseProvider).suspectById(widget.suspectId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInterview());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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

  Future<void> _openInterview() async {
    final fact = ref.read(conversationEngineProvider).openInterview(widget.suspectId);
    if (fact != null) await _sayFact(fact, category: 'introduction');
  }

  Future<void> _sayFact(Fact fact, {required String category}) async {
    setState(() => _loading = true);
    final phrased = await ref.read(aiAdapterServiceProvider).narrate(
          suspectName: _suspect.name,
          persona: _suspect.persona,
          fact: fact.text,
          category: category,
          history: _history,
        );
    if (!mounted) return;
    setState(() {
      _lines.add(_TranscriptLine(speaker: _suspect.name, text: phrased));
      _history.add(SpokenLine(role: 'suspect', text: phrased));
      _loading = false;
    });
    _scrollToBottom();
  }

  Future<void> _ask(FactCategory category) async {
    if (_loading) return;
    final fact = ref.read(conversationEngineProvider).askCategory(widget.suspectId, category);
    if (fact == null) {
      setState(() => _lines.add(const _TranscriptLine(text: "They've said everything they're going to on that.")));
      _scrollToBottom();
      return;
    }
    await _sayFact(fact, category: category.name);
  }

  Future<void> _presentEvidence(Evidence evidence) async {
    if (_loading) return;
    setState(() => _lines.add(_TranscriptLine(text: 'You present: ${evidence.label}.')));
    _scrollToBottom();
    final reaction = ref.read(conversationEngineProvider).presentEvidence(widget.suspectId, evidence.id);
    if (reaction == null) {
      setState(() => _lines.add(const _TranscriptLine(text: "They don't have much to say about that.")));
      _scrollToBottom();
      return;
    }
    await _sayFact(Fact(id: reaction.id, text: reaction.text, isLie: reaction.isLie), category: 'evidence');
  }

  void _openEvidenceSheet() {
    final unlocked = ref.read(gameStateProvider).unlockedEvidenceIds;
    final items = ref.read(caseProvider).evidence.where((e) => unlocked.contains(e.id)).toList();
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
    ref.watch(gameStateProvider); // rebuild when focus/progress/evidence changes

    return Scaffold(
      appBar: AppBar(title: Text(_suspect.name)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _lines.length,
              itemBuilder: (context, i) {
                final line = _lines[i];
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
                    child: Text(line.text),
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
                  for (final category in FactCategory.values)
                    ActionChip(
                      label: Text(_categoryLabel(category)),
                      onPressed: !_loading && engine.hasMoreInCategory(widget.suspectId, category)
                          ? () => _ask(category)
                          : null,
                    ),
                  ActionChip(
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
  }
}
