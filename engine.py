"""Módulo para integração com o engine Stockfish."""

import os
import shutil
from typing import Optional
from stockfish import Stockfish
import chess


def find_stockfish_path() -> Optional[str]:
    """
    Tenta encontrar o executável do Stockfish no sistema.

    Returns:
        Caminho para o Stockfish ou None se não encontrado
    """
    # Tentar encontrar no PATH
    stockfish_path = shutil.which('stockfish')
    if stockfish_path:
        return stockfish_path

    # Caminhos comuns
    common_paths = [
        '/usr/local/bin/stockfish',
        '/usr/bin/stockfish',
        '/opt/homebrew/bin/stockfish',  # macOS ARM
        '/opt/local/bin/stockfish',
        os.path.expanduser('~/stockfish/stockfish'),
    ]

    for path in common_paths:
        if os.path.isfile(path):
            return path

    return None


class ChessEngine:
    """Wrapper para o engine Stockfish."""

    def __init__(self, skill_level: int = 10, depth: int = 15):
        """
        Inicializa o engine Stockfish.

        Args:
            skill_level: Nível de habilidade (0-20)
            depth: Profundidade de análise
        """
        stockfish_path = find_stockfish_path()

        if not stockfish_path:
            raise RuntimeError(
                "Stockfish não encontrado!\n"
                "Instale com: brew install stockfish (macOS)\n"
                "            sudo apt install stockfish (Ubuntu/Debian)"
            )

        self.stockfish = Stockfish(
            path=stockfish_path,
            depth=depth,
            parameters={
                "Threads": 2,
                "Minimum Thinking Time": 30,
                "Skill Level": skill_level,
            }
        )
        self.depth = depth

    def set_position(self, board: chess.Board):
        """Atualiza a posição no engine."""
        self.stockfish.set_fen_position(board.fen())

    def get_best_move(self, board: chess.Board) -> chess.Move:
        """
        Obtém a melhor jogada para a posição atual.

        Args:
            board: Tabuleiro atual

        Returns:
            Melhor jogada
        """
        self.set_position(board)
        best_move_uci = self.stockfish.get_best_move()
        return chess.Move.from_uci(best_move_uci)

    def get_evaluation(self, board: chess.Board) -> dict:
        """
        Obtém a avaliação da posição.

        Args:
            board: Tabuleiro atual

        Returns:
            Dict com 'type' ('cp' ou 'mate') e 'value'
        """
        self.set_position(board)
        eval_result = self.stockfish.get_evaluation()
        return eval_result

    def get_top_moves(self, board: chess.Board, num_moves: int = 3) -> list:
        """
        Obtém as N melhores jogadas com suas avaliações.
        A avaliação é exibida do ponto de vista do jogador atual
        (positivo = bom para quem joga).

        Args:
            board: Tabuleiro atual
            num_moves: Número de jogadas a retornar

        Returns:
            Lista de dicts com 'move' e 'evaluation'
        """
        self.set_position(board)
        top_moves = self.stockfish.get_top_moves(num_moves)

        # A biblioteca stockfish retorna Centipawn/Mate do ponto de vista
        # das brancas (positivo = brancas melhor). Invertemos o sinal
        # quando é a vez das pretas para que positivo = bom para quem joga.
        flip = -1 if not board.turn else 1

        result = []
        for move_info in top_moves:
            move_uci = move_info.get('Move')
            if not move_uci:
                continue

            move = chess.Move.from_uci(move_uci)
            san = board.san(move)

            # Pegar avaliação
            centipawn = move_info.get('Centipawn')
            mate = move_info.get('Mate')

            if mate is not None:
                adjusted_mate = mate * flip
                eval_str = f"M{adjusted_mate}" if adjusted_mate > 0 else f"-M{abs(adjusted_mate)}"
                eval_value = adjusted_mate * 10000  # Para ordenação
            elif centipawn is not None:
                adjusted = centipawn * flip
                eval_str = f"{adjusted/100:+.2f}"
                eval_value = adjusted
            else:
                eval_str = "?"
                eval_value = 0

            result.append({
                'move': move,
                'san': san,
                'eval_str': eval_str,
                'eval_value': eval_value,
            })

        return result

    def set_skill_level(self, level: int):
        """Define o nível de habilidade do engine (0-20)."""
        self.stockfish.set_skill_level(level)

    def quit(self):
        """Encerra o engine."""
        try:
            self.stockfish.send_quit_command()
        except Exception:
            pass
