# Modo Análise (Flutter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar ao app Flutter (`app/`) o Modo Análise — o usuário move as duas cores livremente, sem o engine responder automaticamente — com desfazer lance, virar tabuleiro, e o painel Estratégia acompanhando a orientação do tabuleiro em vez de um lado fixo.

**Architecture:** Estende o `GameState`/`GameController` existentes (não cria um controller paralelo) com um campo `GameMode` e um campo `orientation`. `AnalysisController` e `StrategyPanel` passam a reagir a esses campos em vez de assumir sempre partida vs. engine. `GameControls` ganha um terceiro botão de entrada no modo e, condicionalmente, os controles de desfazer/virar.

**Tech Stack:** Flutter, `flutter_riverpod` (Notifier/copyWith), `dartchess` (Position/Move/Side), `chessground` (Chessboard/GameData/PlayerSide), `flutter_test`.

## Global Constraints

- Todo código novo em português nos comentários e nas strings de UI, como o restante do projeto.
- Seguir os padrões já em uso no arquivo: imports relativos entre features (`../play/game_controller.dart`), estado imutável com `copyWith`, `Notifier`/`NotifierProvider` do Riverpod.
- `dart format` e `dart analyze` devem ficar limpos após cada task (hook local já roda isso em edição; a Task 11 roda a verificação final).
- Cada task termina com `flutter test` das suítes tocadas, passando antes do commit.
- Sem novos arquivos de teste — todas as suítes já existem (`test/features/play/game_controller_test.dart`, `test/features/analysis/analysis_controller_test.dart`, `test/features/board/board_screen_test.dart`, `test/features/strategy/strategy_panel_test.dart`, `test/features/board/game_controls_test.dart`); as tasks apenas adicionam casos a elas.
- Fora de escopo (confirmado no design): cenários (what-if, variações, Monte Carlo) e saves — Fases 4-5 separadas.

---

### Task 1: `GameState` — campos `mode` e `orientation`

**Files:**
- Modify: `app/lib/features/play/game_state.dart`
- Test: `app/test/features/play/game_controller_test.dart`

**Interfaces:**
- Produces: `enum GameMode { playVsEngine, analysis }`; `GameState.mode` (`GameMode`, default `GameMode.playVsEngine`); `GameState.orientation` (`Side`, default `Side.white`); `GameState.copyWith({..., GameMode? mode, Side? orientation})`.

- [ ] **Step 1: Escrever o teste que falha**

Adicionar a `app/test/features/play/game_controller_test.dart`, dentro do `main()`, logo após o teste `'estado inicial: posição inicial, sem histórico'`:

```dart
  test('estado inicial: modo playVsEngine, orientação brancas', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final state = container.read(gameControllerProvider);
    expect(state.mode, GameMode.playVsEngine);
    expect(state.orientation, Side.white);
  });
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: FAIL — `GameMode` e/ou `state.mode`/`state.orientation` não existem (erro de compilação).

- [ ] **Step 3: Implementar `GameMode` e `orientation` em `GameState`**

Substituir o conteúdo de `app/lib/features/play/game_state.dart`:

```dart
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// Modo da partida: contra o engine (auto-play) ou Modo Análise (o usuário
/// move as duas cores, sem resposta automática).
enum GameMode { playVsEngine, analysis }

/// Estado imutável de uma partida.
@immutable
class GameState {
  const GameState({
    required this.position,
    required this.sanHistory,
    required this.playerSide,
    required this.skillLevel,
    required this.mode,
    required this.orientation,
    this.lastMove,
    this.engineThinking = false,
  });

  const GameState.initial()
    : this(
        position: Chess.initial,
        sanHistory: const [],
        playerSide: Side.white,
        skillLevel: 10,
        mode: GameMode.playVsEngine,
        orientation: Side.white,
      );

  final Position position;
  final List<String> sanHistory;
  final Side playerSide;
  final int skillLevel;
  final GameMode mode;

  /// Lado exibido embaixo do tabuleiro. Em [GameMode.playVsEngine] segue
  /// [playerSide]; em [GameMode.analysis] é independente e alternável via
  /// `GameController.flipBoard()`. Também usado pelo painel Estratégia para
  /// decidir a perspectiva "seu/adversário".
  final Side orientation;
  final Move? lastMove;
  final bool engineThinking;

  bool get isGameOver => position.isGameOver;

