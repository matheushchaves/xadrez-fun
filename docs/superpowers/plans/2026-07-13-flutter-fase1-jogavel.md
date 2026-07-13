# Fase 1 — App Flutter macOS jogável: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar o projeto Flutter macOS em `app/` com tabuleiro interativo e partida contra o Stockfish (níveis 0–20), sem backend.

**Architecture:** App desktop Flutter. Regras de xadrez via `dartchess` (posições imutáveis). Tabuleiro via `chessground` (widget `Chessboard` + `ChessboardController`; sem lógica de xadrez própria). Stockfish roda como processo filho controlado por um cliente UCI próprio (stdin/stdout). Estado global com Riverpod (`Notifier`). O engine é injetável via interface `ChessEngineApi` para permitir fakes em teste.

**Tech Stack:** Flutter (macOS desktop), dartchess ^0.13.1, chessground ^10.1.1, flutter_riverpod ^3.3.2, Stockfish (binário do sistema, ex.: `/opt/homebrew/bin/stockfish`).

## Global Constraints

- Projeto Flutter fica em `app/` (raiz do repo), project name Dart: `xadrez_fun`. Código Python existente permanece intacto.
- Spec de referência: `docs/superpowers/specs/2026-07-13-flutter-macos-app-design.md`.
- Todos os comandos `flutter` rodam dentro de `app/` (`cd /Users/matheus/Dev/xadrez-fun/app`).
- Dependências e versões: `dartchess: ^0.13.1`, `chessground: ^10.1.1`, `flutter_riverpod: ^3.3.2`. Nenhuma outra dependência de runtime.
- App Sandbox do macOS DESABILITADO nos dois entitlements (necessário para spawnar o binário do Stockfish fora do bundle).
- Textos da UI em português (pt-BR), com acentuação correta.
- Estado imutável: `GameState` é `@immutable`, com `copyWith`; nunca mutar listas existentes.
- Mensagens de commit em convenção `feat:`/`test:`/`chore:` sem linha de coautoria.
- `flutter analyze` deve passar sem issues ao final de cada task.

---

## Estrutura de arquivos (visão geral)

```
app/
├── pubspec.yaml
├── macos/Runner/DebugProfile.entitlements   (sandbox off)
├── macos/Runner/Release.entitlements        (sandbox off)
├── lib/
│   ├── main.dart
│   ├── engine/
│   │   ├── engine_api.dart          # interface ChessEngineApi
│   │   ├── stockfish_locator.dart   # findStockfishPath()
│   │   ├── uci_engine.dart          # UciEngine + EngineIo + ProcessEngineIo
│   │   └── engine_provider.dart     # engineProvider (FutureProvider)
│   └── features/
│       ├── play/
│       │   ├── game_state.dart      # GameState (imutável)
│       │   └── game_controller.dart # GameController (Notifier) + provider
│       └── board/
│           ├── board_screen.dart    # tela principal com Chessboard
│           └── game_controls.dart   # painel: status, skill, nova partida, histórico
└── test/
    ├── engine/stockfish_locator_test.dart
    ├── engine/uci_engine_test.dart
    ├── features/play/game_controller_test.dart
    └── features/board/board_screen_test.dart
```

---

### Task 1: Scaffold do projeto Flutter macOS

**Files:**
- Create: `app/` (via `flutter create`)
- Modify: `app/pubspec.yaml` (dependências)
- Modify: `app/macos/Runner/DebugProfile.entitlements`
- Modify: `app/macos/Runner/Release.entitlements`
- Delete: `app/test/widget_test.dart` (teste default vai quebrar; substituído na Task 5)

**Interfaces:**
- Consumes: nada.
- Produces: projeto compilável em `app/` com `dartchess`, `chessground` e `flutter_riverpod` disponíveis para import.

- [ ] **Step 1: Criar o projeto**

```bash
cd /Users/matheus/Dev/xadrez-fun
flutter create app --platforms=macos --project-name xadrez_fun --org dev.matheus
```

Expected: "All done!" e pasta `app/` criada.

- [ ] **Step 2: Adicionar dependências**

```bash
cd /Users/matheus/Dev/xadrez-fun/app
flutter pub add dartchess:^0.13.1 chessground:^10.1.1 flutter_riverpod:^3.3.2
```

Expected: "Changed N dependencies" sem erros de resolução.

- [ ] **Step 3: Desabilitar App Sandbox nos entitlements**

