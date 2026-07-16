import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/analysis/analysis_controller.dart';
import 'package:xadrez_fun/features/strategy/strategy_analysis.dart';

void main() {
  test('computeStrategyAnalysis combina os 8 analisadores + plano', () {
    final position = Chess.initial;
    final analysis = computeStrategyAnalysis(position, const CpEval(31));

    expect(analysis.threats.whiteThreats, isEmpty);
    expect(analysis.weaknesses.white, ['Rei ainda não rocou']);
    expect(analysis.pawnStructure.white.count, 8);
    expect(analysis.centerControl.dominant.name, 'equal');
    expect(analysis.kingSafety.white.safe, isTrue);
    expect(analysis.pieces.white.length, 8);
    expect(analysis.tactics.white, isEmpty);
    expect(analysis.plan.evaluationText, isNotNull);
  });

  test('strategyAnalysisProvider deriva da posição e da avaliação atuais', () {
    final container = ProviderContainer(
      overrides: [
        // Evita que o GameController tente resolver um engine real
        // (`ref.listen(engineProvider, ...)` no seu `build()`).
        engineProvider.overrideWith((ref) => Future.value(null)),
        analysisControllerProvider.overrideWith(_StubAnalysisController.new),
      ],
    );
    addTearDown(container.dispose);

    final analysis = container.read(strategyAnalysisProvider);
    expect(analysis.pawnStructure.white.count, 8);
    // Sem avaliação (stub devolve null): o texto de avaliação fica nulo.
    expect(analysis.plan.evaluationText, isNull);
  });
}

class _StubAnalysisController extends AnalysisController {
  @override
  AnalysisState build() => const AnalysisState();
}
