import 'dart:math';

import 'package:xadrez_fun/engine/engine_api.dart';

/// Probabilidades (brancas vencem, empate, pretas vencem). Somam 1.
typedef WinProbabilities = ({double white, double draw, double black});

/// Converte avaliação em centipawns (perspectiva das brancas) em
/// probabilidades de resultado. Port 1:1 de
/// `analysis.eval_to_win_probability`.
WinProbabilities evalToWinProbability(int centipawns) {
  final pawns = centipawns / 100;

  // Fórmula logística: win_prob = 1 / (1 + 10^(-eval/400))
  final winProb = 1 / (1 + pow(10, -pawns / 4));

  // Probabilidade de empate decai com a vantagem (máx. ~35% em posições
  // iguais).
  final drawProb = 0.35 * exp(-pawns.abs() / 2);

  final remaining = 1 - drawProb;
  return (
    white: winProb * remaining,
    draw: drawProb,
    black: (1 - winProb) * remaining,
  );
}

/// Mate em N: certeza para o lado que dá mate. Port 1:1 de
/// `analysis.mate_to_probability` (value > 0 é o único caso de brancas).
WinProbabilities mateToProbability(int mateIn) {
  return mateIn > 0
      ? (white: 1.0, draw: 0.0, black: 0.0)
      : (white: 0.0, draw: 0.0, black: 1.0);
}

/// Despacha para a fórmula certa conforme o tipo da avaliação
/// (perspectiva das brancas).
WinProbabilities winProbabilities(EngineEval eval) => switch (eval) {
  CpEval(:final cp) => evalToWinProbability(cp),
  MateEval(:final moves) => mateToProbability(moves),
};

/// Centipawns como peões com sinal e duas casas, ex.: "+0.35", "-1.20".
String signedPawns(int cp) {
  final value = cp / 100;
  final text = value.abs().toStringAsFixed(2);
  return value < 0 ? '-$text' : '+$text';
}

/// Texto da avaliação (perspectiva das brancas), mesmos textos de
/// `analysis.format_evaluation`.
String formatEvaluation(EngineEval eval) => switch (eval) {
  MateEval(:final moves) =>
    moves > 0 ? 'Mate em $moves (Brancas)' : 'Mate em ${moves.abs()} (Pretas)',
  CpEval(:final cp) => '${signedPawns(cp)} (${_cpDescription(cp)})',
};

String _cpDescription(int cp) {
  final pawns = cp / 100;
  if (pawns.abs() < 0.2) return 'Posição igual';
  if (pawns > 3) return 'Brancas com vantagem decisiva';
  if (pawns > 1.5) return 'Brancas com clara vantagem';
  if (pawns > 0.5) return 'Brancas ligeiramente melhor';
  if (pawns < -3) return 'Pretas com vantagem decisiva';
  if (pawns < -1.5) return 'Pretas com clara vantagem';
  if (pawns < -0.5) return 'Pretas ligeiramente melhor';
  return 'Posição equilibrada';
}

/// Fração da barra de avaliação ocupada pelas brancas, em [0, 1].
/// Mesma curva de `analysis.format_eval_bar` (clamp em ±1000);
/// mate enche a barra do lado vencedor.
double evalBarRatio(EngineEval eval) => switch (eval) {
  MateEval(:final moves) => moves > 0 ? 1.0 : 0.0,
  CpEval(:final cp) => 1 / (1 + pow(10, -cp.clamp(-1000, 1000) / 400)),
};