Em `app/macos/Runner/DebugProfile.entitlements` E `app/macos/Runner/Release.entitlements`, trocar o valor da chave `com.apple.security.app-sandbox` de `<true/>` para `<false/>`:

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

(No DebugProfile, manter as demais chaves como `com.apple.security.cs.allow-jit` intactas.)

- [ ] **Step 4: Remover teste default**

```bash
rm /Users/matheus/Dev/xadrez-fun/app/test/widget_test.dart
```

- [ ] **Step 5: Verificar análise e build**

```bash
cd /Users/matheus/Dev/xadrez-fun/app && flutter analyze && flutter build macos --debug
```

Expected: "No issues found!" e "✓ Built build/macos/Build/Products/Debug/xadrez_fun.app".

- [ ] **Step 6: Commit**

```bash
cd /Users/matheus/Dev/xadrez-fun
git add app
git commit -m "feat: scaffold do app Flutter macOS (xadrez_fun) com dartchess, chessground e riverpod"
```

---

### Task 2: Localizador do Stockfish

**Files:**
- Create: `app/lib/engine/stockfish_locator.dart`
- Test: `app/test/engine/stockfish_locator_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces: `String? findStockfishPath({Map<String, String>? environment, bool Function(String path)? isFile})` — retorna o caminho do binário ou `null`. Mesma semântica de `find_stockfish_path()` de `engine.py` (PATH primeiro, depois caminhos comuns).

- [ ] **Step 1: Escrever os testes que falham**

`app/test/engine/stockfish_locator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/stockfish_locator.dart';

void main() {
  test('encontra stockfish no PATH', () {
    final path = findStockfishPath(
      environment: {'PATH': '/foo/bin:/bar/bin', 'HOME': '/Users/x'},
      isFile: (p) => p == '/bar/bin/stockfish',
    );
    expect(path, '/bar/bin/stockfish');
  });

  test('cai nos caminhos comuns quando não está no PATH', () {
    final path = findStockfishPath(
      environment: {'PATH': '/foo/bin', 'HOME': '/Users/x'},
      isFile: (p) => p == '/opt/homebrew/bin/stockfish',
    );
    expect(path, '/opt/homebrew/bin/stockfish');
  });

  test('inclui ~/stockfish/stockfish como candidato', () {
    final path = findStockfishPath(
      environment: {'PATH': '', 'HOME': '/Users/x'},
      isFile: (p) => p == '/Users/x/stockfish/stockfish',
    );
    expect(path, '/Users/x/stockfish/stockfish');
  });

  test('retorna null quando não encontra', () {
    final path = findStockfishPath(
      environment: {'PATH': '/foo', 'HOME': '/Users/x'},
      isFile: (_) => false,
    );
    expect(path, isNull);
  });

  test('PATH tem prioridade sobre caminhos comuns', () {
    final path = findStockfishPath(
      environment: {'PATH': '/meu/bin', 'HOME': '/Users/x'},
      isFile: (p) =>
          p == '/meu/bin/stockfish' || p == '/opt/homebrew/bin/stockfish',
    );
    expect(path, '/meu/bin/stockfish');
  });
}
```

- [ ] **Step 2: Rodar e verificar falha**

Run: `cd /Users/matheus/Dev/xadrez-fun/app && flutter test test/engine/stockfish_locator_test.dart`
Expected: FAIL — "Error: Couldn't resolve the package 'xadrez_fun/engine/stockfish_locator.dart'" (arquivo não existe).

- [ ] **Step 3: Implementar**

`app/lib/engine/stockfish_locator.dart`:

```dart
import 'dart:io';

