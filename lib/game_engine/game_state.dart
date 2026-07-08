/// Game Engine: Focus economy, evidence unlocking, contradiction tracking,
/// and accusation/outcome logic. Holds the session's mutable progress —
/// never the case truth itself, which stays in the Truth Engine.
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../truth_engine/models.dart';

/// The currently active case, set when the player picks one on the
/// CaseListScreen. Null until then -- every screen that reads this is only
/// ever built inside HomeShell, which is only pushed after a case is chosen,
/// so reads there can safely assume non-null.
final caseProvider = StateProvider<Case?>((ref) => null);

/// Focus is off by default -- evidence and background checks are free, and
/// wrong accusations carry no penalty. Turning this on (a difficulty
/// setting, not a core rule) makes Focus a real limited resource again.
final hardModeProvider = StateProvider<bool>((ref) => false);

/// Which HomeShell tab is selected (0=Suspects, 1=Evidence, 2=Accuse).
/// Lives outside HomeShell's own State so other screens (like the case
/// outcome reveal) can reset it back to the roster when a case changes.
final homeTabIndexProvider = StateProvider<int>((ref) => 0);

/// Whether the full case briefing text is showing in the header (vs.
/// collapsed to just the title). Starts collapsed on the Suspects/
/// Evidence/Accuse tabs -- the player's already heard the briefing via
/// the incoming call, so the header stays out of the way, but they can
/// expand it from any tab anytime.
final briefExpandedProvider = StateProvider<bool>((ref) => false);

enum GameOutcome { inProgress, solved, gaveUp }

/// One line of an interrogation transcript. speaker is null for
/// neutral/system lines (e.g. "You present: X."); audioUrl is null for
/// lines with no narration (system lines, or narration that failed) --
/// only lines with a non-null audioUrl get a replay button.
class TranscriptLine {
  final String? speaker;
  final String text;
  final String? audioUrl;
  const TranscriptLine({this.speaker, required this.text, this.audioUrl});
}

class GameState {
  final int focus;
  final Set<String> interviewedSuspectIds;
  final Set<String> unlockedEvidenceIds;
  final Set<String> backgroundCheckDoneIds;
  final Set<String> contradictionSuspectIds;
  final Set<String> ruledOutSuspectIds;
  final Map<String, int> factProgress;
  final Map<String, List<TranscriptLine>> transcripts;
  final int accusationAttempts;
  final GameOutcome outcome;

  const GameState({
    required this.focus,
    required this.interviewedSuspectIds,
    required this.unlockedEvidenceIds,
    required this.backgroundCheckDoneIds,
    required this.contradictionSuspectIds,
    required this.ruledOutSuspectIds,
    required this.factProgress,
    required this.transcripts,
    required this.accusationAttempts,
    required this.outcome,
  });

  factory GameState.initial(int startingFocus) => GameState(
        focus: startingFocus,
        interviewedSuspectIds: const {},
        unlockedEvidenceIds: const {},
        backgroundCheckDoneIds: const {},
        contradictionSuspectIds: const {},
        ruledOutSuspectIds: const {},
        factProgress: const {},
        transcripts: const {},
        accusationAttempts: 0,
        outcome: GameOutcome.inProgress,
      );

  GameState copyWith({
    int? focus,
    Set<String>? interviewedSuspectIds,
    Set<String>? unlockedEvidenceIds,
    Set<String>? backgroundCheckDoneIds,
    Set<String>? contradictionSuspectIds,
    Set<String>? ruledOutSuspectIds,
    Map<String, int>? factProgress,
    Map<String, List<TranscriptLine>>? transcripts,
    int? accusationAttempts,
    GameOutcome? outcome,
  }) {
    return GameState(
      focus: focus ?? this.focus,
      interviewedSuspectIds: interviewedSuspectIds ?? this.interviewedSuspectIds,
      unlockedEvidenceIds: unlockedEvidenceIds ?? this.unlockedEvidenceIds,
      backgroundCheckDoneIds: backgroundCheckDoneIds ?? this.backgroundCheckDoneIds,
      contradictionSuspectIds: contradictionSuspectIds ?? this.contradictionSuspectIds,
      ruledOutSuspectIds: ruledOutSuspectIds ?? this.ruledOutSuspectIds,
      factProgress: factProgress ?? this.factProgress,
      transcripts: transcripts ?? this.transcripts,
      accusationAttempts: accusationAttempts ?? this.accusationAttempts,
      outcome: outcome ?? this.outcome,
    );
  }
}

String _factProgressKey(String suspectId, FactCategory category) => '$suspectId|${category.name}';

class GameStateNotifier extends Notifier<GameState> {
  @override
  GameState build() {
    final theCase = ref.watch(caseProvider)!;
    return GameState.initial(theCase.startingFocus);
  }

  Case get _case => ref.read(caseProvider)!;

  bool get isConcluded => state.outcome != GameOutcome.inProgress;

  bool get hardMode => ref.read(hardModeProvider);

  void interview(String suspectId) {
    if (state.interviewedSuspectIds.contains(suspectId)) return;
    state = state.copyWith(interviewedSuspectIds: {...state.interviewedSuspectIds, suspectId});
  }

