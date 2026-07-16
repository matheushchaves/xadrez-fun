import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/strategy/center_control_analyzer.dart';
import 'package:xadrez_fun/features/strategy/king_safety_analyzer.dart';
import 'package:xadrez_fun/features/strategy/pawn_structure_analyzer.dart';
import 'package:xadrez_fun/features/strategy/piece_analyzer.dart';
import 'package:xadrez_fun/features/strategy/plan_suggester.dart';
import 'package:xadrez_fun/features/strategy/strategy_analysis.dart';
import 'package:xadrez_fun/features/strategy/strategy_panel.dart';
import 'package:xadrez_fun/features/strategy/tactics_detector.dart';
import 'package:xadrez_fun/features/strategy/threat_analyzer.dart';
import 'package:xadrez_fun/features/strategy/weakness_analyzer.dart';

final _fakeAnalysis = StrategyAnalysis(
  threats: const ThreatAnalysis(
    whiteThreats: [],
    blackThreats: ['Cavalo em e6 não defendido!'],
  ),
  weaknesses: const WeaknessAnalysis(white: ['Rei ainda não rocou'], black: []),
  pawnStructure: const PawnStructureAnalysis(
    white: PawnStructureSide(
      count: 8,
      islands: 1,
      passed: [],
      doubled: [],
      isolated: [],
    ),
    black: PawnStructureSide(
      count: 8,
      islands: 1,
      passed: [],
      doubled: [],
      isolated: [],
    ),
  ),
  centerControl: const CenterControlAnalysis(
    whiteScore: 3,
    blackScore: 1,
    whiteAttacks: 2,
    blackAttacks: 1,
    whitePieces: [],
    blackPieces: [],
    dominant: Dominance.white,
  ),
  kingSafety: const KingSafetyAnalysis(
    white: KingSafety(
      square: 'e1',
      positives: ['Rocado'],
      issues: [],
      safetyScore: 2,
      safe: true,
    ),
    black: KingSafety(
      square: 'e8',
      positives: [],
      issues: ['Ainda no centro'],
      safetyScore: -1,
      safe: false,
    ),
  ),
  pieces: const PieceAnalysis(white: [], black: []),
  tactics: const TacticsAnalysis(white: [], black: []),
  plan: const PlanSuggestion(
    phase: GamePhase.opening,
    evaluationText: '+0.31 (Posição equilibrada)',
    characteristics: ['Brancas têm par de bispos'],
    plans: ['Completar desenvolvimento das peças'],
    avoid: ['Mover a mesma peça duas vezes'],
  ),
);

Widget _makePanel() {
  return ProviderScope(
    overrides: [
      strategyAnalysisProvider.overrideWithValue(_fakeAnalysis),
      // StrategyPanel lê gameControllerProvider (perspectiva do jogador); o
      // GameController real ouve engineProvider no build() — sem
      // sobrescrever, o teste tentaria resolver um engine de verdade.
      engineProvider.overrideWith((ref) => Future.value(null)),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 280, height: 800, child: StrategyPanel()),
      ),
    ),
  );
}

void main() {
  testWidgets('mostra as 8 seções com o conteúdo do provider', (tester) async {
    await tester.pumpWidget(_makePanel());
    await tester.pumpAndSettle();

    expect(find.textContaining('Plano estratégico'), findsOneWidget);
    expect(find.textContaining('Ameaças'), findsOneWidget);
    expect(find.textContaining('Táticas'), findsOneWidget);
    expect(find.textContaining('Controle do centro'), findsOneWidget);
    expect(find.textContaining('Segurança do rei'), findsOneWidget);
    expect(find.textContaining('Peças'), findsOneWidget);
    expect(find.textContaining('Estrutura de peões'), findsOneWidget);
    // Usa o texto completo do cabeçalho (com o ícone) em vez de apenas
    // 'Fraquezas': a seção também contém o rótulo "Fraquezas do oponente",
    // que colidiria com uma checagem por substring simples.
    expect(find.textContaining('🔍 Fraquezas'), findsOneWidget);

    expect(find.textContaining('Cavalo em e6 não defendido!'), findsOneWidget);
    expect(find.textContaining('Rei ainda não rocou'), findsOneWidget);
    expect(find.textContaining('+0.31 (Posição equilibrada)'), findsOneWidget);
  });
}