/// Localiza o executável do Stockfish no sistema.
///
/// Espelha a lógica de `find_stockfish_path()` do engine.py:
/// primeiro o PATH, depois caminhos comuns de instalação.
String? findStockfishPath({
  Map<String, String>? environment,
  bool Function(String path)? isFile,
}) {
  final env = environment ?? Platform.environment;
  final checkFile = isFile ?? (String p) => File(p).existsSync();
  final home = env['HOME'] ?? '';

  final pathDirs =
      (env['PATH'] ?? '').split(':').where((d) => d.isNotEmpty);

  final candidates = [
    for (final dir in pathDirs) '$dir/stockfish',
    '/usr/local/bin/stockfish',
    '/usr/bin/stockfish',
    '/opt/homebrew/bin/stockfish',
    '/opt/local/bin/stockfish',
    '$home/stockfish/stockfish',
  ];

  for (final candidate in candidates) {
    if (checkFile(candidate)) return candidate;
  }
  return null;
}
```

- [ ] **Step 4: Rodar e verificar que passa**

Run: `cd /Users/matheus/Dev/xadrez-fun/app && flutter test test/engine/stockfish_locator_test.dart`
Expected: "All tests passed!" (5 testes).

- [ ] **Step 5: Commit**

```bash
cd /Users/matheus/Dev/xadrez-fun
git add app/lib/engine/stockfish_locator.dart app/test/engine/stockfish_locator_test.dart
git commit -m "feat: localizador do binário do Stockfish (PATH + caminhos comuns)"
```

---

### Task 3: Cliente UCI do Stockfish

**Files:**
- Create: `app/lib/engine/engine_api.dart`
- Create: `app/lib/engine/uci_engine.dart`
- Test: `app/test/engine/uci_engine_test.dart`

**Interfaces:**
- Consumes: nada (independente do locator).
- Produces:
  - `abstract interface class ChessEngineApi` com `Future<void> setSkillLevel(int level)`, `Future<String?> bestMoveFromFen(String fen)`, `Future<void> dispose()`.
  - `abstract interface class EngineIo` com `Stream<String> get lines` (broadcast), `void send(String command)`, `Future<void> kill()`.
  - `class UciEngine implements ChessEngineApi` com construtor `UciEngine(EngineIo io, {int depth = 12})`, `Future<void> init()` e factory `static Future<UciEngine> spawn(String path)`.

- [ ] **Step 1: Escrever os testes que falham**

`app/test/engine/uci_engine_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/uci_engine.dart';

/// Fake de EngineIo: responde a comandos com linhas roteirizadas.
class FakeEngineIo implements EngineIo {
  FakeEngineIo(this.responses);

  /// prefixo do comando enviado -> linhas emitidas em resposta
  final Map<String, List<String>> responses;
  final sent = <String>[];
  final _controller = StreamController<String>.broadcast();
  bool killed = false;

  @override
  Stream<String> get lines => _controller.stream;

  @override
  void send(String command) {
    sent.add(command);
    for (final entry in responses.entries) {
      if (command.startsWith(entry.key)) {
        entry.value.forEach(_controller.add);
      }
    }
  }

  @override
  Future<void> kill() async {
    killed = true;
    await _controller.close();
  }
}

FakeEngineIo standardIo() => FakeEngineIo({
      'uci': ['id name Stockfish 17', 'uciok'],
      'isready': ['readyok'],
      'go depth': [
        'info depth 12 score cp 31 pv e2e4',
        'bestmove e2e4 ponder e7e5',
      ],
    });

void main() {
  test('init faz handshake uci/isready e configura threads', () async {
    final io = standardIo();
    final engine = UciEngine(io);
    await engine.init();
    expect(io.sent, contains('uci'));
    expect(io.sent, contains('setoption name Threads value 2'));
    expect(io.sent, contains('isready'));
  });

  test('bestMoveFromFen envia posição e retorna o lance', () async {
    final io = standardIo();
    final engine = UciEngine(io);
    await engine.init();

    const fen =
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    final move = await engine.bestMoveFromFen(fen);

    expect(move, 'e2e4');
    expect(io.sent, contains('position fen $fen'));
    expect(io.sent, contains('go depth 12'));
  });

  test('bestMoveFromFen retorna null quando não há lance', () async {
    final io = FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      'go depth': ['bestmove (none)'],
    });
    final engine = UciEngine(io);
    await engine.init();
    final move = await engine.bestMoveFromFen('8/8/8/8/8/8/8/k1K5 b - - 0 1');
    expect(move, isNull);
  });

  test('setSkillLevel envia setoption', () async {
    final io = standardIo();
    final engine = UciEngine(io);
    await engine.init();
    await engine.setSkillLevel(5);
    expect(io.sent, contains('setoption name Skill Level value 5'));
  });

  test('dispose envia quit e mata o processo', () async {
    final io = standardIo();
    final engine = UciEngine(io);
    await engine.init();
    await engine.dispose();
    expect(io.sent, contains('quit'));
    expect(io.killed, isTrue);
  });
}
```

- [ ] **Step 2: Rodar e verificar falha**

Run: `cd /Users/matheus/Dev/xadrez-fun/app && flutter test test/engine/uci_engine_test.dart`
Expected: FAIL — package não resolve (arquivos não existem).

- [ ] **Step 3: Implementar**

`app/lib/engine/engine_api.dart`:

```dart
/// Interface do engine de xadrez, injetável para permitir fakes em teste.
abstract interface class ChessEngineApi {
  /// Define o nível de habilidade (0-20).
  Future<void> setSkillLevel(int level);

