import 'package:dartchess/dartchess.dart';

/// Segurança do rei de um lado, mesma saída de
/// `strategy.KingSafetyAnalyzer._analyze_king`.
class KingSafety {
  const KingSafety({
    required this.square,
    required this.positives,
    required this.issues,
    required this.safetyScore,
    required this.safe,
  });

  /// Casa do rei em notação algébrica, ou `null` se não houver rei (não
  /// deve ocorrer numa partida legal — guarda defensivo).
  final String? square;
  final List<String> positives;
  final List<String> issues;
  final int safetyScore;
  final bool safe;
}

/// Segurança do rei para ambos os lados, mesma saída de
/// `strategy.KingSafetyAnalyzer.analyze`.
class KingSafetyAnalysis {
  const KingSafetyAnalysis({required this.white, required this.black});

  final KingSafety white;
  final KingSafety black;
}

/// Port 1:1 de `strategy.KingSafetyAnalyzer`.
KingSafetyAnalysis analyzeKingSafety(Position position) {
  return KingSafetyAnalysis(
    white: _analyzeKingFor(position, Side.white),
    black: _analyzeKingFor(position, Side.black),
  );
}

KingSafety _analyzeKingFor(Position position, Side color) {
  final board = position.board;
  final kingSquare = board.kingOf(color);
  if (kingSquare == null) {
    return const KingSafety(
      square: null,
      positives: [],
      issues: ['Rei não encontrado'],
      safetyScore: -1,
      safe: false,
    );
  }

  final positives = <String>[];
  final issues = <String>[];
  final kingFile = kingSquare.file.value;
  final kingRank = kingSquare.rank.value;
  final initialRank = color == Side.white ? 0 : 7;

  if (kingRank == initialRank) {
    if (kingFile == 6 || kingFile == 2) {
      positives.add('Rocado');
    } else if (kingFile == 4) {
      issues.add('Ainda no centro');
    }
  } else if (kingRank == 0 || kingRank == 7) {
    positives.add('Na primeira/última fila');
  }

  var pawnShield = 0;
  final shieldRank = kingRank + (color == Side.white ? 1 : -1);
  if (shieldRank >= 0 && shieldRank <= 7) {
    for (final f in [kingFile - 1, kingFile, kingFile + 1]) {
      if (f < 0 || f > 7) continue;
      final piece = board.pieceAt(Square.fromCoords(File(f), Rank(shieldRank)));
      if (piece != null && piece.role == Role.pawn && piece.color == color) {
        pawnShield++;
      }
    }
  }

  if (pawnShield >= 2) {
    positives.add('Bom escudo de peões ($pawnShield peões)');
  } else if (pawnShield == 1) {
    issues.add('Escudo de peões fraco (1 peão)');
  } else {
    issues.add('Sem escudo de peões!');
  }

  var attackers = 0;
  for (final zoneSquare in _kingZone(kingFile, kingRank)) {
    attackers += board.attacksTo(zoneSquare, color.opposite).size;
  }

  if (attackers >= 5) {
    issues.add('Muitos atacantes na zona do rei ($attackers)');
  } else if (attackers >= 3) {
    issues.add('Pressão na zona do rei ($attackers ataques)');
  }

  final safetyScore = positives.length * 2 - issues.length;
  return KingSafety(
    square: kingSquare.name,
    positives: positives,
    issues: issues,
    safetyScore: safetyScore,
    safe: safetyScore >= 0,
  );
}

List<Square> _kingZone(int kingFile, int kingRank) {
  final zone = <Square>[];
  for (final df in [-1, 0, 1]) {
    for (final dr in [-1, 0, 1]) {
      final f = kingFile + df;
      final r = kingRank + dr;
      if (f >= 0 && f <= 7 && r >= 0 && r <= 7) {
        zone.add(Square.fromCoords(File(f), Rank(r)));
      }
    }
  }
  return zone;
}
