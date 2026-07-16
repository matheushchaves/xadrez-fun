import 'package:dartchess/dartchess.dart';

import 'move_utils.dart';
import 'strategy_text.dart';

/// Ameaças da posição para ambos os lados, mesma saída de
/// `strategy.ThreatAnalyzer.analyze`.
class ThreatAnalysis {
  const ThreatAnalysis({
    required this.whiteThreats,
    required this.blackThreats,
  });

  final List<String> whiteThreats;
  final List<String> blackThreats;
}

/// Port 1:1 de `strategy.ThreatAnalyzer`.
ThreatAnalysis analyzeThreats(Position position) {
  return ThreatAnalysis(
    whiteThreats: _threatsFor(position, Side.white),
    blackThreats: _threatsFor(position, Side.black),
  );
}

List<String> _threatsFor(Position position, Side color) {
  final threats = <String>[];
  final opponent = color.opposite;
  final board = position.board;

  for (final square in Square.values) {
    final piece = board.pieceAt(square);
    if (piece == null || piece.color != opponent) continue;
    final attackers = board.attacksTo(square, color);
    if (attackers.isEmpty) continue;
    final defenders = board.attacksTo(square, opponent);
    final pieceName = pieceNames[piece.role]!;
    final squareName = square.name;

    if (defenders.isEmpty) {
      threats.add('$pieceName em $squareName não defendido!');
      continue;
    }
    for (final attackerSquare in attackers.squares) {
      final attacker = board.pieceAt(attackerSquare);
      if (attacker != null &&
          pieceValues[attacker.role]! < pieceValues[piece.role]!) {
        final attackerName = pieceNames[attacker.role]!;
        threats.add(
          '$attackerName ataca $pieceName em $squareName (ganho de material)',
        );
        break;
      }
    }
  }

  if (position.turn == color) {
    for (final move in expandLegalMoves(position)) {
      if (position.play(move).isCheckmate) {
        final (_, san) = position.makeSan(move);
        threats.add('Ameaça de MATE com $san!');
        break;
      }
    }
  }

  return threats;
}
