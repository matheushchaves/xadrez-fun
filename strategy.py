"""Módulo de análise estratégica de xadrez."""

import chess
from typing import Optional
from engine import ChessEngine

# Nomes das peças em português
PIECE_NAMES = {
    chess.PAWN: 'Peão',
    chess.KNIGHT: 'Cavalo',
    chess.BISHOP: 'Bispo',
    chess.ROOK: 'Torre',
    chess.QUEEN: 'Dama',
    chess.KING: 'Rei',
}

PIECE_SYMBOLS = {
    (chess.PAWN, chess.WHITE): '♙',
    (chess.KNIGHT, chess.WHITE): '♘',
    (chess.BISHOP, chess.WHITE): '♗',
    (chess.ROOK, chess.WHITE): '♖',
    (chess.QUEEN, chess.WHITE): '♕',
    (chess.KING, chess.WHITE): '♔',
    (chess.PAWN, chess.BLACK): '♟',
    (chess.KNIGHT, chess.BLACK): '♞',
    (chess.BISHOP, chess.BLACK): '♝',
    (chess.ROOK, chess.BLACK): '♜',
    (chess.QUEEN, chess.BLACK): '♛',
    (chess.KING, chess.BLACK): '♚',
}

PIECE_VALUES = {
    chess.PAWN: 1,
    chess.KNIGHT: 3,
    chess.BISHOP: 3,
    chess.ROOK: 5,
    chess.QUEEN: 9,
    chess.KING: 0,
}


def square_name(sq: int) -> str:
    """Converte número da casa para nome (ex: 0 -> a1)."""
    return chess.square_name(sq)


class ThreatAnalyzer:
    """Detecta ameaças na posição."""

    def analyze(self, board: chess.Board) -> dict:
        """Analisa ameaças para ambos os lados."""
        return {
            'white_threats': self._get_threats(board, chess.WHITE),
            'black_threats': self._get_threats(board, chess.BLACK),
        }

    def _get_threats(self, board: chess.Board, color: chess.Color) -> list[str]:
        """Encontra ameaças de uma cor."""
        threats = []
        opponent = not color

        # Peças do oponente que estão atacadas
        for sq in chess.SQUARES:
            piece = board.piece_at(sq)
            if piece and piece.color == opponent:
                attackers = board.attackers(color, sq)
                if attackers:
                    # Verificar se está defendida
                    defenders = board.attackers(opponent, sq)
                    piece_name = PIECE_NAMES[piece.piece_type]
                    sq_name = square_name(sq)

                    if not defenders:
                        threats.append(f"{piece_name} em {sq_name} não defendido!")
                    else:
                        # Verificar se atacante vale menos que peça atacada
                        for attacker_sq in attackers:
                            attacker = board.piece_at(attacker_sq)
                            if attacker and PIECE_VALUES[attacker.piece_type] < PIECE_VALUES[piece.piece_type]:
                                attacker_name = PIECE_NAMES[attacker.piece_type]
                                threats.append(
                                    f"{attacker_name} ataca {piece_name} em {sq_name} (ganho de material)"
                                )
                                break

        # Verificar ameaça de mate
        for move in board.legal_moves:
            if board.turn == color:
                board.push(move)
                if board.is_checkmate():
                    board.pop()
                    threats.append(f"Ameaça de MATE com {board.san(move)}!")
                    break
                board.pop()

        return threats

    def format(self, analysis: dict, perspective: chess.Color) -> str:
        """Formata análise de ameaças."""
        lines = ["⚠️  AMEAÇAS:"]

        # Ameaças contra você
        enemy_threats = analysis['black_threats'] if perspective == chess.WHITE else analysis['white_threats']
        if enemy_threats:
            lines.append("\n  Contra VOCÊ:")
            for t in enemy_threats[:5]:
                lines.append(f"    - {t}")
        else:
            lines.append("\n  Contra você: Nenhuma ameaça imediata")

        # Suas ameaças
        your_threats = analysis['white_threats'] if perspective == chess.WHITE else analysis['black_threats']
        if your_threats:
            lines.append("\n  SUAS ameaças:")
            for t in your_threats[:5]:
                lines.append(f"    - {t}")
        else:
            lines.append("\n  Suas ameaças: Nenhuma")

        return '\n'.join(lines)


