import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/board/board_screen.dart';

class FakeEngine implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => 'e7e5';

  @override
  Future<void> dispose() async {}
}

Widget makeApp(ChessEngineApi? engine) {
  return ProviderScope(
    overrides: [engineProvider.overrideWith((ref) => Future.value(engine))],
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

  testWidgets('painel mostra status e controles de nova partida',
      (tester) async {
    await tester.pumpWidget(makeApp(FakeEngine()));
    await tester.pumpAndSettle();

    expect(find.text('Sua vez.'), findsOneWidget);
    expect(find.text('Jogar de brancas'), findsOneWidget);
    expect(find.text('Jogar de pretas'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('nova partida de pretas: engine abre e histórico aparece',
      (tester) async {
    await tester.pumpWidget(makeApp(FakeEngineOpeningE4()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jogar de pretas'));
    await tester.pumpAndSettle();

    expect(find.textContaining('e4'), findsWidgets);
  });

  testWidgets('botões de nova partida desabilitam enquanto o engine pensa',
      (tester) async {
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
}

class FakeEngineOpeningE4 implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => 'e2e4';

  @override
  Future<void> dispose() async {}
}

class FakeEngineNeverReplies implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) => Completer<String?>().future;

  @override
  Future<void> dispose() async {}
}