  /// Texto do resultado quando a partida terminou, senão null.
  String? get resultText {
    if (position.isCheckmate) {
      return position.turn == Side.white
          ? 'Xeque-mate! Pretas vencem.'
          : 'Xeque-mate! Brancas vencem.';
    }
    if (position.isStalemate) return 'Empate por afogamento.';
    if (position.isInsufficientMaterial) {
      return 'Empate por material insuficiente.';
    }
    if (position.isGameOver) return 'Partida encerrada.';
    return null;
  }

  GameState copyWith({
    Position? position,
    List<String>? sanHistory,
    Side? playerSide,
    int? skillLevel,
    GameMode? mode,
    Side? orientation,
    Move? lastMove,
    bool? engineThinking,
  }) {
    return GameState(
      position: position ?? this.position,
      sanHistory: sanHistory ?? this.sanHistory,
      playerSide: playerSide ?? this.playerSide,
      skillLevel: skillLevel ?? this.skillLevel,
      mode: mode ?? this.mode,
      orientation: orientation ?? this.orientation,
      lastMove: lastMove ?? this.lastMove,
      engineThinking: engineThinking ?? this.engineThinking,
    );
  }
}
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: PASS (todos os testes do arquivo, incluindo o novo).

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/play/game_state.dart test/features/play/game_controller_test.dart
git commit -m "feat: adiciona GameMode e orientation ao GameState"
```

---

### Task 2: `GameController` — `newGame` seta orientação; `startAnalysisMode()`

**Files:**
- Modify: `app/lib/features/play/game_controller.dart:30-43`
- Test: `app/test/features/play/game_controller_test.dart`

**Interfaces:**
- Consumes: `GameState.copyWith({mode, orientation, ...})` (Task 1).
- Produces: `GameController.startAnalysisMode()` (`void`) — reseta para `GameMode.analysis`, `orientation: Side.white`, histórico vazio.

- [ ] **Step 1: Escrever os testes que falham**

Adicionar a `app/test/features/play/game_controller_test.dart`, após o teste `'newGame jogando de pretas: engine abre a partida'`:

```dart
  test('newGame define a orientação igual ao playerSide', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);

    await controller.newGame(playerSide: Side.black, skillLevel: 5);

    final state = container.read(gameControllerProvider);
    expect(state.orientation, Side.black);
    expect(state.mode, GameMode.playVsEngine);
  });

  test(
    'startAnalysisMode reinicia em Modo Análise, orientação brancas',
    () async {
      final engine = FakeEngine('e7e5');
      final container = makeContainer(engine);
      final controller = container.read(gameControllerProvider.notifier);

      await controller.playUserMove(Move.parse('e2e4')!);
      controller.startAnalysisMode();

      final state = container.read(gameControllerProvider);
      expect(state.mode, GameMode.analysis);
      expect(state.orientation, Side.white);
      expect(state.sanHistory, isEmpty);
      expect(state.position.fen, Chess.initial.fen);
    },
  );
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: FAIL — `startAnalysisMode` não existe; `orientation` ainda não é setada em `newGame`.

- [ ] **Step 3: Implementar**

Em `app/lib/features/play/game_controller.dart`, substituir:

```dart
  Future<void> newGame({
    required Side playerSide,
    required int skillLevel,
  }) async {
    state = GameState.initial().copyWith(
      playerSide: playerSide,
      skillLevel: skillLevel,
    );
    final engine = await ref.read(engineProvider.future);
    await engine?.setSkillLevel(skillLevel);
    if (playerSide == Side.black) {
      await _engineMove();
    }
  }
```

por:

```dart
  Future<void> newGame({
    required Side playerSide,
    required int skillLevel,
  }) async {
    state = GameState.initial().copyWith(
      playerSide: playerSide,
      skillLevel: skillLevel,
      mode: GameMode.playVsEngine,
      orientation: playerSide,
    );
    final engine = await ref.read(engineProvider.future);
    await engine?.setSkillLevel(skillLevel);
    if (playerSide == Side.black) {
      await _engineMove();
    }
  }

  /// Inicia uma partida em Modo Análise: o usuário move as duas cores
  /// livremente, sem resposta automática do engine. O engine continua
  /// disponível para avaliação (`AnalysisController`), só não joga sozinho.
  void startAnalysisMode() {
    state = GameState.initial().copyWith(
      mode: GameMode.analysis,
      orientation: Side.white,
    );
  }
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/play/game_controller.dart test/features/play/game_controller_test.dart
git commit -m "feat: adiciona GameController.startAnalysisMode"
```

---

### Task 3: `playUserMove` não dispara o engine em Modo Análise