class WeaknessAnalyzer:
    """Analisa fraquezas posicionais."""

    def analyze(self, board: chess.Board) -> dict:
        """Analisa fraquezas para ambos os lados."""
        return {
            'white': self._get_weaknesses(board, chess.WHITE),
            'black': self._get_weaknesses(board, chess.BLACK),
        }

    def _get_weaknesses(self, board: chess.Board, color: chess.Color) -> list[str]:
        """Encontra fraquezas de uma cor."""
        weaknesses = []

        # Analisar peões
        pawn_files = []
        for sq in chess.SQUARES:
            piece = board.piece_at(sq)
            if piece and piece.piece_type == chess.PAWN and piece.color == color:
                pawn_files.append(chess.square_file(sq))

        # Peões isolados
        for f in set(pawn_files):
            has_neighbor = (f - 1) in pawn_files or (f + 1) in pawn_files
            if not has_neighbor:
                file_name = 'abcdefgh'[f]
                weaknesses.append(f"Peão isolado na coluna {file_name}")

        # Peões dobrados
        from collections import Counter
        file_counts = Counter(pawn_files)
        for f, count in file_counts.items():
            if count > 1:
                file_name = 'abcdefgh'[f]
                weaknesses.append(f"Peões dobrados na coluna {file_name}")

        # Rei exposto (não rocado e centro aberto)
        king_sq = board.king(color)
        if king_sq:
            king_file = chess.square_file(king_sq)
            king_rank = chess.square_rank(king_sq)
            initial_rank = 0 if color == chess.WHITE else 7

            if king_rank == initial_rank and king_file == 4:
                # Rei ainda no centro
                if not board.has_castling_rights(color):
                    weaknesses.append("Rei preso no centro (sem direito a roque)")
                else:
                    weaknesses.append("Rei ainda não rocou")

        return weaknesses

    def format(self, analysis: dict, perspective: chess.Color) -> str:
        """Formata análise de fraquezas."""
        lines = ["🔍 FRAQUEZAS:"]

        your_weak = analysis['white'] if perspective == chess.WHITE else analysis['black']
        enemy_weak = analysis['black'] if perspective == chess.WHITE else analysis['white']

        lines.append("\n  SUAS fraquezas:")
        if your_weak:
            for w in your_weak:
                lines.append(f"    - {w}")
        else:
            lines.append("    - Nenhuma fraqueza significativa")

        lines.append("\n  Fraquezas do OPONENTE:")
        if enemy_weak:
            for w in enemy_weak:
                lines.append(f"    - {w}")
        else:
            lines.append("    - Nenhuma fraqueza significativa")

        return '\n'.join(lines)


class PawnStructureAnalyzer:
    """Analisa estrutura de peões."""

    def analyze(self, board: chess.Board) -> dict:
        """Analisa estrutura de peões."""
        return {
            'white': self._analyze_pawns(board, chess.WHITE),
            'black': self._analyze_pawns(board, chess.BLACK),
        }

    def _analyze_pawns(self, board: chess.Board, color: chess.Color) -> dict:
        """Analisa peões de uma cor."""
        pawns = []
        for sq in chess.SQUARES:
            piece = board.piece_at(sq)
            if piece and piece.piece_type == chess.PAWN and piece.color == color:
                pawns.append(sq)

        pawn_files = [chess.square_file(sq) for sq in pawns]

        # Contar ilhas
        islands = self._count_islands(pawn_files)

        # Peões passados
        passed = []
        for sq in pawns:
            if self._is_passed(board, sq, color):
                passed.append(square_name(sq))

        # Peões dobrados
        from collections import Counter
        doubled_files = [f for f, c in Counter(pawn_files).items() if c > 1]

        # Peões isolados
        isolated = []
        for f in set(pawn_files):
            if (f - 1) not in pawn_files and (f + 1) not in pawn_files:
                isolated.append('abcdefgh'[f])

        return {
            'count': len(pawns),
            'islands': islands,
            'passed': passed,
            'doubled': ['abcdefgh'[f] for f in doubled_files],
            'isolated': isolated,
        }

    def _count_islands(self, files: list[int]) -> int:
        """Conta ilhas de peões."""
        if not files:
            return 0
        sorted_files = sorted(set(files))
        islands = 1
        for i in range(1, len(sorted_files)):
            if sorted_files[i] - sorted_files[i-1] > 1:
                islands += 1
        return islands

    def _is_passed(self, board: chess.Board, sq: int, color: chess.Color) -> bool:
        """Verifica se peão é passado."""
        file = chess.square_file(sq)
        rank = chess.square_rank(sq)

        # Direção de avanço
        direction = 1 if color == chess.WHITE else -1
        enemy_color = not color

        # Verificar se há peões adversários bloqueando
        for f in [file - 1, file, file + 1]:
            if 0 <= f <= 7:
                check_rank = rank + direction
                while 0 <= check_rank <= 7:
                    check_sq = chess.square(f, check_rank)
                    piece = board.piece_at(check_sq)
                    if piece and piece.piece_type == chess.PAWN and piece.color == enemy_color:
                        return False
                    check_rank += direction
        return True

    def format(self, analysis: dict) -> str:
        """Formata análise de estrutura de peões."""
        lines = ["♟ ESTRUTURA DE PEÕES:"]

        w = analysis['white']
        b = analysis['black']

        lines.append(f"\n  Brancas: {w['count']} peões, {w['islands']} ilha(s)")
        lines.append(f"  Pretas:  {b['count']} peões, {b['islands']} ilha(s)")

        # Peões passados
        lines.append("\n  Peões passados:")
        if w['passed']:
            lines.append(f"    Brancas: {', '.join(w['passed'])}")
        if b['passed']:
            lines.append(f"    Pretas: {', '.join(b['passed'])}")
        if not w['passed'] and not b['passed']:
            lines.append("    Nenhum")

        # Fraquezas
        lines.append("\n  Fraquezas:")
        if w['doubled']:
            lines.append(f"    Brancas dobrados: coluna(s) {', '.join(w['doubled'])}")
        if w['isolated']:
            lines.append(f"    Brancas isolados: coluna(s) {', '.join(w['isolated'])}")
        if b['doubled']:
            lines.append(f"    Pretas dobrados: coluna(s) {', '.join(b['doubled'])}")
        if b['isolated']:
            lines.append(f"    Pretas isolados: coluna(s) {', '.join(b['isolated'])}")

        return '\n'.join(lines)


