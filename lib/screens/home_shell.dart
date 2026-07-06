import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game_engine/game_state.dart';
import 'accusation_screen.dart';
import 'case_briefing_header.dart';
import 'case_outcome_screen.dart';
import 'evidence_board_screen.dart';
import 'suspect_roster_screen.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<GameState>(gameStateProvider, (previous, next) {
      final wasInProgress = previous == null || previous.outcome == GameOutcome.inProgress;
      if (wasInProgress && next.outcome != GameOutcome.inProgress) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CaseOutcomeScreen()));
      }
    });

    final tabIndex = ref.watch(homeTabIndexProvider);

    const tabs = [
      SuspectRosterScreen(),
      EvidenceBoardScreen(),
      AccusationScreen(),
    ];

    return Scaffold(
      body: Column(
        children: [
          const CaseBriefingHeader(),
          Expanded(child: IndexedStack(index: tabIndex, children: tabs)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (i) => ref.read(homeTabIndexProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people), label: 'Suspects'),
          NavigationDestination(icon: Icon(Icons.fact_check), label: 'Evidence'),
          NavigationDestination(icon: Icon(Icons.gavel), label: 'Accuse'),
        ],
      ),
    );
  }
}
