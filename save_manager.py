"""Gerenciador de saves para múltiplas partidas com nomes."""

import json
import uuid
from datetime import datetime
from pathlib import Path
from typing import Optional
import chess


class SaveManager:
    SAVE_DIR = Path.home() / ".xadrez-terminal"
    GAMES_DIR = Path.home() / ".xadrez-terminal" / "games"

    def __init__(self):
        self._ensure_dirs()

    def _ensure_dirs(self):
        self.SAVE_DIR.mkdir(parents=True, exist_ok=True)
        self.GAMES_DIR.mkdir(parents=True, exist_ok=True)

    @staticmethod
    def new_id() -> str:
        return uuid.uuid4().hex[:12]

    def list_games(self) -> list[dict]:
        games = []
        for f in sorted(self.GAMES_DIR.glob("*.json"), key=lambda x: x.stat().st_mtime, reverse=True):
            try:
                with open(f, 'r', encoding='utf-8') as fp:
                    data = json.load(fp)
                try:
                    ts = datetime.fromisoformat(data['timestamp']).strftime("%d/%m %H:%M")
                except (KeyError, ValueError):
                    ts = '?'
                mode_name = "Análise" if data.get('mode') == 'analysis' else "vs Stockfish"
                games.append({
                    'id': f.stem,
                    'name': data.get('name', f.stem),
                    'mode': data.get('mode', 'analysis'),
                    'mode_name': mode_name,
                    'move_count': len(data.get('move_history', [])),
                    'timestamp': ts,
                })
            except (json.JSONDecodeError, IOError):
                continue
        return games

    def save_analysis(self, game_id: str, name: str, move_history: list,
                      perspective_white: bool, var_tree_data: Optional[dict] = None):
        self._write(game_id, {
            "id": game_id,
            "name": name,
            "mode": "analysis",
            "timestamp": datetime.now().isoformat(),
            "move_history": move_history,
            "perspective_white": perspective_white,
            "variation_tree": var_tree_data or {},
        })

    def save_game(self, game_id: str, name: str, move_history: list,
                  player_color: chess.Color, skill_level: int):
        self._write(game_id, {
            "id": game_id,
            "name": name,
            "mode": "play",
            "timestamp": datetime.now().isoformat(),
            "move_history": move_history,
            "player_color": "white" if player_color == chess.WHITE else "black",
            "skill_level": skill_level,
        })

    def _write(self, game_id: str, data: dict):
        self._ensure_dirs()
        with open(self.GAMES_DIR / f"{game_id}.json", 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

    def load(self, game_id: str) -> Optional[dict]:
        path = self.GAMES_DIR / f"{game_id}.json"
        if not path.exists():
            return None
        try:
            with open(path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            return None

    def delete(self, game_id: str):
        path = self.GAMES_DIR / f"{game_id}.json"
        if path.exists():
            path.unlink()

    def rename(self, game_id: str, new_name: str):
        data = self.load(game_id)
        if data is not None:
            data['name'] = new_name
            self._write(game_id, data)

    def migrate_autosave(self) -> Optional[str]:
        """Migra autosave.json legado para o novo sistema."""
        old_path = self.SAVE_DIR / "autosave.json"
        if not old_path.exists():
            return None
        try:
            with open(old_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            game_id = self.new_id()
            data['id'] = game_id
            data.setdefault('name', 'Partida importada')
            self._write(game_id, data)
            old_path.unlink()
            return game_id
        except (json.JSONDecodeError, IOError):
            try:
                old_path.unlink()
            except OSError:
                pass
            return None
