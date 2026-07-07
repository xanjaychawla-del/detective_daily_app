import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/status_pill.dart';
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
            child: InkWell(
              onTap: ruledOut
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => InterrogationScreen(suspectId: suspect.id)),
                      ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(child: Text(suspect.name.substring(0, 1))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            suspect.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            suspect.role,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white60),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              StatusPill(
                                label: interviewed
                                    ? (fullyInterviewed ? 'Interviewed' : 'Interview in progress')
                                    : 'Not interviewed',
                                color: interviewed
                                    ? (fullyInterviewed ? Colors.greenAccent : kAccentAmber)
                                    : Colors.white38,
                              ),
                              if (contradiction)
                                const StatusPill(label: 'Contradiction found', color: Colors.deepOrangeAccent),
                              if (ruledOut) const StatusPill(label: 'Ruled out', color: Colors.white38),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
