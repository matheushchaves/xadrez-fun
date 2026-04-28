"""Módulo para cenários e análise estatística de xadrez."""

import random
import chess
from typing import Optional
from engine import ChessEngine


class VariationTree:
    """Gerencia árvore de variações."""

    def __init__(self):
        self.main_line: list[str] = []  # Jogadas da linha principal (SAN)
        self.branches: dict[str, tuple[int, list[str]]] = {}  # {nome: (índice_branch, jogadas)}
        self.current_branch: Optional[str] = None  # None = linha principal
        self._branch_counter = 0

    def add_move(self, san: str):
        """Adiciona jogada à linha atual."""
        if self.current_branch:
            _, moves = self.branches[self.current_branch]
            moves.append(san)
        else:
            self.main_line.append(san)

    def create_branch(self, name: Optional[str] = None) -> str:
        """Cria nova variação a partir da posição atual."""
        if name is None:
            self._branch_counter += 1
            name = f"var{self._branch_counter}"

        # Ponto de branch é o número de jogadas na linha principal atual
        if self.current_branch:
            _, current_moves = self.branches[self.current_branch]
            branch_point = len(self.main_line) + len(current_moves)
        else:
            branch_point = len(self.main_line)

        self.branches[name] = (branch_point, [])
        self.current_branch = name
        return name

    def switch_to_main(self):
        """Volta para linha principal."""
        self.current_branch = None

    def switch_to_branch(self, name: str) -> bool:
        """Muda para uma variação específica."""
        if name in self.branches:
            self.current_branch = name
            return True
        return False

    def get_current_moves(self) -> list[str]:
        """Retorna jogadas da linha atual."""
        if self.current_branch:
            branch_point, branch_moves = self.branches[self.current_branch]
            return self.main_line[:branch_point] + branch_moves
        return self.main_line.copy()

    def get_branch_names(self) -> list[str]:
        """Lista nomes das variações."""
        return list(self.branches.keys())

    def undo_move(self) -> bool:
        """Remove última jogada da linha atual."""
        if self.current_branch:
            _, moves = self.branches[self.current_branch]
            if moves:
                moves.pop()
                return True
        else:
            if self.main_line:
                self.main_line.pop()
                return True
        return False

    def to_tree_string(self) -> str:
        """Gera visualização da árvore de variações."""
        lines = []

        # Linha principal
        main_str = self._format_moves(self.main_line)
        current_marker = " (atual)" if not self.current_branch else ""
        lines.append(f"Principal{current_marker}: {main_str if main_str else '(vazio)'}")

        # Variações
        for name, (branch_point, moves) in self.branches.items():
            current_marker = " (atual)" if self.current_branch == name else ""
            move_num = (branch_point // 2) + 1
            side = "..." if branch_point % 2 == 1 else ""
            var_str = self._format_moves(moves)
            lines.append(f"  └─ {name}{current_marker}: {move_num}{side}{var_str if var_str else '(vazio)'}")

        return "\n".join(lines)

    def _format_moves(self, moves: list[str], max_moves: int = 6) -> str:
        """Formata lista de jogadas para exibição."""
        if not moves:
            return ""

        formatted = []
        for i, san in enumerate(moves[:max_moves]):
            if i % 2 == 0:
                formatted.append(f"{(i//2)+1}.{san}")
            else:
                formatted.append(san)

        result = " ".join(formatted)
        if len(moves) > max_moves:
            result += " ..."
        return result


class WhatIfAnalyzer:
    """Analisa cenários 'E se?' - melhores respostas do oponente."""

    def __init__(self, engine: ChessEngine):
        self.engine = engine

    def analyze_moves(self, board: chess.Board, num_moves: int = 5) -> list[dict]:
        """
        Para cada jogada candidata, analisa a melhor resposta do oponente.

        Returns:
            Lista de dicts com: move, san, opponent_reply, final_eval
        """
        results = []

        # Pegar as melhores jogadas para a posição atual
        top_moves = self.engine.get_top_moves(board, num_moves)

        for move_info in top_moves:
            move = move_info['move']
            san = move_info['san']

            # Fazer a jogada
            board.push(move)

            if not board.is_game_over():
                # Encontrar melhor resposta do oponente
                opponent_best = self.engine.get_best_move(board)
                opponent_san = board.san(opponent_best)

                # Fazer a resposta e avaliar
                board.push(opponent_best)
                final_eval = self.engine.get_evaluation(board)
                board.pop()
            else:
                opponent_san = "-"
                final_eval = self.engine.get_evaluation(board)

            # Desfazer jogada
            board.pop()

            results.append({
                'move': move,
                'san': san,
                'initial_eval': move_info['eval_str'],
                'opponent_reply': opponent_san,
                'final_eval': final_eval,
            })

        return results

    def format_analysis(self, results: list[dict]) -> str:
        """Formata análise what-if para exibição."""
        if not results:
            return "Nenhuma jogada para analisar."

        lines = ["Se você jogar:"]
        for r in results:
            # Formatar avaliação final
            eval_type = r['final_eval'].get('type')
            eval_value = r['final_eval'].get('value', 0)

            if eval_type == 'mate':
                eval_str = f"M{eval_value}" if eval_value > 0 else f"-M{abs(eval_value)}"
            else:
                eval_str = f"{eval_value/100:+.2f}"

            lines.append(
                f"  {r['san']:6} → oponente joga {r['opponent_reply']:6} → {eval_str}"
            )

        return "\n".join(lines)


class MonteCarloSimulator:
    """Simulação Monte Carlo para estatísticas de posição."""

    def simulate(
        self,
        board: chess.Board,
        n_games: int = 1000,
        max_moves: int = 100
    ) -> dict:
        """
        Simula N partidas a partir da posição atual com jogadas aleatórias.

        Returns:
            Dict com white_wins, black_wins, draws (percentuais)
        """
        white_wins = 0
        black_wins = 0
        draws = 0

        for _ in range(n_games):
            result = self._simulate_game(board.copy(), max_moves)
            if result == "1-0":
                white_wins += 1
            elif result == "0-1":
                black_wins += 1
            else:
                draws += 1

        total = n_games
        return {
            'white_wins': (white_wins / total) * 100,
            'black_wins': (black_wins / total) * 100,
            'draws': (draws / total) * 100,
            'total_games': n_games,
        }

    def _simulate_game(self, board: chess.Board, max_moves: int) -> str:
        """Simula uma partida com jogadas aleatórias ponderadas."""
        moves_played = 0

        while not board.is_game_over() and moves_played < max_moves:
            legal_moves = list(board.legal_moves)
            if not legal_moves:
                break

            # Jogada aleatória com peso para capturas e xeques
            weights = []
            for move in legal_moves:
                weight = 1.0
                if board.is_capture(move):
                    weight = 3.0
                if board.gives_check(move):
                    weight = 2.0
                # Promoções são muito importantes
                if move.promotion:
                    weight = 5.0
                weights.append(weight)

            # Escolher jogada ponderada
            move = random.choices(legal_moves, weights=weights, k=1)[0]
            board.push(move)
            moves_played += 1

        # Determinar resultado
        if board.is_checkmate():
            return "0-1" if board.turn == chess.WHITE else "1-0"
        elif board.is_game_over():
            return "1/2-1/2"
        else:
            # Jogo não terminou em max_moves, avaliar material
            return self._evaluate_material(board)

    def _evaluate_material(self, board: chess.Board) -> str:
        """Avalia resultado baseado em material quando jogo não termina."""
        # Valores das peças
        piece_values = {
            chess.PAWN: 1,
            chess.KNIGHT: 3,
            chess.BISHOP: 3,
            chess.ROOK: 5,
            chess.QUEEN: 9,
        }

        white_material = 0
        black_material = 0

        for square in chess.SQUARES:
            piece = board.piece_at(square)
            if piece and piece.piece_type != chess.KING:
                value = piece_values.get(piece.piece_type, 0)
                if piece.color == chess.WHITE:
                    white_material += value
                else:
                    black_material += value

        diff = white_material - black_material
        if diff > 3:
            return "1-0"
        elif diff < -3:
            return "0-1"
        else:
            return "1/2-1/2"

    def format_results(self, results: dict) -> str:
        """Formata resultados da simulação."""
        return (
            f"Simulação Monte Carlo ({results['total_games']} partidas):\n"
            f"  Brancas vencem: {results['white_wins']:.1f}%\n"
            f"  Empate:         {results['draws']:.1f}%\n"
            f"  Pretas vencem:  {results['black_wins']:.1f}%"
        )
