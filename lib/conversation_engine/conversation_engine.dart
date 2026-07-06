/// Conversation Engine: decides which fact a suspect is allowed to reveal,
/// when, and to whom. This is the layer that keeps the AI Adapter honest —
/// it only ever hands the adapter one raw fact at a time to phrase.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game_engine/game_state.dart';
import '../truth_engine/models.dart';

class ConversationEngine {
  final Ref ref;

  ConversationEngine(this.ref);

  GameStateNotifier get _game => ref.read(gameStateProvider.notifier);
  Case get _case => ref.read(caseProvider);

  /// Opens an interrogation with a suspect. The first time a suspect is
  /// opened, their opening statement (their one seeded lie, if the case
  /// gives them one) plays automatically and they're marked interviewed.
  /// Returns null on repeat visits — nothing new to open with.
  Fact? openInterview(String suspectId) {
    final alreadyInterviewed = ref.read(gameStateProvider).interviewedSuspectIds.contains(suspectId);
    _game.interview(suspectId);
    if (alreadyInterviewed) return null;

    final lie = _case.suspectById(suspectId).initialLie;
    if (lie == null) return null;
    return Fact(id: lie.id, text: lie.text, isLie: true);
  }

  /// Reveals the next fact in a category, advancing that category's
  /// progress. Returns null once every fact in the category has been asked.
  Fact? askCategory(String suspectId, FactCategory category) => _game.askCategory(suspectId, category);

  bool hasMoreInCategory(String suspectId, FactCategory category) =>
      _game.peekNextFact(suspectId, category) != null;

  /// Presents a piece of unlocked evidence to a suspect. Returns their
  /// specific reaction if the case defines one for this evidence, else
  /// null — callers should render a neutral, identical-in-form fallback
  /// line rather than anything suspect-specific, so presenting evidence
  /// with no reaction never itself signals guilt or innocence.
  EvidenceReaction? presentEvidence(String suspectId, String evidenceId) =>
      _game.presentEvidence(suspectId, evidenceId);
}

final conversationEngineProvider = Provider<ConversationEngine>((ref) => ConversationEngine(ref));
