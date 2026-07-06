import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game_engine/game_state.dart';
import '../truth_engine/models.dart';

/// Wrong accusations rule a suspect out and cost Focus but never end the
/// case, and never reveal the real culprit's name. Give Up is a distinct,
/// honestly-labeled outcome from actually solving it.
class AccusationScreen extends ConsumerWidget {
  const AccusationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theCase = ref.watch(caseProvider)!;
    final gameState = ref.watch(gameStateProvider);
    final hardMode = ref.watch(hardModeProvider);
    final available = theCase.suspects.where((s) => !gameState.ruledOutSuspectIds.contains(s.id)).toList();
    final ruledOutCount = theCase.suspects.length - available.length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Who is responsible?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            hardMode
                ? 'A wrong accusation rules that suspect out and costs ${theCase.costs.wrongAccusation} Focus, '
                    'but you can keep investigating afterward.'
                : 'A wrong accusation rules that suspect out, but you can keep investigating afterward.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final s in available)
                  Card(
                    child: ListTile(
                      title: Text(s.name),
                      subtitle: Text(s.role),
                      trailing: FilledButton(
                        onPressed: () => _confirmAccuse(context, ref, s, hardMode),
                        child: const Text('Accuse'),
                      ),
                    ),
                  ),
                if (ruledOutCount > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('$ruledOutCount suspect(s) ruled out.', style: const TextStyle(color: Colors.white54)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _confirmGiveUp(context, ref),
            child: const Text('Give Up & Reveal Solution'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAccuse(BuildContext context, WidgetRef ref, Suspect suspect, bool hardMode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Accuse ${suspect.name}?'),
        content: Text(
          hardMode
              ? "This is your formal accusation. If wrong, this suspect will be ruled out and you'll lose some Focus."
              : 'This is your formal accusation. If wrong, this suspect will be ruled out.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accuse')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final wasCorrect = suspect.id == ref.read(caseProvider)!.solution.culpritId;
    ref.read(gameStateProvider.notifier).accuse(suspect.id);
    if (!wasCorrect && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("That's not our culprit. ${suspect.name} has been ruled out.")),
      );
    }
  }

  Future<void> _confirmGiveUp(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Give up?'),
        content: const Text("You'll see the full solution, but this won't count as solving the case."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Investigating')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Give Up')),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(gameStateProvider.notifier).giveUp();
    }
  }
}