  /// Appends one line to a suspect's interrogation transcript so it
  /// survives navigating away and back -- re-opening a suspect shows their
  /// full conversation so far, not a blank screen.
  void appendTranscriptLine(String suspectId, TranscriptLine line) {
    final existing = state.transcripts[suspectId] ?? const <TranscriptLine>[];
    state = state.copyWith(transcripts: {...state.transcripts, suspectId: [...existing, line]});
  }

  /// Returns the next not-yet-revealed fact for this suspect/category, or
  /// null once every fact in that category has already been asked about.
  Fact? peekNextFact(String suspectId, FactCategory category) {
    final facts = _case.suspectById(suspectId).facts.byCategory(category);
    final idx = state.factProgress[_factProgressKey(suspectId, category)] ?? 0;
    if (idx >= facts.length) return null;
    return facts[idx];
  }

  /// True once every category (Timeline/Motive/Relationships/Alibi) has
  /// been asked all the way through for this suspect.
  bool isFullyInterviewed(String suspectId) {
    for (final category in FactCategory.values) {
      if (peekNextFact(suspectId, category) != null) return false;
    }
    return true;
  }

  /// Advances the category's reveal index and returns the fact just
  /// revealed (matches peekNextFact's result before advancing).
  Fact? askCategory(String suspectId, FactCategory category) {
    final fact = peekNextFact(suspectId, category);
    if (fact == null) return null;
    final key = _factProgressKey(suspectId, category);
    final idx = state.factProgress[key] ?? 0;
    state = state.copyWith(factProgress: {...state.factProgress, key: idx + 1});
    return fact;
  }

  bool canAffordEvidence(String evidenceId) {
    if (!hardMode) return true;
    final evidence = _case.evidence.firstWhere((e) => e.id == evidenceId);
    return state.focus >= evidence.unlockCost;
  }

  bool unlockEvidence(String evidenceId) {
    if (state.unlockedEvidenceIds.contains(evidenceId)) return true;
    if (!hardMode) {
      state = state.copyWith(unlockedEvidenceIds: {...state.unlockedEvidenceIds, evidenceId});
      return true;
    }
    final evidence = _case.evidence.firstWhere((e) => e.id == evidenceId);
    if (state.focus < evidence.unlockCost) return false;
    state = state.copyWith(
      focus: state.focus - evidence.unlockCost,
      unlockedEvidenceIds: {...state.unlockedEvidenceIds, evidenceId},
    );
    return true;
  }

  bool canAffordBackgroundCheck() => !hardMode || state.focus >= _case.costs.backgroundCheck;

  bool runBackgroundCheck(String suspectId) {
    if (!state.interviewedSuspectIds.contains(suspectId)) return false;
    if (state.backgroundCheckDoneIds.contains(suspectId)) return true;
    if (!hardMode) {
      state = state.copyWith(backgroundCheckDoneIds: {...state.backgroundCheckDoneIds, suspectId});
      return true;
    }
    final cost = _case.costs.backgroundCheck;
    if (state.focus < cost) return false;
    state = state.copyWith(
      focus: state.focus - cost,
      backgroundCheckDoneIds: {...state.backgroundCheckDoneIds, suspectId},
    );
    return true;
  }

  /// Presents an unlocked piece of evidence to a suspect. Returns their
  /// reaction fact if they have one for this evidence, else null (callers
  /// should show a neutral "nothing to add" line — never suspect-specific
  /// wording that would hint at guilt).
  EvidenceReaction? presentEvidence(String suspectId, String evidenceId) {
    final suspect = _case.suspectById(suspectId);
    final matches = suspect.facts.evidenceReactions.where((r) => r.evidenceId == evidenceId);
    final reaction = matches.isEmpty ? null : matches.first;

    final lie = suspect.initialLie;
    if (lie != null &&
        lie.contradictedByEvidenceId == evidenceId &&
        !state.contradictionSuspectIds.contains(suspectId)) {
      state = state.copyWith(contradictionSuspectIds: {...state.contradictionSuspectIds, suspectId});
    }
    return reaction;
  }

  /// Wrong guesses cost Focus (clamped at 0) and rule the suspect out, but
  /// never end the case — only a correct guess or Give Up concludes it.
  void accuse(String suspectId) {
    if (isConcluded) return;
    if (state.ruledOutSuspectIds.contains(suspectId)) return;
    if (suspectId == _case.solution.culpritId) {
      state = state.copyWith(
        outcome: GameOutcome.solved,
        accusationAttempts: state.accusationAttempts + 1,
      );
      return;
    }
    state = state.copyWith(
      focus: hardMode ? math.max(0, state.focus - _case.costs.wrongAccusation) : state.focus,
      ruledOutSuspectIds: {...state.ruledOutSuspectIds, suspectId},
      accusationAttempts: state.accusationAttempts + 1,
    );
  }

  void giveUp() {
    if (isConcluded) return;
    state = state.copyWith(outcome: GameOutcome.gaveUp);
  }
}

final gameStateProvider = NotifierProvider<GameStateNotifier, GameState>(GameStateNotifier.new);