  /// Melhor lance (UCI, ex.: "e2e4") para a posição, ou null se não houver.
  Future<String?> bestMoveFromFen(String fen);

  /// Encerra o engine.
  Future<void> dispose();
}
```

`app/lib/engine/uci_engine.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'engine_api.dart';

export 'engine_api.dart';

/// Canal de comunicação com o processo do engine (injetável em testes).
abstract interface class EngineIo {
  /// Linhas do stdout do engine (stream broadcast).
  Stream<String> get lines;

  void send(String command);

  Future<void> kill();
}

/// EngineIo real, sobre um [Process] do sistema.
class ProcessEngineIo implements EngineIo {
  ProcessEngineIo(Process process)
      : _process = process,
        lines = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .asBroadcastStream();

  final Process _process;

  @override
  final Stream<String> lines;

  @override
  void send(String command) => _process.stdin.writeln(command);

  @override
  Future<void> kill() async {
    _process.kill();
  }
}

/// Cliente UCI mínimo para a fase 1: handshake, skill level e melhor lance.
class UciEngine implements ChessEngineApi {
  UciEngine(this._io, {this.depth = 12});

  final EngineIo _io;

  /// Profundidade de busca usada em [bestMoveFromFen].
  final int depth;

  /// Handshake UCI e configuração inicial (mesmos parâmetros do engine.py).
  Future<void> init() async {
    _io.send('uci');
    await _io.lines.firstWhere((l) => l.trim() == 'uciok');
    _io.send('setoption name Threads value 2');
    _io.send('isready');
    await _io.lines.firstWhere((l) => l.trim() == 'readyok');
  }

  @override
  Future<void> setSkillLevel(int level) async {
    _io.send('setoption name Skill Level value $level');
  }

  @override
  Future<String?> bestMoveFromFen(String fen) async {
    _io.send('position fen $fen');
    _io.send('go depth $depth');
    final line =
        await _io.lines.firstWhere((l) => l.startsWith('bestmove'));
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts[1] == '(none)') return null;
    return parts[1];
  }

  @override
  Future<void> dispose() async {
    _io.send('quit');
    await _io.kill();
  }

  /// Spawna o binário do Stockfish e completa o handshake.
  static Future<UciEngine> spawn(String path) async {
    final process = await Process.start(path, const []);
    final engine = UciEngine(ProcessEngineIo(process));
    await engine.init();
    return engine;
  }
}
```

- [ ] **Step 4: Rodar e verificar que passa**

Run: `cd /Users/matheus/Dev/xadrez-fun/app && flutter test test/engine/uci_engine_test.dart`
Expected: "All tests passed!" (5 testes).

- [ ] **Step 5: Commit**

```bash
cd /Users/matheus/Dev/xadrez-fun
git add app/lib/engine/engine_api.dart app/lib/engine/uci_engine.dart app/test/engine/uci_engine_test.dart
git commit -m "feat: cliente UCI do Stockfish com IO injetável"
```

---

### Task 4: Estado do jogo e controller (Riverpod)

**Files:**
- Create: `app/lib/engine/engine_provider.dart`
- Create: `app/lib/features/play/game_state.dart`
- Create: `app/lib/features/play/game_controller.dart`
- Test: `app/test/features/play/game_controller_test.dart`

**Interfaces:**
- Consumes: `ChessEngineApi` (Task 3), `findStockfishPath` (Task 2).
- Produces:
  - `final engineProvider = FutureProvider<ChessEngineApi?>(...)` em `engine_provider.dart` — `null` quando Stockfish não está instalado.
  - `class GameState` imutável: campos `Position position`, `List<String> sanHistory`, `Side playerSide`, `int skillLevel`, `Move? lastMove`, `bool engineThinking`; getters `bool get isGameOver`, `String? get resultText`; método `GameState copyWith(...)`.
  - `final gameControllerProvider = NotifierProvider<GameController, GameState>(GameController.new)`.
  - `class GameController extends Notifier<GameState>` com `Future<void> newGame({required Side playerSide, required int skillLevel})` e `Future<void> playUserMove(Move move)`.

- [ ] **Step 1: Escrever os testes que falham**

`app/test/features/play/game_controller_test.dart`:

```dart
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';

