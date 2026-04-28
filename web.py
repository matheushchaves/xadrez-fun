#!/usr/bin/env python3
"""Xadrez Fun - Web Interface."""

import re
import math
import uuid
from flask import Flask, jsonify, request, render_template
import chess

from engine import ChessEngine
from analysis import get_position_analysis
from board_display import parse_move_input
from strategy import (
    ThreatAnalyzer, WeaknessAnalyzer, PawnStructureAnalyzer,
    CenterControlAnalyzer, KingSafetyAnalyzer, PieceAnalyzer,
    TacticsDetector, PlanSuggester, FullAnalyzer,
)
from scenarios import VariationTree, WhatIfAnalyzer, MonteCarloSimulator
from save_manager import SaveManager

app = Flask(__name__)

INITIAL_COUNTS = {'P': 8, 'N': 2, 'B': 2, 'R': 2, 'Q': 1,
                  'p': 8, 'n': 2, 'b': 2, 'r': 2, 'q': 1}
PIECE_VAL = {'p': 1, 'n': 3, 'b': 3, 'r': 5, 'q': 9}

PIECE_UNICODE = {
    'K': '\u2654', 'Q': '\u2655', 'R': '\u2656', 'B': '\u2657', 'N': '\u2658', 'P': '\u2659',
    'k': '\u265a', 'q': '\u265b', 'r': '\u265c', 'b': '\u265d', 'n': '\u265e', 'p': '\u265f',
}


def _new_game_id() -> str:
    return uuid.uuid4().hex[:12]


class GameState:
    def __init__(self):
        self.board = chess.Board()
        self.engine = ChessEngine(skill_level=10, depth=15)
        self.mode = 'analysis'
        self.player_color = chess.WHITE
        self.skill_level = 10
        self.perspective_white = True
        self.move_history = []
        self.last_move = None
        self.var_tree = VariationTree()
        self.save_manager = SaveManager()
        self.game_id = _new_game_id()
        self.game_name = 'Nova Partida'
        # Analyzers
        self.threat_analyzer = ThreatAnalyzer()
        self.weakness_analyzer = WeaknessAnalyzer()
        self.pawn_analyzer = PawnStructureAnalyzer()
        self.center_analyzer = CenterControlAnalyzer()
        self.king_analyzer = KingSafetyAnalyzer()
        self.piece_analyzer = PieceAnalyzer()
        self.tactics_detector = TacticsDetector()
        self.plan_suggester = PlanSuggester(self.engine)
        self.full_analyzer = FullAnalyzer(self.engine)
        self.what_if = WhatIfAnalyzer(self.engine)
        self.monte_carlo = MonteCarloSimulator()

    def auto_save(self):
        if self.mode == 'analysis':
            var_tree_data = {
                'main_line': self.var_tree.main_line,
                'branches': {k: [v[0], v[1]] for k, v in self.var_tree.branches.items()},
            }
            self.save_manager.save_analysis(
                self.game_id, self.game_name,
                self.move_history, self.perspective_white, var_tree_data,
            )
        else:
            self.save_manager.save_game(
                self.game_id, self.game_name,
                self.move_history, self.player_color, self.skill_level,
            )


state = GameState()


def get_captured(board):
    current = {}
    for sq in chess.SQUARES:
        p = board.piece_at(sq)
        if p:
            s = p.symbol()
            current[s] = current.get(s, 0) + 1

    white_cap, black_cap = [], []
    for sym in ['q', 'r', 'b', 'n', 'p']:
        diff = INITIAL_COUNTS.get(sym, 0) - current.get(sym, 0)
        white_cap.extend([PIECE_UNICODE[sym]] * max(0, diff))
    for sym in ['Q', 'R', 'B', 'N', 'P']:
        diff = INITIAL_COUNTS.get(sym, 0) - current.get(sym, 0)
        black_cap.extend([PIECE_UNICODE[sym]] * max(0, diff))

    w_material = sum(PIECE_VAL.get(p.symbol().lower(), 0) for sq in chess.SQUARES if (p := board.piece_at(sq)) and p.color == chess.WHITE)
    b_material = sum(PIECE_VAL.get(p.symbol().lower(), 0) for sq in chess.SQUARES if (p := board.piece_at(sq)) and p.color == chess.BLACK)

    return {
        'white_captured': ''.join(white_cap),
        'black_captured': ''.join(black_cap),
        'diff': w_material - b_material,
    }


