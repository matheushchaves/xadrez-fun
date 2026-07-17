import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';
import 'package:xadrez_fun/features/saves/games_repository.dart';
import 'package:xadrez_fun/features/saves/saved_game.dart';
import 'package:xadrez_fun/features/saves/saved_games_screen.dart';

class FakeGamesRepository implements GamesRepository {
  final saved = <String, SavedGame>{};

  @override
  Future<void> save(SavedGame game) async => saved[game.id] = game;

  @override
  Future<SavedGame?> load(String id) async => saved[id];

  @override
  Future<List<SavedGameSummary>> listGames() async {
    final list = [
      for (final game in saved.values)
        SavedGameSummary(
          id: game.id,
          name: game.name,
          mode: game.mode,
          moveCount: game.sanHistory.length,
          timestamp: game.timestamp,
        ),
    ];
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Future<void> delete(String id) async => saved.remove(id);

  @override
  Future<void> rename(String id, String name) async {
    final game = saved[id];
    if (game != null) saved[id] = game.copyWith(name: name);
  }
}

Widget _makeApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: SavedGamesScreen()),
  );
}

ProviderContainer _makeContainer(FakeGamesRepository repository) {
  final container = ProviderContainer(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(null)),
      gamesRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  testWidgets('mostra mensagem quando não há partidas salvas', (tester) async {
    final container = _makeContainer(FakeGamesRepository());
    await tester.pumpWidget(_makeApp(container));
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma partida salva ainda.'), findsOneWidget);
  });

  testWidgets('lista as partidas salvas', (tester) async {
    final repository = FakeGamesRepository();
    repository.saved['id1'] = SavedGame(
      id: 'id1',
      name: 'Minha partida',
      mode: GameMode.analysis,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const ['e4', 'e5'],
    );
    final container = _makeContainer(repository);
    await tester.pumpWidget(_makeApp(container));
    await tester.pumpAndSettle();

    expect(find.text('Minha partida'), findsOneWidget);
    expect(find.textContaining('Modo Análise'), findsOneWidget);
    expect(find.textContaining('2 lances'), findsOneWidget);
  });

  testWidgets('tocar numa partida carrega e fecha a tela', (tester) async {
    final repository = FakeGamesRepository();
    repository.saved['id1'] = SavedGame(
      id: 'id1',
      name: 'Minha partida',
      mode: GameMode.analysis,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const ['e4', 'e5'],
    );
    final container = _makeContainer(repository);
    await tester.pumpWidget(_makeApp(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Minha partida'));
    await tester.pumpAndSettle();

    final state = container.read(gameControllerProvider);
    expect(state.gameId, 'id1');
    expect(state.sanHistory, ['e4', 'e5']);
    expect(find.byType(SavedGamesScreen), findsNothing);
  });

  testWidgets('renomear atualiza a lista', (tester) async {
    final repository = FakeGamesRepository();
    repository.saved['id1'] = SavedGame(
      id: 'id1',
      name: 'Nome antigo',
      mode: GameMode.analysis,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const ['e4'],
    );
    final container = _makeContainer(repository);
    await tester.pumpWidget(_makeApp(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Renomear'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Nome novo');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Nome novo'), findsOneWidget);
    expect(repository.saved['id1']?.name, 'Nome novo');
  });

  testWidgets('deletar remove da lista', (tester) async {
    final repository = FakeGamesRepository();
    repository.saved['id1'] = SavedGame(
      id: 'id1',
      name: 'Vai sumir',
      mode: GameMode.analysis,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const ['e4'],
    );
    final container = _makeContainer(repository);
    await tester.pumpWidget(_makeApp(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Deletar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deletar'));
    await tester.pumpAndSettle();

    expect(find.text('Vai sumir'), findsNothing);
    expect(repository.saved.containsKey('id1'), isFalse);
  });

  testWidgets('deletar a partida ativa reseta o GameController para uma nova', (
    tester,
  ) async {
    final repository = FakeGamesRepository();
    final container = _makeContainer(repository);
    final activeId = container.read(gameControllerProvider).gameId;
    repository.saved[activeId] = SavedGame(
      id: activeId,
      name: 'Partida ativa',
      mode: GameMode.playVsEngine,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const ['e4'],
      playerSide: Side.white,
      skillLevel: 10,
    );
    await tester.pumpWidget(_makeApp(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Deletar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deletar'));
    await tester.pumpAndSettle();

    final state = container.read(gameControllerProvider);
    expect(state.gameId, isNot(activeId));
    expect(state.sanHistory, isEmpty);
  });
}
