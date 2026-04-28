#!/usr/bin/env python3
"""
Hotkey global para análise de xadrez.

Instalação: pip install pynput

Uso:
  python hotkey_analyzer.py

Depois, pressione Cmd+Shift+X (macOS) ou Ctrl+Shift+X (Linux/Windows)
para capturar e analisar a posição atual do tabuleiro.

Para parar: Cmd+C (macOS) ou Ctrl+C ( Linux/Windows)
"""

import sys
import threading
import time
from pathlib import Path

# Adicionar diretório do script ao path
sys.path.insert(0, str(Path(__file__).parent))

try:
    from pynput import keyboard
except ImportError:
    print("❌ pynput não instalado.")
    print("   pip install pynput")
    sys.exit(1)

from chess_vision import ChessVision
from engine import ChessEngine
from analysis import get_position_analysis


class HotkeyAnalyzer:
    """Analisador ativado por hotkey global."""

    HOTKEY = {keyboard.Key.cmd, keyboard.Key.shift, keyboard.KeyCode.from_char('x')}
    # Para Linux/Windows: trocar cmd por ctrl

    def __init__(self):
        self.vision = ChessVision()
        self.engine = None
        self.running = False
        self.current_keys = set()

    def start(self):
        """Inicia o listener de hotkey."""
        # Verificar calibração
        if not self.vision.calibrated:
            print("🔧 Primeira execução - calibrando...")
            if not self.vision.calibrate_interactive():
                print("❌ Calibração necessária para continuar.")
                return

        # Inicializar engine
        print("⚙️  Inicializando Stockfish...")
        try:
            self.engine = ChessEngine()
            print("✅ Engine pronto!")
        except Exception as e:
            print(f"❌ Erro no engine: {e}")
            return

        print("\n" + "="*60)
        print("🎯 HOTKEY ANALYZER ATIVO")
        print("="*60)
        print("Atalho: Cmd+Shift+X (macOS) ou Ctrl+Shift+X")
        print("        Captura tela → Analisa posição")
        print("\nPara sair: Cmd+C ou Ctrl+C")
        print("="*60)

        self.running = True

        # Iniciar listener
        with keyboard.Listener(
            on_press=self._on_press,
            on_release=self._on_release
        ) as listener:
            listener.join()

    def _on_press(self, key):
        """Callback para tecla pressionada."""
        self.current_keys.add(key)

        # Verificar hotkey
        if self._check_hotkey():
            self._trigger_analysis()

        # Verificar saída (Ctrl+C ou Cmd+C)
        if key == keyboard.Key.c and (
            keyboard.Key.ctrl in self.current_keys or
            keyboard.Key.cmd in self.current_keys
        ):
            print("\n👋 Encerrando...")
            return False  # Para o listener

    def _on_release(self, key):
        """Callback para tecla liberada."""
        self.current_keys.discard(key)

    def _check_hotkey(self) -> bool:
        """Verifica se o hotkey está pressionado."""
        return self.HOTKEY.issubset(self.current_keys)

    def _trigger_analysis(self):
        """Executa análise."""
        print("\n📸 Hotkey detectado! Capturando...")

        try:
            fen, analysis = self.vision.analyze_current_position(
                self.engine,
                interactive_correction=False  # Automático no hotkey
            )

            if analysis:
                self.vision.display_analysis(fen, analysis)

                # Tocar som de notificação (macOS)
                try:
                    import subprocess
                    subprocess.run(['afplay', '/System/Library/Sounds/Glass.aiff'])
                except:
                    pass
            else:
                print("⚠️  Não foi possível detectar posição.")

        except Exception as e:
            print(f"❌ Erro na análise: {e}")

        print("\n" + "-"*40)
        print("Aguardando próximo hotkey... (Cmd+Shift+X)")
        print("-"*40)


def main():
    analyzer = HotkeyAnalyzer()
    analyzer.start()


if __name__ == '__main__':
    main()
