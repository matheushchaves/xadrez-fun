import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';
import 'package:xadrez_fun/features/saves/saved_game.dart';

void main() {
  test('toJson/fromJson faz roundtrip para partida vs. engine', () {
    final original = SavedGame(
      id: 'abc123',
      name: 'Minha partida',
      mode: GameMode.playVsEngine,
      timestamp: DateTime.utc(2026, 7, 17, 14, 30),
      sanHistory: const ['e4', 'e5', 'Nf3'],
      playerSide: Side.black,
      skillLevel: 7,
    );

    final decoded = SavedGame.fromJson(original.toJson());

    expect(decoded.id, original.id);
    expect(decoded.name, original.name);
    expect(decoded.mode, original.mode);
    expect(decoded.timestamp, original.timestamp);
    expect(decoded.sanHistory, original.sanHistory);
    expect(decoded.playerSide, original.playerSide);
    expect(decoded.skillLevel, original.skillLevel);
  });

  test('toJson/fromJson faz roundtrip para Modo Análise '
      '(sem playerSide/skillLevel)', () {
    final original = SavedGame(
      id: 'def456',
      name: 'Análise da Siciliana',
      mode: GameMode.analysis,
      timestamp: DateTime.utc(2026, 7, 17, 15),
      sanHistory: const ['e4', 'c5'],
    );

    final decoded = SavedGame.fromJson(original.toJson());

    expect(decoded.mode, GameMode.analysis);
    expect(decoded.playerSide, isNull);
    expect(decoded.skillLevel, isNull);
    expect(decoded.sanHistory, original.sanHistory);
  });

  test('fromGameState zera playerSide/skillLevel em Modo Análise', () {
    final state = GameState.initial().copyWith(
      mode: GameMode.analysis,
      sanHistory: const ['e4'],
    );

    final saved = SavedGame.fromGameState(state);

    expect(saved.mode, GameMode.analysis);
    expect(saved.playerSide, isNull);
    expect(saved.skillLevel, isNull);
    expect(saved.id, state.gameId);
    expect(saved.name, state.gameName);
    expect(saved.sanHistory, ['e4']);
  });

  test('fromGameState preserva playerSide/skillLevel em playVsEngine', () {
    final state = GameState.initial().copyWith(
      playerSide: Side.black,
      skillLevel: 3,
      sanHistory: const ['e4'],
    );

    final saved = SavedGame.fromGameState(state);

    expect(saved.mode, GameMode.playVsEngine);
    expect(saved.playerSide, Side.black);
    expect(saved.skillLevel, 3);
  });

  test(
    'SavedGameSummary.fromJson deriva moveCount do tamanho do histórico',
    () {
      final json = SavedGame(
        id: 'xyz',
        name: 'Teste',
        mode: GameMode.playVsEngine,
        timestamp: DateTime.utc(2026, 7, 17),
        sanHistory: const ['e4', 'e5', 'Nf3', 'Nc6'],
        playerSide: Side.white,
        skillLevel: 10,
      ).toJson();

      final summary = SavedGameSummary.fromJson(json);

      expect(summary.moveCount, 4);
      expect(summary.id, 'xyz');
      expect(summary.name, 'Teste');
    },
  );

  test('copyWith troca só o nome', () {
    final original = SavedGame(
      id: 'id1',
      name: 'Antigo',
      mode: GameMode.analysis,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const [],
    );

    final renamed = original.copyWith(name: 'Novo nome');

    expect(renamed.name, 'Novo nome');
    expect(renamed.id, original.id);
    expect(renamed.sanHistory, original.sanHistory);
  });
}
