import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/features/strategy/threat_analyzer.dart';

import '../../fixtures/strategy_fixtures.dart';

void main() {
  final fixtures = loadStrategyFixtures();

  for (final name in fixtures.keys) {
    test('ameaças batem com o fixture "$name"', () {
      final fen = fixtures[name]['fen'] as String;
      final expected = fixtures[name]['threat'] as Map<String, dynamic>;
      final position = Chess.fromSetup(Setup.parseFen(fen));

      final result = analyzeThreats(position);

      expect(result.whiteThreats, expected['white_threats']);
      expect(result.blackThreats, expected['black_threats']);
    });
  }
}
