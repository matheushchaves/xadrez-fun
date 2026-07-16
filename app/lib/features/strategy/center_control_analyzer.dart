import 'package:dartchess/dartchess.dart';

import 'strategy_text.dart';

/// Quem domina o controle do centro.
enum Dominance { white, black, equal }

/// Controle do centro, mesma saída de
/// `strategy.CenterControlAnalyzer.analyze`.
class CenterControlAnalysis {
  const CenterControlAnalysis({
    required this.whiteScore,
    required this.blackScore,
    required this.whiteAttacks,
    required this.blackAttacks,
    required this.whitePieces,
    required this.blackPieces,
    required this.dominant,
  });

  final double whiteScore;
  final double blackScore;
  final int whiteAttacks;
  final int blackAttacks;
  final List<String> whitePieces;
  final List<String> blackPieces;
  final Dominance dominant;
}

const _centerSquares = [Square.e4, Square.d4, Square.e5, Square.d5];

const _occupationPoints = {
  Role.pawn: 3,
  Role.knight: 4,
  Role.bishop: 2,
  Role.rook: 1,
  Role.queen: 1,
  Role.king: 0,
};

/// Port 1:1 de `strategy.CenterControlAnalyzer`.
CenterControlAnalysis analyzeCenterControl(Position position) {
  final board = position.board;
  var whiteScore = 0.0;
  var blackScore = 0.0;
  final whitePieces = <String>[];
  final blackPieces = <String>[];

  for (final square in _centerSquares) {
    final piece = board.pieceAt(square);
    if (piece == null) continue;
    final points = (_occupationPoints[piece.role] ?? 1).toDouble();
    final label = '${pieceNames[piece.role]!} em ${square.name}';
    if (piece.color == Side.white) {
      whitePieces.add(label);
      whiteScore += points;
    } else {
      blackPieces.add(label);
      blackScore += points;
    }
  }

  var whiteAttacks = 0;
  var blackAttacks = 0;
  for (final square in _centerSquares) {
    whiteAttacks += board.attacksTo(square, Side.white).size;
    blackAttacks += board.attacksTo(square, Side.black).size;
  }

  whiteScore += whiteAttacks * 0.5;
  blackScore += blackAttacks * 0.5;

  final diff = whiteScore - blackScore;
  final Dominance dominant;
  if (diff >= 2) {
    dominant = Dominance.white;
  } else if (diff <= -2) {
    dominant = Dominance.black;
  } else {
    dominant = Dominance.equal;
  }

  return CenterControlAnalysis(
    whiteScore: whiteScore,
    blackScore: blackScore,
    whiteAttacks: whiteAttacks,
    blackAttacks: blackAttacks,
    whitePieces: whitePieces,
    blackPieces: blackPieces,
    dominant: dominant,
  );
}
