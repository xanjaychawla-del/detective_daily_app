import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../case_repository/case_repository_providers.dart';
import '../case_repository/case_repository_service.dart';
import '../core/theme.dart';
import '../game_engine/game_state.dart';

/// Solving and giving up share this screen and both show the full
/// narrative reveal -- only the label and framing differ ("Case Closed"
/// vs "Case Revealed"), never a bare name.
class CaseOutcomeScreen extends ConsumerStatefulWidget {
  const CaseOutcomeScreen({super.key});

  @override
  ConsumerState<CaseOutcomeScreen> createState() => _CaseOutcomeScreenState();
}

class _CaseOutcomeScreenState extends ConsumerState<CaseOutcomeScreen> {
  int? _selectedRating;
  bool _ratingSubmitted = false;

  Future<void> _rate(String caseId, int rating) async {
    setState(() => _selectedRating = rating);
    try {
      await ref.read(caseRepositoryServiceProvider).submitRating(caseId, rating);
      if (mounted) setState(() => _ratingSubmitted = true);
    } catch (_) {
      // Rating is a nice-to-have, not core to the case-solving loop --
      // fail silently rather than blocking the player here.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theCase = ref.watch(caseProvider)!;
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
              Text('Rate this case', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: () => _rate(theCase.id, i),
                      icon: Icon(
                        _selectedRating != null && i <= _selectedRating!
                            ? Icons.star
                            : Icons.star_border,
                        color: kAccentAmber,
                      ),
                    ),
                  if (_ratingSubmitted)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Text('Thanks!', style: TextStyle(color: Colors.white54)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        // Same case, fresh session -- just resets progress.
                        // A single pop returns to the HomeShell already on
                        // the stack underneath this outcome screen.
                        ref.invalidate(gameStateProvider);
                        ref.read(homeTabIndexProvider.notifier).state = 0;
                        Navigator.of(context).pop();
                      },
                      child: const Text('Play Again'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await ref.read(caseRepositoryServiceProvider).setPlayStatus(
                              theCase.id,
                              solved ? PlayStatus.solved : PlayStatus.gaveUp,
                            );
                        ref.invalidate(caseListProvider);
                        if (!context.mounted) return;
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      child: const Text('Back to Cases'),
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
