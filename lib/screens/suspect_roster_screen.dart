import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../game_engine/game_state.dart';
import 'interrogation_screen.dart';

/// Badges shown here are purely progress markers -- interviewed,
/// contradiction found, ruled out. Never a guilt indicator: every suspect
/// looks exactly the same shape of card until the player earns a reason to
/// think otherwise.
class SuspectRosterScreen extends ConsumerWidget {
  const SuspectRosterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theCase = ref.watch(caseProvider)!;
    final gameState = ref.watch(gameStateProvider);
    final notifier = ref.read(gameStateProvider.notifier);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: theCase.suspects.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final suspect = theCase.suspects[index];
        final interviewed = gameState.interviewedSuspectIds.contains(suspect.id);
        final fullyInterviewed = interviewed && notifier.isFullyInterviewed(suspect.id);
        final contradiction = gameState.contradictionSuspectIds.contains(suspect.id);
        final ruledOut = gameState.ruledOutSuspectIds.contains(suspect.id);

        return Opacity(
          opacity: ruledOut ? 0.55 : 1,
          child: Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(suspect.name.substring(0, 1))),
              title: Text(suspect.name),
              subtitle: Text(suspect.role, style: const TextStyle(color: Colors.white60)),
              trailing: Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  _StatusPill(
                    label: interviewed ? (fullyInterviewed ? 'Interviewed' : 'Interview in progress') : 'Not interviewed',
                    color: interviewed ? (fullyInterviewed ? Colors.greenAccent : kAccentAmber) : Colors.white38,
                  ),
                  if (contradiction) const _StatusPill(label: 'Contradiction found', color: Colors.deepOrangeAccent),
                  if (ruledOut) const _StatusPill(label: 'Ruled out', color: Colors.white38),
                ],
              ),
              enabled: !ruledOut,
              onTap: ruledOut
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => InterrogationScreen(suspectId: suspect.id)),
                      ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
}
