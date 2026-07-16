import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_api.dart';
import '../analysis/analysis_controller.dart';
import '../play/game_controller.dart';
import 'center_control_analyzer.dart';
import 'king_safety_analyzer.dart';
import 'pawn_structure_analyzer.dart';
import 'piece_analyzer.dart';
import 'plan_suggester.dart';
import 'tactics_detector.dart';
import 'threat_analyzer.dart';
import 'weakness_analyzer.dart';

/// Agregado de todos os analisadores estratégicos, mesma composição de
/// `strategy.FullAnalyzer` — mas como dados estruturados, sem formatação.
class StrategyAnalysis {
  const StrategyAnalysis({
    required this.threats,
    required this.weaknesses,
    required this.pawnStructure,
    required this.centerControl,
    required this.kingSafety,
    required this.pieces,
    required this.tactics,
    required this.plan,
  });

  final ThreatAnalysis threats;
  final WeaknessAnalysis weaknesses;
  final PawnStructureAnalysis pawnStructure;
  final CenterControlAnalysis centerControl;
  final KingSafetyAnalysis kingSafety;
  final PieceAnalysis pieces;
  final TacticsAnalysis tactics;
  final PlanSuggestion plan;
}

/// Executa os 8 analisadores puros + o plano estratégico para a posição
/// corrente.
StrategyAnalysis computeStrategyAnalysis(
  Position position,
  EngineEval? whiteEval,
) {
  return StrategyAnalysis(
    threats: analyzeThreats(position),
    weaknesses: analyzeWeaknesses(position),
    pawnStructure: analyzePawnStructure(position),
    centerControl: analyzeCenterControl(position),
    kingSafety: analyzeKingSafety(position),
    pieces: analyzePieces(position),
    tactics: analyzeTactics(position),
    plan: suggestPlan(position, whiteEval),
  );
}

/// Deriva a análise estratégica da posição corrente e da avaliação já
/// calculada pelo `AnalysisController` — sem consulta adicional ao engine.
final strategyAnalysisProvider = Provider<StrategyAnalysis>((ref) {
  final position = ref.watch(gameControllerProvider).position;
  final eval = ref.watch(analysisControllerProvider).eval;
  return computeStrategyAnalysis(position, eval);
});
