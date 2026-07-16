import 'package:dartchess/dartchess.dart';

import 'strategy_text.dart';

/// Relatório de uma peça (não-peão), mesma saída de
/// `strategy.PieceAnalyzer._analyze_piece`.
class PieceReport {
  const PieceReport({
    required this.piece,
    required this.symbol,
    required this.square,
    required this.mobility,
    required this.status,
    required this.issues,
    required this.active,
  });

  final String piece;
  final String symbol;
  final String square;
  final int mobility;
  final List<String> status;
  final List<String> issues;
  final bool active;
}

/// Peças de ambos os lados, mesma saída de `strategy.PieceAnalyzer.analyze`.
class PieceAnalysis {
  const PieceAnalysis({required this.white, required this.black});

  final List<PieceReport> white;
  final List<PieceReport> black;
}

/// Port 1:1 de `strategy.PieceAnalyzer` (peões excluídos, como no Python).
PieceAnalysis analyzePieces(Position position) {
  return PieceAnalysis(
    white: _analyzePiecesFor(position, Side.white),
    black: _analyzePiecesFor(position, Side.black),
  );
}

List<PieceReport> _analyzePiecesFor(Position position, Side color) {
  final board = position.board;
  final reports = <PieceReport>[];
  for (final square in Square.values) {
    final piece = board.pieceAt(square);
    if (piece != null && piece.color == color && piece.role != Role.pawn) {
      reports.add(_analyzePiece(position, square, piece));
    }
  }
  return reports;
}

PieceReport _analyzePiece(Position position, Square square, Piece piece) {
  final board = position.board;
  final mobility = position.legalMoves[square]?.size ?? 0;
  final status = <String>[];
  final issues = <String>[];

  switch (piece.role) {
    case Role.knight:
      final file = square.file.value;
      final rank = square.rank.value;
      if (file >= 2 && file <= 5 && rank >= 2 && rank <= 5) {
        status.add('bem centralizado');
      } else if (file == 0 || file == 7 || rank == 0 || rank == 7) {
        issues.add('na borda (ruim)');
      }
      break;
    case Role.bishop:
      final bishopColor = (square.file.value + square.rank.value) % 2;
      var ownPawnsSameColor = 0;
      for (final pawnSquare in Square.values) {
        final p = board.pieceAt(pawnSquare);
        if (p != null && p.role == Role.pawn && p.color == piece.color) {
          final pawnColor = (pawnSquare.file.value + pawnSquare.rank.value) % 2;
          if (pawnColor == bishopColor) ownPawnsSameColor++;
        }
      }
      if (ownPawnsSameColor >= 4) {
        issues.add('bispo ruim (bloqueado por peões)');
      } else {
        status.add('bispo bom');
      }
      break;
    case Role.rook:
      final file = square.file.value;
      var hasOwnPawn = false;
      var hasEnemyPawn = false;
      for (var r = 0; r <= 7; r++) {
        final p = board.pieceAt(Square.fromCoords(File(file), Rank(r)));
        if (p != null && p.role == Role.pawn) {
          if (p.color == piece.color) {
            hasOwnPawn = true;
          } else {
            hasEnemyPawn = true;
          }
        }
      }
      if (!hasOwnPawn && !hasEnemyPawn) {
        status.add('coluna aberta!');
      } else if (!hasOwnPawn) {
        status.add('coluna semi-aberta');
      } else {
        issues.add('coluna fechada');
      }
      break;
    case Role.queen:
      if (mobility >= 15) {
        status.add('muito ativa');
      } else if (mobility <= 5) {
        issues.add('restrita');
      }
      break;
    case Role.king:
    case Role.pawn:
      break;
  }

  if (mobility == 0) {
    issues.add('sem movimentos!');
  } else if (mobility <= 2) {
    issues.add('pouca mobilidade');
  } else if (mobility >= 8) {
    status.add('boa mobilidade');
  }

  return PieceReport(
    piece: pieceNames[piece.role]!,
    symbol: pieceSymbol(piece.role, piece.color),
    square: square.name,
    mobility: mobility,
    status: status,
    issues: issues,
    active: status.length >= issues.length,
  );
}
