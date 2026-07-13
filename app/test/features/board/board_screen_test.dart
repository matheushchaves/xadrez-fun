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
}