/// Engine fake que responde sempre o mesmo lance.
class FakeEngine implements ChessEngineApi {
  FakeEngine(this.reply);

  final String? reply;
  final skillLevels = <int>[];
  final fensAsked = <String>[];

  @override
  Future<void> setSkillLevel(int level) async => skillLevels.add(level);

  @override
  Future<String?> bestMoveFromFen(String fen) async {
    fensAsked.add(fen);
    return reply;
  }

  @override
  Future<void> dispose() async {}
}

ProviderContainer makeContainer(ChessEngineApi? engine) {
  final container = ProviderContainer(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(engine)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('estado inicial: posição inicial, sem histórico', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final state = container.read(gameControllerProvider);
    expect(state.position.fen, Chess.initial.fen);
    expect(state.sanHistory, isEmpty);
    expect(state.isGameOver, isFalse);
  });

  test('lance do jogador dispara resposta do engine', () async {
    final engine = FakeEngine('e7e5');
    final container = makeContainer(engine);
    final controller = container.read(gameControllerProvider.notifier);

    await controller.playUserMove(Move.parse('e2e4')!);

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, ['e4', 'e5']);
    expect(state.position.turn, Side.white);
    expect(engine.fensAsked, hasLength(1));
    expect(state.engineThinking, isFalse);
  });

  test('sem engine, o lance do jogador não trava (tabuleiro livre)', () async {
    final container = makeContainer(null);
    final controller = container.read(gameControllerProvider.notifier);

    await controller.playUserMove(Move.parse('e2e4')!);

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, ['e4']);
    expect(state.position.turn, Side.black);
  });

  test('newGame reinicia estado e aplica skill level', () async {
    final engine = FakeEngine('e7e5');
    final container = makeContainer(engine);
    final controller = container.read(gameControllerProvider.notifier);

    await controller.playUserMove(Move.parse('e2e4')!);
    await controller.newGame(playerSide: Side.white, skillLevel: 3);

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, isEmpty);
    expect(state.skillLevel, 3);
    expect(engine.skillLevels, contains(3));
  });

  test('newGame jogando de pretas: engine abre a partida', () async {
    final engine = FakeEngine('e2e4');
    final container = makeContainer(engine);
    final controller = container.read(gameControllerProvider.notifier);

    await controller.newGame(playerSide: Side.black, skillLevel: 10);

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, ['e4']);
    expect(state.position.turn, Side.black);
  });

  test('detecta xeque-mate ao final da sequência de lances', () async {
    // Mate do louco: 1.f3 e5 2.g4 Dh4# — tabuleiro livre (sem engine),
    // todos os lances entram como lances do "jogador".
    final freeContainer = makeContainer(null);
    final free = freeContainer.read(gameControllerProvider.notifier);
    await free.playUserMove(Move.parse('f2f3')!);
    await free.playUserMove(Move.parse('e7e5')!);
    await free.playUserMove(Move.parse('g2g4')!);
    await free.playUserMove(Move.parse('d8h4')!);

    final state = freeContainer.read(gameControllerProvider);
    expect(state.isGameOver, isTrue);
    expect(state.resultText, 'Xeque-mate! Pretas vencem.');
  });
}
```

- [ ] **Step 2: Rodar e verificar falha**

Run: `cd /Users/matheus/Dev/xadrez-fun/app && flutter test test/features/play/game_controller_test.dart`
Expected: FAIL — packages não resolvem (arquivos não existem).

- [ ] **Step 3: Implementar**

`app/lib/engine/engine_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine_api.dart';
import 'stockfish_locator.dart';
import 'uci_engine.dart';

/// Engine global do app. `null` quando o Stockfish não está instalado.
final engineProvider = FutureProvider<ChessEngineApi?>((ref) async {
  final path = findStockfishPath();
  if (path == null) return null;
  final engine = await UciEngine.spawn(path);
  ref.onDispose(engine.dispose);
  return engine;
});
```

`app/lib/features/play/game_state.dart`:

```dart
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// Estado imutável de uma partida.
@immutable
class GameState {
  const GameState({
    required this.position,
    required this.sanHistory,
    required this.playerSide,
    required this.skillLevel,
    this.lastMove,
    this.engineThinking = false,
  });