**Files:**
- Modify: `app/lib/features/play/game_controller.dart` (método `playUserMove`)
- Test: `app/test/features/play/game_controller_test.dart`

**Interfaces:**
- Consumes: `GameState.mode` (Task 1), `GameController.startAnalysisMode()` (Task 2).

- [ ] **Step 1: Escrever o teste que falha**

Adicionar a `app/test/features/play/game_controller_test.dart`, após o teste `'startAnalysisMode reinicia em Modo Análise, orientação brancas'`:

```dart
  test('em Modo Análise, playUserMove não dispara o engine', () async {
    final engine = FakeEngine('e7e5');
    final container = makeContainer(engine);
    final controller = container.read(gameControllerProvider.notifier);
    controller.startAnalysisMode();

    await controller.playUserMove(Move.parse('e2e4')!);
    await controller.playUserMove(Move.parse('e7e5')!);

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, ['e4', 'e5']);
    expect(state.position.turn, Side.white);
    expect(engine.fensAsked, isEmpty);
  });
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: FAIL — `engine.fensAsked` não está vazio (o engine ainda responde automaticamente após o segundo lance).

- [ ] **Step 3: Implementar**

Em `app/lib/features/play/game_controller.dart`, substituir:

```dart
  Future<void> playUserMove(Move move) async {
    if (state.engineThinking || state.isGameOver) return;
    if (!state.position.isLegal(move)) return;
    _applyMove(move);
    if (!state.isGameOver) {
      await _engineMove();
    }
  }
```

por:

```dart
  Future<void> playUserMove(Move move) async {
    if (state.engineThinking || state.isGameOver) return;
    if (!state.position.isLegal(move)) return;
    _applyMove(move);
    if (state.mode == GameMode.playVsEngine && !state.isGameOver) {
      await _engineMove();
    }
  }
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/play/game_controller.dart test/features/play/game_controller_test.dart
git commit -m "feat: joga vs. engine só chama _engineMove fora do Modo Análise"
```

---

### Task 4: `GameController.undoMove()`

**Files:**
- Modify: `app/lib/features/play/game_controller.dart`
- Test: `app/test/features/play/game_controller_test.dart`

**Interfaces:**
- Consumes: `Position.parseSan(String)` → `Move?`, `Position.makeSan(Move)` → `(Position, String)` (dartchess), `Chess.initial` (tipo `Chess`, subtipo de `Position`).
- Produces: `GameController.undoMove()` (`void`) — no-op fora de `GameMode.analysis` ou com `sanHistory` vazio; caso contrário remove o último lance e reconstrói a posição.

- [ ] **Step 1: Escrever os testes que falham**

Adicionar a `app/test/features/play/game_controller_test.dart`, após o teste `'em Modo Análise, playUserMove não dispara o engine'`:

```dart
  test('undoMove desfaz o último lance em Modo Análise', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    controller.startAnalysisMode();
    await controller.playUserMove(Move.parse('e2e4')!);
    await controller.playUserMove(Move.parse('e7e5')!);

    controller.undoMove();

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, ['e4']);
    expect(state.position.turn, Side.black);
    expect(state.lastMove, Move.parse('e2e4'));
  });

  test('undoMove até esvaziar o histórico zera lastMove', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    controller.startAnalysisMode();
    await controller.playUserMove(Move.parse('e2e4')!);

    controller.undoMove();

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, isEmpty);
    expect(state.position.fen, Chess.initial.fen);
    expect(state.lastMove, isNull);
  });

  test('undoMove não faz nada fora do Modo Análise', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    await controller.playUserMove(Move.parse('e2e4')!);
    final before = container.read(gameControllerProvider);

    controller.undoMove();

    expect(container.read(gameControllerProvider), same(before));
  });

  test('undoMove com histórico vazio não faz nada', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    controller.startAnalysisMode();
    final before = container.read(gameControllerProvider);

    controller.undoMove();

    expect(container.read(gameControllerProvider), same(before));
  });
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: FAIL — `undoMove` não existe (erro de compilação).

- [ ] **Step 3: Implementar**

Em `app/lib/features/play/game_controller.dart`, adicionar após `startAnalysisMode()`:

