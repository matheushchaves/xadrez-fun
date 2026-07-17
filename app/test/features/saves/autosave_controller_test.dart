import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';
import 'package:xadrez_fun/features/saves/autosave_controller.dart';
import 'package:xadrez_fun/features/saves/games_repository.dart';
import 'package:xadrez_fun/features/saves/saved_game.dart';

class FakeEngine implements ChessEngineApi {
  FakeEngine(this.reply);

  final String? reply;

  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => reply;

  @override
  Future<EngineEval?> evaluateFen(String fen) async => null;

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      const [];

  @override
  Future<void> dispose() async {}
}

class FakeGamesRepository implements GamesRepository {
  final saved = <String, SavedGame>{};

  @override
  Future<void> save(SavedGame game) async {
    saved[game.id] = game;
  }

  @override
  Future<SavedGame?> load(String id) async => saved[id];

  @override
  Future<List<SavedGameSummary>> listGames() async {
    return [
      for (final game in saved.values)
        SavedGameSummary(
          id: game.id,
          name: game.name,
          mode: game.mode,
          moveCount: game.sanHistory.length,
          timestamp: game.timestamp,
        ),
    ];
  }

  @override
  Future<void> delete(String id) async => saved.remove(id);

  @override
  Future<void> rename(String id, String name) async {
    final game = saved[id];
    if (game != null) saved[id] = game.copyWith(name: name);
  }
}

ProviderContainer makeContainer({
  ChessEngineApi? engine,
  required FakeGamesRepository repository,
}) {
  final container = ProviderContainer(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(engine)),
      gamesRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('não salva enquanto o histórico está vazio', () async {
    final repository = FakeGamesRepository();
    final container = makeContainer(repository: repository);
    container.read(autosaveControllerProvider);

    await container.read(autosaveControllerProvider.notifier).idle;

    expect(repository.saved, isEmpty);
  });

  test('salva após um lance', () async {
    final repository = FakeGamesRepository();
    final container = makeContainer(
      engine: FakeEngine('e7e5'),
      repository: repository,
    );
    container.read(autosaveControllerProvider);

    final game = container.read(gameControllerProvider.notifier);
    await game.playUserMove(Move.parse('e2e4')!);
    await container.read(autosaveControllerProvider.notifier).idle;

    final id = container.read(gameControllerProvider).gameId;
    expect(repository.saved[id]?.sanHistory, ['e4', 'e5']);
  });

  test('salva após undoMove (histórico ainda não vazio)', () async {
    final repository = FakeGamesRepository();
    final container = makeContainer(repository: repository);
    container.read(autosaveControllerProvider);

    final game = container.read(gameControllerProvider.notifier);
    game.startAnalysisMode();
    await game.playUserMove(Move.parse('e2e4')!);
    await game.playUserMove(Move.parse('e7e5')!);
    await container.read(autosaveControllerProvider.notifier).idle;

    game.undoMove();
    await container.read(autosaveControllerProvider.notifier).idle;

    final id = container.read(gameControllerProvider).gameId;
    expect(repository.saved[id]?.sanHistory, ['e4']);
  });

  test('salva após flipBoard (mesmo histórico, mesma persistência)', () async {
    final repository = FakeGamesRepository();
    final container = makeContainer(repository: repository);
    container.read(autosaveControllerProvider);

    final game = container.read(gameControllerProvider.notifier);
    game.startAnalysisMode();
    await game.playUserMove(Move.parse('e2e4')!);
    await container.read(autosaveControllerProvider.notifier).idle;
    final savesBeforeFlip = container.read(autosaveControllerProvider);

    game.flipBoard();
    await container.read(autosaveControllerProvider.notifier).idle;

    expect(
      container.read(autosaveControllerProvider),
      greaterThan(savesBeforeFlip),
    );
  });

  test('salva a partida carregada por loadGame', () async {
    final repository = FakeGamesRepository();
    final container = makeContainer(repository: repository);
    container.read(autosaveControllerProvider);

    final game = container.read(gameControllerProvider.notifier);
    await game.loadGame(
      id: 'carregada-1',
      name: 'Partida carregada',
      mode: GameMode.analysis,
      sanHistory: const ['d4', 'd5'],
    );
    await container.read(autosaveControllerProvider.notifier).idle;

    expect(repository.saved['carregada-1']?.sanHistory, ['d4', 'd5']);
  });
}