  GameState.initial()
      : this(
          position: Chess.initial,
          sanHistory: const [],
          playerSide: Side.white,
          skillLevel: 10,
        );

  final Position position;
  final List<String> sanHistory;
  final Side playerSide;
  final int skillLevel;
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
    Move? lastMove,
    bool? engineThinking,
  }) {
    return GameState(
      position: position ?? this.position,
      sanHistory: sanHistory ?? this.sanHistory,
      playerSide: playerSide ?? this.playerSide,
      skillLevel: skillLevel ?? this.skillLevel,
      lastMove: lastMove ?? this.lastMove,
      engineThinking: engineThinking ?? this.engineThinking,
    );
  }
}
```

`app/lib/features/play/game_controller.dart`:

```dart
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_provider.dart';
import 'game_state.dart';

export 'game_state.dart';

final gameControllerProvider =
    NotifierProvider<GameController, GameState>(GameController.new);

/// Orquestra a partida: aplica lances do jogador e pede resposta ao engine.
class GameController extends Notifier<GameState> {
  @override
  GameState build() => GameState.initial();

  Future<void> newGame({
    required Side playerSide,
    required int skillLevel,
  }) async {
    state = GameState.initial()
        .copyWith(playerSide: playerSide, skillLevel: skillLevel);
    final engine = await ref.read(engineProvider.future);
    await engine?.setSkillLevel(skillLevel);
    if (playerSide == Side.black) {
      await _engineMove();
    }
  }

  Future<void> playUserMove(Move move) async {
    if (state.engineThinking || state.isGameOver) return;
    if (!state.position.isLegal(move)) return;
    _applyMove(move);
    if (!state.isGameOver) {
      await _engineMove();
    }
  }

  void _applyMove(Move move) {
    final (newPosition, san) = state.position.makeSan(move);
    state = state.copyWith(
      position: newPosition,
      sanHistory: [...state.sanHistory, san],
      lastMove: move,
    );
  }

  Future<void> _engineMove() async {
    final engine = await ref.read(engineProvider.future);
    if (engine == null) return;
    state = state.copyWith(engineThinking: true);
    try {
      final uci = await engine.bestMoveFromFen(state.position.fen);
      final move = uci == null ? null : Move.parse(uci);
      if (move != null && state.position.isLegal(move)) {
        _applyMove(move);
      }
    } finally {
      state = state.copyWith(engineThinking: false);
    }
  }
}
```

- [ ] **Step 4: Rodar e verificar que passa**

Run: `cd /Users/matheus/Dev/xadrez-fun/app && flutter test test/features/play/game_controller_test.dart`
Expected: "All tests passed!" (6 testes).

- [ ] **Step 5: Rodar todos os testes**

Run: `cd /Users/matheus/Dev/xadrez-fun/app && flutter test && flutter analyze`
Expected: todos passam, "No issues found!".

- [ ] **Step 6: Commit**

```bash
cd /Users/matheus/Dev/xadrez-fun
git add app/lib/engine/engine_provider.dart app/lib/features/play app/test/features/play app/pubspec.yaml app/pubspec.lock
git commit -m "feat: estado do jogo e controller com resposta automática do engine"
```

---

### Task 5: Tela do tabuleiro

**Files:**
- Create: `app/lib/features/board/board_screen.dart`
- Modify: `app/lib/main.dart` (substituir conteúdo inteiro)
- Test: `app/test/features/board/board_screen_test.dart`

**Interfaces:**
- Consumes: `gameControllerProvider`, `GameState` (Task 4), `engineProvider` (Task 4).
- Produces: `class BoardScreen extends ConsumerStatefulWidget` — tela principal; `class XadrezFunApp extends StatelessWidget` em `main.dart`. A Task 6 insere `GameControls` no `Row` da `BoardScreen` (placeholder `SizedBox` até lá).

- [ ] **Step 1: Escrever o teste que falha**

`app/test/features/board/board_screen_test.dart`:

```dart
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/board/board_screen.dart';

class FakeEngine implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => 'e7e5';

  @override
  Future<void> dispose() async {}
}

Widget makeApp(ChessEngineApi? engine) {
  return ProviderScope(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(engine)),
    ],
    child: const MaterialApp(home: BoardScreen()),
  );
}

