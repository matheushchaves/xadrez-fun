import 'package:flutter_test/flutter_test.dart';

import 'strategy_fixtures.dart';

void main() {
  test('carrega as fixtures com o caso "start"', () {
    final fixtures = loadStrategyFixtures();
    expect(fixtures.containsKey('start'), isTrue);
    expect(
      fixtures['start']['fen'],
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    );
  });

  test('todos os 8 casos curados estão presentes', () {
    final fixtures = loadStrategyFixtures();
    expect(fixtures.keys.toSet(), {
      'start',
      'pin_rook_knight',
      'fork_knight',
      'isolated_doubled_pawns',
      'king_exposed_center',
      'endgame_passed_pawn',
      'unprotected_piece',
      'no_pawns',
    });
  });
}
