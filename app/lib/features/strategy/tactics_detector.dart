import 'package:dartchess/dartchess.dart';

import 'move_utils.dart';
import 'strategy_text.dart';

/// Motivos táticos detectados para ambos os lados, mesma saída de
/// `strategy.TacticsDetector.analyze`.
class TacticsAnalysis {
  const TacticsAnalysis({required this.white, required this.black});

  final List<String> white;
  final List<String> black;
}

/// Port 1:1 de `strategy.TacticsDetector`.
TacticsAnalysis analyzeTactics(Position position) {
  return TacticsAnalysis(
    white: _findTactics(position, Side.white),
    black: _findTactics(position, Side.black),
  );
}

List<String> _findTactics(Position position, Side color) {
  return [
    ..._findPins(position, color),
    ..._findForks(position, color),
    ..._findDiscoveries(position, color),
  ];
}

enum _PinLineType { diagonal, straight }

List<String> _findPins(Position position, Side color) {
  final board = position.board;
  final enemy = color.opposite;
  final enemyKingSquare = board.kingOf(enemy);
  if (enemyKingSquare == null) return const [];

  final pins = <String>[];
  for (final square in Square.values) {
    final piece = board.pieceAt(square);
    if (piece != null &&
        piece.color == color &&
        (piece.role == Role.bishop || piece.role == Role.queen)) {
      final pin = _checkPinLine(
        board,
        square,
        enemyKingSquare,
        enemy,
        _PinLineType.diagonal,
      );
      if (pin != null) pins.add(pin);
    }
  }
  for (final square in Square.values) {
    final piece = board.pieceAt(square);
    if (piece != null &&
        piece.color == color &&
        (piece.role == Role.rook || piece.role == Role.queen)) {
      final pin = _checkPinLine(
        board,
        square,
        enemyKingSquare,
        enemy,
        _PinLineType.straight,
      );
      if (pin != null) pins.add(pin);
    }
  }
  return pins;
}

String? _checkPinLine(
  Board board,
  Square attackerSquare,
  Square kingSquare,
  Side enemyColor,
  _PinLineType lineType,
) {
  final af = attackerSquare.file.value;
  final ar = attackerSquare.rank.value;
  final kf = kingSquare.file.value;
  final kr = kingSquare.rank.value;
  final df = kf == af ? 0 : (kf > af ? 1 : -1);
  final dr = kr == ar ? 0 : (kr > ar ? 1 : -1);

  if (lineType == _PinLineType.diagonal && (df == 0 || dr == 0)) return null;
  if (lineType == _PinLineType.straight && (df != 0 && dr != 0)) return null;

  var f = af + df;
  var r = ar + dr;
  Piece? pinnedPiece;
  Square? pinnedSquare;

  while (f >= 0 && f <= 7 && r >= 0 && r <= 7) {
    final square = Square.fromCoords(File(f), Rank(r));
    if (square == kingSquare) {
      if (pinnedPiece != null) {
        final attacker = board.pieceAt(attackerSquare)!;
        return '📌 PIN: ${pieceNames[attacker.role]!} crava '
            '${pieceNames[pinnedPiece.role]!} em ${pinnedSquare!.name}';
      }
      break;
    }
    final piece = board.pieceAt(square);
    if (piece != null) {
      if (pinnedPiece != null) break;
      if (piece.color == enemyColor) {
        pinnedPiece = piece;
        pinnedSquare = square;
      } else {
        break;
      }
    }
    f += df;
    r += dr;
  }
  return null;
}

List<String> _findForks(Position position, Side color) {
  final board = position.board;
  final enemy = color.opposite;
  final forks = <String>[];

  for (final square in Square.values) {
    final piece = board.pieceAt(square);
    if (piece == null || piece.color != color || piece.role != Role.knight) {
      continue;
    }
    final destinations = position.legalMoves[square];
    if (destinations == null) continue;
    for (final targetSquare in destinations.squares) {
      final targets = <String>[];
      final attacks = knightAttacks(targetSquare);
      for (final attackedSquare in Square.values) {
        if (!attacks.has(attackedSquare)) continue;
        final attackedPiece = board.pieceAt(attackedSquare);
        if (attackedPiece != null &&
            attackedPiece.color == enemy &&
            (attackedPiece.role == Role.queen ||
                attackedPiece.role == Role.rook ||
                attackedPiece.role == Role.king)) {
          targets.add(pieceNames[attackedPiece.role]!);
        }
      }
      if (targets.length >= 2) {
        forks.add(
          '🍴 FORK: Cavalo em ${targetSquare.name} ataca ${targets.join(' e ')}',
        );
        break;
      }
    }
  }
  return forks.length > 2 ? forks.sublist(0, 2) : forks;
}

List<String> _findDiscoveries(Position position, Side color) {
  if (position.turn != color) return const [];
  final board = position.board;
  final discoveries = <String>[];

  // Usa `expandLegalMoves` (com as 4 variações de promoção) porque, ao
  // contrário de um xeque descoberto "de verdade", `strategy.py` só testa
  // `board.is_check()` após o lance — um peão que dá xeque só ao se
  // promover a dama (por exemplo) também entra aqui, então a peça de
  // promoção importa e não pode ser ignorada.
  for (final move in expandLegalMoves(position)) {
    final piece = board.pieceAt(move.from);
    if (piece == null || piece.color != color) continue;
    final newPosition = position.play(move);
    if (newPosition.isCheck) {
      discoveries.add(
        '💨 DESCOBERTA: Mover ${pieceNames[piece.role]!} dá xeque descoberto!',
      );
      break;
    }
  }
  return discoveries;
}
