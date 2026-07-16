import 'package:dartchess/dartchess.dart';

/// Nomes das peças em português, mesmo texto de `strategy.PIECE_NAMES`.
const Map<Role, String> pieceNames = {
  Role.pawn: 'Peão',
  Role.knight: 'Cavalo',
  Role.bishop: 'Bispo',
  Role.rook: 'Torre',
  Role.queen: 'Dama',
  Role.king: 'Rei',
};

/// Valores relativos de peça, mesmos de `strategy.PIECE_VALUES` (rei = 0).
const Map<Role, int> pieceValues = {
  Role.pawn: 1,
  Role.knight: 3,
  Role.bishop: 3,
  Role.rook: 5,
  Role.queen: 9,
  Role.king: 0,
};

/// Símbolo Unicode da peça, mesmo de `strategy.PIECE_SYMBOLS`.
String pieceSymbol(Role role, Side color) {
  if (color == Side.white) {
    return switch (role) {
      Role.pawn => '♙',
      Role.knight => '♘',
      Role.bishop => '♗',
      Role.rook => '♖',
      Role.queen => '♕',
      Role.king => '♔',
    };
  }
  return switch (role) {
    Role.pawn => '♟',
    Role.knight => '♞',
    Role.bishop => '♝',
    Role.rook => '♜',
    Role.queen => '♛',
    Role.king => '♚',
  };
}

/// Letra da coluna (0 -> 'a', 7 -> 'h').
String fileLetter(int file) => String.fromCharCode(0x61 + file);
