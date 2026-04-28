#!/usr/bin/env python3
"""
Modo Visão Assistida para Xadrez Terminal.

Uso:
  python vision_mode.py        # Modo interativo com hotkey simulado (Enter)
  python vision_mode.py --calibrate  # Só calibrar
  python vision_mode.py --quick      # Uma análise rápida e sai

Integração com chess.com/lichess:
1. Abra o site no navegador
2. Execute este script
3. Posicione o tabuleiro visível
4. Pressione Enter para capturar e analisar
"""

import argparse
import sys
import time

from chess_vision import ChessVision, quick_analyze


def calibrate_only():
    """Apenas executa calibração."""
    vision = ChessVision()
    print("🎯 Modo Calibração")
    if vision.calibrate_interactive():
        print("\n✅ Calibrado com sucesso!")
        print(f"Região salva: {vision.board_region}")
    else:
        print("\n❌ Calibração falhou.")
        sys.exit(1)


def quick_mode():
    """Uma análise rápida e sai."""
    vision = ChessVision()

    if not vision.calibrated:
        print("Sem calibração. Execute --calibrate primeiro.")
        sys.exit(1)

    from engine import ChessEngine
    from analysis import get_position_analysis

    engine = ChessEngine()

    # Capturar
    print("📸 Capturando...")
    board_img = vision.capture_board()
    if board_img is None:
        print("❌ Falha na captura")
        sys.exit(1)

    vision.show_board_preview(board_img)

    # Análise (com correção manual)
    fen, analysis = vision.analyze_current_position(engine)
    if analysis:
        vision.display_analysis(fen, analysis)


def main():
    parser = argparse.ArgumentParser(
        description="Análise assistida de xadrez via captura de tela"
    )
    parser.add_argument(
        '--calibrate', '-c',
        action='store_true',
        help='Apenas calibrar a região do tabuleiro'
    )
    parser.add_argument(
        '--quick', '-q',
        action='store_true',
        help='Análise rápida (única) e sair'
    )

    args = parser.parse_args()

    if args.calibrate:
        calibrate_only()
    elif args.quick:
        quick_mode()
    else:
        # Modo interativo padrão
        quick_analyze()


if __name__ == '__main__':
    main()
