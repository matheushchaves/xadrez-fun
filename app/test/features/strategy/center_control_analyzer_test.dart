import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/features/strategy/center_control_analyzer.dart';

import '../../fixtures/strategy_fixtures.dart';

void main() {
  final fixtures = loadStrategyFixtures();

  const dominantByName = {
    'white': Dominance.white,
    'black': Dominance.black,
    'equal': Dominance.equal,
  };

  for (final name in fixtures.keys) {
    test('controle do centro bate com o fixture "$name"', () {
      final fen = fixtures[name]['fen'] as String;
      final expected = fixtures[name]['center'] as Map<String, dynamic>;
      final position = Chess.fromSetup(Setup.parseFen(fen));

      final result = analyzeCenterControl(position);

      expect(result.whiteScore, (expected['white_score'] as num).toDouble());
      expect(result.blackScore, (expected['black_score'] as num).toDouble());
      expect(result.whiteAttacks, expected['white_attacks']);
      expect(result.blackAttacks, expected['black_attacks']);
      expect(result.whitePieces, expected['white_pieces']);
      expect(result.blackPieces, expected['black_pieces']);
      expect(result.dominant, dominantByName[expected['dominant']]);
    });
  }
}
