import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_api.dart';
import '../../engine/engine_provider.dart';
import '../play/game_controller.dart';
import 'analysis_math.dart';

/// Lance sugerido pelo engine, pronto para exibição.
@immutable
class TopMove {
  const TopMove({required this.san, required this.uci, required this.evalText});

  final String san;
  final String uci;

  /// Avaliação na perspectiva de quem joga, ex.: "+0.35" ou "M3".
  final String evalText;
}

/// Estado da análise da posição corrente (perspectiva das brancas).
@immutable
class AnalysisState {
  const AnalysisState({
    this.analyzing = false,
    this.eval,
    this.evalFen,
    this.evalText,
    this.probabilities,
    this.topMoves = const [],
  });

  final bool analyzing;
  final EngineEval? eval;

  /// FEN da posição a que [eval] se refere — permite a quem combina [eval]
  /// com uma posição obtida de outra fonte (ex.: `strategyAnalysisProvider`)
  /// detectar quando a avaliação está desatualizada em relação a ela.
  final String? evalFen;
  final String? evalText;
  final WinProbabilities? probabilities;
  final List<TopMove> topMoves;

  AnalysisState copyWith({bool? analyzing}) {
    return AnalysisState(
      analyzing: analyzing ?? this.analyzing,
      eval: eval,
      evalFen: evalFen,
      evalText: evalText,
      probabilities: probabilities,
      topMoves: topMoves,
    );
  }
}

final analysisControllerProvider =
    NotifierProvider<AnalysisController, AnalysisState>(AnalysisController.new);

/// Observa a partida e mantém a análise da posição que o jogador enfrenta.
class AnalysisController extends Notifier<AnalysisState> {
  String? _lastAnalyzedFen;
  Future<void> _inFlight = Future.value();

  /// Conclui quando a análise em andamento termina (para testes).
  @visibleForTesting
  Future<void> get idle => _inFlight;

  @override
  AnalysisState build() {
    ref.listen(gameControllerProvider, (_, next) => _maybeAnalyze(next));
    ref.listen(engineProvider, (_, next) {
      if (next.hasValue) _maybeAnalyze(ref.read(gameControllerProvider));
    });
    Future.microtask(() => _maybeAnalyze(ref.read(gameControllerProvider)));
    return const AnalysisState();
  }

  void _maybeAnalyze(GameState game) {
    if (game.engineThinking) return;
    // Só analisa posições que o jogador enfrenta (ou o fim da partida):
    // durante a vez do engine a posição é transitória e a consulta
    // atrasaria o bestmove (comandos UCI são serializados).
    if (!game.isGameOver && game.position.turn != game.playerSide) return;
    final fen = game.position.fen;
    if (fen == _lastAnalyzedFen) return;
    _lastAnalyzedFen = fen;
    _inFlight = _analyze(fen, game.position);
  }

  Future<void> _analyze(String fen, Position position) async {
    final engine = await ref.read(engineProvider.future);
    if (engine == null) {
      _lastAnalyzedFen = null; // permite reanalisar quando o engine chegar
      return;
    }
    state = state.copyWith(analyzing: true);
    var failed = false;
    try {
      final eval = await engine.evaluateFen(fen);
      final lines = await engine.topMovesFromFen(fen, count: 3);
      // Descarta resultado obsoleto: a posição mudou durante a análise.
      if (ref.read(gameControllerProvider).position.fen != fen) return;
      if (eval == null) {
        failed = true;
        state = const AnalysisState();
        return;
      }
      state = AnalysisState(
        eval: eval,
        evalFen: fen,
        evalText: formatEvaluation(eval),
        probabilities: winProbabilities(eval),
        topMoves: [for (final line in lines) ?_toTopMove(line, position)],
      );
    } on Exception {
      // Falha do engine no meio da análise: mantém o resultado anterior.
      failed = true;
    } finally {
      // Só age se esta ainda é a análise corrente: uma análise obsoleta não
      // pode apagar o "analisando" nem destravar o retry de uma mais nova.
      if (_lastAnalyzedFen == fen) {
        if (state.analyzing) {
          state = state.copyWith(analyzing: false);
        }
        if (failed) {
          // Libera o retry desta mesma posição: sem isso, um engine que se
          // recupera (reinício automático pós-crash) nunca reanalisaria a
          // posição corrente, deixando o painel preso em "Aguardando
          // análise…" até o jogador mover.
          _lastAnalyzedFen = null;
        }
      }
    }
  }

  TopMove? _toTopMove(EngineLine line, Position position) {
    final move = Move.parse(line.uci);
    if (move == null || !position.isLegal(move)) return null;
    final (_, san) = position.makeSan(move);
    return TopMove(san: san, uci: line.uci, evalText: _evalText(line.eval));
  }

  /// Mesmo formato de `engine.py::get_top_moves` (perspectiva de quem joga).
  String _evalText(EngineEval eval) => switch (eval) {
    MateEval(:final moves) => moves > 0 ? 'M$moves' : '-M${moves.abs()}',
    CpEval(:final cp) => signedPawns(cp),
  };
}
