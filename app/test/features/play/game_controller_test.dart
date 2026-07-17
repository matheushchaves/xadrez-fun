import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';

/// Engine fake que responde sempre o mesmo lance.
class FakeEngine implements ChessEngineApi {
  FakeEngine(this.reply);

  final String? reply;
  final skillLevels = <int>[];
  final fensAsked = <String>[];

  @override
  Future<void> setSkillLevel(int level) async => skillLevels.add(level);

  @override
  Future<String?> bestMoveFromFen(String fen) async {
    fensAsked.add(fen);
    return reply;
  }

  @override
  Future<EngineEval?> evaluateFen(String fen) async => null;

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      const [];

  @override
  Future<void> dispose() async {}
}

ProviderContainer makeContainer(ChessEngineApi? engine) {
  final container = ProviderContainer(
    overrides: [engineProvider.overrideWith((ref) => Future.value(engine))],
  );
  addTearDown(container.dispose);
  return container;
}

/// Permite trocar o engine em tempo de teste (simula reinício pós-crash).
final _engineHolderProvider = NotifierProvider<_EngineHolder, ChessEngineApi?>(
  _EngineHolder.new,
);

class _EngineHolder extends Notifier<ChessEngineApi?> {
  @override
  ChessEngineApi? build() => null;

  void set(ChessEngineApi? engine) => state = engine;
}

