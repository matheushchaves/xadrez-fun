import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/features/strategy/tactics_detector.dart';

import '../../fixtures/strategy_fixtures.dart';

void main() {
  final fixtures = loadStrategyFixtures();

  for (final name in fixtures.keys) {
    test('táticas batem com o fixture "$name"', () {
      final fen = fixtures[name]['fen'] as String;
      final expected = fixtures[name]['tactics'] as Map<String, dynamic>;
      final position = Chess.fromSetup(Setup.parseFen(fen));

      final result = analyzeTactics(position);

      expect(result.white, expected['white']);
      expect(result.black, expected['black']);
    });
  }
}
