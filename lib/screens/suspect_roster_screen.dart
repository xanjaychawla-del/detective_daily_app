import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final theCase = ref.watch(caseProvider);
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
              subtitle: Text(suspect.role),
              trailing: Wrap(
                spacing: 6,
                children: [
                  if (interviewed)
                    Tooltip(
                      message: fullyInterviewed ? 'Fully interviewed' : 'Interview in progress',
                      child: Icon(
                        Icons.check_circle,
                        color: fullyInterviewed ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                    ),
                  if (contradiction)
                    const Tooltip(message: 'Contradiction found', child: Icon(Icons.flag, color: Colors.deepOrange, size: 20)),
                  if (ruledOut)
                    const Tooltip(message: 'Ruled out', child: Icon(Icons.block, color: Colors.grey, size: 20)),
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
