import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game_engine/game_state.dart';
import '../onboarding/coachmark_overlay.dart';
import '../onboarding/onboarding_prefs.dart';
import 'accusation_screen.dart';
import 'case_briefing_header.dart';
import 'case_outcome_screen.dart';
import 'evidence_board_screen.dart';
import 'incoming_call_overlay.dart';
import 'suspect_roster_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  // The incoming call only plays the first time a case is opened
  // (unopened -> in_progress). Reopening an already-started case skips
  // straight to the Suspects tab.
  final bool isFirstOpen;
  const HomeShell({super.key, required this.isFirstOpen});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late bool _showIntro = widget.isFirstOpen;
  bool _showTutorial = false;
  final _backButtonKey = GlobalKey();
  final _difficultyButtonKey = GlobalKey();
  final _navBarKey = GlobalKey();

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
    // If there's no call to answer this time, the tutorial still needs a
    // chance to show (e.g. the player closed the app before ever seeing it
    // and keeps reopening the same in-progress case).
    if (!widget.isFirstOpen) _maybeShowTutorial();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _maybeShowTutorial() {
    OnboardingPrefs.hasSeen(kHomeShellTutorialKey).then((seen) {
      if (seen || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showTutorial = true);
      });
    });
  }

  void _onIntroDismissed() {
    if (!mounted) return;
    setState(() => _showIntro = false);
    _maybeShowTutorial();
  }

  void _dismissTutorial() {
    setState(() => _showTutorial = false);
    OnboardingPrefs.markSeen(kHomeShellTutorialKey);
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
              CaseBriefingHeader(
                backButtonKey: _backButtonKey,
                difficultyButtonKey: _difficultyButtonKey,
              ),
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
            IncomingCallOverlay(
              caseId: theCase.id,
              title: theCase.title,
              briefing: theCase.briefing,
              onFinished: _onIntroDismissed,
            ),
          if (_showTutorial)
            CoachmarkOverlay(
              steps: [
                CoachmarkStep(
                  targetKey: _backButtonKey,
                  title: 'Back to Case Files',
                  description: 'Tap here anytime to return to your case list -- your progress is saved.',
                ),
                CoachmarkStep(
                  targetKey: _difficultyButtonKey,
                  title: 'Difficulty',
                  description: 'Turn on Hard Mode to make Focus a limited resource for a bigger challenge.',
                ),
                CoachmarkStep(
                  targetKey: _navBarKey,
                  title: 'Suspects · Evidence · Accuse',
                  description: 'Swipe or tap to move between interviewing suspects, reviewing evidence, and making your accusation.',
                ),
              ],
              onFinished: _dismissTutorial,
            ),
        ],
      ),
      bottomNavigationBar: _showIntro
          ? null
          : NavigationBar(
              key: _navBarKey,
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