```dart
  /// Desfaz o último lance (Modo Análise). `Position` do dartchess é
  /// imutável — sem operação de "pop" —, então desfazer é um replay: refaz o
  /// tabuleiro do zero a partir de `Chess.initial` reaplicando o histórico
  /// sem o último lance.
  void undoMove() {
    if (state.mode != GameMode.analysis || state.sanHistory.isEmpty) return;
    final newHistory = state.sanHistory.sublist(
      0,
      state.sanHistory.length - 1,
    );
    Position position = Chess.initial;
    Move? lastMove;
    for (final san in newHistory) {
      final move = position.parseSan(san);
      if (move == null) return;
      final (next, _) = position.makeSan(move);
      lastMove = move;
      position = next;
    }
    // Construído diretamente (não via copyWith): copyWith usa o padrão
    // `campo ?? this.campo`, que não consegue expressar "zerar lastMove"
    // quando o histórico esvazia.
    state = GameState(
      position: position,
      sanHistory: newHistory,
      playerSide: state.playerSide,
      skillLevel: state.skillLevel,
      mode: state.mode,
      orientation: state.orientation,
      lastMove: lastMove,
      engineThinking: state.engineThinking,
    );
  }
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/play/game_controller.dart test/features/play/game_controller_test.dart
git commit -m "feat: adiciona GameController.undoMove"
```

---

### Task 5: `GameController.flipBoard()`

**Files:**
- Modify: `app/lib/features/play/game_controller.dart`
- Test: `app/test/features/play/game_controller_test.dart`

**Interfaces:**
- Produces: `GameController.flipBoard()` (`void`) — alterna `orientation` entre `Side.white`/`Side.black`.

- [ ] **Step 1: Escrever o teste que falha**

Adicionar a `app/test/features/play/game_controller_test.dart`, após o bloco de testes de `undoMove`:

```dart
  test('flipBoard alterna a orientação', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    controller.startAnalysisMode();
    expect(container.read(gameControllerProvider).orientation, Side.white);

    controller.flipBoard();
    expect(container.read(gameControllerProvider).orientation, Side.black);

    controller.flipBoard();
    expect(container.read(gameControllerProvider).orientation, Side.white);
  });
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: FAIL — `flipBoard` não existe (erro de compilação).

- [ ] **Step 3: Implementar**

Em `app/lib/features/play/game_controller.dart`, adicionar após `undoMove()`:

```dart
  /// Alterna o lado exibido embaixo do tabuleiro (Modo Análise).
  void flipBoard() {
    state = state.copyWith(
      orientation: state.orientation == Side.white ? Side.black : Side.white,
    );
  }
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: PASS (arquivo inteiro)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/play/game_controller.dart test/features/play/game_controller_test.dart
git commit -m "feat: adiciona GameController.flipBoard"
```

---

### Task 6: `AnalysisController` — analisa os dois turnos em Modo Análise

**Files:**
- Modify: `app/lib/features/analysis/analysis_controller.dart:79-89`
- Test: `app/test/features/analysis/analysis_controller_test.dart`

**Interfaces:**
- Consumes: `GameState.mode` (Task 1), `GameController.startAnalysisMode()` (Task 2).

- [ ] **Step 1: Escrever o teste que falha**

Adicionar a `app/test/features/analysis/analysis_controller_test.dart`, após o teste `'não repete análise da mesma posição'`:

```dart
  test(
    'Modo Análise: analisa a posição após o lance das pretas também',
    () async {
      final engine = FakeAnalysisEngine();
      final container = makeContainer(engine);
      container.read(analysisControllerProvider);
      await settle(container);

      final game = container.read(gameControllerProvider.notifier);
      game.startAnalysisMode();
      await settle(container);
      engine.evaluatedFens.clear();

      await game.playUserMove(Move.parse('e2e4')!);
      await settle(container);
      final fenAfterWhite = container.read(gameControllerProvider).position.fen;

      await game.playUserMove(Move.parse('e7e5')!);
      await settle(container);
      final fenAfterBlack = container.read(gameControllerProvider).position.fen;

      // Antes desta mudança, o gate `turn != playerSide` (playerSide fica
      // fixo em brancas) pulava a análise logo após o lance das brancas,
      // porque aí é a vez das pretas — e em Modo Análise não existe "vez do
      // engine" para justificar esse gate.
      expect(engine.evaluatedFens, [fenAfterWhite, fenAfterBlack]);
    },
  );
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd app && flutter test test/features/analysis/analysis_controller_test.dart`
Expected: FAIL — `engine.evaluatedFens` não contém `fenAfterWhite` (posição de vez das pretas é pulada pelo gate atual).

- [ ] **Step 3: Implementar**

Em `app/lib/features/analysis/analysis_controller.dart`, substituir:

```dart
  void _maybeAnalyze(GameState game) {
    if (game.engineThinking) return;
    // Só analisa posições que o jogador enfrenta (ou o fim da partida):
    // durante a vez do engine a posição é transitória e a consulta
    // atrasaria o bestmove (comandos UCI são serializados).
    if (!game.isGameOver && game.position.turn != game.playerSide) return;
    final fen = game.position.fen;
    if (fen == _lastAnalyzedFen) return;
    _lastAnalyzedFen = fen;
    _inFlight = _analyze(fen, game.position);
  }
