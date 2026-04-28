"""
Módulo de visão assistida para xadrez - captura e análise em tempo real.

Funcionalidade:
1. Captura região do tabuleiro via hotkey
2. Calibração por clique nas 4 quinas
3. Detecção de posição (simples por cor/padrão ou manual)
4. Integração com engine.py para análise instantânea

Uso seguro: hotkey ativa captura, sem automação contínua.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional, Tuple, List

import chess
import cv2
import mss
import numpy as np
from PIL import Image

# Configurações
CALIBRATION_FILE = Path(__file__).parent / ".chess_vision_config.json"
ANALYSIS_WINDOW = Path(__file__).parent / "analysis_window.py"


class ChessVision:
    """Sistema de visão assistida para xadrez."""

    def __init__(self):
        self.board_region = None  # (x, y, w, h)
        self.screenshot = None
        self.calibrated = False
        self._load_calibration()

    def _load_calibration(self):
        """Carrega calibração salva."""
        if CALIBRATION_FILE.exists():
            try:
                with open(CALIBRATION_FILE) as f:
                    config = json.load(f)
                    self.board_region = tuple(config.get('board_region', []))
                    self.calibrated = len(self.board_region) == 4
            except Exception:
                pass

    def _save_calibration(self):
        """Salva calibração atual."""
        with open(CALIBRATION_FILE, 'w') as f:
            json.dump({'board_region': list(self.board_region)}, f)

    def calibrate_interactive(self):
        """
        Calibração interativa por linha de comando.
        Alternativa ao clique visual - usuário informa coordenadas.
        """
        print("\n" + "="*60)
        print("🎯 CALIBRAÇÃO DO TABULEIRO")
        print("="*60)
        print("\nInstruções:")
        print("1. Abra o chess.com ou lichess em uma aba visível")
        print("2. Ajuste o tabuleiro para aparecer completamente")
        print("3. Usaremos a ferramenta de seleção de região...")

        # Usar peekaboo se disponível, ou fallback para manual
        try:
            return self._calibrate_with_peekaboo()
        except Exception as e:
            print(f"Peekaboo indisponível: {e}")
            return self._calibrate_manual()

    def _calibrate_with_peekaboo(self) -> bool:
        """Usa peekaboo para capturar região do tabuleiro."""
        print("\n📸 Capturando screenshot para seleção...")

        # Captura tela completa
        with mss.mss() as sct:
            screenshot = np.array(sct.grab(sct.monitors[1]))

        # Salva temporário
        temp_path = "/tmp/chess_calibration.png"
        cv2.imwrite(temp_path, cv2.cvtColor(screenshot, cv2.COLOR_BGRA2BGR))

        print(f"Screenshot salvo em: {temp_path}")
        print("\nAgora você pode:")
        print(f"  1. Abrir a imagem: open {temp_path}")
        print("  2. Identificar as coordenadas do canto superior-esquerdo e inferior-direito")
        print("  3. Informar as coordenadas abaixo")

        return self._calibrate_manual()

    def _calibrate_manual(self) -> bool:
        """Calibração manual por coordenadas."""
        print("\n📐 Informe as coordenadas do tabuleiro:")

        try:
            x = int(input("Posição X (canto superior esquerdo): "))
            y = int(input("Posição Y (canto superior esquerdo): "))
            w = int(input("Largura do tabuleiro: "))
            h = int(input("Altura do tabuleiro: "))

            self.board_region = (x, y, w, h)
            self.calibrated = True
            self._save_calibration()

            print(f"✅ Calibrado: {self.board_region}")
            return True

        except ValueError:
            print("❌ Coordenadas inválidas!")
            return False

    def capture_board(self) -> Optional[np.ndarray]:
        """
        Captura screenshot da região do tabuleiro.

        Returns:
            Imagem do tabuleiro ou None se não calibrado
        """
        if not self.calibrated:
            print("⚠️  Tabuleiro não calibrado! Execute calibrate_interactive() primeiro.")
            return None

        x, y, w, h = self.board_region

        with mss.mss() as sct:
            monitor = {"left": x, "top": y, "width": w, "height": h}
            screenshot = np.array(sct.grab(monitor))
            # BGRA -> BGR
            self.screenshot = cv2.cvtColor(screenshot, cv2.COLOR_BGRA2BGR)
            return self.screenshot

    def detect_position_simple(self, board_img: np.ndarray) -> Optional[str]:
        """
        Detecção simplificada baseada em análise de quadrantes.
        
        MÉTODO FALLBACK - não usa ML, apenas heurísticas de cor.
        Para detecção robusta, usaríamos modelo treinado (chesscog, etc).
        
        Returns:
            FEN string ou None se não conseguir detectar
        """
        h, w = board_img.shape[:2]

        # Dividir em 64 quadrantes
        sq_h, sq_w = h // 8, w // 8

        board = chess.Board()
        board.clear_board()

        # Mapeamento de cores (simplificado)
        # Esta é uma heurística básica - na prática precisaria de ML
        print("🔍 Analisando quadrantes...")

        fen_chars = []
        for rank in range(8):  # 8-1
            rank_chars = []
            empty_count = 0

            for file in range(8):  # a-h
                x1 = file * sq_w
                y1 = (7 - rank) * sq_h  # Inverter rank
                x2 = (file + 1) * sq_w
                y2 = ((7 - rank) + 1) * sq_h

                square = board_img[y1:y2, x1:x2]

                # Detectar se há peça (análise de cor/contraste)
                piece = self._detect_piece_in_square(square)

                if piece:
                    if empty_count > 0:
                        rank_chars.append(str(empty_count))
                        empty_count = 0
                    rank_chars.append(piece)
                else:
                    empty_count += 1

            if empty_count > 0:
                rank_chars.append(str(empty_count))

            fen_chars.append(''.join(rank_chars))

        # Montar FEN (só posição, sem turno/roque/en passant)
        position_part = '/'.join(fen_chars)
        fen = f"{position_part} w - - 0 1"  # Assume brancas jogam

        return fen

    def _detect_piece_in_square(self, square_img: np.ndarray) -> Optional[str]:
        """
        Detecta peça em um quadrado baseado em heurísticas simples.
        
        FALLBACK: Retorna None (vazio) - implementação real precisaria de ML.
        Por ora, apenas detecta se há algo significativo no quadrado.
        """
        # Análise básica: verificar se há contraste significativo
        gray = cv2.cvtColor(square_img, cv2.COLOR_BGR2GRAY)

        # Verificar variância (quadrados vazios são mais uniformes)
        variance = np.var(gray)

        if variance < 800:  # Threshold empírico
            return None  # Provavelmente vazio

        # Se há variação, tentar distinguir cor
        mean_color = np.mean(square_img, axis=(0, 1))
        brightness = np.mean(gray)

        # Heurística: peças escuras vs claras
        # Isso é MUITO simplificado - na prática precisaria de template matching
        if brightness < 100:
            return 'p'  # Placeholder para peça escura
        else:
            return 'P'  # Placeholder para peça clara

    def show_board_preview(self, board_img: np.ndarray):
        """Mostra preview da captura."""
        print(f"📸 Board capturado: {board_img.shape[1]}x{board_img.shape[0]} pixels")

        # Salvar preview
        preview_path = "/tmp/chess_preview.png"
        cv2.imwrite(preview_path, board_img)
        print(f"   Preview salvo: {preview_path}")

        # Tentar abrir preview
        try:
            subprocess.run(['open', preview_path])
        except:
            pass

    def analyze_current_position(self, engine, interactive_correction: bool = True) -> tuple:
        """
        Fluxo completo: captura → detecção → análise.

        Args:
            engine: Instância de ChessEngine
            interactive_correction: Permite correção manual da FEN

        Returns:
            (fen_detected, analysis_result) ou (None, None)
        """
        # 1. Capturar
        board_img = self.capture_board()
        if board_img is None:
            return None, None

        self.show_board_preview(board_img)

        # 2. Tentar detecção automática (simplified)
        fen = self.detect_position_simple(board_img)

        # 3. Fallback: input manual ou correção
        if interactive_correction:
            print("\n" + "="*60)
            print("📋 POSIÇÃO DETECTADA (FEN)")
            print("="*60)

            if fen:
                print(f"Auto-detect: {fen}")
                use_auto = input("Usar esta FEN? (s/n): ").lower().strip() == 's'
            else:
                print("Auto-detect falhou.")
                use_auto = False

            if not use_auto:
                print("\nInforme a posição manualmente:")
                print("Opcões:")
                print("  1. Digitar FEN completo")
                print("  2. Digitar jogadas (ex: '1. e4 e5 2. Nf3')")
                choice = input("Escolha (1/2): ").strip()

                if choice == '1':
                    fen = input("FEN: ").strip()
                else:
                    moves = input("Jogadas: ").strip()
                    fen = self._moves_to_fen(moves)

        if not fen:
            print("❌ Nenhuma posição válida.")
            return None, None

        # 4. Validar FEN
        try:
            board = chess.Board(fen)
        except ValueError:
            print(f"❌ FEN inválido: {fen}")
            return None, None

        # 5. Analisar com engine
        print(f"\n🔍 Analisando posição...")
        from analysis import get_position_analysis, format_top_moves

        analysis = get_position_analysis(engine, board)

        return fen, analysis

    def _moves_to_fen(self, moves_str: str) -> str:
        """Converte string de jogadas para FEN."""
        board = chess.Board()

        # Parser simples
        import re
        tokens = moves_str.split()

        for token in tokens:
            # Ignorar números de lance
            if re.match(r'^\d+\.$', token):
                continue
            # Remover número se colado
            clean = re.sub(r'^\d+\.', '', token)

            if clean:
                try:
                    move = board.parse_san(clean)
                    board.push(move)
                except ValueError:
                    print(f"⚠️  Ignorando jogada inválida: {clean}")

        return board.fen()

    def display_analysis(self, fen: str, analysis: dict):
        """Mostra análise formatada."""
        print("\n" + "="*50)
        print("        📊 ANÁLISE DA POSIÇÃO")
        print("="*50)
        print(f"\nFEN: {fen}")
        eval_bar = analysis.get('eval_bar')
        if eval_bar:
            print(f"\n  ⬜[{eval_bar}]⬛  {analysis['eval_str']}")
        else:
            print(f"\n  📈 {analysis['eval_str']}")
        print(f"  {analysis['probs_str']}")
        print(f"\n  💡 Melhores jogadas:")
        for i, move in enumerate(analysis['top_moves']):
            if i == 0:
                print(f"     ★ {move['san']} ({move['eval_str']})")
            else:
                print(f"       {move['san']} ({move['eval_str']})")
        print("="*50)


def quick_analyze():
    """
    Função standalone para análise rápida com hotkey.
    Pode ser chamada via terminal: python chess_vision.py
    """
    print("\n" + "="*60)
    print("♔ XADREZ VISION - Análise Assistida")
    print("="*60)

    vision = ChessVision()

    # Verificar calibração
    if not vision.calibrated:
        print("\n⚠️  Primeira execução - calibração necessária")
        if not vision.calibrate_interactive():
            print("❌ Calibração cancelada.")
            return

    # Inicializar engine
    print("\n⚙️  Inicializando Stockfish...")
    try:
        from engine import ChessEngine
        engine = ChessEngine()
        print("✅ Engine pronto!")
    except Exception as e:
        print(f"❌ Erro no engine: {e}")
        return

    # Loop de análise
    print("\n" + "="*60)
    print("INSTRUÇÕES:")
    print("  [Enter]  - Capturar e analisar posição atual")
    print("  'c'      - Recalibrar")
    print("  'q'      - Sair")
    print("="*60)

    while True:
        cmd = input("\n> ").strip().lower()

        if cmd == 'q':
            break
        elif cmd == 'c':
            vision.calibrate_interactive()
            continue
        elif cmd == '' or cmd == 'a':
            # Análise!
            fen, analysis = vision.analyze_current_position(engine)
            if analysis:
                vision.display_analysis(fen, analysis)

    print("\nAté a próxima! ♔")


if __name__ == '__main__':
    quick_analyze()
