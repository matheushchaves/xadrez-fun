import 'package:dartchess/dartchess.dart';

import 'strategy_text.dart';

/// Estrutura de peões de um lado, mesma saída de
/// `strategy.PawnStructureAnalyzer._analyze_pawns`.
class PawnStructureSide {
  const PawnStructureSide({
    required this.count,
    required this.islands,
    required this.passed,
    required this.doubled,
    required this.isolated,
  });

  final int count;
  final int islands;
  final List<String> passed;
  final List<String> doubled;
  final List<String> isolated;
}

/// Estrutura de peões para ambos os lados, mesma saída de
/// `strategy.PawnStructureAnalyzer.analyze`.
class PawnStructureAnalysis {
  const PawnStructureAnalysis({required this.white, required this.black});

  final PawnStructureSide white;
  final PawnStructureSide black;
}

/// Port 1:1 de `strategy.PawnStructureAnalyzer`.
PawnStructureAnalysis analyzePawnStructure(Position position) {
  return PawnStructureAnalysis(
    white: _analyzePawnsFor(position, Side.white),
    black: _analyzePawnsFor(position, Side.black),
  );
}

PawnStructureSide _analyzePawnsFor(Position position, Side color) {
  final board = position.board;
  final pawns = <Square>[];
  final fileCounts = <int, int>{};

  for (final square in Square.values) {
    final piece = board.pieceAt(square);
    if (piece != null && piece.role == Role.pawn && piece.color == color) {
      pawns.add(square);
      final file = square.file.value;
      fileCounts[file] = (fileCounts[file] ?? 0) + 1;
    }
  }

  final uniqueFiles = fileCounts.keys.toSet();
  final sortedFiles = uniqueFiles.toList()..sort();
  var islands = sortedFiles.isEmpty ? 0 : 1;
  for (var i = 1; i < sortedFiles.length; i++) {
    if (sortedFiles[i] - sortedFiles[i - 1] > 1) islands++;
  }

  final passed = [
    for (final square in pawns)
      if (_isPassed(board, square, color)) square.name,
  ];

  final doubled = [
    for (final entry in fileCounts.entries)
      if (entry.value > 1) fileLetter(entry.key),
  ];

  final isolated = [
    for (var f = 0; f <= 7; f++)
      if (uniqueFiles.contains(f) &&
          !uniqueFiles.contains(f - 1) &&
          !uniqueFiles.contains(f + 1))
        fileLetter(f),
  ];

  return PawnStructureSide(
    count: pawns.length,
    islands: islands,
    passed: passed,
    doubled: doubled,
    isolated: isolated,
  );
}

bool _isPassed(Board board, Square square, Side color) {
  final file = square.file.value;
  final rank = square.rank.value;
  final direction = color == Side.white ? 1 : -1;
  final enemyColor = color.opposite;

  for (final f in [file - 1, file, file + 1]) {
    if (f < 0 || f > 7) continue;
    var checkRank = rank + direction;
    while (checkRank >= 0 && checkRank <= 7) {
      final checkSquare = Square.fromCoords(File(f), Rank(checkRank));
      final piece = board.pieceAt(checkSquare);
      if (piece != null &&
          piece.role == Role.pawn &&
          piece.color == enemyColor) {
        return false;
      }
      checkRank += direction;
    }
  }
  return true;
}
