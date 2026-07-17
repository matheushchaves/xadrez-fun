import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/board/game_controls.dart';

class FakeEngine implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => null;

  @override
  Future<EngineEval?> evaluateFen(String fen) async => const CpEval(0);

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      const [];

  @override
  Future<void> dispose() async {}
}

Widget _makeControls() {
  return ProviderScope(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(FakeEngine())),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SizedBox(height: 800, child: GameControls())),
    ),
  );
}

void main() {
  testWidgets('controles fixos e abas Análise/Estratégia aparecem', (
    tester,
  ) async {
    await tester.pumpWidget(_makeControls());
    await tester.pumpAndSettle();

    expect(find.text('Sua vez.'), findsOneWidget);
    expect(find.text('Jogar de brancas'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Análise'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Estratégia'), findsOneWidget);
  });

  testWidgets('trocar para a aba Estratégia mostra o painel de estratégia', (
    tester,
  ) async {
    await tester.pumpWidget(_makeControls());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, 'Estratégia'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Plano estratégico'), findsOneWidget);
  });

  testWidgets('botão Modo Análise inicia o modo e atualiza o status', (
    tester,
  ) async {
    await tester.pumpWidget(_makeControls());
    await tester.pumpAndSettle();

    expect(find.text('Modo Análise'), findsOneWidget);

    await tester.tap(find.text('Modo Análise'));
    await tester.pumpAndSettle();

    expect(find.text('Vez das brancas.'), findsOneWidget);
  });
}
