import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../game_engine/game_state.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatToday() {
  final now = DateTime.now();
  return '${_months[now.month - 1]} ${now.day}, ${now.year}';
}

/// Shown on every screen, per the fairness rule that the case briefing
/// should never be tucked away on just one tab.
class CaseBriefingHeader extends ConsumerWidget {
  const CaseBriefingHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theCase = ref.watch(caseProvider)!;
    final focus = ref.watch(gameStateProvider.select((s) => s.focus));
    final hardMode = ref.watch(hardModeProvider);
    final briefExpanded = ref.watch(briefExpandedProvider);

    return Material(
      color: kSurfaceCard,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    tooltip: 'Case Files',
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                  ),
                  Expanded(
                    child: Text(
                      'DETECTIVE DAILY · ${_formatToday()}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune, color: Colors.white70),
                    tooltip: 'Difficulty',
                    onPressed: () => _showDifficultyDialog(context, ref),
                  ),
                ],
              ),
              InkWell(
                onTap: () => ref.read(briefExpandedProvider.notifier).state = !briefExpanded,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(theCase.title, style: Theme.of(context).textTheme.titleLarge),
                    ),
                    Icon(
                      briefExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: briefExpanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(theCase.briefing, style: const TextStyle(color: Colors.white70)),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              if (hardMode) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.bolt, size: 14, color: kAccentAmber),
                    const SizedBox(width: 4),
                    Text(
                      'FOCUS $focus/${theCase.startingFocus}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kAccentAmber),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: theCase.startingFocus == 0 ? 0 : focus / theCase.startingFocus,
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(kAccentAmber),
                  ),
                ),
              ],
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
