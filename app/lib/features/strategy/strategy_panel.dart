import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../play/game_controller.dart';
import 'center_control_analyzer.dart';
import 'king_safety_analyzer.dart';
import 'pawn_structure_analyzer.dart';
import 'piece_analyzer.dart';
import 'plan_suggester.dart';
import 'strategy_analysis.dart';
import 'strategy_widgets.dart';
import 'tactics_detector.dart';

/// Painel da aba "Estratégia": uma seção por analisador.
class StrategyPanel extends ConsumerWidget {
  const StrategyPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(strategyAnalysisProvider);
    final playerSide = ref.watch(gameControllerProvider).playerSide;

    final (yourThreats, enemyThreats) = playerSide == Side.white
        ? (analysis.threats.whiteThreats, analysis.threats.blackThreats)
        : (analysis.threats.blackThreats, analysis.threats.whiteThreats);
    final (yourWeaknesses, enemyWeaknesses) = playerSide == Side.white
        ? (analysis.weaknesses.white, analysis.weaknesses.black)
        : (analysis.weaknesses.black, analysis.weaknesses.white);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            icon: '📋',
            title: 'Plano estratégico',
            child: _PlanSection(plan: analysis.plan),
          ),
          SectionCard(
            icon: '⚠️',
            title: 'Ameaças',
            child: _ThreatsSection(
              yourThreats: yourThreats,
              enemyThreats: enemyThreats,
            ),
          ),
          SectionCard(
            icon: '⚔️',
            title: 'Táticas',
            child: _TacticsSection(tactics: analysis.tactics),
          ),
          SectionCard(
            icon: '🎯',
            title: 'Controle do centro',
            child: _CenterSection(center: analysis.centerControl),
          ),
          SectionCard(
            icon: '👑',
            title: 'Segurança do rei',
            child: _KingSafetySection(kingSafety: analysis.kingSafety),
          ),
          SectionCard(
            icon: '♟',
            title: 'Peças',
            child: _PiecesSection(pieces: analysis.pieces),
          ),
          SectionCard(
            icon: '♟',
            title: 'Estrutura de peões',
            child: _PawnStructureSection(pawns: analysis.pawnStructure),
          ),
          SectionCard(
            icon: '🔍',
            title: 'Fraquezas',
            child: _WeaknessesSection(
              yourWeaknesses: yourWeaknesses,
              enemyWeaknesses: enemyWeaknesses,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({required this.plan});

  final PlanSuggestion plan;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fase: ${gamePhaseLabel(plan.phase)}'),
        Text('Avaliação: ${plan.evaluationText ?? 'indisponível'}'),
        if (plan.characteristics.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Características',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          BulletList(items: plan.characteristics),
        ],
        const SizedBox(height: 8),
        Text(
          'Plano recomendado',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        for (final (i, step) in plan.plans.indexed) Text('${i + 1}. $step'),
        if (plan.avoid.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Evitar', style: Theme.of(context).textTheme.labelMedium),
          BulletList(items: plan.avoid),
        ],
      ],
    );
  }
}

class _ThreatsSection extends StatelessWidget {
  const _ThreatsSection({
    required this.yourThreats,
    required this.enemyThreats,
  });

  final List<String> yourThreats;
  final List<String> enemyThreats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Contra você', style: Theme.of(context).textTheme.labelMedium),
        BulletList(items: enemyThreats, emptyText: 'Nenhuma ameaça imediata'),
        const SizedBox(height: 8),
        Text('Suas ameaças', style: Theme.of(context).textTheme.labelMedium),
        BulletList(items: yourThreats, emptyText: 'Nenhuma'),
      ],
    );
  }
}

class _TacticsSection extends StatelessWidget {
  const _TacticsSection({required this.tactics});

  final TacticsAnalysis tactics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Brancas', style: Theme.of(context).textTheme.labelMedium),
        BulletList(items: tactics.white, emptyText: 'Nenhuma tática óbvia'),
        const SizedBox(height: 8),
        Text('Pretas', style: Theme.of(context).textTheme.labelMedium),
        BulletList(items: tactics.black, emptyText: 'Nenhuma tática óbvia'),
      ],
    );
  }
}