class CenterControlAnalyzer:
    """Avalia controle do centro."""

    CENTER_SQUARES = [chess.E4, chess.D4, chess.E5, chess.D5]
    EXTENDED_CENTER = [chess.C3, chess.D3, chess.E3, chess.F3,
                       chess.C4, chess.F4, chess.C5, chess.F5,
                       chess.C6, chess.D6, chess.E6, chess.F6]

    # Pontos por ocupação de peça no centro
    OCCUPATION_POINTS = {
        chess.PAWN: 3,
        chess.KNIGHT: 4,
        chess.BISHOP: 2,
        chess.ROOK: 1,
        chess.QUEEN: 1,
        chess.KING: 0,
    }

    def analyze(self, board: chess.Board) -> dict:
        """Analisa controle do centro."""
        white_score = 0
        black_score = 0
        white_pieces_center = []
        black_pieces_center = []

        # Peças no centro (mais importante!)
        for sq in self.CENTER_SQUARES:
            piece = board.piece_at(sq)
            if piece:
                sq_name = square_name(sq)
                piece_name = PIECE_NAMES[piece.piece_type]
                points = self.OCCUPATION_POINTS.get(piece.piece_type, 1)
                if piece.color == chess.WHITE:
                    white_pieces_center.append(f"{piece_name} em {sq_name}")
                    white_score += points
                else:
                    black_pieces_center.append(f"{piece_name} em {sq_name}")
                    black_score += points

        # Ataques às casas centrais (menos importante, 0.5 pontos por ataque)
        white_attacks = 0
        black_attacks = 0
        for sq in self.CENTER_SQUARES:
            w_att = len(board.attackers(chess.WHITE, sq))
            b_att = len(board.attackers(chess.BLACK, sq))
            white_attacks += w_att
            black_attacks += b_att

        white_score += white_attacks * 0.5
        black_score += black_attacks * 0.5

        # Determinar dominância (precisa de diferença significativa)
        diff = white_score - black_score
        if diff >= 2:
            dominant = 'white'
        elif diff <= -2:
            dominant = 'black'
        else:
            dominant = 'equal'

        return {
            'white_score': white_score,
            'black_score': black_score,
            'white_attacks': white_attacks,
            'black_attacks': black_attacks,
            'white_pieces': white_pieces_center,
            'black_pieces': black_pieces_center,
            'dominant': dominant,
        }

    def format(self, analysis: dict) -> str:
        """Formata análise de centro."""
        lines = ["🎯 CONTROLE DO CENTRO:"]

        # Ocupação (mais importante)
        if analysis['white_pieces'] or analysis['black_pieces']:
            lines.append("\n  Ocupação do centro:")
            if analysis['white_pieces']:
                lines.append(f"    Brancas: {', '.join(analysis['white_pieces'])}")
            else:
                lines.append("    Brancas: nenhuma peça")
            if analysis['black_pieces']:
                lines.append(f"    Pretas:  {', '.join(analysis['black_pieces'])}")
            else:
                lines.append("    Pretas:  nenhuma peça")
        else:
            lines.append("\n  Centro vazio (nenhuma peça em e4/d4/e5/d5)")

        # Ataques
        lines.append(f"\n  Ataques ao centro:")
        lines.append(f"    Brancas: {analysis['white_attacks']} ataques")
        lines.append(f"    Pretas:  {analysis['black_attacks']} ataques")

        # Score total
        lines.append(f"\n  Score total: Brancas {analysis['white_score']:.1f} vs Pretas {analysis['black_score']:.1f}")

        if analysis['dominant'] == 'white':
            lines.append("  → Brancas DOMINAM o centro")
        elif analysis['dominant'] == 'black':
            lines.append("  → Pretas DOMINAM o centro")
        else:
            lines.append("  → Centro DISPUTADO")

        return '\n'.join(lines)


