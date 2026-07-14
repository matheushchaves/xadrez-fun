import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/analysis/analysis_controller.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';

/// Engine fake com respostas de análise roteirizadas.
class FakeAnalysisEngine implements ChessEngineApi {
  FakeAnalysisEngine({
    this.bestMove,
    this.eval = const CpEval(31),
    this.lines = const [EngineLine(uci: 'e2e4', eval: CpEval(31))],
  });

  final String? bestMove;
  final EngineEval? eval;
  final List<EngineLine> lines;
  final evaluatedFens = <String>[];

  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => bestMove;

  @override
  Future<EngineEval?> evaluateFen(String fen) async {
    evaluatedFens.add(fen);
    return eval;
  }

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      lines;

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

/// Drena microtasks até a análise corrente terminar.
Future<void> settle(ProviderContainer container) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
    await container.read(analysisControllerProvider.notifier).idle;
  }
}

void main() {
  test('analisa a posição inicial quando o engine está pronto', () async {
    final engine = FakeAnalysisEngine();
    final container = makeContainer(engine);

    // Materializa o provider (dispara a análise inicial).
    container.read(analysisControllerProvider);
    await settle(container);

    final state = container.read(analysisControllerProvider);
    expect(state.eval, const CpEval(31));
    expect(state.evalText, '+0.31 (Posição equilibrada)');
    expect(state.probabilities, isNotNull);
    expect(state.topMoves.single.san, 'e4');
    expect(state.topMoves.single.evalText, '+0.31');
    expect(state.analyzing, isFalse);
  });

  test('sem engine, estado permanece vazio', () async {
    final container = makeContainer(null);
    container.read(analysisControllerProvider);
    await settle(container);

    final state = container.read(analysisControllerProvider);
    expect(state.eval, isNull);
    expect(state.topMoves, isEmpty);
  });

  test(
    'reanalisa após o ciclo lance do jogador + resposta do engine',
    () async {
      final engine = FakeAnalysisEngine(bestMove: 'e7e5');
      final container = makeContainer(engine);
      container.read(analysisControllerProvider);
      await settle(container);
      engine.evaluatedFens.clear();

      final game = container.read(gameControllerProvider.notifier);
      await game.playUserMove(Move.parse('e2e4')!);
      await settle(container);

      // Analisou a posição resultante (vez do jogador de novo, após e5),
      // e NÃO a intermediária (vez do engine).
      final fenAfterReply = container.read(gameControllerProvider).position.fen;
      expect(engine.evaluatedFens, [fenAfterReply]);
    },
  );

  test('não repete análise da mesma posição', () async {
    final engine = FakeAnalysisEngine();
    final container = makeContainer(engine);
    container.read(analysisControllerProvider);
    await settle(container);
    await settle(container);

    expect(engine.evaluatedFens, hasLength(1));
  });

  test('mate na avaliação vira texto e probabilidade de mate', () async {
    final engine = FakeAnalysisEngine(
      eval: const MateEval(-2),
      // g1f3 é legal na posição inicial (o lance em si não importa aqui,
      // mas precisa ser legal para virar TopMove).
      lines: const [EngineLine(uci: 'g1f3', eval: MateEval(2))],
    );
    final container = makeContainer(engine);
    container.read(analysisControllerProvider);
    await settle(container);

    final state = container.read(analysisControllerProvider);
    expect(state.evalText, 'Mate em 2 (Pretas)');
    expect(state.probabilities!.black, 1.0);
    // Top move na perspectiva de quem joga: M2.
    expect(state.topMoves.single.evalText, 'M2');
  });
}
