import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game_engine/game_state.dart';

/// Solving and giving up share this screen and both show the full
/// narrative reveal -- only the label and framing differ ("Case Closed"
/// vs "Case Revealed"), never a bare name.
class CaseOutcomeScreen extends ConsumerWidget {
  const CaseOutcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theCase = ref.watch(caseProvider);
    final gameState = ref.watch(gameStateProvider);
    final hardMode = ref.watch(hardModeProvider);
    final solved = gameState.outcome == GameOutcome.solved;
    final culprit = theCase.suspectById(theCase.solution.culpritId);

    return Scaffold(
      appBar: AppBar(
        title: Text(solved ? 'Case Closed' : 'Case Revealed'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                solved
                    ? 'You correctly identified ${culprit.name} as the culprit.'
                    : "You gave up before naming the culprit. Here's what actually happened.",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(theCase.solution.narrative, style: Theme.of(context).textTheme.bodyLarge),
                ),
              ),
              const Divider(height: 24),
              _StatRow(label: 'Accusations made', value: '${gameState.accusationAttempts}'),
              _StatRow(label: 'Contradictions found', value: '${gameState.contradictionSuspectIds.length}'),
              if (hardMode) _StatRow(label: 'Focus remaining', value: '${gameState.focus}'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        // Same case, fresh session -- just resets progress.
                        ref.invalidate(gameStateProvider);
                        ref.read(homeTabIndexProvider.notifier).state = 0;
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      child: const Text('Play Again'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final cases = ref.read(allCasesProvider);
                        final currentIndex = cases.indexWhere((c) => c.id == theCase.id);
                        final nextCase = cases[(currentIndex + 1) % cases.length];
                        // Switching caseProvider's value makes GameStateNotifier
                        // rebuild from scratch for the new case automatically.
                        ref.read(caseProvider.notifier).state = nextCase;
                        ref.read(homeTabIndexProvider.notifier).state = 0;
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      child: const Text('New Case'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
        ),
      );
}