```

por:

```dart
  void _maybeAnalyze(GameState game) {
    if (game.engineThinking) return;
    // Só analisa posições que o jogador enfrenta (ou o fim da partida):
    // durante a vez do engine a posição é transitória e a consulta
    // atrasaria o bestmove (comandos UCI são serializados). Em Modo Análise
    // esse gate não se aplica — o engine nunca joga sozinho, então não há
    // "vez do engine" transitória; toda posição nova é analisada.
    if (game.mode == GameMode.playVsEngine &&
        !game.isGameOver &&
        game.position.turn != game.playerSide) {
      return;
    }
    final fen = game.position.fen;
    if (fen == _lastAnalyzedFen) return;
    _lastAnalyzedFen = fen;
    _inFlight = _analyze(fen, game.position);
  }
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd app && flutter test test/features/analysis/analysis_controller_test.dart`
Expected: PASS (arquivo inteiro)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/analysis/analysis_controller.dart test/features/analysis/analysis_controller_test.dart
git commit -m "feat: AnalysisController analisa os dois turnos em Modo Análise"
```

---

### Task 7: `BoardScreen` — tabuleiro livre e orientação vêm do estado

**Files:**
- Modify: `app/lib/features/board/board_screen.dart`
- Test: `app/test/features/board/board_screen_test.dart`

**Interfaces:**
- Consumes: `GameState.mode`, `GameState.orientation` (Task 1), `GameController.startAnalysisMode()` (Task 2), `GameController.flipBoard()` (Task 5).

- [ ] **Step 1: Escrever os testes que falham**

Em `app/test/features/board/board_screen_test.dart`, substituir o bloco de imports do topo:

```dart
import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/board/board_screen.dart';
```

por:

```dart
import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/board/board_screen.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';
```

Depois, adicionar dentro do `main()`, após o teste `'engine reiniciado mostra aviso e mantém o jogo'`:

```dart
  testWidgets('Modo Análise: tabuleiro fica livre para as duas cores', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp(FakeEngine()));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(BoardScreen));
    ProviderScope.containerOf(context, listen: false)
        .read(gameControllerProvider.notifier)
        .startAnalysisMode();
    await tester.pumpAndSettle();

    final chessboard = tester.widget<Chessboard>(find.byType(Chessboard));
    expect(chessboard.controller.game.playerSide, PlayerSide.both);
  });

  testWidgets(
    'Modo Análise: virar tabuleiro muda a orientação do Chessboard',
    (tester) async {
      await tester.pumpWidget(makeApp(FakeEngine()));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(BoardScreen));
      final controller = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(gameControllerProvider.notifier);
      controller.startAnalysisMode();
      controller.flipBoard();
      await tester.pumpAndSettle();

      final chessboard = tester.widget<Chessboard>(find.byType(Chessboard));
      expect(chessboard.orientation, Side.black);
    },
  );
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `cd app && flutter test test/features/board/board_screen_test.dart`
Expected: FAIL — `gameControllerProvider.notifier` não tem `startAnalysisMode`/`flipBoard` visível no comportamento esperado (o `playerSide` continua `PlayerSide.white`, não `both`; a orientação não muda).

- [ ] **Step 3: Implementar**

Em `app/lib/features/board/board_screen.dart`, substituir `_gameData`:

```dart
  GameData _gameData(GameState state, bool engineAvailable) {
    final PlayerSide playerSide;
    if (state.isGameOver || state.engineThinking) {
      playerSide = PlayerSide.none;
    } else if (!engineAvailable) {
      playerSide = PlayerSide.both;
    } else {
      playerSide = state.playerSide == Side.white
          ? PlayerSide.white
          : PlayerSide.black;
    }
    return GameData(
      fen: state.position.fen,
      lastMove: state.lastMove,
      playerSide: playerSide,
      sideToMove: state.position.turn,
      kingSquareInCheck: state.position.isCheck
          ? state.position.board.kingOf(state.position.turn)
          : null,
      validMoves: makeLegalMoves(state.position),
    );
  }