void main() {
  testWidgets('renderiza o tabuleiro', (tester) async {
    await tester.pumpWidget(makeApp(FakeEngine()));
    await tester.pumpAndSettle();
    expect(find.byType(Chessboard), findsOneWidget);
  });

  testWidgets('sem engine, mostra aviso de instalação', (tester) async {
    await tester.pumpWidget(makeApp(null));
    await tester.pumpAndSettle();
    expect(find.textContaining('brew install stockfish'), findsOneWidget);
    expect(find.byType(Chessboard), findsOneWidget);
  });
}
```

- [ ] **Step 2: Rodar e verificar falha**

Run: `cd /Users/matheus/Dev/xadrez-fun/app && flutter test test/features/board/board_screen_test.dart`
Expected: FAIL — `board_screen.dart` não existe.

- [ ] **Step 3: Implementar a tela**

`app/lib/features/board/board_screen.dart`:

```dart
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_provider.dart';
import '../play/game_controller.dart';

/// Tela principal: tabuleiro à esquerda, controles à direita.
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  late final ChessboardController _boardController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(gameControllerProvider);
    final engineAvailable =
        ref.read(engineProvider).valueOrNull != null;
    _boardController =
        ChessboardController(game: _gameData(state, engineAvailable));
  }

  @override
  void dispose() {
    _boardController.dispose();
    super.dispose();
  }

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

  void _onMove(Move move, {bool? isDrop}) {
    ref.read(gameControllerProvider.notifier).playUserMove(move);
  }

  @override
  Widget build(BuildContext context) {
    final engineAvailable =
        ref.watch(engineProvider).valueOrNull != null;
    final engineReady = !ref.watch(engineProvider).isLoading;

    ref.listen(gameControllerProvider, (previous, next) {
      _boardController.updatePosition(_gameData(next, engineAvailable));
    });

    final state = ref.watch(gameControllerProvider);
    final orientation =
        state.playerSide == Side.black ? Side.black : Side.white;

    return Scaffold(
      body: Column(
        children: [
          if (engineReady && !engineAvailable)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Stockfish não encontrado — instale com: brew install stockfish. '
                'Tabuleiro livre habilitado.',
              ),
            ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = constraints.biggest.shortestSide;
                        return Chessboard(
                          controller: _boardController,
                          size: size,
                          orientation: orientation,
                          onMove: _onMove,
                        );
                      },
                    ),
                  ),
                ),
                // Task 6 substitui por GameControls.
                const SizedBox(width: 280),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

Nota para o implementador: confira a assinatura exata do callback `onMove` e dos parâmetros de `Chessboard`/`GameData` na versão instalada (`dart doc` ou o código-fonte em `~/.pub-cache/hosted/pub.dev/chessground-10.1.1/`). Se `onMove` tiver assinatura diferente (ex.: parâmetro nomeado `viaDragAndDrop`), ajuste `_onMove` para casar — o comportamento (delegar ao controller) não muda.

- [ ] **Step 4: Substituir `app/lib/main.dart` (conteúdo inteiro)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/board/board_screen.dart';

void main() {
  runApp(const ProviderScope(child: XadrezFunApp()));
}

