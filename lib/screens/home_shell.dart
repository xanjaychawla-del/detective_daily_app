import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game_engine/game_state.dart';
import 'accusation_screen.dart';
import 'case_briefing_header.dart';
import 'case_intro_overlay.dart';
import 'case_outcome_screen.dart';
import 'evidence_board_screen.dart';
import 'suspect_roster_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _showIntro = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: ref.read(homeTabIndexProvider),
    );
    // Swiping changes _tabController.index directly -- mirror that back into
    // the shared provider so other screens (case_outcome_screen resetting to
    // Suspects on Play Again) stay the single source of truth for which tab
    // is active.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(homeTabIndexProvider.notifier).state = _tabController.index;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<GameState>(gameStateProvider, (previous, next) {
      final wasInProgress = previous == null || previous.outcome == GameOutcome.inProgress;
      if (wasInProgress && next.outcome != GameOutcome.inProgress) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CaseOutcomeScreen()));
      }
    });
    // External changes to the shared tab index (bottom nav taps, or a reset
    // to Suspects from the outcome screen) drive the TabController here.
    ref.listen<int>(homeTabIndexProvider, (previous, next) {
      if (_tabController.index != next) _tabController.animateTo(next);
    });

    final tabIndex = ref.watch(homeTabIndexProvider);
    final theCase = ref.watch(caseProvider)!;

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              const CaseBriefingHeader(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    SuspectRosterScreen(),
                    EvidenceBoardScreen(),
                    AccusationScreen(),
                  ],
                ),
              ),
            ],
          ),
          if (_showIntro)
            CaseIntroOverlay(
              title: theCase.title,
              briefing: theCase.briefing,
              onDismissed: () {
                if (mounted) setState(() => _showIntro = false);
              },
            ),
        ],
      ),
      bottomNavigationBar: _showIntro
          ? null
          : NavigationBar(
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
