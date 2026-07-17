import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/board/board_screen.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';

class FakeEngine implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => 'e7e5';

  @override
  Future<EngineEval?> evaluateFen(String fen) async => null;

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      const [];

  @override
  Future<void> dispose() async {}
}

Widget makeApp(ChessEngineApi? engine, {EngineStatus? status}) {
  return ProviderScope(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(engine)),
      engineStatusProvider.overrideWithValue(
        status ??
            (engine == null ? const EngineNotFound() : const EngineReady()),
      ),
    ],
    child: const MaterialApp(home: BoardScreen()),
  );
}

void main() {
  testWidgets('renderiza o tabuleiro', (tester) async {
    await tester.pumpWidget(makeApp(FakeEngine()));
    await tester.pumpAndSettle();
    expect(find.byType(Chessboard), findsOneWidget);
  });

  testWidgets('sem engine, mostra aviso de instalação', (tester) async {
    await tester.pumpWidget(makeApp(null));
    await tester.pumpAndSettle();
    expect(find.textContaining('brew install stockfish'), findsOneWidget);
    expect(find.byType(Chessboard), findsOneWidget);
  });

  testWidgets('painel mostra status e controles de nova partida', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp(FakeEngine()));
    await tester.pumpAndSettle();

    expect(find.text('Sua vez.'), findsOneWidget);
    expect(find.text('Jogar de brancas'), findsOneWidget);
    expect(find.text('Jogar de pretas'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('nova partida de pretas: engine abre e histórico aparece', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp(FakeEngineOpeningE4()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jogar de pretas'));
    await tester.pumpAndSettle();

    expect(find.textContaining('e4'), findsWidgets);
  });

  testWidgets('botões de nova partida desabilitam enquanto o engine pensa', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp(FakeEngineNeverReplies()));
    await tester.pumpAndSettle();

    // Engine abre jogando de pretas e fica "pensando" para sempre.
    await tester.tap(find.text('Jogar de pretas'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Stockfish pensando…'), findsOneWidget);

    final whiteButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Jogar de brancas'),
    );
    expect(whiteButton.onPressed, isNull);
  });

  testWidgets('falha de spawn mostra mensagem específica', (tester) async {
    await tester.pumpWidget(
      makeApp(null, status: const EngineFailed('ProcessException: boom')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Stockfish falhou ao iniciar'), findsOneWidget);
    expect(find.textContaining('brew install stockfish'), findsNothing);
  });

  testWidgets('engine reiniciado mostra aviso e mantém o jogo', (tester) async {
    await tester.pumpWidget(
      makeApp(FakeEngine(), status: const EngineRestarted(1)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Stockfish reiniciado'), findsOneWidget);
    expect(find.byType(Chessboard), findsOneWidget);
  });

  testWidgets('Modo Análise: tabuleiro fica livre para as duas cores', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp(FakeEngine()));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(BoardScreen));
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(gameControllerProvider.notifier).startAnalysisMode();
    await tester.pumpAndSettle();

    final chessboard = tester.widget<Chessboard>(find.byType(Chessboard));
    expect(chessboard.controller.game.playerSide, PlayerSide.both);
  });

  testWidgets('Modo Análise: virar tabuleiro muda a orientação do Chessboard', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp(FakeEngine()));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(BoardScreen));
    final controller = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(gameControllerProvider.notifier);
    controller.startAnalysisMode();
    controller.flipBoard();
    await tester.pumpAndSettle();

    final chessboard = tester.widget<Chessboard>(find.byType(Chessboard));
    expect(chessboard.orientation, Side.black);
  });
}

class FakeEngineOpeningE4 implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => 'e2e4';

  @override
  Future<EngineEval?> evaluateFen(String fen) async => null;

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      const [];

  @override
  Future<void> dispose() async {}
}

class FakeEngineNeverReplies implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) => Completer<String?>().future;

  @override
  Future<EngineEval?> evaluateFen(String fen) async => null;

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      const [];

  @override
  Future<void> dispose() async {}
}
