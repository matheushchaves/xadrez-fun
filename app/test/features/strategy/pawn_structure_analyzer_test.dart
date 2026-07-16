import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/features/strategy/pawn_structure_analyzer.dart';

import '../../fixtures/strategy_fixtures.dart';

void main() {
  final fixtures = loadStrategyFixtures();

  for (final name in fixtures.keys) {
    test('estrutura de peões bate com o fixture "$name"', () {
      final fen = fixtures[name]['fen'] as String;
      final expected = fixtures[name]['pawns'] as Map<String, dynamic>;
      final position = Chess.fromSetup(Setup.parseFen(fen));

      final result = analyzePawnStructure(position);

      for (final (side, sideResult) in [
        ('white', result.white),
        ('black', result.black),
      ]) {
        final expectedSide = expected[side] as Map<String, dynamic>;
        expect(
          sideResult.count,
          expectedSide['count'],
          reason: '$name/$side count',
        );
        expect(
          sideResult.islands,
          expectedSide['islands'],
          reason: '$name/$side islands',
        );
        expect(
          sideResult.passed,
          expectedSide['passed'],
          reason: '$name/$side passed',
        );
        expect(
          sideResult.doubled,
          expectedSide['doubled'],
          reason: '$name/$side doubled',
        );
        expect(
          sideResult.isolated,
          expectedSide['isolated'],
          reason: '$name/$side isolated',
        );
      }
    });
  }
}
