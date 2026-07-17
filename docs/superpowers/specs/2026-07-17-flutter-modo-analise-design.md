# Modo Análise (Flutter) — Design

## Contexto

O app Flutter (`app/`) hoje só suporta partida jogador-vs-engine: `GameController.playUserMove` sempre dispara `_engineMove()` em seguida (`app/lib/features/play/game_controller.dart:45`). O app Python (`main.py:245`, `analysis_mode`) tem um segundo modo — Modo Análise — onde o usuário insere os lances das duas cores livremente, sem o engine responder automaticamente. É o recurso mais usado pelo usuário no app Python e ainda não existe no port Flutter (ver `docs/superpowers/plans/2026-07-16-flutter-fase3-estrategia.md` e memória `flutter-app-fase3`).

Este design cobre o núcleo do Modo Análise — mover os dois lados manualmente, com o painel Análise/Estratégia (Fase 3, já pronto) continuando a funcionar sobre a posição corrente — mais três recursos que o Python já oferece nesse modo: desfazer lance, virar tabuleiro, e a perspectiva "seu/adversário" do painel Estratégia acompanhando a orientação em vez de um lado fixo.

Fora de escopo: cenários (what-if, variações, Monte Carlo) e saves compatíveis com `~/.xadrez-terminal/games/` — já mapeados como Fases 4-5 separadas.

## Arquitetura

Estende o `GameState`/`GameController` existentes em vez de criar um controller paralelo: o Modo Análise passa a ser uma variação de estado do mesmo fluxo, não um sistema duplicado. Isso reaproveita `AnalysisController` e `StrategyPanel` tal como já corrigidos (commit `05c3b27`, rastreio de `evalFen`) sem duplicar `sanHistory`/lógica de posição.

### `GameState`

Dois campos novos:

- `enum GameMode { playVsEngine, analysis }` — campo `mode`, default `playVsEngine`.
- `Side orientation` — lado exibido embaixo do tabuleiro. Em `playVsEngine` sempre igual a `playerSide` (setado em `newGame`); em `analysis` é independente e alternável via `flipBoard()`.

`orientation` substitui o cálculo local que hoje existe em `board_screen.dart` (`state.playerSide == Side.black ? Side.black : Side.white`) — passa a viver no estado.

`playerSide` mantém seu sentido atual ("lado do humano vs. engine") e continua sendo lido por `AnalysisController` (gate de turno) e pela UI de status em modo `playVsEngine`. Ele deixa de ser a fonte de orientação/perspectiva — esse papel passa a `orientation`.

### `GameController`

- `newGame(playerSide, skillLevel)` — sem mudança de assinatura. Passa a setar `mode: playVsEngine, orientation: playerSide`.
- `startAnalysisMode()` — novo. Reseta para `GameState.initial().copyWith(mode: GameMode.analysis, orientation: Side.white)`. Não chama `setSkillLevel` — esse parâmetro só afeta a força do lance automático do engine, que não roda em Modo Análise (o engine continua sendo usado, só para avaliação via `AnalysisController`).
- `playUserMove(move)` — só dispara `_engineMove()` quando `state.mode == GameMode.playVsEngine`. Em `analysis`, aplica o lance e para.
- `undoMove()` — novo. Só age se `mode == analysis` e `sanHistory` não vazio. `Position` do dartchess é imutável (sem operação de "pop"), então desfazer é replay: reconstrói a posição do zero a partir de `Chess.initial`, reaplicando `sanHistory.sublist(0, length - 1)` via `parseSan`/`makeSan`. Constrói o `GameState` resultante diretamente com o construtor (não via `copyWith`), porque `copyWith` usa o padrão `campo ?? this.campo` e não consegue expressar "zerar `lastMove`" — necessário quando o histórico fica vazio após o undo.
- `flipBoard()` — novo. Alterna `orientation` via `copyWith` normal (aqui o padrão `??` não é um problema, pois o novo valor nunca é null).

### `board_screen.dart`

`_gameData` passa a retornar `PlayerSide.both` quando `state.mode == GameMode.analysis` (mesma peça que hoje já existe como fallback para engine indisponível — `playerSide = PlayerSide.both` — agora com uma segunda razão de disparo). A variável local `orientation` some; o valor vem de `state.orientation`.

### `AnalysisController`

O gate em `_maybeAnalyze` (`analysis_controller.dart:84`) — que hoje pula análise quando não é a vez do `playerSide`, para não atrasar o `bestmove` do engine durante seu turno — só se aplica quando `game.mode == GameMode.playVsEngine`. Em `analysis`, toda posição nova é analisada, nas duas cores: não existe "vez do engine" transitória, pois ele nunca joga sozinho nesse modo.

### `StrategyPanel`

Troca a leitura de `playerSide` (linha 22) por `orientation` para decidir "seu/adversário" nas seções Ameaças/Fraquezas. Em `playVsEngine` o comportamento é idêntico ao atual (`orientation == playerSide` sempre). Em `analysis`, acompanha o lado que está embaixo do tabuleiro no momento — mesmo critério usado pelo Python (`perspective_white` em `main.py:531`).

### `GameControls`

- Novo botão "Modo Análise" ao lado de "Jogar de brancas"/"Jogar de pretas", chama `controller.startAnalysisMode()`.
- Quando `state.mode == GameMode.analysis`: aparecem os botões "Desfazer" (desabilitado se `sanHistory` vazio) e "Virar tabuleiro".
- `_statusText`: em `analysis`, mostra "Vez das brancas."/"Vez das pretas." (a moldura "Sua vez"/"Vez do adversário" não se aplica quando as duas cores são manuais).

## Testes

Estende as suítes existentes (sem novos arquivos):

- `game_controller_test.dart`: `startAnalysisMode` reseta o estado corretamente; `playUserMove` não dispara `_engineMove` em `analysis`; `undoMove` reconstrói posição/`sanHistory`/`lastMove` corretamente, incluindo o caso limite de desfazer até esvaziar o histórico (`lastMove` deve virar `null`); `flipBoard` alterna `orientation`.
- `analysis_controller_test.dart`: em `analysis`, a posição é reanalisada nos dois turnos (branco e preto).
- `strategy_panel_test.dart`: "seu/adversário" troca ao alternar `orientation`.
- `board_screen_test.dart`: `PlayerSide.both` quando `mode == analysis`.
- `game_controls_test.dart`: botão "Modo Análise" aparece; "Desfazer"/"Virar tabuleiro" só aparecem em `analysis`; texto de status correto em cada modo.
