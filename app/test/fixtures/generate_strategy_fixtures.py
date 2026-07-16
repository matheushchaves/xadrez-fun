"""Gera fixtures de referência rodando strategy.py sobre posições curadas.

Não faz parte do app Flutter nem do app Python em produção — só serve para
gerar `strategy_fixtures.json`, usado pelos testes Dart dos analisadores
portados. Rodar com o venv do repositório (tem python-chess instalado):

    cd app/test/fixtures
    ../../../venv/bin/python3 generate_strategy_fixtures.py > strategy_fixtures.json
"""

import json
import os
import sys

REPO_ROOT = os.path.join(os.path.dirname(__file__), '..', '..', '..')
sys.path.insert(0, REPO_ROOT)

import chess
from strategy import (
    ThreatAnalyzer,
    WeaknessAnalyzer,
    PawnStructureAnalyzer,
    CenterControlAnalyzer,
    KingSafetyAnalyzer,
    PieceAnalyzer,
    TacticsDetector,
    PlanSuggester,
)

# Posições curadas: cada uma exercita um conjunto de comportamentos dos
# analisadores (ameaças, fraquezas, estrutura de peões, pin, fork, etc).
FENS = {
    "start": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    "pin_rook_knight": "4k3/8/4n3/8/8/8/4R3/4K3 w - - 0 1",
    "fork_knight": "8/3k1q2/8/8/8/5N2/8/6K1 w - - 0 1",
    "isolated_doubled_pawns": "4k3/8/8/8/8/2P5/2P2P1P/4K3 w - - 0 1",
    "king_exposed_center": (
        "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2N2N2/PPPP1PPP/R1BQK2R w KQkq - 6 5"
    ),
    "endgame_passed_pawn": "8/8/8/3k4/3P4/3K4/8/8 w - - 0 1",
    "unprotected_piece": "4k3/8/8/3n4/8/2B5/8/4K3 w - - 0 1",
    "no_pawns": "4k3/8/8/8/8/8/8/4K3 w - - 0 1",
}

threat = ThreatAnalyzer()
weakness = WeaknessAnalyzer()
pawns = PawnStructureAnalyzer()
center = CenterControlAnalyzer()
king = KingSafetyAnalyzer()
pieces = PieceAnalyzer()
tactics = TacticsDetector()
# PlanSuggester.suggest() precisa de um engine real só para a avaliação;
# usamos os métodos puros diretamente (fase/características/planos/evitar
# não dependem do engine) via __new__ para pular o __init__.
plan = PlanSuggester.__new__(PlanSuggester)

out = {}
for name, fen in FENS.items():
    board = chess.Board(fen)
    phase = plan._get_game_phase(board)
    chars = plan._analyze_position(board)
    out[name] = {
        "fen": board.fen(),
        "threat": threat.analyze(board),
        "weakness": weakness.analyze(board),
        "pawns": pawns.analyze(board),
        "center": center.analyze(board),
        "king": king.analyze(board),
        "pieces": pieces.analyze(board),
        "tactics": tactics.analyze(board),
        "plan": {
            "phase": phase,
            "characteristics": chars,
            "plans": plan._generate_plans(board, phase, chars),
            "avoid": plan._what_to_avoid(board, phase, chars),
        },
    }

print(json.dumps(out, indent=2, ensure_ascii=False))