class KingSafetyAnalyzer:
    """Avalia segurança do rei."""

    def analyze(self, board: chess.Board) -> dict:
        """Analisa segurança dos reis."""
        return {
            'white': self._analyze_king(board, chess.WHITE),
            'black': self._analyze_king(board, chess.BLACK),
        }

    def _analyze_king(self, board: chess.Board, color: chess.Color) -> dict:
        """Analisa segurança de um rei."""
        king_sq = board.king(color)
        if not king_sq:
            return {'safe': False, 'issues': ['Rei não encontrado']}

        issues = []
        positives = []

        king_file = chess.square_file(king_sq)
        king_rank = chess.square_rank(king_sq)

        # Verificar se rocou
        initial_rank = 0 if color == chess.WHITE else 7
        if king_rank == initial_rank:
            if king_file in [6, 2]:  # g1/c1 ou g8/c8
                positives.append("Rocado")
            elif king_file == 4:
                issues.append("Ainda no centro")
        else:
            if king_rank in [0, 7]:
                positives.append("Na primeira/última fila")

        # Verificar peões protetores
        pawn_shield = 0
        shield_files = [king_file - 1, king_file, king_file + 1]
        shield_rank = king_rank + (1 if color == chess.WHITE else -1)

        for f in shield_files:
            if 0 <= f <= 7 and 0 <= shield_rank <= 7:
                sq = chess.square(f, shield_rank)
                piece = board.piece_at(sq)
                if piece and piece.piece_type == chess.PAWN and piece.color == color:
                    pawn_shield += 1

        if pawn_shield >= 2:
            positives.append(f"Bom escudo de peões ({pawn_shield} peões)")
        elif pawn_shield == 1:
            issues.append("Escudo de peões fraco (1 peão)")
        else:
            issues.append("Sem escudo de peões!")

        # Atacantes na zona do rei
        king_zone = self._get_king_zone(king_sq)
        enemy = not color
        attackers = 0
        for sq in king_zone:
            attackers += len(board.attackers(enemy, sq))

        if attackers >= 5:
            issues.append(f"Muitos atacantes na zona do rei ({attackers})")
        elif attackers >= 3:
            issues.append(f"Pressão na zona do rei ({attackers} ataques)")

        safety_score = len(positives) * 2 - len(issues)

        return {
            'square': square_name(king_sq),
            'positives': positives,
            'issues': issues,
            'safety_score': safety_score,
            'safe': safety_score >= 0,
        }

    def _get_king_zone(self, king_sq: int) -> list[int]:
        """Retorna casas ao redor do rei."""
        zone = []
        kf = chess.square_file(king_sq)
        kr = chess.square_rank(king_sq)
        for df in [-1, 0, 1]:
            for dr in [-1, 0, 1]:
                f, r = kf + df, kr + dr
                if 0 <= f <= 7 and 0 <= r <= 7:
                    zone.append(chess.square(f, r))
        return zone

    def format(self, analysis: dict) -> str:
        """Formata análise de segurança do rei."""
        lines = ["👑 SEGURANÇA DO REI:"]

        for color_name, color_key in [("Brancas", "white"), ("Pretas", "black")]:
            a = analysis[color_key]
            status = "SEGURO" if a['safe'] else "EM RISCO"
            lines.append(f"\n  {color_name} (Rei em {a['square']}): {status}")

            if a['positives']:
                for p in a['positives']:
                    lines.append(f"    ✓ {p}")
            if a['issues']:
                for i in a['issues']:
                    lines.append(f"    ✗ {i}")

        return '\n'.join(lines)


