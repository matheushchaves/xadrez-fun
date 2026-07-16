# Design: Fase 3 — Estratégia (port dos 9 analisadores de `strategy.py`)

**Data:** 2026-07-16
**Status:** Aprovado

## Objetivo

Portar para Dart os 9 analisadores de `strategy.py` (`ThreatAnalyzer`,
`WeaknessAnalyzer`, `PawnStructureAnalyzer`, `CenterControlAnalyzer`,
`KingSafetyAnalyzer`, `PieceAnalyzer`, `TacticsDetector`, `PlanSuggester`,
`FullAnalyzer`), integrando-os ao app Flutter macOS como a Fase 3 do plano de
paridade descrito em
`docs/superpowers/specs/2026-07-13-flutter-macos-app-design.md`. Escopo desta
spec é só a Fase 3; cenários (Fase 4) e saves (Fase 5) continuam pendentes.

## Contexto

O app hoje (`app/`, `main` após merge da Fase 1+2) já tem:

- `lib/features/play/` — partida contra o Stockfish (`GameState`,
  `GameController`).
- `lib/features/analysis/` — avaliação, eval bar, probabilidades e top moves
  via `AnalysisController` (`Notifier` Riverpod que observa
  `gameControllerProvider` e `engineProvider`, com FEN tracking e
  reinício após crash do engine).
- `lib/features/board/` — `BoardScreen` (tabuleiro) + `GameControls`
  (barra lateral fixa de 280px: status, slider de nível, botões de nova
  partida, `AnalysisPanel`, histórico de lances).
- `lib/engine/` — cliente UCI (`ChessEngineApi`, `EngineManager`).

O código Python (`strategy.py`) permanece intacto como referência de
comportamento.

## Arquitetura

Nova pasta `lib/features/strategy/`, um arquivo por analisador (mesma
organização 1:1 do módulo Python):

```
features/strategy/
├── threat_analyzer.dart
├── weakness_analyzer.dart
├── pawn_structure_analyzer.dart
├── center_control_analyzer.dart
├── king_safety_analyzer.dart
├── piece_analyzer.dart
├── tactics_detector.dart
├── plan_suggester.dart
├── strategy_analysis.dart      # agregador puro (equivalente ao FullAnalyzer)
├── strategy_panel.dart         # UI da aba "Estratégia"
└── strategy_widgets.dart       # SectionCard/BulletList reutilizáveis
```

Cada analisador é uma função/classe **pura**: recebe `Position`
(`dartchess`) e devolve um objeto imutável com a mesma semântica de saída do
Python (listas de strings em português, scores, flags) — como dados
estruturados em vez de texto ASCII pré-formatado, para a UI renderizar com
widgets Material (ícones, cores, hierarquia) em vez de blocos de texto.

Diferença deliberada em relação ao Python: os 8 analisadores puros (tudo
exceto `PlanSuggester`) não dependem do engine — só do `Position`. Em vez de
um `Notifier` com ciclo de vida (como o `AnalysisController`, que precisou de
correções para lidar com crash/reinício do engine — ver lições na memória de
projeto), o estado estratégico é um `Provider` Riverpod simples e síncrono:

```dart
final strategyAnalysisProvider = Provider<StrategyAnalysis>((ref) {
  final position = ref.watch(gameControllerProvider).position;
  final eval = ref.watch(analysisControllerProvider).eval; // reaproveitado
  return computeStrategyAnalysis(position, eval);
});
```

Isso evita reproduzir bugs de estado assíncrono (FEN tracking, retry após
crash) para analisadores que são puros e baratos (O(64 casas) ou O(lances
legais)). Só o `PlanSuggester` consome `eval`, reaproveitando o que o
`AnalysisController` já calculou para a posição corrente — sem nova consulta
UCI.

## Componentes (mapeamento Python → Dart)

| Python | Dart | Saída |
|---|---|---|
| `ThreatAnalyzer` | `threat_analyzer.dart` | `ThreatAnalysis { whiteThreats, blackThreats: List<String> }` |
| `WeaknessAnalyzer` | `weakness_analyzer.dart` | `WeaknessAnalysis { white, black: List<String> }` |
| `PawnStructureAnalyzer` | `pawn_structure_analyzer.dart` | `PawnStructureAnalysis { white, black: PawnStructureSide }` (count, islands, passed, doubled, isolated) |
| `CenterControlAnalyzer` | `center_control_analyzer.dart` | `CenterControlAnalysis { whiteScore, blackScore, whiteAttacks, blackAttacks, whitePieces, blackPieces, dominant: Dominance }` |
| `KingSafetyAnalyzer` | `king_safety_analyzer.dart` | `KingSafetyAnalysis { white, black: KingSafety }` (square, positives, issues, safetyScore, safe) |
| `PieceAnalyzer` | `piece_analyzer.dart` | `PieceAnalysis { white, black: List<PieceReport> }` (piece, symbol, square, mobility, status, issues, active) |
| `TacticsDetector` | `tactics_detector.dart` | `TacticsAnalysis { white, black: List<String> }` (pins, forks, descobertas) |
| `PlanSuggester` | `plan_suggester.dart` | `PlanSuggestion { phase: GamePhase, evaluationText?, characteristics, plans, avoid }` |
| `FullAnalyzer` | `strategy_analysis.dart` | `StrategyAnalysis` agregando os 8 acima |

