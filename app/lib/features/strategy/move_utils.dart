import 'package:dartchess/dartchess.dart';

/// Enumera todos os lances legais da posição como [NormalMove], incluindo
/// as 4 variações de promoção quando aplicável (mesma cobertura de
/// `board.legal_moves` do python-chess, que gera um `Move` por peça
/// promovida possível).
List<NormalMove> expandLegalMoves(Position position) {
  final moves = <NormalMove>[];
  for (final entry in position.legalMoves.entries) {
    final from = entry.key;
    final piece = position.board.pieceAt(from);
    for (final to in entry.value.squares) {
      final destRank = to.rank.value;
      final isPromotion =
          piece?.role == Role.pawn && (destRank == 0 || destRank == 7);
      if (isPromotion) {
        for (final promotion in const [
          Role.queen,
          Role.rook,
          Role.bishop,
          Role.knight,
        ]) {
          moves.add(NormalMove(from: from, to: to, promotion: promotion));
        }
      } else {
        moves.add(NormalMove(from: from, to: to));
      }
    }
  }
  return moves;
}
