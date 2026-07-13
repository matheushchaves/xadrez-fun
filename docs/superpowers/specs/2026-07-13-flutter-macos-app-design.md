# Design: xadrez-fun desktop (Flutter macOS)

**Data:** 2026-07-13
**Status:** Aprovado

## Objetivo

Substituir a interface web Flask por um aplicativo desktop macOS em Flutter que
funcione sem nenhum backend: o usuário abre o app e joga/analisa. Paridade
completa de funcionalidades com o app Python atual.

## Contexto

O projeto hoje é um assistente de xadrez em Python:

- `engine.py` — wrapper do Stockfish (localiza binário, UCI via python-chess)
- `analysis.py` — avaliação, probabilidades de vitória, top moves
- `strategy.py` — 9 analisadores: ThreatAnalyzer, WeaknessAnalyzer,
  PawnStructureAnalyzer, CenterControlAnalyzer, KingSafetyAnalyzer,
  PieceAnalyzer, TacticsDetector, PlanSuggester, FullAnalyzer
- `scenarios.py` — VariationTree, WhatIfAnalyzer, MonteCarloSimulator
- `save_manager.py` — saves JSON em `~/.xadrez-terminal/games/`
- `web.py` + `templates/index.html` — interface web Flask (será substituída)

O código Python permanece intacto no repositório.

## Decisão de arquitetura

**Port completo para Dart.** Alternativas descartadas:

- *Python embutido como processo auxiliar*: continua sendo um backend
  disfarçado; complica distribuição.
- *Flutter web + Stockfish WASM*: usuário prefere app desktop; WASM é mais
  lento e ainda exige servir arquivos estáticos.

## Estrutura

Nova pasta `app/` no repositório (project name Dart: `xadrez_fun`):

```
app/
└── lib/
    ├── main.dart
    ├── engine/           # cliente UCI do Stockfish (Process + stdin/stdout)
    ├── core/             # regras de xadrez (pacote Dart) e modelos de domínio
    └── features/
        ├── board/        # tabuleiro interativo, perspectiva branca/preta
        ├── play/         # modo vs Stockfish com níveis de habilidade
        ├── analysis/     # avaliação, eval bar, top moves + 9 analisadores
        ├── scenarios/    # árvore de variações, what-if, Monte Carlo
        └── saves/        # salvar/carregar partidas
```

## Componentes

### Engine (lib/engine/)

- Localiza o binário do Stockfish com a mesma lógica de
  `find_stockfish_path()` (PATH, caminhos do Homebrew).
- Se não encontrar, a UI mostra instrução: `brew install stockfish`.
- Comunicação UCI via `Process.start` (stdin/stdout), com API assíncrona:
  avaliação, melhores lances (MultiPV), lance do engine com skill level 0–20.

### Regras e tabuleiro (lib/core/, lib/features/board/)

- Regras de xadrez (movimentos legais, FEN, SAN, detecção de fim de jogo) via
  `dartchess` (pacote mantido pela lichess).
- Widget do tabuleiro: `chessground` (também da lichess, usado no app móvel
  oficial) — drag-and-drop, destaques de lances e inversão de perspectiva
  prontos. Destaques extras (ameaças/fraquezas) via camada de overlay própria.
  Se o `chessground` não atender no desktop, fallback é tabuleiro custom.

### Analisadores (lib/features/analysis/)

Port 1:1 dos 9 analisadores de `strategy.py`, um arquivo Dart por analisador,
mesma semântica de saída (listas de itens com descrição e severidade). O
comportamento do código Python é a referência.

### Cenários (lib/features/scenarios/)

Port de `VariationTree` (linha principal + ramos), `WhatIfAnalyzer` (comparação
de lances candidatos via engine) e `MonteCarloSimulator`.

### Saves (lib/features/saves/)

Mesmo formato JSON e mesma pasta `~/.xadrez-terminal/games/` do
`save_manager.py`: partidas salvas no app Python abrem no app Flutter e
vice-versa. Campos: `id`, `name`, `mode` (`analysis`/`play`),
`timestamp` ISO, `move_history`, e específicos do modo
(`perspective_white`/`variation_tree` ou `player_color`/`skill_level`).
Auto-save após cada lance, como hoje.

### Estado

Riverpod. O estado central do jogo (posição, histórico, modo, análises) é
compartilhado entre tabuleiro, painéis de análise e cenários.

## Tratamento de erros

- Stockfish ausente: tela de instrução, app segue utilizável em modo análise
  estática (sem avaliação de engine).
- Stockfish trava/morre: reinicialização automática do processo, aviso na UI.
- Saves corrompidos: ignorados na listagem (como `list_games` faz hoje).

## Fases de implementação

1. **Jogável:** scaffold Flutter macOS + tabuleiro interativo + jogar contra o
   Stockfish com níveis de habilidade.
2. **Análise:** avaliação, probabilidades de vitória, eval bar, top moves.
3. **Estratégia:** port dos 9 analisadores de `strategy.py`.
4. **Cenários:** árvore de variações, what-if, Monte Carlo.
5. **Saves:** salvar/carregar/renomear/excluir, compatível com os saves
   existentes.

Cada fase termina com o app compilando e utilizável.

## Testes

- Testes unitários para cada analisador portado, validando contra resultados
  do código Python em posições FEN conhecidas.
- Testes unitários do parser/serializador de saves (round-trip com arquivos
  gerados pelo Python).
- Testes de widget para o tabuleiro (lances legais, destaques, perspectiva).
- Cliente UCI testado com um fake de processo.
