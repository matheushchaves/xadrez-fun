import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/analysis/analysis_controller.dart';
import 'package:xadrez_fun/features/analysis/analysis_panel.dart';

class FakeEngine implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => null;

  @override
  Future<EngineEval?> evaluateFen(String fen) async => null;

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      const [];

  @override
  Future<void> dispose() async {}
}

/// Controller stub: devolve um estado fixo, sem ouvir a partida.
class StubAnalysisController extends AnalysisController {
  StubAnalysisController(this._stub);

  final AnalysisState _stub;

  @override
  AnalysisState build() => _stub;
}

Widget makePanel(AnalysisState state, {ChessEngineApi? engine}) {
  return ProviderScope(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(engine)),
      analysisControllerProvider.overrideWith(
        () => StubAnalysisController(state),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SizedBox(width: 280, child: AnalysisPanel())),
    ),
  );
}

void main() {
  const analyzedState = AnalysisState(
    eval: CpEval(31),
    evalText: '+0.31 (Posição equilibrada)',
    probabilities: (white: 0.4, draw: 0.3, black: 0.3),
    topMoves: [
      TopMove(san: 'e4', uci: 'e2e4', evalText: '+0.31'),
      TopMove(san: 'd4', uci: 'd2d4', evalText: '+0.20'),
    ],
  );

  testWidgets('mostra avaliação, barra, probabilidades e top moves', (
    tester,
  ) async {
    await tester.pumpWidget(makePanel(analyzedState, engine: FakeEngine()));
    await tester.pumpAndSettle();

    expect(find.text('+0.31 (Posição equilibrada)'), findsOneWidget);
    expect(find.byType(EvalBar), findsOneWidget);
    expect(find.byType(ProbabilityBar), findsOneWidget);
    expect(find.textContaining('⬜ 40%'), findsOneWidget);
    // Primeiro lance destacado com estrela; segundo sem.
    expect(find.text('★ e4 (+0.31)'), findsOneWidget);
    expect(find.text('d4 (+0.20)'), findsOneWidget);
  });

  testWidgets('sem engine, o painel some', (tester) async {
    await tester.pumpWidget(makePanel(analyzedState, engine: null));
    await tester.pumpAndSettle();

    expect(find.byType(EvalBar), findsNothing);
    expect(find.text('Análise'), findsNothing);
  });

  testWidgets('enquanto analisa, mostra indicador de progresso', (
    tester,
  ) async {
    const analyzing = AnalysisState(analyzing: true);
    await tester.pumpWidget(makePanel(analyzing, engine: FakeEngine()));
    // Sem pumpAndSettle: o indicador anima para sempre.
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Aguardando análise…'), findsOneWidget);
  });

  testWidgets('mate enche a barra do lado vencedor', (tester) async {
    const mateState = AnalysisState(
      eval: MateEval(3),
      evalText: 'Mate em 3 (Brancas)',
      probabilities: (white: 1.0, draw: 0.0, black: 0.0),
    );
    await tester.pumpWidget(makePanel(mateState, engine: FakeEngine()));
    await tester.pumpAndSettle();

    final bar = tester.widget<EvalBar>(find.byType(EvalBar));
    expect(bar.ratio, 1.0);
    expect(find.text('Mate em 3 (Brancas)'), findsOneWidget);
  });
}