void main() {
  test('estado inicial: posição inicial, sem histórico', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final state = container.read(gameControllerProvider);
    expect(state.position.fen, Chess.initial.fen);
    expect(state.sanHistory, isEmpty);
    expect(state.isGameOver, isFalse);
  });

  test('estado inicial: modo playVsEngine, orientação brancas', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final state = container.read(gameControllerProvider);
    expect(state.mode, GameMode.playVsEngine);
    expect(state.orientation, Side.white);
  });

  test('lance do jogador dispara resposta do engine', () async {
    final engine = FakeEngine('e7e5');
    final container = makeContainer(engine);
    final controller = container.read(gameControllerProvider.notifier);

    await controller.playUserMove(Move.parse('e2e4')!);

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, ['e4', 'e5']);
    expect(state.position.turn, Side.white);
    expect(engine.fensAsked, hasLength(1));
    expect(state.engineThinking, isFalse);
  });

  test('sem engine, o lance do jogador não trava (tabuleiro livre)', () async {
    final container = makeContainer(null);
    final controller = container.read(gameControllerProvider.notifier);

    await controller.playUserMove(Move.parse('e2e4')!);

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, ['e4']);
    expect(state.position.turn, Side.black);
  });

  test('newGame reinicia estado e aplica skill level', () async {
    final engine = FakeEngine('e7e5');
    final container = makeContainer(engine);
    final controller = container.read(gameControllerProvider.notifier);

    await controller.playUserMove(Move.parse('e2e4')!);
    await controller.newGame(playerSide: Side.white, skillLevel: 3);

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, isEmpty);
    expect(state.skillLevel, 3);
    expect(engine.skillLevels, contains(3));
  });

  test('newGame jogando de pretas: engine abre a partida', () async {
    final engine = FakeEngine('e2e4');
    final container = makeContainer(engine);
    final controller = container.read(gameControllerProvider.notifier);

    await controller.newGame(playerSide: Side.black, skillLevel: 10);

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, ['e4']);
    expect(state.position.turn, Side.black);
  });

  test('newGame define a orientação igual ao playerSide', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);

    await controller.newGame(playerSide: Side.black, skillLevel: 5);

    final state = container.read(gameControllerProvider);
    expect(state.orientation, Side.black);
    expect(state.mode, GameMode.playVsEngine);
  });

  test(
    'startAnalysisMode reinicia em Modo Análise, orientação brancas',
    () async {
      final engine = FakeEngine('e7e5');
      final container = makeContainer(engine);
      final controller = container.read(gameControllerProvider.notifier);

      await controller.playUserMove(Move.parse('e2e4')!);
      controller.startAnalysisMode();

      final state = container.read(gameControllerProvider);
      expect(state.mode, GameMode.analysis);
      expect(state.orientation, Side.white);
      expect(state.sanHistory, isEmpty);
      expect(state.position.fen, Chess.initial.fen);
    },
  );

  test('em Modo Análise, playUserMove não dispara o engine', () async {
    final engine = FakeEngine('e7e5');
    final container = makeContainer(engine);
    final controller = container.read(gameControllerProvider.notifier);
    controller.startAnalysisMode();

    await controller.playUserMove(Move.parse('e2e4')!);
    await controller.playUserMove(Move.parse('e7e5')!);

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, ['e4', 'e5']);
    expect(state.position.turn, Side.white);
    expect(engine.fensAsked, isEmpty);
  });

  test('undoMove desfaz o último lance em Modo Análise', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    controller.startAnalysisMode();
    await controller.playUserMove(Move.parse('e2e4')!);
    await controller.playUserMove(Move.parse('e7e5')!);

    controller.undoMove();

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, ['e4']);
    expect(state.position.turn, Side.black);
    expect(state.lastMove, Move.parse('e2e4'));
  });

  test('undoMove até esvaziar o histórico zera lastMove', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    controller.startAnalysisMode();
    await controller.playUserMove(Move.parse('e2e4')!);

    controller.undoMove();

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, isEmpty);
    expect(state.position.fen, Chess.initial.fen);
    expect(state.lastMove, isNull);
  });

  test('undoMove não faz nada fora do Modo Análise', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    await controller.playUserMove(Move.parse('e2e4')!);
    final before = container.read(gameControllerProvider);

    controller.undoMove();

    expect(container.read(gameControllerProvider), same(before));
  });

  test('undoMove com histórico vazio não faz nada', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    controller.startAnalysisMode();
    final before = container.read(gameControllerProvider);

    controller.undoMove();

    expect(container.read(gameControllerProvider), same(before));
  });

  test('detecta xeque-mate ao final da sequência de lances', () async {
    // Mate do louco: 1.f3 e5 2.g4 Dh4# — tabuleiro livre (sem engine),
    // todos os lances entram como lances do "jogador".
    final freeContainer = makeContainer(null);
    final free = freeContainer.read(gameControllerProvider.notifier);
    await free.playUserMove(Move.parse('f2f3')!);
    await free.playUserMove(Move.parse('e7e5')!);
    await free.playUserMove(Move.parse('g2g4')!);
    await free.playUserMove(Move.parse('d8h4')!);

    final state = freeContainer.read(gameControllerProvider);
    expect(state.isGameOver, isTrue);
    expect(state.resultText, 'Xeque-mate! Pretas vencem.');
  });

  test(
    'engine trocado (reinício) recebe o skill level da partida em curso',
    () async {
      final engineA = FakeEngine('e7e5');
      final engineB = FakeEngine('e7e5');
      final container = ProviderContainer(
        overrides: [
          engineProvider.overrideWith(
            (ref) async => ref.watch(_engineHolderProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(_engineHolderProvider.notifier).set(engineA);

      final controller = container.read(gameControllerProvider.notifier);
      await controller.newGame(playerSide: Side.white, skillLevel: 7);

      // Simula o reinício: o manager publica um engine novo. `container.pump()`
      // aguarda o agendador do Riverpod processar rebuilds/notificações
      // pendentes; o `read` força o flush do provider marcado como "sujo" a
      // cada rodada, até a cadeia (holder -> engineProvider -> ref.listen do
      // GameController) assentar por completo.
      container.read(_engineHolderProvider.notifier).set(engineB);
      for (var i = 0; i < 5; i++) {
        container.read(engineProvider);
        await container.pump();
      }

      expect(engineB.skillLevels, contains(7));
    },
  );
}
