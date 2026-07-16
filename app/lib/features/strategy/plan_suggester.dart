import 'package:dartchess/dartchess.dart';

import '../../engine/engine_api.dart';
import '../analysis/analysis_math.dart';
import 'center_control_analyzer.dart';
import 'strategy_text.dart';

/// Fase da partida, mesma classificação de
/// `strategy.PlanSuggester._get_game_phase`.
enum GamePhase { opening, middlegame, endgame }

/// Texto de exibição da fase, em português.
String gamePhaseLabel(GamePhase phase) => switch (phase) {
  GamePhase.opening => 'Abertura',
  GamePhase.middlegame => 'Meio-jogo',
  GamePhase.endgame => 'Final',
};

/// Sugestão de plano estratégico, mesma saída de
/// `strategy.PlanSuggester.suggest` (exceto pela avaliação, reaproveitada
/// do `AnalysisController` em vez de uma nova consulta ao engine).
class PlanSuggestion {
  const PlanSuggestion({
    required this.phase,
    required this.evaluationText,
    required this.characteristics,
    required this.plans,
    required this.avoid,
  });

  final GamePhase phase;

  /// Texto da avaliação (perspectiva das brancas), ou `null` se não houver
  /// avaliação disponível (engine ausente/falhou).
  final String? evaluationText;
  final List<String> characteristics;
  final List<String> plans;
  final List<String> avoid;
}

class _PositionCharacteristics {
  const _PositionCharacteristics({
    required this.dominant,
    required this.openFile,
    required this.whiteBishopPair,
    required this.blackBishopPair,
    required this.characteristics,
  });

  final Dominance dominant;
  final String? openFile;
  final bool whiteBishopPair;
  final bool blackBishopPair;
  final List<String> characteristics;
}

/// Port de `strategy.PlanSuggester`.
PlanSuggestion suggestPlan(Position position, EngineEval? whiteEval) {
  final phase = _gamePhase(position);
  final chars = _positionCharacteristics(position);
  return PlanSuggestion(
    phase: phase,
    evaluationText: whiteEval == null ? null : formatEvaluation(whiteEval),
    characteristics: chars.characteristics,
    plans: _generatePlans(phase, chars),
    avoid: _whatToAvoid(phase, chars),
  );
}

GamePhase _gamePhase(Position position) {
  final board = position.board;
  final queens =
      board.piecesOf(Side.white, Role.queen).size +
      board.piecesOf(Side.black, Role.queen).size;
  final minors =
      board.piecesOf(Side.white, Role.knight).size +
      board.piecesOf(Side.black, Role.knight).size +
      board.piecesOf(Side.white, Role.bishop).size +
      board.piecesOf(Side.black, Role.bishop).size;
  final rooks =
      board.piecesOf(Side.white, Role.rook).size +
      board.piecesOf(Side.black, Role.rook).size;

  if (position.fullmoves <= 10) return GamePhase.opening;
  if (queens == 0 && rooks <= 2 && minors <= 2) return GamePhase.endgame;
  if (queens == 0) return GamePhase.endgame;
  return GamePhase.middlegame;
}

_PositionCharacteristics _positionCharacteristics(Position position) {
  final board = position.board;
  final center = analyzeCenterControl(position);
  final characteristics = <String>[];

  if (center.dominant == Dominance.white) {
    characteristics.add('Brancas controlam centro');
  } else if (center.dominant == Dominance.black) {
    characteristics.add('Pretas controlam centro');
  }

  String? openFile;
  for (var f = 0; f <= 7; f++) {
    var hasPawn = false;
    for (var r = 0; r <= 7; r++) {
      final piece = board.pieceAt(Square.fromCoords(File(f), Rank(r)));
      if (piece != null && piece.role == Role.pawn) {
        hasPawn = true;
        break;
      }
    }
    if (!hasPawn) {
      openFile = fileLetter(f);
      characteristics.add('Coluna $openFile aberta');
      break;
    }
  }

  final whiteBishopPair = board.piecesOf(Side.white, Role.bishop).size == 2;
  final blackBishopPair = board.piecesOf(Side.black, Role.bishop).size == 2;
  if (whiteBishopPair) characteristics.add('Brancas têm par de bispos');
  if (blackBishopPair) characteristics.add('Pretas têm par de bispos');

  return _PositionCharacteristics(
    dominant: center.dominant,
    openFile: openFile,
    whiteBishopPair: whiteBishopPair,
    blackBishopPair: blackBishopPair,
    characteristics: characteristics,
  );
}

List<String> _generatePlans(GamePhase phase, _PositionCharacteristics chars) {
  final plans = <String>[];
  switch (phase) {
    case GamePhase.opening:
      plans.addAll([
        'Completar desenvolvimento das peças',
        'Rocar para segurança do rei',
        'Controlar o centro com peões e peças',
      ]);
      break;
    case GamePhase.middlegame:
      if (chars.dominant != Dominance.equal) {
        plans.add('Expandir no flanco onde você tem vantagem espacial');
      }
      if (chars.openFile != null) {
        plans.add('Ocupar coluna aberta com torre(s)');
      }
      if (chars.whiteBishopPair || chars.blackBishopPair) {
        plans.add('Abrir posição para maximizar bispos');
      }
      plans.add('Buscar trocar peças ruins por peças boas do adversário');
      plans.add('Criar fraquezas na posição adversária');
      break;
    case GamePhase.endgame:
      plans.addAll([
        'Ativar o rei (rei é peça forte no final)',
        'Criar peão passado',
        'Centralizar torres atrás de peões passados',
      ]);
      break;
  }
  return plans.length > 4 ? plans.sublist(0, 4) : plans;
}

List<String> _whatToAvoid(GamePhase phase, _PositionCharacteristics chars) {
  final avoid = <String>[];
  switch (phase) {
    case GamePhase.opening:
      avoid.addAll([
        'Mover a mesma peça duas vezes',
        'Trazer dama cedo demais',
      ]);
      break;
    case GamePhase.middlegame:
      if (chars.whiteBishopPair || chars.blackBishopPair) {
        avoid.add('Fechar a posição');
      }
      avoid.add('Trocas que ajudem o adversário');
      break;
    case GamePhase.endgame:
      avoid.add('Passividade - rei deve estar ativo');
      break;
  }
  return avoid;
}