```

por:

```dart
  GameData _gameData(GameState state, bool engineAvailable) {
    final PlayerSide playerSide;
    if (state.isGameOver || state.engineThinking) {
      playerSide = PlayerSide.none;
    } else if (state.mode == GameMode.analysis || !engineAvailable) {
      playerSide = PlayerSide.both;
    } else {
      playerSide = state.playerSide == Side.white
          ? PlayerSide.white
          : PlayerSide.black;
    }
    return GameData(
      fen: state.position.fen,
      lastMove: state.lastMove,
      playerSide: playerSide,
      sideToMove: state.position.turn,
      kingSquareInCheck: state.position.isCheck
          ? state.position.board.kingOf(state.position.turn)
          : null,
      validMoves: makeLegalMoves(state.position),
    );
  }
```

E, no método `build`, substituir:

```dart
    final state = ref.watch(gameControllerProvider);
    final orientation = state.playerSide == Side.black
        ? Side.black
        : Side.white;
```

por:

```dart
    final state = ref.watch(gameControllerProvider);
    final orientation = state.orientation;
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `cd app && flutter test test/features/board/board_screen_test.dart`
Expected: PASS (arquivo inteiro)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/board/board_screen.dart test/features/board/board_screen_test.dart
git commit -m "feat: BoardScreen usa mode/orientation do GameState"
```

---

### Task 8: `StrategyPanel` — perspectiva segue `orientation`

**Files:**
- Modify: `app/lib/features/strategy/strategy_panel.dart:20-29`
- Test: `app/test/features/strategy/strategy_panel_test.dart`

**Interfaces:**
- Consumes: `GameState.orientation` (Task 1), `GameController.flipBoard()` (Task 5).

- [ ] **Step 1: Escrever o teste que falha**

Em `app/test/features/strategy/strategy_panel_test.dart`, substituir:

```dart
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/strategy/center_control_analyzer.dart';
```

por (novo import alfabeticamente antes de `features/strategy/`):

```dart
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';
import 'package:xadrez_fun/features/strategy/center_control_analyzer.dart';
```

Depois, substituir a função `_makePanel` e o `main()` por:

```dart
ProviderContainer _makeContainer() {
  return ProviderContainer(
    overrides: [
      strategyAnalysisProvider.overrideWithValue(_fakeAnalysis),
      // StrategyPanel lê gameControllerProvider (perspectiva do jogador); o
      // GameController real ouve engineProvider no build() — sem
      // sobrescrever, o teste tentaria resolver um engine de verdade.
      engineProvider.overrideWith((ref) => Future.value(null)),
    ],
  );
}

Widget _makePanel(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 280, height: 800, child: StrategyPanel()),
      ),
    ),
  );
}

void main() {
  testWidgets('mostra as 8 seções com o conteúdo do provider', (tester) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_makePanel(container));
    await tester.pumpAndSettle();

    expect(find.textContaining('Plano estratégico'), findsOneWidget);
    expect(find.textContaining('Ameaças'), findsOneWidget);
    expect(find.textContaining('Táticas'), findsOneWidget);
    expect(find.textContaining('Controle do centro'), findsOneWidget);
    expect(find.textContaining('Segurança do rei'), findsOneWidget);
    expect(find.textContaining('Peças'), findsOneWidget);
    expect(find.textContaining('Estrutura de peões'), findsOneWidget);
    // Usa o texto completo do cabeçalho (com o ícone) em vez de apenas
    // 'Fraquezas': a seção também contém o rótulo "Fraquezas do oponente",
    // que colidiria com uma checagem por substring simples.
    expect(find.textContaining('🔍 Fraquezas'), findsOneWidget);

    expect(find.textContaining('Cavalo em e6 não defendido!'), findsOneWidget);
    expect(find.textContaining('Rei ainda não rocou'), findsOneWidget);
    expect(find.textContaining('+0.31 (Posição equilibrada)'), findsOneWidget);
  });

  testWidgets('perspectiva "seu/adversário" acompanha a orientação', (
    tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_makePanel(container));
    await tester.pumpAndSettle();

    // Orientação inicial (brancas): a ameaça das pretas ("Cavalo em e6...")
    // é "contra você" — aparece ANTES do rótulo "Suas ameaças" na coluna.
    final threatY = tester
        .getTopLeft(find.text('Cavalo em e6 não defendido!'))
        .dy;
    final yoursLabelY = tester.getTopLeft(find.text('Suas ameaças')).dy;
    expect(threatY, lessThan(yoursLabelY));

    container.read(gameControllerProvider.notifier).flipBoard();
    await tester.pumpAndSettle();

    // Orientação pretas: a mesma ameaça agora é seu ataque — aparece DEPOIS
    // do rótulo "Suas ameaças".
    final threatY2 = tester
        .getTopLeft(find.text('Cavalo em e6 não defendido!'))
        .dy;
    final yoursLabelY2 = tester.getTopLeft(find.text('Suas ameaças')).dy;
    expect(threatY2, greaterThan(yoursLabelY2));
  });
}
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `cd app && flutter test test/features/strategy/strategy_panel_test.dart`
Expected: FAIL — o novo teste falha porque `StrategyPanel` ainda usa `playerSide` (fixo em brancas), então `flipBoard()` não muda nada na perspectiva exibida.

