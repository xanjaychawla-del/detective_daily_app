import 'package:detective_daily_app/conversation_engine/conversation_engine.dart';
import 'package:detective_daily_app/game_engine/game_state.dart';
import 'package:detective_daily_app/truth_engine/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/test_case.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(overrides: [caseProvider.overrideWith((ref) => buildTestCase())]);
  });

  tearDown(() => container.dispose());

  test('opening an interview reveals the seeded opening lie once, then nothing on repeat visits', () {
    final engine = container.read(conversationEngineProvider);

    final first = engine.openInterview('alice');
    expect(first, isNotNull);
    expect(first!.isLie, isTrue);
    expect(container.read(gameStateProvider).interviewedSuspectIds, contains('alice'));

    final second = engine.openInterview('alice');
    expect(second, isNull);
  });

  test('opening an interview for a suspect with no seeded lie returns null but still marks interviewed', () {
    final engine = container.read(conversationEngineProvider);
    final result = engine.openInterview('bob'); // fixture gives bob no initialLie
    expect(result, isNull);
    expect(container.read(gameStateProvider).interviewedSuspectIds, contains('bob'));
  });

  test('askCategory reveals facts in order then returns null once exhausted', () {
    final engine = container.read(conversationEngineProvider);
    final first = engine.askCategory('alice', FactCategory.timeline);
    expect(first, isNotNull);
    final second = engine.askCategory('alice', FactCategory.timeline); // fixture only seeds one
    expect(second, isNull);
  });

  test('presenting the contradicting evidence flags a contradiction exactly once', () {
    final engine = container.read(conversationEngineProvider);
    final reaction = engine.presentEvidence('alice', 'ev1');
    expect(reaction, isNotNull);
    expect(container.read(gameStateProvider).contradictionSuspectIds, contains('alice'));

    engine.presentEvidence('alice', 'ev1'); // presenting again must not duplicate the flag
    expect(container.read(gameStateProvider).contradictionSuspectIds.length, 1);
  });

  test('presenting evidence with no matching reaction returns null and flags nothing', () {
    final engine = container.read(conversationEngineProvider);
    final reaction = engine.presentEvidence('bob', 'ev1'); // bob has no reaction to ev1
    expect(reaction, isNull);
    expect(container.read(gameStateProvider).contradictionSuspectIds, isEmpty);
  });
}
