import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_provider.dart';
import 'game_state.dart';

export 'game_state.dart';

final gameControllerProvider = NotifierProvider<GameController, GameState>(
  GameController.new,
);

/// Orquestra a partida: aplica lances do jogador e pede resposta ao engine.
class GameController extends Notifier<GameState> {
  @override
  GameState build() {
    ref.listen(engineProvider, (previous, next) {
      final engine = next.value;
      if (engine != null && !identical(previous?.value, engine)) {
        // Engine novo (primeiro spawn ou reinício pós-crash): reaplica o
        // nível de habilidade da partida em curso.
        unawaited(engine.setSkillLevel(state.skillLevel));
      }
    });
    return GameState.initial();
  }

  Future<void> newGame({
    required Side playerSide,
    required int skillLevel,
  }) async {
    state = GameState.initial().copyWith(
      playerSide: playerSide,
      skillLevel: skillLevel,
      mode: GameMode.playVsEngine,
      orientation: playerSide,
    );
    final engine = await ref.read(engineProvider.future);
    await engine?.setSkillLevel(skillLevel);
    if (playerSide == Side.black) {
      await _engineMove();
    }
  }

  /// Inicia uma partida em Modo Análise: o usuário move as duas cores
  /// livremente, sem resposta automática do engine. O engine continua
  /// disponível para avaliação (`AnalysisController`), só não joga sozinho.
  void startAnalysisMode() {
    state = GameState.initial().copyWith(
      mode: GameMode.analysis,
      orientation: Side.white,
    );
  }

  /// Desfaz o último lance (Modo Análise). `Position` do dartchess é
  /// imutável — sem operação de "pop" —, então desfazer é um replay: refaz o
  /// tabuleiro do zero a partir de `Chess.initial` reaplicando o histórico
  /// sem o último lance.
  void undoMove() {
    if (state.mode != GameMode.analysis || state.sanHistory.isEmpty) return;
    final newHistory = state.sanHistory.sublist(0, state.sanHistory.length - 1);
    Position position = Chess.initial;
    Move? lastMove;
    for (final san in newHistory) {
      final move = position.parseSan(san);
      if (move == null) return;
      final (next, _) = position.makeSan(move);
      lastMove = move;
      position = next;
    }
    // Construído diretamente (não via copyWith): copyWith usa o padrão
    // `campo ?? this.campo`, que não consegue expressar "zerar lastMove"
    // quando o histórico esvazia.
    state = GameState(
      position: position,
      sanHistory: newHistory,
      playerSide: state.playerSide,
      skillLevel: state.skillLevel,
      mode: state.mode,
      orientation: state.orientation,
      gameId: state.gameId,
      gameName: state.gameName,
      lastMove: lastMove,
      engineThinking: state.engineThinking,
    );
  }

  /// Alterna o lado exibido embaixo do tabuleiro (Modo Análise).
  void flipBoard() {
    state = state.copyWith(
      orientation: state.orientation == Side.white ? Side.black : Side.white,
    );
  }

  /// Carrega uma partida salva, substituindo a partida corrente. Recebe
  /// campos primitivos (não `SavedGame`) para este arquivo não depender da
  /// feature `saves` — quem chama (tela de partidas salvas, diálogo de
  /// retomar) faz o mapeamento.
  Future<void> loadGame({
    required String id,
    required String name,
    required GameMode mode,
    required List<String> sanHistory,
    Side? playerSide,
    int? skillLevel,
  }) async {
    Position position = Chess.initial;
    Move? lastMove;
    final replayed = <String>[];
    for (final san in sanHistory) {
      final move = position.parseSan(san);
      if (move == null) break;
      final (next, sanApplied) = position.makeSan(move);
      lastMove = move;
      position = next;
      replayed.add(sanApplied);
    }
    final resolvedPlayerSide = mode == GameMode.playVsEngine
        ? (playerSide ?? Side.white)
        : state.playerSide;
    final resolvedSkillLevel = mode == GameMode.playVsEngine
        ? (skillLevel ?? 10)
        : state.skillLevel;
    final orientation = mode == GameMode.playVsEngine
        ? resolvedPlayerSide
        : Side.white;
    state = GameState(
      position: position,
      sanHistory: replayed,
      playerSide: resolvedPlayerSide,
      skillLevel: resolvedSkillLevel,
      mode: mode,
      orientation: orientation,
      gameId: id,
      gameName: name,
      lastMove: lastMove,
    );
    if (mode == GameMode.playVsEngine) {
      final engine = await ref.read(engineProvider.future);
      await engine?.setSkillLevel(resolvedSkillLevel);
    }
  }

  Future<void> playUserMove(Move move) async {
    if (state.engineThinking || state.isGameOver) return;
    if (!state.position.isLegal(move)) return;
    _applyMove(move);
    if (state.mode == GameMode.playVsEngine && !state.isGameOver) {
      await _engineMove();
    }
  }

  void _applyMove(Move move) {
    final (newPosition, san) = state.position.makeSan(move);
    state = state.copyWith(
      position: newPosition,
      sanHistory: [...state.sanHistory, san],
      lastMove: move,
    );
  }

  Future<void> _engineMove() async {
    final engine = await ref.read(engineProvider.future);
    if (engine == null) return;
    state = state.copyWith(engineThinking: true);
    try {
      final uci = await engine.bestMoveFromFen(state.position.fen);
      final move = uci == null ? null : Move.parse(uci);
      if (move != null && state.position.isLegal(move)) {
        _applyMove(move);
      }
    } finally {
      state = state.copyWith(engineThinking: false);
    }
  }
}
