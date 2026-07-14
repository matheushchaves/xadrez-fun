import 'package:flutter/foundation.dart';

/// Avaliação de uma posição pelo engine.
///
/// A perspectiva (brancas ou quem joga) é definida por quem produz o valor —
/// veja [ChessEngineApi.evaluateFen] e [ChessEngineApi.topMovesFromFen].
@immutable
sealed class EngineEval {
  const EngineEval();

  /// Mesma avaliação com o sinal invertido (troca de perspectiva).
  EngineEval get flipped;
}

/// Avaliação em centipawns (positivo = melhor para a perspectiva adotada).
final class CpEval extends EngineEval {
  const CpEval(this.cp);

  final int cp;

  @override
  CpEval get flipped => CpEval(-cp);

  @override
  bool operator ==(Object other) => other is CpEval && other.cp == cp;

  @override
  int get hashCode => cp.hashCode;

  @override
  String toString() => 'CpEval($cp)';
}

/// Mate em [moves] lances (positivo = a perspectiva adotada dá mate).
final class MateEval extends EngineEval {
  const MateEval(this.moves);

  final int moves;

  @override
  MateEval get flipped => MateEval(-moves);

  @override
  bool operator ==(Object other) => other is MateEval && other.moves == moves;

  @override
  int get hashCode => moves.hashCode;

  @override
  String toString() => 'MateEval($moves)';
}

/// Interface do engine de xadrez, injetável para permitir fakes em teste.
abstract interface class ChessEngineApi {
  /// Define o nível de habilidade (0-20).
  Future<void> setSkillLevel(int level);

  /// Melhor lance (UCI, ex.: "e2e4") para a posição, ou null se não houver.
  Future<String?> bestMoveFromFen(String fen);

  /// Avaliação da posição na perspectiva das BRANCAS (positivo = brancas
  /// melhor), como `ChessEngine.get_evaluation` do app Python.
  /// Null se o engine não emitir score (ex.: stream fechado).
  Future<EngineEval?> evaluateFen(String fen);

  /// Encerra o engine.
  Future<void> dispose();
}