def board_to_array(board, perspective_white=True):
    rows = []
    ranks = range(7, -1, -1) if perspective_white else range(8)
    files = range(8) if perspective_white else range(7, -1, -1)
    for rank in ranks:
        row = []
        for file in files:
            sq = chess.square(file, rank)
            piece = board.piece_at(sq)
            row.append({
                'sq': chess.square_name(sq),
                'p': piece.symbol() if piece else None,
                'c': 'w' if piece and piece.color else ('b' if piece else None),
                'l': (rank + file) % 2 == 1,
            })
        rows.append(row)
    return rows


def get_legal_moves_map(board):
    moves = {}
    for move in board.legal_moves:
        fr = chess.square_name(move.from_square)
        if fr not in moves:
            moves[fr] = []
        moves[fr].append({
            'to': chess.square_name(move.to_square),
            'uci': move.uci(),
            'promo': chess.piece_symbol(move.promotion).upper() if move.promotion else None,
        })
    return moves


def build_state():
    board = state.board

    # Analysis
    analysis_data = None
    if not board.is_game_over():
        try:
            analysis = get_position_analysis(state.engine, board)
            ev = analysis['evaluation']
            val = ev.get('value', 0)

            if ev.get('type') == 'mate':
                bar = 100 if val > 0 else 0
            else:
                bar = round(100 / (1 + math.pow(10, -val / 400)))

            probs = analysis['probabilities']
            show_top = state.mode != 'play' or board.turn == state.player_color

            analysis_data = {
                'eval_str': analysis['eval_str'],
                'bar': bar,
                'probs': [round(probs[0] * 100), round(probs[1] * 100), round(probs[2] * 100)],
                'top': [{'san': m['san'], 'ev': m['eval_str']} for m in analysis['top_moves']] if show_top else [],
            }
        except Exception as e:
            print(f"Analysis error: {e}")

    # PGN
    parts = []
    for i, san in enumerate(state.move_history):
        if i % 2 == 0:
            parts.append(f"{i // 2 + 1}. {san}")
        else:
            parts.append(san)

    lm = None
    if state.last_move:
        lm = {'f': chess.square_name(state.last_move.from_square),
              't': chess.square_name(state.last_move.to_square)}

    # Variation info
    var_info = {
        'current': state.var_tree.current_branch,
        'branches': list(state.var_tree.branches.keys()),
    }

    return {
        'fen': board.fen(),
        'board': board_to_array(board, state.perspective_white),
        'turn': 'w' if board.turn else 'b',
        'check': board.is_check(),
        'over': board.is_game_over(),
        'result': board.result() if board.is_game_over() else None,
        'history': state.move_history,
        'pgn': ' '.join(parts),
        'lm': lm,
        'pw': state.perspective_white,
        'mode': state.mode,
        'pc': 'w' if state.player_color else 'b',
        'skill': state.skill_level,
        'captured': get_captured(board),
        'analysis': analysis_data,
        'legal': get_legal_moves_map(board),
        'variations': var_info,
        'game_id': state.game_id,
        'game_name': state.game_name,
    }


# --- Routes ---

@app.route('/')
def index():
    return render_template('index.html')


@app.route('/api/state')
def api_state():
    return jsonify(build_state())


@app.route('/api/move', methods=['POST'])
def api_move():
    data = request.json
    move_str = data.get('move', '')
    board = state.board

    if board.is_game_over():
        return jsonify({'error': 'Jogo já terminou'}), 400
    if state.mode == 'play' and board.turn != state.player_color:
        return jsonify({'error': 'Não é sua vez'}), 400

    move = None
    try:
        move = chess.Move.from_uci(move_str)
        if move not in board.legal_moves:
            move = None
    except (ValueError, chess.InvalidMoveError):
        pass

    if not move:
        move = parse_move_input(board, move_str)

    if not move:
        return jsonify({'error': f'Jogada inválida: {move_str}'}), 400

    san = board.san(move)
    board.push(move)
    state.last_move = move
    state.move_history.append(san)
    state.var_tree.add_move(san)
    state.auto_save()
    return jsonify(build_state())


@app.route('/api/undo', methods=['POST'])
def api_undo():
    if not state.board.move_stack:
        return jsonify({'error': 'Nada para desfazer'}), 400
    state.board.pop()
    if state.move_history:
        state.move_history.pop()
    state.var_tree.undo_move()
    state.last_move = state.board.move_stack[-1] if state.board.move_stack else None
    state.auto_save()
    return jsonify(build_state())


@app.route('/api/reset', methods=['POST'])
def api_reset():
    state.board = chess.Board()
    state.last_move = None
    state.move_history = []
    state.var_tree = VariationTree()
    state.auto_save()
    return jsonify(build_state())


