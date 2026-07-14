import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_provider.dart';
import 'analysis_controller.dart';
import 'analysis_math.dart';

/// Painel de análise: eval bar, avaliação, probabilidades e top moves.
class AnalysisPanel extends ConsumerWidget {
  const AnalysisPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(analysisControllerProvider);
    final engineAvailable = ref.watch(engineProvider).value != null;
    if (!engineAvailable) return const SizedBox.shrink();

    final eval = analysis.eval;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Análise', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (analysis.analyzing)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (eval == null)
          const Text('Aguardando análise…')
        else ...[
          EvalBar(ratio: evalBarRatio(eval)),
          const SizedBox(height: 4),
          Text(analysis.evalText ?? ''),
          if (analysis.probabilities case final probs?) ...[
            const SizedBox(height: 8),
            ProbabilityBar(probabilities: probs),
          ],
          if (analysis.topMoves.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Melhores lances',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (final (i, move) in analysis.topMoves.indexed)
              Text(
                i == 0
                    ? '★ ${move.san} (${move.evalText})'
                    : '${move.san} (${move.evalText})',
              ),
          ],
        ],
      ],
    );
  }
}

/// Barra horizontal de avaliação: fração branca à esquerda, resto preto.
class EvalBar extends StatelessWidget {
  const EvalBar({super.key, required this.ratio});

  /// Fração da barra ocupada pelas brancas, em [0, 1].
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 12,
        color: Colors.black87,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: ratio.clamp(0.0, 1.0),
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );
  }
}

/// Barra de probabilidades (brancas/empate/pretas) com legenda percentual.
class ProbabilityBar extends StatelessWidget {
  const ProbabilityBar({super.key, required this.probabilities});

  final WinProbabilities probabilities;

  @override
  Widget build(BuildContext context) {
    final white = (probabilities.white * 1000).round();
    final draw = (probabilities.draw * 1000).round();
    final black = (probabilities.black * 1000).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (white > 0)
                  Expanded(
                    flex: white,
                    child: const ColoredBox(color: Colors.white),
                  ),
                if (draw > 0)
                  Expanded(
                    flex: draw,
                    child: const ColoredBox(color: Colors.grey),
                  ),
                if (black > 0)
                  Expanded(
                    flex: black,
                    child: const ColoredBox(color: Colors.black87),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '⬜ ${(probabilities.white * 100).round()}%   '
          '= ${(probabilities.draw * 100).round()}%   '
          '⬛ ${(probabilities.black * 100).round()}%',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
