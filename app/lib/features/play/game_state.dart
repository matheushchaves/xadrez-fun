import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// Modo da partida: contra o engine (auto-play) ou Modo Análise (o usuário
/// move as duas cores, sem resposta automática).
enum GameMode { playVsEngine, analysis }

/// Estado imutável de uma partida.
@immutable
class GameState {
  const GameState({
    required this.position,
    required this.sanHistory,
    required this.playerSide,
    required this.skillLevel,
    required this.mode,
    required this.orientation,
    this.lastMove,
    this.engineThinking = false,
  });

  const GameState.initial()
    : this(
        position: Chess.initial,
        sanHistory: const [],
        playerSide: Side.white,
        skillLevel: 10,
        mode: GameMode.playVsEngine,
        orientation: Side.white,
      );

  final Position position;
  final List<String> sanHistory;
  final Side playerSide;
  final int skillLevel;
  final GameMode mode;

  /// Lado exibido embaixo do tabuleiro. Em [GameMode.playVsEngine] segue
  /// [playerSide]; em [GameMode.analysis] é independente e alternável via
  /// `GameController.flipBoard()`. Também usado pelo painel Estratégia para
  /// decidir a perspectiva "seu/adversário".
  final Side orientation;
  final Move? lastMove;
  final bool engineThinking;

  bool get isGameOver => position.isGameOver;

  /// Texto do resultado quando a partida terminou, senão null.
  String? get resultText {
    if (position.isCheckmate) {
      return position.turn == Side.white
          ? 'Xeque-mate! Pretas vencem.'
          : 'Xeque-mate! Brancas vencem.';
    }
    if (position.isStalemate) return 'Empate por afogamento.';
    if (position.isInsufficientMaterial) {
      return 'Empate por material insuficiente.';
    }
    if (position.isGameOver) return 'Partida encerrada.';
    return null;
  }

  GameState copyWith({
    Position? position,
    List<String>? sanHistory,
    Side? playerSide,
    int? skillLevel,
    GameMode? mode,
    Side? orientation,
    Move? lastMove,
    bool? engineThinking,
  }) {
    return GameState(
      position: position ?? this.position,
      sanHistory: sanHistory ?? this.sanHistory,
      playerSide: playerSide ?? this.playerSide,
      skillLevel: skillLevel ?? this.skillLevel,
      mode: mode ?? this.mode,
      orientation: orientation ?? this.orientation,
      lastMove: lastMove ?? this.lastMove,
      engineThinking: engineThinking ?? this.engineThinking,
    );
  }
}
