import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../play/game_controller.dart';

/// Dados completos de uma partida salva, prontos para persistir ou para
/// `GameController.loadGame` reconstruir a partida.
@immutable
class SavedGame {
  const SavedGame({
    required this.id,
    required this.name,
    required this.mode,
    required this.timestamp,
    required this.sanHistory,
    this.playerSide,
    this.skillLevel,
  });

  /// Deriva os dados de save a partir do estado corrente do jogo.
  /// `playerSide`/`skillLevel` só fazem sentido em [GameMode.playVsEngine] —
  /// em [GameMode.analysis] ficam null, igual ao `save_analysis` do Python.
  factory SavedGame.fromGameState(GameState state) {
    final isPlayVsEngine = state.mode == GameMode.playVsEngine;
    return SavedGame(
      id: state.gameId,
      name: state.gameName,
      mode: state.mode,
      timestamp: DateTime.now(),
      sanHistory: state.sanHistory,
      playerSide: isPlayVsEngine ? state.playerSide : null,
      skillLevel: isPlayVsEngine ? state.skillLevel : null,
    );
  }

  final String id;
  final String name;
  final GameMode mode;
  final DateTime timestamp;
  final List<String> sanHistory;
  final Side? playerSide;
  final int? skillLevel;

  SavedGame copyWith({String? name}) {
    return SavedGame(
      id: id,
      name: name ?? this.name,
      mode: mode,
      timestamp: timestamp,
      sanHistory: sanHistory,
      playerSide: playerSide,
      skillLevel: skillLevel,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mode': mode.name,
    'timestamp': timestamp.toIso8601String(),
    'sanHistory': sanHistory,
    'playerSide': playerSide?.name,
    'skillLevel': skillLevel,
  };

  static SavedGame fromJson(Map<String, dynamic> json) {
    final playerSideName = json['playerSide'] as String?;
    return SavedGame(
      id: json['id'] as String,
      name: json['name'] as String,
      mode: GameMode.values.byName(json['mode'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      sanHistory: (json['sanHistory'] as List).cast<String>(),
      playerSide: playerSideName == null
          ? null
          : Side.values.byName(playerSideName),
      skillLevel: json['skillLevel'] as int?,
    );
  }
}

/// Dados leves de uma partida salva, para a lista de "Partidas salvas" —
/// evita carregar o histórico inteiro só para exibir nome/modo/contagem.
@immutable
class SavedGameSummary {
  const SavedGameSummary({
    required this.id,
    required this.name,
    required this.mode,
    required this.moveCount,
    required this.timestamp,
  });

  final String id;
  final String name;
  final GameMode mode;
  final int moveCount;
  final DateTime timestamp;

  static SavedGameSummary fromJson(Map<String, dynamic> json) {
    return SavedGameSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      mode: GameMode.values.byName(json['mode'] as String),
      moveCount: (json['sanHistory'] as List).length,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