class XadrezFunApp extends StatelessWidget {
  const XadrezFunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xadrez Fun',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
      ),
      home: const BoardScreen(),
    );
  }
}
```

- [ ] **Step 5: Rodar e verificar que passa**

Run: `cd /Users/matheus/Dev/xadrez-fun/app && flutter test test/features/board/board_screen_test.dart && flutter analyze`
Expected: "All tests passed!" (2 testes), "No issues found!".

- [ ] **Step 6: Commit**

```bash
cd /Users/matheus/Dev/xadrez-fun
git add app/lib/features/board/board_screen.dart app/lib/main.dart app/test/features/board/board_screen_test.dart
git commit -m "feat: tela do tabuleiro com chessground integrado ao controller"
```

---

### Task 6: Painel de controles

**Files:**
- Create: `app/lib/features/board/game_controls.dart`
- Modify: `app/lib/features/board/board_screen.dart` (trocar o `SizedBox(width: 280)` por `GameControls`)
- Test: `app/test/features/board/board_screen_test.dart` (adicionar testes)

**Interfaces:**
- Consumes: `gameControllerProvider`, `GameState` (Task 4).
- Produces: `class GameControls extends ConsumerWidget` — painel lateral com status, slider de nível, botões de nova partida e histórico de lances.

- [ ] **Step 1: Adicionar testes que falham**

Acrescentar ao final do `main()` de `app/test/features/board/board_screen_test.dart`:

```dart
  testWidgets('painel mostra status e controles de nova partida',
      (tester) async {
    await tester.pumpWidget(makeApp(FakeEngine()));
    await tester.pumpAndSettle();

    expect(find.text('Sua vez.'), findsOneWidget);
    expect(find.text('Jogar de brancas'), findsOneWidget);
    expect(find.text('Jogar de pretas'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('nova partida de pretas: engine abre e histórico aparece',
      (tester) async {
    await tester.pumpWidget(makeApp(FakeEngineOpeningE4()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jogar de pretas'));
    await tester.pumpAndSettle();

    expect(find.textContaining('e4'), findsWidgets);
  });
```

E adicionar a classe fake junto ao `FakeEngine` existente:

```dart
class FakeEngineOpeningE4 implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => 'e2e4';

  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 2: Rodar e verificar falha**

Run: `cd /Users/matheus/Dev/xadrez-fun/app && flutter test test/features/board/board_screen_test.dart`
Expected: FAIL — textos "Sua vez."/"Jogar de brancas" não encontrados.

- [ ] **Step 3: Implementar o painel**

`app/lib/features/board/game_controls.dart`:

```dart
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../play/game_controller.dart';

/// Painel lateral: status da partida, nível do engine, nova partida
/// e histórico de lances.
class GameControls extends ConsumerStatefulWidget {
  const GameControls({super.key});

  @override
  ConsumerState<GameControls> createState() => _GameControlsState();
}

class _GameControlsState extends ConsumerState<GameControls> {
  double _skill = 10;

  String _statusText(GameState state) {
    final result = state.resultText;
    if (result != null) return result;
    if (state.engineThinking) return 'Stockfish pensando…';
    final isPlayerTurn = state.position.turn == state.playerSide;
    return isPlayerTurn ? 'Sua vez.' : 'Vez do adversário.';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameControllerProvider);
    final controller = ref.read(gameControllerProvider.notifier);

    return SizedBox(
      width: 280,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _statusText(state),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            Text('Nível do Stockfish: ${_skill.round()}'),
            Slider(
              value: _skill,
              min: 0,
              max: 20,
              divisions: 20,
              label: '${_skill.round()}',
              onChanged: (value) => setState(() => _skill = value),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => controller.newGame(
                playerSide: Side.white,
                skillLevel: _skill.round(),
              ),
              child: const Text('Jogar de brancas'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => controller.newGame(
                playerSide: Side.black,
                skillLevel: _skill.round(),
              ),
              child: const Text('Jogar de pretas'),
            ),
            const SizedBox(height: 24),
            Text('Lances', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < state.sanHistory.length; i++)
                      Text(
                        i.isEven
                            ? '${i ~/ 2 + 1}. ${state.sanHistory[i]}'
                            : state.sanHistory[i],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Em `app/lib/features/board/board_screen.dart`, trocar:

```dart
                // Task 6 substitui por GameControls.
                const SizedBox(width: 280),
```

por:

```dart
                const GameControls(),
```

e adicionar o import no topo do arquivo:

```dart
import 'game_controls.dart';
```

- [ ] **Step 4: Rodar tudo e verificar que passa**

Run: `cd /Users/matheus/Dev/xadrez-fun/app && flutter test && flutter analyze`
Expected: todos os testes passam (13+), "No issues found!".

- [ ] **Step 5: Build final e smoke test manual**

```bash
cd /Users/matheus/Dev/xadrez-fun/app && flutter build macos --debug
```

Expected: "✓ Built ...xadrez_fun.app".

Smoke test manual (com o usuário ou via `flutter run -d macos`): abrir o app, jogar 1.e4 e verificar que o Stockfish responde; verificar slider de nível e "Jogar de pretas" (engine abre a partida).

- [ ] **Step 6: Commit**

```bash
cd /Users/matheus/Dev/xadrez-fun
git add app/lib/features/board app/test/features/board
git commit -m "feat: painel de controles (status, nível, nova partida, histórico)"
```

---

## Fora do escopo desta fase

Fases 2–5 do spec (análise de posição, analisadores estratégicos, cenários, saves) terão planos próprios. Nada aqui deve antecipá-las (YAGNI).
