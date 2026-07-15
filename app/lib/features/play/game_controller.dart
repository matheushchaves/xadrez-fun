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
    );
    final engine = await ref.read(engineProvider.future);
    await engine?.setSkillLevel(skillLevel);
    if (playerSide == Side.black) {
      await _engineMove();
    }
  }

  Future<void> playUserMove(Move move) async {
    if (state.engineThinking || state.isGameOver) return;
    if (!state.position.isLegal(move)) return;
    _applyMove(move);
    if (!state.isGameOver) {
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