class PieceAnalyzer:
    """Avalia qualidade das peças."""

    def analyze(self, board: chess.Board) -> dict:
        """Analisa todas as peças."""
        return {
            'white': self._analyze_pieces(board, chess.WHITE),
            'black': self._analyze_pieces(board, chess.BLACK),
        }

    def _analyze_pieces(self, board: chess.Board, color: chess.Color) -> list[dict]:
        """Analisa peças de uma cor."""
        pieces = []

        for sq in chess.SQUARES:
            piece = board.piece_at(sq)
            if piece and piece.color == color and piece.piece_type != chess.PAWN:
                analysis = self._analyze_piece(board, sq, piece)
                pieces.append(analysis)

        return pieces

    def _analyze_piece(self, board: chess.Board, sq: int, piece: chess.Piece) -> dict:
        """Analisa uma peça específica."""
        sq_name = square_name(sq)
        piece_name = PIECE_NAMES[piece.piece_type]
        symbol = PIECE_SYMBOLS[(piece.piece_type, piece.color)]

        # Calcular mobilidade
        mobility = 0
        for move in board.legal_moves:
            if move.from_square == sq:
                mobility += 1

        # Avaliar posição
        status = []
        issues = []

        if piece.piece_type == chess.KNIGHT:
            # Cavalos são melhores no centro
            file = chess.square_file(sq)
            rank = chess.square_rank(sq)
            if 2 <= file <= 5 and 2 <= rank <= 5:
                status.append("bem centralizado")
            elif file in [0, 7] or rank in [0, 7]:
                issues.append("na borda (ruim)")

        elif piece.piece_type == chess.BISHOP:
            # Verificar se é bispo "bom" ou "ruim"
            # Bispo bom: poucos peões próprios na mesma cor de casa
            bishop_color = (chess.square_file(sq) + chess.square_rank(sq)) % 2
            own_pawns_same_color = 0
            for psq in chess.SQUARES:
                p = board.piece_at(psq)
                if p and p.piece_type == chess.PAWN and p.color == piece.color:
                    pawn_sq_color = (chess.square_file(psq) + chess.square_rank(psq)) % 2
                    if pawn_sq_color == bishop_color:
                        own_pawns_same_color += 1

            if own_pawns_same_color >= 4:
                issues.append("bispo ruim (bloqueado por peões)")
            else:
                status.append("bispo bom")

        elif piece.piece_type == chess.ROOK:
            # Torres são boas em colunas abertas/semi-abertas
            file = chess.square_file(sq)
            has_own_pawn = False
            has_enemy_pawn = False
            for r in range(8):
                p = board.piece_at(chess.square(file, r))
                if p and p.piece_type == chess.PAWN:
                    if p.color == piece.color:
                        has_own_pawn = True
                    else:
                        has_enemy_pawn = True

            if not has_own_pawn and not has_enemy_pawn:
                status.append("coluna aberta!")
            elif not has_own_pawn:
                status.append("coluna semi-aberta")
            else:
                issues.append("coluna fechada")

        elif piece.piece_type == chess.QUEEN:
            if mobility >= 15:
                status.append("muito ativa")
            elif mobility <= 5:
                issues.append("restrita")

        elif piece.piece_type == chess.KING:
            # Já analisado em KingSafetyAnalyzer
            pass

        # Avaliar mobilidade geral
        if mobility == 0:
            issues.append("sem movimentos!")
        elif mobility <= 2:
            issues.append("pouca mobilidade")
        elif mobility >= 8:
            status.append("boa mobilidade")

        return {
            'piece': piece_name,
            'symbol': symbol,
            'square': sq_name,
            'mobility': mobility,
            'status': status,
            'issues': issues,
            'active': len(status) >= len(issues),
        }

    def format(self, analysis: dict) -> str:
        """Formata análise de peças."""
        lines = ["♟ ANÁLISE DAS PEÇAS:"]

        for color_name, color_key in [("BRANCAS", "white"), ("PRETAS", "black")]:
            lines.append(f"\n  {color_name}:")
            for p in analysis[color_key]:
                status_str = ", ".join(p['status'] + p['issues']) if (p['status'] or p['issues']) else "ok"
                active = "✓" if p['active'] else "✗"
                lines.append(f"    {p['symbol']} {p['piece']:6} {p['square']}: {status_str} [{active}]")

        return '\n'.join(lines)


