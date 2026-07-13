/// Interface do engine de xadrez, injetável para permitir fakes em teste.
abstract interface class ChessEngineApi {
  /// Define o nível de habilidade (0-20).
  Future<void> setSkillLevel(int level);

  /// Melhor lance (UCI, ex.: "e2e4") para a posição, ou null se não houver.
  Future<String?> bestMoveFromFen(String fen);

  /// Encerra o engine.
  Future<void> dispose();
}
