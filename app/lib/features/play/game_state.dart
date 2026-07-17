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
    required this.gameId,
    required this.gameName,
    this.lastMove,
    this.engineThinking = false,
  });

  /// Partida nova: identidade (`gameId`/`gameName`) gerada na hora — por
  /// isso não é mais `const` como antes de existir identidade de partida.
  factory GameState.initial() {
    final now = DateTime.now();
    return GameState(
      position: Chess.initial,
      sanHistory: const [],
      playerSide: Side.white,
      skillLevel: 10,
      mode: GameMode.playVsEngine,
      orientation: Side.white,
      gameId: _newGameId(now),
      gameName: _defaultGameName(now),
    );
  }

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

  /// Identificador único da partida — gerado uma vez em [GameState.initial]
  /// (ou recebido de uma partida carregada) e preservado por toda a sessão
  /// (lances, undo, flip). Só muda quando uma partida nova começa ou uma
  /// partida salva é carregada via `GameController.loadGame`.
  final String gameId;

  /// Nome de exibição da partida (padrão automático, renomeável via
  /// `GameController.renameCurrentGame`).
  final String gameName;
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
    String? gameName,
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
      gameId: gameId,
      gameName: gameName ?? this.gameName,
      lastMove: lastMove ?? this.lastMove,
      engineThinking: engineThinking ?? this.engineThinking,
    );
  }
}

String _newGameId(DateTime now) {
  final salt = Object().hashCode.abs();
  return '${now.microsecondsSinceEpoch.toRadixString(36)}'
      '${salt.toRadixString(36)}';
}

String _defaultGameName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Partida ${two(now.day)}/${two(now.month)} '
      '${two(now.hour)}:${two(now.minute)}';
}