`GamePhase` e `Dominance` são enums Dart (`abertura`/`meioJogo`/`final`;
`white`/`black`/`equal`) em vez de strings soltas.

Perspectiva ("contra você" / "suas ameaças", como o parâmetro `perspective`
do Python) é resolvida na UI a partir de `game.playerSide`, não dentro do
analisador — os analisadores sempre calculam ambos os lados (branco e
preto).

## Estado e fluxo de dados

```
gameControllerProvider (Position)  ┐
                                    ├─> strategyAnalysisProvider (Provider, síncrono)
analysisControllerProvider (eval)  ┘         │
                                              v
                                       StrategyPanel (aba "Estratégia")
```

Recomputa automaticamente quando a posição muda ou quando uma nova avaliação
chega, sem tracking manual de FEN.

## UI

`GameControls` mantém fixos (fora de abas): status da partida, slider de
nível, botões "Jogar de brancas/pretas" e histórico de lances. Abaixo disso,
uma área com `TabBar`/`TabBarView` de duas abas dividindo o espaço restante:

- **Análise** — `AnalysisPanel` já existente, sem mudança de conteúdo.
- **Estratégia** — novo `StrategyPanel`, coluna rolável com uma seção por
  analisador, cada uma em um `SectionCard` (título + ícone + conteúdo):

  1. Ameaças (⚠️) — listas "Contra você" / "Suas ameaças".
  2. Fraquezas (🔍) — mesma estrutura.
  3. Estrutura de peões (♟) — contagem/ilhas por lado + chips de peões
     passados/dobrados/isolados.
  4. Controle do centro (🎯) — scores por lado + badge de dominância.
  5. Segurança do rei (👑) — chip "seguro"/"em risco" por lado + listas de
     pontos positivos (✓) e problemas (✗).
  6. Peças (♟) — lista por peça (símbolo, casa, mobilidade, status/issues).
  7. Táticas (⚔️) — pins/forks/descobertas por lado, ícones distintos.
  8. Plano estratégico (📋) — badge de fase, linha de avaliação (ou
     "indisponível" sem engine), características, plano numerado, lista do
     que evitar.

`SectionCard` e `BulletList` (`strategy_widgets.dart`) evitam repetir a
mesma estrutura de card 8 vezes.

## Tratamento de erros

- **Stockfish ausente/falhou:** os 8 analisadores puros continuam
  funcionando normalmente (só dependem do `Position`). Só a linha de
  avaliação do `PlanSuggester` degrada para "indisponível" — fase,
  características, plano e o que evitar continuam calculados a partir do
  tabuleiro.
- **Nulabilidade defensiva:** onde a API do `dartchess` retorna nullable
  (ex.: `board.kingOf(side)`), seguimos o mesmo guarda do Python
  (`if not king_sq: return {'safe': False, ...}`) sem usar `!`.
- **Performance:** todos os analisadores são O(64 casas) ou O(lances
  legais); recomputar a cada mudança de posição via `Provider` síncrono é
  barato o bastante para não precisar de debounce ou cache adicional.

## Testes

- Script Python auxiliar
  (`app/test/fixtures/generate_strategy_fixtures.py`, não roda em CI — só
  para gerar fixtures) importa os analisadores de `strategy.py`, roda
  `.analyze()` (dados brutos, não `.format()`) sobre um conjunto curado de
  FENs (abertura, meio-jogo com pin/fork, rei exposto, final com peão
  passado, etc.) e grava um JSON por analisador em `app/test/fixtures/`.
- Testes unitários Dart carregam esses JSONs e comparam campo a campo com a
  saída do port (adaptando chaves para camelCase).
- Teste unitário do agregador `computeStrategyAnalysis` (combinação dos 8 +
  `PlanSuggestion` com eval mockado e com eval nulo).
- Teste de widget para `StrategyPanel` (renderização básica das seções e
  troca de aba Análise/Estratégia).

## Fora de escopo

- Cenários (árvore de variações, what-if, Monte Carlo) — Fase 4.
- Saves — Fase 5.