class TacticsDetector:
    """Detecta motivos táticos."""

    def analyze(self, board: chess.Board) -> dict:
        """Detecta táticas para ambos os lados."""
        return {
            'white': self._find_tactics(board, chess.WHITE),
            'black': self._find_tactics(board, chess.BLACK),
        }

    def _find_tactics(self, board: chess.Board, color: chess.Color) -> list[str]:
        """Encontra táticas disponíveis."""
        tactics = []

        # Detectar PINS
        pins = self._find_pins(board, color)
        tactics.extend(pins)

        # Detectar FORKS potenciais
        forks = self._find_forks(board, color)
        tactics.extend(forks)

        # Detectar xeques descobertos
        discoveries = self._find_discoveries(board, color)
        tactics.extend(discoveries)

        return tactics

    def _find_pins(self, board: chess.Board, color: chess.Color) -> list[str]:
        """Encontra cravadas."""
        pins = []
        enemy = not color
        enemy_king_sq = board.king(enemy)

        if not enemy_king_sq:
            return pins

        # Verificar bispos e damas em diagonais
        for sq in chess.SQUARES:
            piece = board.piece_at(sq)
            if piece and piece.color == color and piece.piece_type in [chess.BISHOP, chess.QUEEN]:
                # Verificar se há peça inimiga entre esta peça e o rei
                pin = self._check_pin_line(board, sq, enemy_king_sq, enemy, 'diagonal')
                if pin:
                    pins.append(pin)

        # Verificar torres e damas em linhas/colunas
        for sq in chess.SQUARES:
            piece = board.piece_at(sq)
            if piece and piece.color == color and piece.piece_type in [chess.ROOK, chess.QUEEN]:
                pin = self._check_pin_line(board, sq, enemy_king_sq, enemy, 'straight')
                if pin:
                    pins.append(pin)

        return pins

    def _check_pin_line(self, board: chess.Board, attacker_sq: int, king_sq: int,
                        enemy_color: chess.Color, line_type: str) -> Optional[str]:
        """Verifica se há uma cravada em uma linha."""
        af, ar = chess.square_file(attacker_sq), chess.square_rank(attacker_sq)
        kf, kr = chess.square_file(king_sq), chess.square_rank(king_sq)

        df = 0 if kf == af else (1 if kf > af else -1)
        dr = 0 if kr == ar else (1 if kr > ar else -1)

        # Verificar tipo de linha
        if line_type == 'diagonal' and (df == 0 or dr == 0):
            return None
        if line_type == 'straight' and (df != 0 and dr != 0):
            return None

        # Percorrer linha
        f, r = af + df, ar + dr
        pinned_piece = None
        pinned_sq = None

        while 0 <= f <= 7 and 0 <= r <= 7:
            sq = chess.square(f, r)
            if sq == king_sq:
                if pinned_piece:
                    attacker = board.piece_at(attacker_sq)
                    return f"📌 PIN: {PIECE_NAMES[attacker.piece_type]} crava {PIECE_NAMES[pinned_piece.piece_type]} em {square_name(pinned_sq)}"
                break

            piece = board.piece_at(sq)
            if piece:
                if pinned_piece:
                    break  # Segunda peça, não é pin
                if piece.color == enemy_color:
                    pinned_piece = piece
                    pinned_sq = sq
                else:
                    break  # Peça própria bloqueia

            f += df
            r += dr

        return None

    def _find_forks(self, board: chess.Board, color: chess.Color) -> list[str]:
        """Encontra garfos potenciais."""
        forks = []
        enemy = not color

        # Verificar cavalos
        for sq in chess.SQUARES:
            piece = board.piece_at(sq)
            if piece and piece.color == color and piece.piece_type == chess.KNIGHT:
                # Verificar casas que o cavalo pode atacar
                for move in board.legal_moves:
                    if move.from_square == sq:
                        # Simular movimento
                        targets = []
                        target_sq = move.to_square

                        # Casas que um cavalo atacaria a partir de target_sq
                        knight_attacks = chess.BB_KNIGHT_ATTACKS[target_sq]

                        for attacked_sq in chess.SQUARES:
                            if chess.BB_SQUARES[attacked_sq] & knight_attacks:
                                attacked_piece = board.piece_at(attacked_sq)
                                if attacked_piece and attacked_piece.color == enemy:
                                    if attacked_piece.piece_type in [chess.QUEEN, chess.ROOK, chess.KING]:
                                        targets.append(PIECE_NAMES[attacked_piece.piece_type])

                        if len(targets) >= 2:
                            forks.append(f"🍴 FORK: Cavalo em {square_name(target_sq)} ataca {' e '.join(targets)}")
                            break

        return forks[:2]  # Limitar

    def _find_discoveries(self, board: chess.Board, color: chess.Color) -> list[str]:
        """Encontra ataques descobertos potenciais."""
        discoveries = []

        # Simplificado: verificar se mover uma peça revela ataque
        for move in board.legal_moves:
            if board.turn != color:
                continue

            piece = board.piece_at(move.from_square)
            if not piece or piece.color != color:
                continue

            # Simular movimento
            board.push(move)

            # Verificar se revelou xeque
            if board.is_check():
                board.pop()
                discoveries.append(f"💨 DESCOBERTA: Mover {PIECE_NAMES[piece.piece_type]} dá xeque descoberto!")
                break

            board.pop()

        return discoveries

    def format(self, analysis: dict) -> str:
        """Formata análise tática."""
        lines = ["⚔️  TÁTICAS DISPONÍVEIS:"]

        w_tactics = analysis['white']
        b_tactics = analysis['black']

        lines.append("\n  Para BRANCAS:")
        if w_tactics:
            for t in w_tactics[:5]:
                lines.append(f"    {t}")
        else:
            lines.append("    Nenhuma tática óbvia")

        lines.append("\n  Para PRETAS:")
        if b_tactics:
            for t in b_tactics[:5]:
                lines.append(f"    {t}")
        else:
            lines.append("    Nenhuma tática óbvia")

        return '\n'.join(lines)