class _CenterSection extends StatelessWidget {
  const _CenterSection({required this.center});

  final CenterControlAnalysis center;

  @override
  Widget build(BuildContext context) {
    final dominantText = switch (center.dominant) {
      Dominance.white => 'Brancas dominam o centro',
      Dominance.black => 'Pretas dominam o centro',
      Dominance.equal => 'Centro disputado',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Score: Brancas ${center.whiteScore.toStringAsFixed(1)} '
          'vs Pretas ${center.blackScore.toStringAsFixed(1)}',
        ),
        Text(dominantText),
      ],
    );
  }
}

class _KingSafetyRow extends StatelessWidget {
  const _KingSafetyRow({required this.label, required this.safety});

  final String label;
  final KingSafety safety;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label (${safety.square ?? '?'}): ${safety.safe ? 'seguro' : 'em risco'}',
        ),
        for (final p in safety.positives) Text('✓ $p'),
        for (final i in safety.issues) Text('✗ $i'),
      ],
    );
  }
}

class _KingSafetySection extends StatelessWidget {
  const _KingSafetySection({required this.kingSafety});

  final KingSafetyAnalysis kingSafety;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KingSafetyRow(label: 'Brancas', safety: kingSafety.white),
        const SizedBox(height: 8),
        _KingSafetyRow(label: 'Pretas', safety: kingSafety.black),
      ],
    );
  }
}

class _PieceRow extends StatelessWidget {
  const _PieceRow({required this.piece});

  final PieceReport piece;

  @override
  Widget build(BuildContext context) {
    final tags = [...piece.status, ...piece.issues];
    final summary = tags.isEmpty ? 'ok' : tags.join(', ');
    return Text(
      '${piece.symbol} ${piece.piece} ${piece.square}: $summary '
      '${piece.active ? '✓' : '✗'}',
    );
  }
}

class _PiecesSection extends StatelessWidget {
  const _PiecesSection({required this.pieces});

  final PieceAnalysis pieces;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Brancas', style: Theme.of(context).textTheme.labelMedium),
        for (final piece in pieces.white) _PieceRow(piece: piece),
        const SizedBox(height: 8),
        Text('Pretas', style: Theme.of(context).textTheme.labelMedium),
        for (final piece in pieces.black) _PieceRow(piece: piece),
      ],
    );
  }
}

class _PawnStructureSection extends StatelessWidget {
  const _PawnStructureSection({required this.pawns});

  final PawnStructureAnalysis pawns;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Brancas: ${pawns.white.count} peões, ${pawns.white.islands} ilha(s)',
        ),
        Text(
          'Pretas: ${pawns.black.count} peões, ${pawns.black.islands} ilha(s)',
        ),
        const SizedBox(height: 4),
        Text('Peões passados', style: Theme.of(context).textTheme.labelMedium),
        if (pawns.white.passed.isEmpty && pawns.black.passed.isEmpty)
          const Text('Nenhum')
        else ...[
          if (pawns.white.passed.isNotEmpty)
            Text('Brancas: ${pawns.white.passed.join(', ')}'),
          if (pawns.black.passed.isNotEmpty)
            Text('Pretas: ${pawns.black.passed.join(', ')}'),
        ],
      ],
    );
  }
}

class _WeaknessesSection extends StatelessWidget {
  const _WeaknessesSection({
    required this.yourWeaknesses,
    required this.enemyWeaknesses,
  });

  final List<String> yourWeaknesses;
  final List<String> enemyWeaknesses;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Suas fraquezas', style: Theme.of(context).textTheme.labelMedium),
        BulletList(
          items: yourWeaknesses,
          emptyText: 'Nenhuma fraqueza significativa',
        ),
        const SizedBox(height: 8),
        Text(
          'Fraquezas do oponente',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        BulletList(
          items: enemyWeaknesses,
          emptyText: 'Nenhuma fraqueza significativa',
        ),
      ],
    );
  }
}
