"""Módulo para renderização do tabuleiro de xadrez no terminal."""

import chess

# Peças Unicode
PIECE_SYMBOLS = {
    'R': '♖', 'N': '♘', 'B': '♗', 'Q': '♕', 'K': '♔', 'P': '♙',
    'r': '♜', 'n': '♞', 'b': '♝', 'q': '♛', 'k': '♚', 'p': '♟',
}

# ANSI color codes
RESET = '\033[0m'
BOLD = '\033[1m'
DIM = '\033[2m'

# Board square backgrounds (256-color)
LIGHT_SQ = '\033[48;5;222m'
DARK_SQ = '\033[48;5;130m'
HL_LIGHT_SQ = '\033[48;5;190m'
HL_DARK_SQ = '\033[48;5;142m'

# Piece foreground colors
WHITE_PC = f'{BOLD}\033[97m'
BLACK_PC = '\033[38;5;234m'

PIECE_VALUES = {
    chess.QUEEN: 9, chess.ROOK: 5, chess.BISHOP: 3,
    chess.KNIGHT: 3, chess.PAWN: 1,
}

PIECE_ORDER = [chess.QUEEN, chess.ROOK, chess.BISHOP, chess.KNIGHT, chess.PAWN]

PIECE_UNICODE = {
    (chess.QUEEN, chess.WHITE): '♕', (chess.ROOK, chess.WHITE): '♖',
    (chess.BISHOP, chess.WHITE): '♗', (chess.KNIGHT, chess.WHITE): '♘',
    (chess.PAWN, chess.WHITE): '♙',
    (chess.QUEEN, chess.BLACK): '♛', (chess.ROOK, chess.BLACK): '♜',
    (chess.BISHOP, chess.BLACK): '♝', (chess.KNIGHT, chess.BLACK): '♞',
    (chess.PAWN, chess.BLACK): '♟',
}


def get_material_info(board: chess.Board) -> tuple[str, str, int]:
    """Calcula peças capturadas e diferença material."""
    on_board = {chess.WHITE: {}, chess.BLACK: {}}
    for square in chess.SQUARES:
        piece = board.piece_at(square)
        if piece and piece.piece_type != chess.KING:
            on_board[piece.color][piece.piece_type] = (
                on_board[piece.color].get(piece.piece_type, 0) + 1
            )

    starting = {chess.PAWN: 8, chess.KNIGHT: 2, chess.BISHOP: 2, chess.ROOK: 2, chess.QUEEN: 1}
    white_mat = 0
    black_mat = 0
    captured_by_white = []
    captured_by_black = []

    for pt in PIECE_ORDER:
        val = PIECE_VALUES[pt]
        w_count = on_board[chess.WHITE].get(pt, 0)
        b_count = on_board[chess.BLACK].get(pt, 0)
        white_mat += w_count * val
        black_mat += b_count * val
        captured_by_black.extend(
            [PIECE_UNICODE[(pt, chess.WHITE)]] * max(0, starting[pt] - w_count)
        )
        captured_by_white.extend(
            [PIECE_UNICODE[(pt, chess.BLACK)]] * max(0, starting[pt] - b_count)
        )

    diff = white_mat - black_mat
    return (
        ''.join(captured_by_white) if captured_by_white else '',
        ''.join(captured_by_black) if captured_by_black else '',
        diff,
    )