@app.route('/api/flip', methods=['POST'])
def api_flip():
    state.perspective_white = not state.perspective_white
    return jsonify(build_state())


@app.route('/api/engine-move', methods=['POST'])
def api_engine_move():
    if state.board.is_game_over():
        return jsonify({'error': 'Jogo já terminou'}), 400
    move = state.engine.get_best_move(state.board)
    san = state.board.san(move)
    state.board.push(move)
    state.last_move = move
    state.move_history.append(san)
    state.auto_save()
    return jsonify(build_state())


@app.route('/api/new-game', methods=['POST'])
def api_new_game():
    data = request.json
    state.mode = data.get('mode', 'analysis')
    state.player_color = chess.WHITE if data.get('color', 'w') == 'w' else chess.BLACK
    state.skill_level = data.get('skill', 10)
    state.engine.set_skill_level(state.skill_level)
    state.perspective_white = True if state.mode == 'analysis' else (state.player_color == chess.WHITE)
    state.board = chess.Board()
    state.last_move = None
    state.move_history = []
    state.var_tree = VariationTree()
    state.game_id = _new_game_id()
    state.game_name = data.get('name', 'Nova Partida').strip() or 'Nova Partida'

    if state.mode == 'play' and state.player_color == chess.BLACK:
        move = state.engine.get_best_move(state.board)
        san = state.board.san(move)
        state.board.push(move)
        state.last_move = move
        state.move_history.append(san)

    state.auto_save()
    return jsonify(build_state())


@app.route('/api/load-moves', methods=['POST'])
def api_load_moves():
    data = request.json
    moves_str = data.get('moves', '')
    board = chess.Board()
    history = []

    tokens = moves_str.split()
    for token in tokens:
        clean = re.sub(r'^\d+\.+', '', token)
        if not clean or clean in ('1-0', '0-1', '1/2-1/2', '*'):
            continue
        try:
            move = board.parse_san(clean)
            history.append(board.san(move))
            board.push(move)
        except (ValueError, chess.IllegalMoveError, chess.AmbiguousMoveError):
            break

    state.board = board
    state.move_history = history
    state.last_move = board.move_stack[-1] if board.move_stack else None
    state.mode = 'analysis'
    state.perspective_white = True
    state.var_tree = VariationTree()
    for san in history:
        state.var_tree.add_move(san)

    state.auto_save()
    return jsonify(build_state())


@app.route('/api/games')
def api_games():
    state.save_manager.migrate_autosave()
    return jsonify({'games': state.save_manager.list_games()})


def _restore_game_data(data: dict):
    """Aplica dados de uma partida salva ao estado global."""
    board = chess.Board()
    move_history = data.get('move_history', [])
    last_move = None
    for san in move_history:
        try:
            move = board.parse_san(san)
            board.push(move)
            last_move = move
        except ValueError:
            break

    state.board = board
    state.move_history = move_history[:len(board.move_stack)]
    state.last_move = last_move
    state.game_id = data.get('id', _new_game_id())
    state.game_name = data.get('name', 'Partida')

    if data.get('mode') == 'analysis':
        state.mode = 'analysis'
        state.perspective_white = data.get('perspective_white', True)
        state.var_tree = VariationTree()
        var_data = data.get('variation_tree', {})
        if var_data.get('main_line'):
            state.var_tree.main_line = var_data['main_line']
        if var_data.get('branches'):
            for name, branch_data in var_data['branches'].items():
                if isinstance(branch_data, list) and len(branch_data) == 2:
                    state.var_tree.branches[name] = (branch_data[0], branch_data[1])
    else:
        state.mode = 'play'
        state.player_color = chess.WHITE if data.get('player_color') == 'white' else chess.BLACK
        state.skill_level = data.get('skill_level', 10)
        state.engine.set_skill_level(state.skill_level)
        state.perspective_white = state.player_color == chess.WHITE
        state.var_tree = VariationTree()
        for san in state.move_history:
            state.var_tree.add_move(san)


@app.route('/api/games/load', methods=['POST'])
def api_games_load():
    data_req = request.json
    game_id = data_req.get('id', '')
    data = state.save_manager.load(game_id)
    if not data:
        return jsonify({'error': 'Partida não encontrada'}), 404
    _restore_game_data(data)
    return jsonify(build_state())


@app.route('/api/games/delete', methods=['POST'])
def api_games_delete():
    data = request.json
    state.save_manager.delete(data.get('id', ''))
    return jsonify({'ok': True, 'games': state.save_manager.list_games()})