class PlanSuggester:
    """Sugere planos estratégicos."""

    def __init__(self, engine: ChessEngine):
        self.engine = engine

    def suggest(self, board: chess.Board) -> dict:
        """Sugere plano estratégico."""
        # Determinar fase do jogo
        phase = self._get_game_phase(board)

        # Obter avaliação
        eval_dict = self.engine.get_evaluation(board)

        # Analisar características da posição
        characteristics = self._analyze_position(board)

        # Gerar planos baseados na fase e características
        plans = self._generate_plans(board, phase, characteristics)

        # O que evitar
        avoid = self._what_to_avoid(board, phase, characteristics)

        return {
            'phase': phase,
            'evaluation': eval_dict,
            'characteristics': characteristics,
            'plans': plans,
            'avoid': avoid,
        }

    def _get_game_phase(self, board: chess.Board) -> str:
        """Determina fase do jogo."""
        # Contar peças
        queens = len(board.pieces(chess.QUEEN, chess.WHITE)) + len(board.pieces(chess.QUEEN, chess.BLACK))
        minors = (len(board.pieces(chess.KNIGHT, chess.WHITE)) + len(board.pieces(chess.KNIGHT, chess.BLACK)) +
                  len(board.pieces(chess.BISHOP, chess.WHITE)) + len(board.pieces(chess.BISHOP, chess.BLACK)))
        rooks = len(board.pieces(chess.ROOK, chess.WHITE)) + len(board.pieces(chess.ROOK, chess.BLACK))

        if board.fullmove_number <= 10:
            return "Abertura"
        elif queens == 0 and rooks <= 2 and minors <= 2:
            return "Final"
        elif queens == 0:
            return "Final"
        else:
            return "Meio-jogo"

    def _analyze_position(self, board: chess.Board) -> list[str]:
        """Analisa características da posição."""
        chars = []

        # Centro
        center_analyzer = CenterControlAnalyzer()
        center = center_analyzer.analyze(board)
        if center['dominant'] == 'white':
            chars.append("Brancas controlam centro")
        elif center['dominant'] == 'black':
            chars.append("Pretas controlam centro")

        # Colunas abertas
        for f in range(8):
            has_pawn = False
            for r in range(8):
                p = board.piece_at(chess.square(f, r))
                if p and p.piece_type == chess.PAWN:
                    has_pawn = True
                    break
            if not has_pawn:
                chars.append(f"Coluna {chr(ord('a') + f)} aberta")
                break  # Só mencionar uma

        # Bispos vs cavalos
        w_bishops = len(board.pieces(chess.BISHOP, chess.WHITE))
        b_bishops = len(board.pieces(chess.BISHOP, chess.BLACK))
        if w_bishops == 2:
            chars.append("Brancas têm par de bispos")
        if b_bishops == 2:
            chars.append("Pretas têm par de bispos")

        return chars

    def _generate_plans(self, board: chess.Board, phase: str, chars: list[str]) -> list[str]:
        """Gera sugestões de plano."""
        plans = []

        if phase == "Abertura":
            plans.append("Completar desenvolvimento das peças")
            plans.append("Rocar para segurança do rei")
            plans.append("Controlar o centro com peões e peças")

        elif phase == "Meio-jogo":
            if any("controlam centro" in c for c in chars):
                plans.append("Expandir no flanco onde você tem vantagem espacial")

            if any("Coluna" in c and "aberta" in c for c in chars):
                plans.append("Ocupar coluna aberta com torre(s)")

            if any("par de bispos" in c for c in chars):
                plans.append("Abrir posição para maximizar bispos")

            plans.append("Buscar trocar peças ruins por peças boas do adversário")
            plans.append("Criar fraquezas na posição adversária")

        else:  # Final
            plans.append("Ativar o rei (rei é peça forte no final)")
            plans.append("Criar peão passado")
            plans.append("Centralizar torres atrás de peões passados")

        return plans[:4]

    def _what_to_avoid(self, board: chess.Board, phase: str, chars: list[str]) -> list[str]:
        """Gera lista do que evitar."""
        avoid = []

        if phase == "Abertura":
            avoid.append("Mover a mesma peça duas vezes")
            avoid.append("Trazer dama cedo demais")

        elif phase == "Meio-jogo":
            if any("par de bispos" in c for c in chars):
                avoid.append("Fechar a posição")

            avoid.append("Trocas que ajudem o adversário")

        else:  # Final
            avoid.append("Passividade - rei deve estar ativo")

        return avoid

    def format(self, analysis: dict) -> str:
        """Formata sugestão de plano."""
        lines = ["📋 PLANO ESTRATÉGICO:"]

        lines.append(f"\n  Fase: {analysis['phase']}")

        # Avaliação
        ev = analysis['evaluation']
        if ev['type'] == 'mate':
            eval_str = f"Mate em {abs(ev['value'])}"
        else:
            val = ev['value'] / 100
            if val > 0.5:
                eval_str = f"+{val:.2f} (Brancas melhor)"
            elif val < -0.5:
                eval_str = f"{val:.2f} (Pretas melhor)"
            else:
                eval_str = f"{val:.2f} (Equilibrado)"
        lines.append(f"  Avaliação: {eval_str}")

        # Características
        if analysis['characteristics']:
            lines.append("\n  Características da posição:")
            for c in analysis['characteristics']:
                lines.append(f"    • {c}")

        # Planos
        lines.append("\n  Plano recomendado:")
        for i, p in enumerate(analysis['plans'], 1):
            lines.append(f"    {i}. {p}")

        # Evitar
        if analysis['avoid']:
            lines.append("\n  Evitar:")
            for a in analysis['avoid']:
                lines.append(f"    ✗ {a}")

        return '\n'.join(lines)