def render_board(board: chess.Board, perspective_white: bool = True, last_move: chess.Move = None) -> str:
    """Renderiza o tabuleiro com cores ANSI e peças capturadas."""
    lines = []

    highlight_squares = set()
    if last_move:
        highlight_squares.add(last_move.from_square)
        highlight_squares.add(last_move.to_square)

    ranks = range(7, -1, -1) if perspective_white else range(8)
    files = range(8) if perspective_white else range(7, -1, -1)

    # Material info
    w_captured, b_captured, mat_diff = get_material_info(board)
    top_captured = b_captured if perspective_white else w_captured
    bottom_captured = w_captured if perspective_white else b_captured
    top_diff = ""
    bottom_diff = ""
    if mat_diff > 0:
        if perspective_white:
            bottom_diff = f" +{mat_diff}"
        else:
            top_diff = f" +{mat_diff}"
    elif mat_diff < 0:
        if perspective_white:
            top_diff = f" +{abs(mat_diff)}"
        else:
            bottom_diff = f" +{abs(mat_diff)}"

    if top_captured:
        lines.append(f"   {top_captured}{top_diff}")
    else:
        lines.append("")

    # Column headers
    file_letters = list('abcdefgh' if perspective_white else 'hgfedcba')
    header = ''.join(f' {c} ' for c in file_letters)
    lines.append(f'  {DIM}{header}{RESET}')

    for rank in ranks:
        row_parts = []
        for file in files:
            square = chess.square(file, rank)
            piece = board.piece_at(square)
            is_light = (file + rank) % 2 == 1
            is_hl = square in highlight_squares

            if is_hl:
                bg = HL_LIGHT_SQ if is_light else HL_DARK_SQ
            else:
                bg = LIGHT_SQ if is_light else DARK_SQ

            if piece:
                fg = WHITE_PC if piece.color == chess.WHITE else BLACK_PC
                symbol = PIECE_SYMBOLS[piece.symbol()]
            else:
                symbol = ' '
                fg = ''

            row_parts.append(f'{bg}{fg} {symbol} {RESET}')

        rank_num = rank + 1
        row_str = ''.join(row_parts)
        lines.append(f'{DIM}{rank_num}{RESET} {row_str} {DIM}{rank_num}{RESET}')

    lines.append(f'  {DIM}{header}{RESET}')

    if bottom_captured:
        lines.append(f"   {bottom_captured}{bottom_diff}")
    else:
        lines.append("")

    return '\n'.join(lines)


def format_legal_moves(board: chess.Board) -> str:
    """
    Formata a lista de jogadas legais de forma legível.

    Args:
        board: Tabuleiro de xadrez

    Returns:
        String com jogadas agrupadas
    """
    moves = list(board.legal_moves)

    if not moves:
        return "Nenhuma jogada legal disponível!"

    # Converter para notação SAN e ordenar
    san_moves = sorted([board.san(move) for move in moves])

    # Agrupar em linhas de 10
    groups = []
    for i in range(0, len(san_moves), 10):
        groups.append(', '.join(san_moves[i:i+10]))

    return '\n'.join(groups)


def format_move_uci(move: chess.Move) -> str:
    """Formata um movimento em notação UCI (ex: e2e4)."""
    return move.uci()


def parse_move_input(board: chess.Board, move_str: str) -> chess.Move:
    """
    Tenta interpretar a entrada do usuário como um movimento.
    Aceita tanto UCI (e2e4) quanto SAN (e4, Nf3).

    Args:
        board: Tabuleiro atual
        move_str: String da jogada

    Returns:
        Movimento válido ou None se inválido
    """
    move_str = move_str.strip()

    # Tentar como UCI primeiro
    try:
        move = chess.Move.from_uci(move_str)
        if move in board.legal_moves:
            return move
    except ValueError:
        pass

    # Tentar como SAN
    try:
        move = board.parse_san(move_str)
        if move in board.legal_moves:
            return move
    except ValueError:
        pass

    return None


def show_game_status(board: chess.Board) -> str:
    """
    Retorna string com o status atual do jogo.
    """
    status = []

    turn = "Brancas" if board.turn == chess.WHITE else "Pretas"
    status.append(f"Turno: {turn}")

    if board.is_check():
        status.append("⚠️  XEQUE!")

    if board.is_checkmate():
        winner = "Pretas" if board.turn == chess.WHITE else "Brancas"
        status.append(f"♚ XEQUE-MATE! {winner} vencem!")
    elif board.is_stalemate():
        status.append("Empate por afogamento!")
    elif board.is_insufficient_material():
        status.append("Empate por material insuficiente!")
    elif board.is_fifty_moves():
        status.append("Empate pela regra dos 50 movimentos!")
    elif board.is_repetition():
        status.append("Empate por repetição!")

    return ' | '.join(status)