@app.route('/api/games/rename', methods=['POST'])
def api_games_rename():
    data = request.json
    game_id = data.get('id', '')
    new_name = data.get('name', '').strip()
    if not new_name:
        return jsonify({'error': 'Nome inválido'}), 400
    state.save_manager.rename(game_id, new_name)
    if state.game_id == game_id:
        state.game_name = new_name
    return jsonify({'ok': True})


@app.route('/api/hint')
def api_hint():
    """Get best move hint."""
    if state.board.is_game_over():
        return jsonify({'error': 'Jogo terminou'}), 400
    try:
        analysis = get_position_analysis(state.engine, state.board)
        if analysis.get('top_moves'):
            best = analysis['top_moves'][0]
            return jsonify({'san': best['san'], 'eval': best['eval_str']})
        return jsonify({'error': 'Sem sugestao'}), 400
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/var/create', methods=['POST'])
def api_var_create():
    """Create a new variation branch."""
    name = state.var_tree.create_branch()
    return jsonify({**build_state(), 'var_created': name})


@app.route('/api/var/back', methods=['POST'])
def api_var_back():
    """Switch back to main line."""
    if not state.var_tree.current_branch:
        return jsonify({'error': 'Ja esta na linha principal'}), 400

    state.var_tree.switch_to_main()
    # Rebuild board from main line
    board = chess.Board()
    move_history = []
    last_move = None
    for san in state.var_tree.main_line:
        try:
            move = board.parse_san(san)
            board.push(move)
            move_history.append(san)
            last_move = move
        except ValueError:
            break

    state.board = board
    state.move_history = move_history
    state.last_move = last_move
    state.auto_save()
    return jsonify(build_state())


@app.route('/api/var/switch', methods=['POST'])
def api_var_switch():
    """Switch to a specific variation."""
    data = request.json
    name = data.get('name', '')
    if not state.var_tree.switch_to_branch(name):
        return jsonify({'error': f'Variacao "{name}" nao encontrada'}), 400

    # Rebuild board from branch moves
    moves = state.var_tree.get_current_moves()
    board = chess.Board()
    move_history = []
    last_move = None
    for san in moves:
        try:
            move = board.parse_san(san)
            board.push(move)
            move_history.append(san)
            last_move = move
        except ValueError:
            break

    state.board = board
    state.move_history = move_history
    state.last_move = last_move
    state.auto_save()
    return jsonify(build_state())


@app.route('/api/var/tree')
def api_var_tree():
    """Get variation tree as text."""
    return jsonify({'text': state.var_tree.to_tree_string()})


@app.route('/api/analysis/<atype>', methods=['POST'])
def api_analysis(atype):
    board = state.board
    perspective = chess.WHITE if state.perspective_white else chess.BLACK
    try:
        if atype == 'threats':
            a = state.threat_analyzer.analyze(board)
            text = state.threat_analyzer.format(a, perspective)
        elif atype == 'tactics':
            a = state.tactics_detector.analyze(board)
            text = state.tactics_detector.format(a)
        elif atype == 'plan':
            a = state.plan_suggester.suggest(board)
            text = state.plan_suggester.format(a)
        elif atype == 'pawns':
            a = state.pawn_analyzer.analyze(board)
            text = state.pawn_analyzer.format(a)
        elif atype == 'center':
            a = state.center_analyzer.analyze(board)
            text = state.center_analyzer.format(a)
        elif atype == 'king':
            a = state.king_analyzer.analyze(board)
            text = state.king_analyzer.format(a)
        elif atype == 'pieces':
            a = state.piece_analyzer.analyze(board)
            text = state.piece_analyzer.format(a)
        elif atype == 'weak':
            a = state.weakness_analyzer.analyze(board)
            text = state.weakness_analyzer.format(a, perspective)
        elif atype == 'full':
            text = state.full_analyzer.analyze_all(board, perspective)
        elif atype == 'whatif':
            r = state.what_if.analyze_moves(board, num_moves=5)
            text = state.what_if.format_analysis(r)
        elif atype == 'simulate':
            data = request.json or {}
            n = data.get('n', 500)
            r = state.monte_carlo.simulate(board, n_games=n)
            text = state.monte_carlo.format_results(r)
        else:
            return jsonify({'error': 'Unknown'}), 400
        return jsonify({'text': text})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    print("\n\u2654 Xadrez Fun - Web")
    print("  http://localhost:8080\n")
    app.run(debug=False, port=8080)
