import 'package:detective_daily_app/truth_engine/models.dart';

/// A small, hand-built Case used across engine tests -- deliberately
/// unrelated to the authored museum-diamond content so these tests keep
/// passing even if that case's narrative changes.
Case buildTestCase() {
  return Case(
    id: 'test-case',
    title: 'Test Case',
    briefing: 'A briefing for testing purposes.',
    startingFocus: 10,
    costs: const CaseCosts(unlockEvidence: 2, backgroundCheck: 3, wrongAccusation: 3),
    suspects: [
      Suspect(
        id: 'alice',
        name: 'Alice',
        role: 'Witness',
        persona: 'Calm and precise.',
        facts: SuspectFacts(
          timeline: const [Fact(id: 'a_t1', text: 'Alice was near the door at 8pm.')],
          motive: const [],
          relationships: const [],
          alibi: const [],
          evidenceReactions: const [
            EvidenceReaction(id: 'a_e1', evidenceId: 'ev1', text: 'Alice reacts to ev1.'),
          ],
        ),
        backgroundCheck: const BackgroundCheckResult(flagged: false, text: 'Clean record.'),
        initialLie: const InitialLie(
          id: 'a_lie',
          text: 'Alice claims she was never near the door.',
          contradictedByEvidenceId: 'ev1',
        ),
      ),
      Suspect(
        id: 'bob',
        name: 'Bob',
        role: 'Culprit',
        persona: 'Nervous.',
        facts: const SuspectFacts(
          timeline: [],
          motive: [],
          relationships: [],
          alibi: [],
          evidenceReactions: [],
        ),
        backgroundCheck: const BackgroundCheckResult(flagged: true, text: 'Flagged record.'),
      ),
    ],
    evidence: const [
      Evidence(id: 'ev1', suspectId: 'alice', label: 'Evidence 1', description: 'A relevant clue.', unlockCost: 2),
      Evidence(id: 'ev2', suspectId: 'bob', label: 'Evidence 2', description: 'An expensive clue.', unlockCost: 15),
    ],
    timeline: const [
      TimelineEntry(time: '8:00 PM', type: TimelineEntryType.confirmed, text: 'Something confirmed happened.'),
    ],
    solution: const Solution(culpritId: 'bob', narrative: 'Bob did it, for reasons.'),
  );
}
