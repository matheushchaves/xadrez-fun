import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/features/strategy/king_safety_analyzer.dart';

import '../../fixtures/strategy_fixtures.dart';

void main() {
  final fixtures = loadStrategyFixtures();

  for (final name in fixtures.keys) {
    test('segurança do rei bate com o fixture "$name"', () {
      final fen = fixtures[name]['fen'] as String;
      final expected = fixtures[name]['king'] as Map<String, dynamic>;
      final position = Chess.fromSetup(Setup.parseFen(fen));

      final result = analyzeKingSafety(position);

      for (final (side, sideResult) in [
        ('white', result.white),
        ('black', result.black),
      ]) {
        final expectedSide = expected[side] as Map<String, dynamic>;
        expect(
          sideResult.square,
          expectedSide['square'],
          reason: '$name/$side square',
        );
        expect(
          sideResult.positives,
          expectedSide['positives'],
          reason: '$name/$side positives',
        );
        expect(
          sideResult.issues,
          expectedSide['issues'],
          reason: '$name/$side issues',
        );
        expect(
          sideResult.safetyScore,
          expectedSide['safety_score'],
          reason: '$name/$side safetyScore',
        );
        expect(
          sideResult.safe,
          expectedSide['safe'],
          reason: '$name/$side safe',
        );
      }
    });
  }
}
