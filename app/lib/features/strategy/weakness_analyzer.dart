import 'package:dartchess/dartchess.dart';

import 'strategy_text.dart';

/// Fraquezas posicionais para ambos os lados, mesma saída de
/// `strategy.WeaknessAnalyzer.analyze`.
class WeaknessAnalysis {
  const WeaknessAnalysis({required this.white, required this.black});

  final List<String> white;
  final List<String> black;
}

/// Port 1:1 de `strategy.WeaknessAnalyzer`.
WeaknessAnalysis analyzeWeaknesses(Position position) {
  return WeaknessAnalysis(
    white: _weaknessesFor(position, Side.white),
    black: _weaknessesFor(position, Side.black),
  );
}

List<String> _weaknessesFor(Position position, Side color) {
  final weaknesses = <String>[];
  final board = position.board;
  final fileCounts = <int, int>{};

  for (final square in Square.values) {
    final piece = board.pieceAt(square);
    if (piece != null && piece.role == Role.pawn && piece.color == color) {
      final file = square.file.value;
      fileCounts[file] = (fileCounts[file] ?? 0) + 1;
    }
  }

  final uniqueFiles = fileCounts.keys.toSet();
  for (var f = 0; f <= 7; f++) {
    if (!uniqueFiles.contains(f)) continue;
    final hasNeighbor =
        uniqueFiles.contains(f - 1) || uniqueFiles.contains(f + 1);
    if (!hasNeighbor) {
      weaknesses.add('Peão isolado na coluna ${fileLetter(f)}');
    }
  }

  for (final entry in fileCounts.entries) {
    if (entry.value > 1) {
      weaknesses.add('Peões dobrados na coluna ${fileLetter(entry.key)}');
    }
  }

  final kingSquare = board.kingOf(color);
  if (kingSquare != null) {
    final kingFile = kingSquare.file.value;
    final kingRank = kingSquare.rank.value;
    final initialRank = color == Side.white ? 0 : 7;
    if (kingRank == initialRank && kingFile == 4) {
      if (!_hasCastlingRights(position, color)) {
        weaknesses.add('Rei preso no centro (sem direito a roque)');
      } else {
        weaknesses.add('Rei ainda não rocou');
      }
    }
  }

  return weaknesses;
}

bool _hasCastlingRights(Position position, Side side) {
  return (position.castles.castlingRights & SquareSet.backrankOf(side))
      .isNotEmpty;
}