- [ ] **Step 3: Implementar**

Em `app/lib/features/strategy/strategy_panel.dart`, substituir:

```dart
    final analysis = ref.watch(strategyAnalysisProvider);
    final playerSide = ref.watch(gameControllerProvider).playerSide;

    final (yourThreats, enemyThreats) = playerSide == Side.white
        ? (analysis.threats.whiteThreats, analysis.threats.blackThreats)
        : (analysis.threats.blackThreats, analysis.threats.whiteThreats);
    final (yourWeaknesses, enemyWeaknesses) = playerSide == Side.white
        ? (analysis.weaknesses.white, analysis.weaknesses.black)
        : (analysis.weaknesses.black, analysis.weaknesses.white);
```

por:

```dart
    final analysis = ref.watch(strategyAnalysisProvider);
    final orientation = ref.watch(gameControllerProvider).orientation;

    final (yourThreats, enemyThreats) = orientation == Side.white
        ? (analysis.threats.whiteThreats, analysis.threats.blackThreats)
        : (analysis.threats.blackThreats, analysis.threats.whiteThreats);
    final (yourWeaknesses, enemyWeaknesses) = orientation == Side.white
        ? (analysis.weaknesses.white, analysis.weaknesses.black)
        : (analysis.weaknesses.black, analysis.weaknesses.white);
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `cd app && flutter test test/features/strategy/strategy_panel_test.dart`
Expected: PASS (arquivo inteiro)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/strategy/strategy_panel.dart test/features/strategy/strategy_panel_test.dart
git commit -m "feat: StrategyPanel usa orientation em vez de playerSide"
```

---

### Task 9: `GameControls` — botão "Modo Análise" e status text

**Files:**
- Modify: `app/lib/features/board/game_controls.dart`
- Test: `app/test/features/board/game_controls_test.dart`

**Interfaces:**
- Consumes: `GameController.startAnalysisMode()` (Task 2), `GameState.mode` (Task 1).

- [ ] **Step 1: Escrever o teste que falha**

Adicionar a `app/test/features/board/game_controls_test.dart`, dentro do `main()`, após o teste `'trocar para a aba Estratégia mostra o painel de estratégia'`:

```dart
  testWidgets('botão Modo Análise inicia o modo e atualiza o status', (
    tester,
  ) async {
    await tester.pumpWidget(_makeControls());
    await tester.pumpAndSettle();

    expect(find.text('Modo Análise'), findsOneWidget);

    await tester.tap(find.text('Modo Análise'));
    await tester.pumpAndSettle();

    expect(find.text('Vez das brancas.'), findsOneWidget);
  });
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd app && flutter test test/features/board/game_controls_test.dart`
Expected: FAIL — não existe texto `'Modo Análise'` na árvore de widgets.

- [ ] **Step 3: Implementar**

Em `app/lib/features/board/game_controls.dart`, substituir `_statusText`:

```dart
  String _statusText(GameState state) {
    final result = state.resultText;
    if (result != null) return result;
    if (state.engineThinking) return 'Stockfish pensando…';
    final isPlayerTurn = state.position.turn == state.playerSide;
    return isPlayerTurn ? 'Sua vez.' : 'Vez do adversário.';
  }
```

por:

```dart
  String _statusText(GameState state) {
    final result = state.resultText;
    if (result != null) return result;
    if (state.mode == GameMode.analysis) {
      return state.position.turn == Side.white
          ? 'Vez das brancas.'
          : 'Vez das pretas.';
    }
    if (state.engineThinking) return 'Stockfish pensando…';
    final isPlayerTurn = state.position.turn == state.playerSide;
    return isPlayerTurn ? 'Sua vez.' : 'Vez do adversário.';
  }
```

E, no `build`, substituir:

```dart
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: state.engineThinking
                  ? null
                  : () => controller.newGame(
                      playerSide: Side.black,
                      skillLevel: _skill.round(),
                    ),
              child: const Text('Jogar de pretas'),
            ),
            const SizedBox(height: 16),
            Text('Lances', style: Theme.of(context).textTheme.titleSmall),
```

