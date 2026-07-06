import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game_engine/game_state.dart';

/// Shown on every screen, per the fairness rule that the case briefing
/// should never be tucked away on just one tab.
class CaseBriefingHeader extends ConsumerWidget {
  const CaseBriefingHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theCase = ref.watch(caseProvider);
    final focus = ref.watch(gameStateProvider.select((s) => s.focus));
    final hardMode = ref.watch(hardModeProvider);

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(theCase.title, style: Theme.of(context).textTheme.titleLarge),
                  ),
                  if (hardMode) ...[
                    Chip(
                      avatar: const Icon(Icons.bolt, size: 18),
                      label: Text('$focus Focus'),
                    ),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    icon: const Icon(Icons.tune),
                    tooltip: 'Difficulty',
                    onPressed: () => _showDifficultyDialog(context, ref),
                  ),
                ],
              ),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  // Keyed by case id so switching cases starts freshly
                  // expanded again, rather than staying collapsed from
                  // whatever state the previous case's tile was left in.
                  key: ValueKey(theCase.id),
                  initiallyExpanded: true,
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Case briefing'),
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(theCase.briefing),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDifficultyDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, dialogRef, _) {
          final hardMode = dialogRef.watch(hardModeProvider);
          return AlertDialog(
            title: const Text('Difficulty'),
            content: RadioGroup<bool>(
              groupValue: hardMode,
              onChanged: (value) => dialogRef.read(hardModeProvider.notifier).state = value!,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<bool>(
                    value: false,
                    title: Text('Normal'),
                    subtitle: Text('Explore freely -- evidence and background checks are free.'),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    title: Text('Hard'),
                    subtitle: Text('Evidence, background checks, and wrong accusations cost Focus.'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
            ],
          );
        },
      ),
    );
  }
}
