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

void main() {
  test('estado inicial: posição inicial, sem histórico', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final state = container.read(gameControllerProvider);
    expect(state.position.fen, Chess.initial.fen);
    expect(state.sanHistory, isEmpty);
    expect(state.isGameOver, isFalse);
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
}