por:

```dart
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: state.engineThinking
                  ? null
                  : () => controller.newGame(
                      playerSide: Side.black,
                      skillLevel: _skill.round(),
                    ),
              child: const Text('Jogar de pretas'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: state.engineThinking
                  ? null
                  : () => controller.startAnalysisMode(),
              child: const Text('Modo Análise'),
            ),
            const SizedBox(height: 16),
            Text('Lances', style: Theme.of(context).textTheme.titleSmall),
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd app && flutter test test/features/board/game_controls_test.dart`
Expected: PASS (arquivo inteiro)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/board/game_controls.dart test/features/board/game_controls_test.dart
git commit -m "feat: botão Modo Análise e status text em GameControls"
```

---

### Task 10: `GameControls` — botões "Desfazer" e "Virar tabuleiro"

**Files:**
- Modify: `app/lib/features/board/game_controls.dart`
- Test: `app/test/features/board/game_controls_test.dart`

**Interfaces:**
- Consumes: `GameController.undoMove()` (Task 4), `GameController.flipBoard()` (Task 5), `GameState.mode`/`sanHistory` (Task 1).

- [ ] **Step 1: Escrever o teste que falha**

Adicionar a `app/test/features/board/game_controls_test.dart`, após o teste `'botão Modo Análise inicia o modo e atualiza o status'`:

```dart
  testWidgets('Desfazer e Virar tabuleiro só aparecem em Modo Análise', (
    tester,
  ) async {
    await tester.pumpWidget(_makeControls());
    await tester.pumpAndSettle();

    expect(find.text('Desfazer'), findsNothing);
    expect(find.text('Virar tabuleiro'), findsNothing);

    await tester.tap(find.text('Modo Análise'));
    await tester.pumpAndSettle();

    expect(find.text('Desfazer'), findsOneWidget);
    expect(find.text('Virar tabuleiro'), findsOneWidget);

    final undoButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Desfazer'),
    );
    expect(undoButton.onPressed, isNull);
  });
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd app && flutter test test/features/board/game_controls_test.dart`
Expected: FAIL — não existem os textos `'Desfazer'`/`'Virar tabuleiro'` na árvore de widgets.

- [ ] **Step 3: Implementar**

Em `app/lib/features/board/game_controls.dart`, substituir:

```dart
              child: const Text('Modo Análise'),
            ),
            const SizedBox(height: 16),
            Text('Lances', style: Theme.of(context).textTheme.titleSmall),
```

por:

```dart
              child: const Text('Modo Análise'),
            ),
            if (state.mode == GameMode.analysis) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.sanHistory.isEmpty
                          ? null
                          : controller.undoMove,
                      child: const Text('Desfazer'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: controller.flipBoard,
                      child: const Text('Virar tabuleiro'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('Lances', style: Theme.of(context).textTheme.titleSmall),
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd app && flutter test test/features/board/game_controls_test.dart`
Expected: PASS (arquivo inteiro)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/board/game_controls.dart test/features/board/game_controls_test.dart
git commit -m "feat: botões Desfazer e Virar tabuleiro no Modo Análise"
```

---

### Task 11: Verificação final

**Files:** nenhum (apenas verificação — sem alterações de código)

- [ ] **Step 1: Rodar a suíte completa**

Run: `cd app && flutter test`
Expected: PASS — todos os testes, incluindo os das Tasks 1-10.

- [ ] **Step 2: Rodar o analisador estático**

Run: `cd app && dart analyze`
Expected: `No issues found!`

- [ ] **Step 3: Confirmar formatação**

Run: `cd app && dart format --output=none --set-exit-if-changed .`
Expected: exit code 0 (nenhum arquivo precisa de reformatação).

- [ ] **Step 4: Corrigir divergências, se houver**

Se qualquer um dos steps 1-3 falhar, corrigir o problema no arquivo indicado e repetir o step até passar. Não commitar com testes falhando, `dart analyze` com issues, ou formatação pendente.

- [ ] **Step 5: Commit final (se houver correções do Step 4)**

```bash
cd app && git add -A
git commit -m "chore: ajustes finais de verificação do Modo Análise"
```

Se nenhuma correção foi necessária, não há o que commitar neste step.

**Observação:** smoke test manual (`cd app && flutter run -d macos`, testar o fluxo completo do Modo Análise) fica a critério do usuário rodar depois, como já é o padrão deste projeto (ver Fase 3).
