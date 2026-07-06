import 'package:detective_daily_app/game_engine/game_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/test_case.dart';

void main() {
  test("starts with the case's starting focus and in-progress outcome", () {
    final container = ProviderContainer(overrides: [caseProvider.overrideWith((ref) => buildTestCase())]);
    addTearDown(container.dispose);
    final state = container.read(gameStateProvider);
    expect(state.focus, 10);
    expect(state.outcome, GameOutcome.inProgress);
  });

  test('give up concludes the case, and further accusations no longer change the outcome', () {
    final container = ProviderContainer(overrides: [caseProvider.overrideWith((ref) => buildTestCase())]);
    addTearDown(container.dispose);
    final notifier = container.read(gameStateProvider.notifier);
    notifier.giveUp();
    expect(container.read(gameStateProvider).outcome, GameOutcome.gaveUp);

    notifier.accuse('bob');
    expect(container.read(gameStateProvider).outcome, GameOutcome.gaveUp);
  });

  test('background check requires having interviewed the suspect first, regardless of difficulty', () {
    final container = ProviderContainer(overrides: [caseProvider.overrideWith((ref) => buildTestCase())]);
    addTearDown(container.dispose);
    final notifier = container.read(gameStateProvider.notifier);
    expect(notifier.runBackgroundCheck('alice'), isFalse);
    expect(container.read(gameStateProvider).backgroundCheckDoneIds, isEmpty);

    notifier.interview('alice');
    expect(notifier.runBackgroundCheck('alice'), isTrue);
    expect(container.read(gameStateProvider).backgroundCheckDoneIds, contains('alice'));
  });

  group('normal mode (default) -- Focus is off', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(overrides: [caseProvider.overrideWith((ref) => buildTestCase())]);
    });

    tearDown(() => container.dispose());

    test('evidence unlocks and background checks are free, regardless of the case\'s costs', () {
      final notifier = container.read(gameStateProvider.notifier);
      notifier.interview('alice');

      expect(notifier.unlockEvidence('ev2'), isTrue); // costs 15 in hard mode, free here
      expect(notifier.runBackgroundCheck('alice'), isTrue);
      expect(container.read(gameStateProvider).focus, 10); // untouched
    });

    test('wrong accusation rules out the suspect but does not touch Focus', () {
      final notifier = container.read(gameStateProvider.notifier);
      notifier.accuse('alice'); // alice is not the culprit in the fixture
      final state = container.read(gameStateProvider);
      expect(state.ruledOutSuspectIds, contains('alice'));
      expect(state.focus, 10);
      expect(state.outcome, GameOutcome.inProgress);
    });

    test('re-accusing an already ruled-out suspect is a no-op', () {
      final notifier = container.read(gameStateProvider.notifier);
      notifier.accuse('alice');
      notifier.accuse('alice');
      expect(container.read(gameStateProvider).ruledOutSuspectIds.length, 1);
    });

    test('correct accusation solves the case', () {
      final notifier = container.read(gameStateProvider.notifier);
      notifier.accuse('bob'); // bob is the culprit in the fixture
      expect(container.read(gameStateProvider).outcome, GameOutcome.solved);
    });
  });

  group('hard mode -- Focus is a real limited resource', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(overrides: [
        caseProvider.overrideWith((ref) => buildTestCase()),
        hardModeProvider.overrideWith((ref) => true),
      ]);
    });

    tearDown(() => container.dispose());

    test('wrong accusation rules out the suspect, costs focus, and does not conclude the game', () {
      final notifier = container.read(gameStateProvider.notifier);
      notifier.accuse('alice'); // alice is not the culprit in the fixture
      final state = container.read(gameStateProvider);
      expect(state.ruledOutSuspectIds, contains('alice'));
      expect(state.focus, 7); // 10 - 3
      expect(state.outcome, GameOutcome.inProgress);
    });

    test('re-accusing an already ruled-out suspect is a no-op, never double-charges Focus', () {
      final notifier = container.read(gameStateProvider.notifier);
      notifier.accuse('alice');
      notifier.accuse('alice');
      expect(container.read(gameStateProvider).focus, 7);
    });

    test('correct accusation solves the case without touching focus', () {
      final notifier = container.read(gameStateProvider.notifier);
      notifier.accuse('bob'); // bob is the culprit in the fixture
      final state = container.read(gameStateProvider);
      expect(state.outcome, GameOutcome.solved);
      expect(state.focus, 10);
    });

    test('background check costs focus once interviewed', () {
      final notifier = container.read(gameStateProvider.notifier);
      notifier.interview('alice');
      expect(notifier.runBackgroundCheck('alice'), isTrue);
      expect(container.read(gameStateProvider).focus, 7); // 10 - 3
    });

    test('evidence unlock fails without enough focus, succeeds once affordable, and is idempotent', () {
      final notifier = container.read(gameStateProvider.notifier);
      expect(notifier.unlockEvidence('ev2'), isFalse); // costs 15, only 10 focus available
      expect(container.read(gameStateProvider).unlockedEvidenceIds, isEmpty);

      expect(notifier.unlockEvidence('ev1'), isTrue); // costs 2
      expect(container.read(gameStateProvider).focus, 8);

      expect(notifier.unlockEvidence('ev1'), isTrue); // already unlocked -- no re-charge
      expect(container.read(gameStateProvider).focus, 8);
    });
  });
}
