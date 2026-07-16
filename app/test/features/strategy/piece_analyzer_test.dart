import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/features/strategy/piece_analyzer.dart';

import '../../fixtures/strategy_fixtures.dart';

void main() {
  final fixtures = loadStrategyFixtures();

  for (final name in fixtures.keys) {
    test('peças batem com o fixture "$name"', () {
      final fen = fixtures[name]['fen'] as String;
      final expected = fixtures[name]['pieces'] as Map<String, dynamic>;
      final position = Chess.fromSetup(Setup.parseFen(fen));

      final result = analyzePieces(position);

      for (final (side, sideResult) in [
        ('white', result.white),
        ('black', result.black),
      ]) {
        final expectedList = expected[side] as List<dynamic>;
        expect(
          sideResult.length,
          expectedList.length,
          reason: '$name/$side count',
        );
        for (var i = 0; i < expectedList.length; i++) {
          final expectedPiece = expectedList[i] as Map<String, dynamic>;
          final actual = sideResult[i];
          expect(
            actual.piece,
            expectedPiece['piece'],
            reason: '$name/$side[$i] piece',
          );
          expect(
            actual.symbol,
            expectedPiece['symbol'],
            reason: '$name/$side[$i] symbol',
          );
          expect(
            actual.square,
            expectedPiece['square'],
            reason: '$name/$side[$i] square',
          );
          expect(
            actual.mobility,
            expectedPiece['mobility'],
            reason: '$name/$side[$i] mobility',
          );
          expect(
            actual.status,
            expectedPiece['status'],
            reason: '$name/$side[$i] status',
          );
          expect(
            actual.issues,
            expectedPiece['issues'],
            reason: '$name/$side[$i] issues',
          );
          expect(
            actual.active,
            expectedPiece['active'],
            reason: '$name/$side[$i] active',
          );
        }
      }
    });
  }
}
