"""Módulo para análise e cálculo de probabilidades."""

import math
import chess
from engine import ChessEngine


def eval_to_win_probability(centipawns: int) -> tuple[float, float, float]:
    """
    Converte avaliação em centipawns para probabilidade de vitória.
    Usa a fórmula logística baseada em estatísticas de partidas reais.

    Args:
        centipawns: Avaliação em centipawns (positivo = brancas melhor)

    Returns:
        Tupla (prob_brancas, prob_empate, prob_pretas)
    """
    # Fórmula logística: win_prob = 1 / (1 + 10^(-eval/400))
    # Ajustada para incluir probabilidade de empate

    # Converter para pawns
    pawns = centipawns / 100

    # Probabilidade base de vitória das brancas
    win_prob = 1 / (1 + math.pow(10, -pawns / 4))

    # Estimar probabilidade de empate (maior quando avaliação próxima de 0)
    draw_factor = math.exp(-abs(pawns) / 2)  # Decai com a vantagem
    draw_prob = 0.35 * draw_factor  # Max ~35% de empate em posições iguais

    # Ajustar probabilidades de vitória
    remaining = 1 - draw_prob
    white_win = win_prob * remaining
    black_win = (1 - win_prob) * remaining

    return (white_win, draw_prob, black_win)


def mate_to_probability(mate_in: int) -> tuple[float, float, float]:
    """
    Converte mate em N jogadas para probabilidade.

    Args:
        mate_in: Número de jogadas até mate (positivo = brancas, negativo = pretas)

    Returns:
        Tupla (prob_brancas, prob_empate, prob_pretas)
    """
    if mate_in > 0:
        return (1.0, 0.0, 0.0)  # Brancas dão mate
    else:
        return (0.0, 0.0, 1.0)  # Pretas dão mate


def format_eval_bar(centipawns: int, width: int = 20) -> str:
    """Barra visual de avaliação (brancas à esquerda, pretas à direita)."""
    clamped = max(-1000, min(1000, centipawns))
    ratio = 1 / (1 + math.pow(10, -clamped / 400))
    filled = round(ratio * width)
    return '█' * filled + '░' * (width - filled)


def format_evaluation(eval_dict: dict, turn_white: bool = True) -> str:
    """
    Formata a avaliação para exibição.

    Args:
        eval_dict: Dict com 'type' e 'value' do Stockfish
        turn_white: Se é o turno das brancas

    Returns:
        String formatada da avaliação
    """
    eval_type = eval_dict.get('type')
    value = eval_dict.get('value', 0)

    if eval_type == 'mate':
        if value > 0:
            return f"Mate em {value} (Brancas)"
        else:
            return f"Mate em {abs(value)} (Pretas)"
    else:  # centipawns
        pawns = value / 100

        if abs(pawns) < 0.2:
            desc = "Posição igual"
        elif pawns > 3:
            desc = "Brancas com vantagem decisiva"
        elif pawns > 1.5:
            desc = "Brancas com clara vantagem"
        elif pawns > 0.5:
            desc = "Brancas ligeiramente melhor"
        elif pawns < -3:
            desc = "Pretas com vantagem decisiva"
        elif pawns < -1.5:
            desc = "Pretas com clara vantagem"
        elif pawns < -0.5:
            desc = "Pretas ligeiramente melhor"
        else:
            desc = "Posição equilibrada"

        return f"{pawns:+.2f} ({desc})"


def format_probabilities(probs: tuple[float, float, float]) -> str:
    """
    Formata as probabilidades para exibição.

    Args:
        probs: Tupla (prob_brancas, prob_empate, prob_pretas)

    Returns:
        String formatada
    """
    white, draw, black = probs
    width = 20
    w = round(white * width)
    d = round(draw * width)
    b = max(0, width - w - d)
    bar = '█' * w + '▒' * d + '░' * b
    return f"[{bar}] ⬜{white*100:.0f}%  ={draw*100:.0f}%  ⬛{black*100:.0f}%"


def get_position_analysis(engine: ChessEngine, board: chess.Board) -> dict:
    """
    Obtém análise completa da posição.

    Args:
        engine: Instância do ChessEngine
        board: Tabuleiro atual

    Returns:
        Dict com avaliação, probabilidades e melhores jogadas
    """
    # Avaliação
    eval_dict = engine.get_evaluation(board)

    # Probabilidades
    if eval_dict.get('type') == 'mate':
        probs = mate_to_probability(eval_dict.get('value', 0))
    else:
        probs = eval_to_win_probability(eval_dict.get('value', 0))

    # Melhores jogadas
    top_moves = engine.get_top_moves(board, num_moves=3)

    eval_bar = None
    if eval_dict.get('type') != 'mate':
        eval_bar = format_eval_bar(eval_dict.get('value', 0))

    return {
        'evaluation': eval_dict,
        'eval_str': format_evaluation(eval_dict),
        'eval_bar': eval_bar,
        'probabilities': probs,
        'probs_str': format_probabilities(probs),
        'top_moves': top_moves,
    }


def format_top_moves(top_moves: list) -> str:
    """
    Formata as melhores jogadas para exibição.

    Args:
        top_moves: Lista de dicts com jogadas

    Returns:
        String formatada
    """
    if not top_moves:
        return "Nenhuma sugestão disponível"

    parts = []
    for i, move_info in enumerate(top_moves):
        san = move_info.get('san', '?')
        eval_str = move_info.get('eval_str', '?')
        if i == 0:
            parts.append(f"★ {san} ({eval_str})")
        else:
            parts.append(f"{san} ({eval_str})")

    return ' │ '.join(parts)
