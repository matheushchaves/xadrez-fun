import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/features/strategy/plan_suggester.dart';
import 'package:xadrez_fun/engine/engine_api.dart';

import '../../fixtures/strategy_fixtures.dart';

void main() {
  final fixtures = loadStrategyFixtures();

  const phaseByName = {
    'Abertura': GamePhase.opening,
    'Meio-jogo': GamePhase.middlegame,
    'Final': GamePhase.endgame,
  };

  for (final name in fixtures.keys) {
    test('plano bate com o fixture "$name" (sem avaliação)', () {
      final fen = fixtures[name]['fen'] as String;
      final expected = fixtures[name]['plan'] as Map<String, dynamic>;
      final position = Chess.fromSetup(Setup.parseFen(fen));

      final result = suggestPlan(position, null);

      expect(result.phase, phaseByName[expected['phase']]);
      expect(result.characteristics, expected['characteristics']);
      expect(result.plans, expected['plans']);
      expect(result.avoid, expected['avoid']);
      expect(result.evaluationText, isNull);
    });
  }

  test('com avaliação, evaluationText usa formatEvaluation', () {
    final position = Chess.initial;
    final result = suggestPlan(position, const CpEval(31));
    expect(result.evaluationText, isNotNull);
  });
}
