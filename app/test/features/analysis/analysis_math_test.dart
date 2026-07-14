import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/features/analysis/analysis_math.dart';

void main() {
  group('evalToWinProbability (valores validados contra analysis.py)', () {
    test('posição igual (cp 0): empate máximo de 35%', () {
      final p = evalToWinProbability(0);
      expect(p.white, closeTo(0.325, 0.0005));
      expect(p.draw, closeTo(0.35, 0.0005));
      expect(p.black, closeTo(0.325, 0.0005));
    });

    test('vantagem de 1 peão (cp 100)', () {
      final p = evalToWinProbability(100);
      expect(p.white, closeTo(0.5042, 0.0005));
      expect(p.draw, closeTo(0.2123, 0.0005));
      expect(p.black, closeTo(0.2835, 0.0005));
    });

    test('vantagem de 4 peões (cp 400)', () {
      final p = evalToWinProbability(400);
      expect(p.white, closeTo(0.8660, 0.0005));
      expect(p.draw, closeTo(0.0474, 0.0005));
      expect(p.black, closeTo(0.0866, 0.0005));
    });

    test('simetria: cp negativo espelha branco/preto', () {
      final plus = evalToWinProbability(150);
      final minus = evalToWinProbability(-150);
      expect(minus.white, closeTo(plus.black, 1e-9));
      expect(minus.black, closeTo(plus.white, 1e-9));
      expect(minus.draw, closeTo(plus.draw, 1e-9));
    });

    test('probabilidades somam 1', () {
      for (final cp in [-800, -200, 0, 50, 300, 1200]) {
        final p = evalToWinProbability(cp);
        expect(p.white + p.draw + p.black, closeTo(1.0, 1e-9));
      }
    });
  });

  group('mateToProbability', () {
    test('mate positivo: brancas 100%', () {
      expect(mateToProbability(3), (white: 1.0, draw: 0.0, black: 0.0));
    });

    test('mate negativo ou zero: pretas 100%', () {
      expect(mateToProbability(-2).black, 1.0);
      // mate 0 = quem joga está em mate; segue a semântica do Python
      // (value > 0 é o único caso de brancas).
      expect(mateToProbability(0).black, 1.0);
    });
  });

  group('winProbabilities (despacho por tipo)', () {
    test('CpEval usa a fórmula logística', () {
      expect(winProbabilities(const CpEval(0)).draw, closeTo(0.35, 0.0005));
    });

    test('MateEval usa probabilidade de mate', () {
      expect(winProbabilities(const MateEval(4)).white, 1.0);
    });
  });

  group('formatEvaluation (mesmos textos do analysis.py)', () {
    test('mate', () {
      expect(formatEvaluation(const MateEval(3)), 'Mate em 3 (Brancas)');
      expect(formatEvaluation(const MateEval(-2)), 'Mate em 2 (Pretas)');
    });

    test('faixas de centipawns', () {
      expect(formatEvaluation(const CpEval(10)), '+0.10 (Posição igual)');
      expect(formatEvaluation(const CpEval(30)), '+0.30 (Posição equilibrada)');
      expect(
        formatEvaluation(const CpEval(80)),
        '+0.80 (Brancas ligeiramente melhor)',
      );
      expect(
        formatEvaluation(const CpEval(200)),
        '+2.00 (Brancas com clara vantagem)',
      );
      expect(
        formatEvaluation(const CpEval(350)),
        '+3.50 (Brancas com vantagem decisiva)',
      );
      expect(
        formatEvaluation(const CpEval(-80)),
        '-0.80 (Pretas ligeiramente melhor)',
      );
      expect(
        formatEvaluation(const CpEval(-200)),
        '-2.00 (Pretas com clara vantagem)',
      );
      expect(
        formatEvaluation(const CpEval(-350)),
        '-3.50 (Pretas com vantagem decisiva)',
      );
    });
  });

  group('signedPawns', () {
    test('formata com sinal e duas casas', () {
      expect(signedPawns(35), '+0.35');
      expect(signedPawns(-120), '-1.20');
      expect(signedPawns(0), '+0.00');
    });
  });

  group('evalBarRatio', () {
    test('cp 0 fica no meio', () {
      expect(evalBarRatio(const CpEval(0)), closeTo(0.5, 1e-9));
    });

    test('clamp em ±1000', () {
      expect(
        evalBarRatio(const CpEval(2000)),
        closeTo(evalBarRatio(const CpEval(1000)), 1e-9),
      );
      expect(evalBarRatio(const CpEval(1000)), closeTo(0.9968, 0.0005));
      expect(evalBarRatio(const CpEval(-1000)), closeTo(0.0032, 0.0005));
    });

    test('mate enche a barra do lado vencedor', () {
      expect(evalBarRatio(const MateEval(2)), 1.0);
      expect(evalBarRatio(const MateEval(-2)), 0.0);
      expect(evalBarRatio(const MateEval(0)), 0.0);
    });
  });
}