class FullAnalyzer:
    """Executa todas as análises."""

    def __init__(self, engine: ChessEngine):
        self.threat = ThreatAnalyzer()
        self.weakness = WeaknessAnalyzer()
        self.pawns = PawnStructureAnalyzer()
        self.center = CenterControlAnalyzer()
        self.king = KingSafetyAnalyzer()
        self.pieces = PieceAnalyzer()
        self.tactics = TacticsDetector()
        self.plan = PlanSuggester(engine)

    def analyze_all(self, board: chess.Board, perspective: chess.Color) -> str:
        """Executa todas as análises e formata."""
        sections = []

        # Plano (primeiro, mais importante)
        plan_analysis = self.plan.suggest(board)
        sections.append(self.plan.format(plan_analysis))

        sections.append("")

        # Ameaças
        threat_analysis = self.threat.analyze(board)
        sections.append(self.threat.format(threat_analysis, perspective))

        sections.append("")

        # Táticas
        tactics_analysis = self.tactics.analyze(board)
        sections.append(self.tactics.format(tactics_analysis))

        sections.append("")

        # Centro
        center_analysis = self.center.analyze(board)
        sections.append(self.center.format(center_analysis))

        sections.append("")

        # Rei
        king_analysis = self.king.analyze(board)
        sections.append(self.king.format(king_analysis))

        sections.append("")

        # Peças
        pieces_analysis = self.pieces.analyze(board)
        sections.append(self.pieces.format(pieces_analysis))

        sections.append("")

        # Peões
        pawns_analysis = self.pawns.analyze(board)
        sections.append(self.pawns.format(pawns_analysis))

        sections.append("")

        # Fraquezas
        weakness_analysis = self.weakness.analyze(board)
        sections.append(self.weakness.format(weakness_analysis, perspective))

        return '\n'.join(sections)
