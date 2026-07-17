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

  test('usa a avaliação quando evalFen corresponde à posição corrente', () {
    final container = ProviderContainer(
      overrides: [
        engineProvider.overrideWith((ref) => Future.value(null)),
        analysisControllerProvider.overrideWith(
          () => _StubAnalysisController(
            AnalysisState(eval: const CpEval(31), evalFen: Chess.initial.fen),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final analysis = container.read(strategyAnalysisProvider);
    expect(analysis.plan.evaluationText, isNotNull);
  });

  test('ignora a avaliação quando evalFen é de uma posição diferente da '
      'corrente (engine ainda pensando na resposta ao último lance)', () {
    const staleFen =
        'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
    final container = ProviderContainer(
      overrides: [
        engineProvider.overrideWith((ref) => Future.value(null)),
        analysisControllerProvider.overrideWith(
          () => _StubAnalysisController(
            const AnalysisState(eval: CpEval(31), evalFen: staleFen),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    // gameControllerProvider começa na posição inicial, que não bate com
    // staleFen: a avaliação (de uma posição diferente) deve ser ignorada.
    final analysis = container.read(strategyAnalysisProvider);
    expect(analysis.plan.evaluationText, isNull);
  });
}

class _StubAnalysisController extends AnalysisController {
  _StubAnalysisController([this._state = const AnalysisState()]);

  final AnalysisState _state;

  @override
  AnalysisState build() => _state;
}
