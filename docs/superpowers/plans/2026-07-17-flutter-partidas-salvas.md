# Partidas Salvas (Flutter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar ao app Flutter (`app/`) uma biblioteca de partidas salvas — criar, listar, carregar, renomear e deletar, com autosave silencioso a cada lance e um diálogo de retomar ao abrir o app — equivalente ao sistema de saves do `web.py`/`SaveManager` em Python, com formato e local próprios do Flutter.

**Architecture:** Autosave como observador reativo (`AutosaveController`), separado do `GameController`, seguindo o mesmo padrão já usado pelo `AnalysisController`. Um `GamesRepository` (interface + implementação em arquivo via `path_provider`, com fake em memória para os testes) fica disponível tanto para o autosave quanto para a tela de partidas salvas. `GameState` ganha `gameId`/`gameName`; `GameController` ganha `loadGame`, `renameCurrentGame` e `resetIfActiveGame`.

**Tech Stack:** Flutter, `flutter_riverpod` (Notifier/copyWith/Provider), `dartchess` (Position/Move/Side), `path_provider` (novo — acesso ao diretório de suporte do app), `dart:convert`/`dart:io` (JSON e arquivos), `flutter_test`.

## Global Constraints

- Todo código novo em português nos comentários e nas strings de UI, como o restante do projeto.
- Seguir os padrões já em uso: imports relativos entre features, estado imutável com `copyWith`, `Notifier`/`NotifierProvider`/`Provider` do Riverpod, fakes definidos inline em cada arquivo de teste que precisa deles (não um helper compartilhado — é assim que `FakeEngine` já é feito em várias suítes).
- Local e formato de armazenamento são **próprios do Flutter** — não compartilha arquivos com `~/.xadrez-terminal/` do Python.
- Autosave é silencioso (sem botão "Salvar") e dispara a cada mudança de estado do `GameController` cujo `sanHistory` não está vazio.
- O diálogo de retomar ao abrir o app, se recusado ("Nova partida"), **não apaga** a partida salva.
- `dart format` e `dart analyze` devem ficar limpos após cada task.
- Cada task termina com `flutter test` das suítes tocadas, passando.
- Fora de escopo (confirmado no design): cenários (what-if, variações, Monte Carlo) do Python — ficam para uma fase futura separada.

---

### Task 1: `GameState` — identidade da partida (`gameId`/`gameName`)

**Files:**
- Modify: `app/lib/features/play/game_state.dart`
- Modify: `app/lib/features/play/game_controller.dart` (só o corpo de `undoMove()`)
- Test: `app/test/features/play/game_controller_test.dart`

**Interfaces:**
- Produces: `GameState.gameId` (`String`), `GameState.gameName` (`String`); `GameState.initial()` deixa de ser `const` (vira `factory`, gera um id/nome novos a cada chamada); `GameState.copyWith({..., String? gameName})` (`gameId` nunca é alterável via `copyWith` — só via construção direta, como em `undoMove`/`loadGame`).

- [ ] **Step 1: Escrever os testes que falham**

Em `app/test/features/play/game_controller_test.dart`, substituir:

```dart
  test('estado inicial: modo playVsEngine, orientação brancas', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final state = container.read(gameControllerProvider);
    expect(state.mode, GameMode.playVsEngine);
    expect(state.orientation, Side.white);
  });

  test('lance do jogador dispara resposta do engine', () async {
```

por:

```dart
  test('estado inicial: modo playVsEngine, orientação brancas', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final state = container.read(gameControllerProvider);
    expect(state.mode, GameMode.playVsEngine);
    expect(state.orientation, Side.white);
  });

  test('estado inicial tem gameId e gameName preenchidos automaticamente', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final state = container.read(gameControllerProvider);
    expect(state.gameId, isNotEmpty);
    expect(state.gameName, isNotEmpty);
  });

  test('GameState.initial() gera gameId diferente a cada chamada', () {
    final a = GameState.initial();
    final b = GameState.initial();
    expect(a.gameId, isNot(equals(b.gameId)));
  });

  test('lance do jogador dispara resposta do engine', () async {
```

E substituir:

```dart
  test('undoMove com histórico vazio não faz nada', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    controller.startAnalysisMode();
    final before = container.read(gameControllerProvider);

    controller.undoMove();

    expect(container.read(gameControllerProvider), same(before));
  });

  test('flipBoard alterna a orientação', () {
```

por:

```dart
  test('undoMove com histórico vazio não faz nada', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    controller.startAnalysisMode();
    final before = container.read(gameControllerProvider);

    controller.undoMove();

    expect(container.read(gameControllerProvider), same(before));
  });

  test('undoMove preserva gameId e gameName', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    controller.startAnalysisMode();
    final before = container.read(gameControllerProvider);
    await controller.playUserMove(Move.parse('e2e4')!);

    controller.undoMove();

    final after = container.read(gameControllerProvider);
    expect(after.gameId, before.gameId);
    expect(after.gameName, before.gameName);
  });

  test('flipBoard alterna a orientação', () {
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: FAIL — `state.gameId`/`state.gameName` não existem (erro de compilação).

- [ ] **Step 3: Implementar**

Substituir todo o conteúdo de `app/lib/features/play/game_state.dart`:

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
    required this.gameId,
    required this.gameName,
    this.lastMove,
    this.engineThinking = false,
  });

  /// Partida nova: identidade (`gameId`/`gameName`) gerada na hora — por
  /// isso não é mais `const` como antes de existir identidade de partida.
  factory GameState.initial() {
    final now = DateTime.now();
    return GameState(
      position: Chess.initial,
      sanHistory: const [],
      playerSide: Side.white,
      skillLevel: 10,
      mode: GameMode.playVsEngine,
      orientation: Side.white,
      gameId: _newGameId(now),
      gameName: _defaultGameName(now),
    );
  }

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

  /// Identificador único da partida — gerado uma vez em [GameState.initial]
  /// (ou recebido de uma partida carregada) e preservado por toda a sessão
  /// (lances, undo, flip). Só muda quando uma partida nova começa ou uma
  /// partida salva é carregada via `GameController.loadGame`.
  final String gameId;

  /// Nome de exibição da partida (padrão automático, renomeável via
  /// `GameController.renameCurrentGame`).
  final String gameName;
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
    String? gameName,
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
      gameId: gameId,
      gameName: gameName ?? this.gameName,
      lastMove: lastMove ?? this.lastMove,
      engineThinking: engineThinking ?? this.engineThinking,
    );
  }
}

String _newGameId(DateTime now) {
  final salt = Object().hashCode.abs();
  return '${now.microsecondsSinceEpoch.toRadixString(36)}'
      '${salt.toRadixString(36)}';
}

String _defaultGameName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Partida ${two(now.day)}/${two(now.month)} '
      '${two(now.hour)}:${two(now.minute)}';
}
```

Em `app/lib/features/play/game_controller.dart`, dentro de `undoMove()`, substituir:

```dart
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
```

por:

```dart
    state = GameState(
      position: position,
      sanHistory: newHistory,
      playerSide: state.playerSide,
      skillLevel: state.skillLevel,
      mode: state.mode,
      orientation: state.orientation,
      gameId: state.gameId,
      gameName: state.gameName,
      lastMove: lastMove,
      engineThinking: state.engineThinking,
    );
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: PASS (arquivo inteiro)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/play/game_state.dart lib/features/play/game_controller.dart test/features/play/game_controller_test.dart
git commit -m "feat: adiciona gameId/gameName ao GameState"
```

---

### Task 2: Modelos `SavedGame`/`SavedGameSummary`

**Files:**
- Create: `app/lib/features/saves/saved_game.dart`
- Test: `app/test/features/saves/saved_game_test.dart`

**Interfaces:**
- Consumes: `GameState`, `GameMode` (Task 1).
- Produces: `SavedGame` (`id`, `name`, `mode`, `timestamp`, `sanHistory`, `playerSide?`, `skillLevel?`, com `toJson()`/`fromJson()`/`copyWith({name})`/`fromGameState(GameState)`); `SavedGameSummary` (`id`, `name`, `mode`, `moveCount`, `timestamp`, com `fromJson()`).

- [ ] **Step 1: Escrever os testes que falham**

Criar `app/test/features/saves/saved_game_test.dart`:

```dart
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';
import 'package:xadrez_fun/features/saves/saved_game.dart';

void main() {
  test('toJson/fromJson faz roundtrip para partida vs. engine', () {
    final original = SavedGame(
      id: 'abc123',
      name: 'Minha partida',
      mode: GameMode.playVsEngine,
      timestamp: DateTime.utc(2026, 7, 17, 14, 30),
      sanHistory: const ['e4', 'e5', 'Nf3'],
      playerSide: Side.black,
      skillLevel: 7,
    );

    final decoded = SavedGame.fromJson(original.toJson());

    expect(decoded.id, original.id);
    expect(decoded.name, original.name);
    expect(decoded.mode, original.mode);
    expect(decoded.timestamp, original.timestamp);
    expect(decoded.sanHistory, original.sanHistory);
    expect(decoded.playerSide, original.playerSide);
    expect(decoded.skillLevel, original.skillLevel);
  });

  test(
    'toJson/fromJson faz roundtrip para Modo Análise '
    '(sem playerSide/skillLevel)',
    () {
      final original = SavedGame(
        id: 'def456',
        name: 'Análise da Siciliana',
        mode: GameMode.analysis,
        timestamp: DateTime.utc(2026, 7, 17, 15),
        sanHistory: const ['e4', 'c5'],
      );

      final decoded = SavedGame.fromJson(original.toJson());

      expect(decoded.mode, GameMode.analysis);
      expect(decoded.playerSide, isNull);
      expect(decoded.skillLevel, isNull);
      expect(decoded.sanHistory, original.sanHistory);
    },
  );

  test('fromGameState zera playerSide/skillLevel em Modo Análise', () {
    final state = GameState.initial().copyWith(
      mode: GameMode.analysis,
      sanHistory: const ['e4'],
    );

    final saved = SavedGame.fromGameState(state);

    expect(saved.mode, GameMode.analysis);
    expect(saved.playerSide, isNull);
    expect(saved.skillLevel, isNull);
    expect(saved.id, state.gameId);
    expect(saved.name, state.gameName);
    expect(saved.sanHistory, ['e4']);
  });

  test('fromGameState preserva playerSide/skillLevel em playVsEngine', () {
    final state = GameState.initial().copyWith(
      playerSide: Side.black,
      skillLevel: 3,
      sanHistory: const ['e4'],
    );

    final saved = SavedGame.fromGameState(state);

    expect(saved.mode, GameMode.playVsEngine);
    expect(saved.playerSide, Side.black);
    expect(saved.skillLevel, 3);
  });

  test('SavedGameSummary.fromJson deriva moveCount do tamanho do histórico', () {
    final json = SavedGame(
      id: 'xyz',
      name: 'Teste',
      mode: GameMode.playVsEngine,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const ['e4', 'e5', 'Nf3', 'Nc6'],
      playerSide: Side.white,
      skillLevel: 10,
    ).toJson();

    final summary = SavedGameSummary.fromJson(json);

    expect(summary.moveCount, 4);
    expect(summary.id, 'xyz');
    expect(summary.name, 'Teste');
  });

  test('copyWith troca só o nome', () {
    final original = SavedGame(
      id: 'id1',
      name: 'Antigo',
      mode: GameMode.analysis,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const [],
    );

    final renamed = original.copyWith(name: 'Novo nome');

    expect(renamed.name, 'Novo nome');
    expect(renamed.id, original.id);
    expect(renamed.sanHistory, original.sanHistory);
  });
}
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `cd app && flutter test test/features/saves/saved_game_test.dart`
Expected: FAIL — `package:xadrez_fun/features/saves/saved_game.dart` não existe.

- [ ] **Step 3: Implementar**

Criar `app/lib/features/saves/saved_game.dart`:

```dart
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../play/game_controller.dart';

/// Dados completos de uma partida salva, prontos para persistir ou para
/// `GameController.loadGame` reconstruir a partida.
@immutable
class SavedGame {
  const SavedGame({
    required this.id,
    required this.name,
    required this.mode,
    required this.timestamp,
    required this.sanHistory,
    this.playerSide,
    this.skillLevel,
  });

  /// Deriva os dados de save a partir do estado corrente do jogo.
  /// `playerSide`/`skillLevel` só fazem sentido em [GameMode.playVsEngine] —
  /// em [GameMode.analysis] ficam null, igual ao `save_analysis` do Python.
  factory SavedGame.fromGameState(GameState state) {
    final isPlayVsEngine = state.mode == GameMode.playVsEngine;
    return SavedGame(
      id: state.gameId,
      name: state.gameName,
      mode: state.mode,
      timestamp: DateTime.now(),
      sanHistory: state.sanHistory,
      playerSide: isPlayVsEngine ? state.playerSide : null,
      skillLevel: isPlayVsEngine ? state.skillLevel : null,
    );
  }

  final String id;
  final String name;
  final GameMode mode;
  final DateTime timestamp;
  final List<String> sanHistory;
  final Side? playerSide;
  final int? skillLevel;

  SavedGame copyWith({String? name}) {
    return SavedGame(
      id: id,
      name: name ?? this.name,
      mode: mode,
      timestamp: timestamp,
      sanHistory: sanHistory,
      playerSide: playerSide,
      skillLevel: skillLevel,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mode': mode.name,
    'timestamp': timestamp.toIso8601String(),
    'sanHistory': sanHistory,
    'playerSide': playerSide?.name,
    'skillLevel': skillLevel,
  };

  static SavedGame fromJson(Map<String, dynamic> json) {
    final playerSideName = json['playerSide'] as String?;
    return SavedGame(
      id: json['id'] as String,
      name: json['name'] as String,
      mode: GameMode.values.byName(json['mode'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      sanHistory: (json['sanHistory'] as List).cast<String>(),
      playerSide: playerSideName == null
          ? null
          : Side.values.byName(playerSideName),
      skillLevel: json['skillLevel'] as int?,
    );
  }
}

/// Dados leves de uma partida salva, para a lista de "Partidas salvas" —
/// evita carregar o histórico inteiro só para exibir nome/modo/contagem.
@immutable
class SavedGameSummary {
  const SavedGameSummary({
    required this.id,
    required this.name,
    required this.mode,
    required this.moveCount,
    required this.timestamp,
  });

  final String id;
  final String name;
  final GameMode mode;
  final int moveCount;
  final DateTime timestamp;

  static SavedGameSummary fromJson(Map<String, dynamic> json) {
    return SavedGameSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      mode: GameMode.values.byName(json['mode'] as String),
      moveCount: (json['sanHistory'] as List).length,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `cd app && flutter test test/features/saves/saved_game_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/saves/saved_game.dart test/features/saves/saved_game_test.dart
git commit -m "feat: adiciona modelos SavedGame/SavedGameSummary"
```

---

### Task 3: `GamesRepository` + `FileGamesRepository`

**Files:**
- Modify: `app/pubspec.yaml` (dependências novas)
- Create: `app/lib/features/saves/games_repository.dart`
- Test: `app/test/features/saves/games_repository_test.dart`

**Interfaces:**
- Consumes: `SavedGame`, `SavedGameSummary` (Task 2).
- Produces: `abstract interface class GamesRepository` (`listGames`, `load`, `save`, `delete`, `rename`); `FileGamesRepository implements GamesRepository`; `gamesRepositoryProvider` (`Provider<GamesRepository>`).

- [ ] **Step 1: Adicionar as dependências**

Run:
```bash
cd app && flutter pub add path_provider
cd app && flutter pub add dev:path_provider_platform_interface
```
Expected: `pubspec.yaml` ganha `path_provider: ^2.1.5` (ou versão compatível resolvida) em `dependencies` e `path_provider_platform_interface: ^2.1.2` em `dev_dependencies`; `pubspec.lock` atualizado; comando termina sem erro.

- [ ] **Step 2: Escrever os testes que falham**

Criar `app/test/features/saves/games_repository_test.dart`:

```dart
import 'dart:io';

import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';
import 'package:xadrez_fun/features/saves/games_repository.dart';
import 'package:xadrez_fun/features/saves/saved_game.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory tempDir;
  late FileGamesRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('xadrez_fun_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    repository = FileGamesRepository();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  SavedGame makeGame({String id = 'id1', String name = 'Partida teste'}) {
    return SavedGame(
      id: id,
      name: name,
      mode: GameMode.playVsEngine,
      timestamp: DateTime.utc(2026, 7, 17, 10),
      sanHistory: const ['e4', 'e5'],
      playerSide: Side.white,
      skillLevel: 10,
    );
  }

  test('save + load faz roundtrip', () async {
    final game = makeGame();
    await repository.save(game);

    final loaded = await repository.load(game.id);

    expect(loaded, isNotNull);
    expect(loaded!.id, game.id);
    expect(loaded.name, game.name);
    expect(loaded.sanHistory, game.sanHistory);
  });

  test('load com id inexistente retorna null', () async {
    final loaded = await repository.load('nao-existe');
    expect(loaded, isNull);
  });

  test('listGames retorna vazio quando não há partidas', () async {
    final games = await repository.listGames();
    expect(games, isEmpty);
  });

  test('listGames ordena por timestamp decrescente', () async {
    await repository.save(
      SavedGame(
        id: 'old',
        name: 'Antiga',
        mode: GameMode.playVsEngine,
        timestamp: DateTime.utc(2026, 7, 1),
        sanHistory: const ['e4'],
        playerSide: Side.white,
        skillLevel: 10,
      ),
    );
    await repository.save(
      SavedGame(
        id: 'new',
        name: 'Recente',
        mode: GameMode.playVsEngine,
        timestamp: DateTime.utc(2026, 7, 17),
        sanHistory: const ['d4'],
        playerSide: Side.white,
        skillLevel: 10,
      ),
    );

    final games = await repository.listGames();

    expect(games.map((g) => g.id), ['new', 'old']);
  });

  test('listGames ignora arquivos corrompidos', () async {
    await repository.save(makeGame());
    final gamesDir = Directory('${tempDir.path}/games');
    await File('${gamesDir.path}/corrupto.json').writeAsString('{not json');

    final games = await repository.listGames();

    expect(games, hasLength(1));
    expect(games.single.id, 'id1');
  });

  test('delete remove a partida', () async {
    final game = makeGame();
    await repository.save(game);

    await repository.delete(game.id);

    expect(await repository.load(game.id), isNull);
  });

  test('delete de id inexistente não lança erro', () async {
    await repository.delete('nao-existe');
  });

  test('rename atualiza o nome preservando o resto', () async {
    final game = makeGame();
    await repository.save(game);

    await repository.rename(game.id, 'Nome novo');

    final loaded = await repository.load(game.id);
    expect(loaded!.name, 'Nome novo');
    expect(loaded.sanHistory, game.sanHistory);
  });

  test('rename de id inexistente não lança erro', () async {
    await repository.rename('nao-existe', 'Nome novo');
  });
}
```

- [ ] **Step 3: Rodar os testes e confirmar que falham**

Run: `cd app && flutter test test/features/saves/games_repository_test.dart`
Expected: FAIL — `package:xadrez_fun/features/saves/games_repository.dart` não existe.

- [ ] **Step 4: Implementar**

Criar `app/lib/features/saves/games_repository.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'saved_game.dart';

/// Acesso a partidas salvas, injetável para permitir fakes em teste.
abstract interface class GamesRepository {
  /// Lista as partidas salvas, mais recente primeiro.
  Future<List<SavedGameSummary>> listGames();

  /// Carrega os dados completos de uma partida, ou null se não existir ou
  /// estiver corrompida.
  Future<SavedGame?> load(String id);

  /// Grava (cria ou sobrescreve) uma partida.
  Future<void> save(SavedGame game);

  /// Remove uma partida, se existir.
  Future<void> delete(String id);

  /// Renomeia uma partida existente. Não faz nada se ela não existir.
  Future<void> rename(String id, String name);
}

/// Implementação em arquivo: um JSON por partida em
/// `<diretório de suporte do app>/games/<id>.json`. Formato e local
/// próprios do Flutter — não relacionados aos saves do app Python.
class FileGamesRepository implements GamesRepository {
  Future<Directory> _gamesDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/games');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File _fileFor(Directory dir, String id) => File('${dir.path}/$id.json');

  @override
  Future<void> save(SavedGame game) async {
    final dir = await _gamesDir();
    await _fileFor(dir, game.id).writeAsString(jsonEncode(game.toJson()));
  }

  @override
  Future<SavedGame?> load(String id) async {
    final dir = await _gamesDir();
    final file = _fileFor(dir, id);
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return SavedGame.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<List<SavedGameSummary>> listGames() async {
    final dir = await _gamesDir();
    final summaries = <SavedGameSummary>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        summaries.add(SavedGameSummary.fromJson(json));
      } on FormatException {
        continue;
      }
    }
    summaries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return summaries;
  }

  @override
  Future<void> delete(String id) async {
    final dir = await _gamesDir();
    final file = _fileFor(dir, id);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> rename(String id, String name) async {
    final data = await load(id);
    if (data == null) return;
    await save(data.copyWith(name: name));
  }
}

/// Repositório de partidas salvas global do app. Sobrescrito em testes com
/// um fake em memória.
final gamesRepositoryProvider = Provider<GamesRepository>(
  (ref) => FileGamesRepository(),
);
```

- [ ] **Step 5: Rodar os testes e confirmar que passam**

Run: `cd app && flutter test test/features/saves/games_repository_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
cd app && git add pubspec.yaml pubspec.lock lib/features/saves/games_repository.dart test/features/saves/games_repository_test.dart
git commit -m "feat: adiciona GamesRepository com implementação em arquivo"
```

---

### Task 4: `GameController.loadGame()`

**Files:**
- Modify: `app/lib/features/play/game_controller.dart`
- Test: `app/test/features/play/game_controller_test.dart`

**Interfaces:**
- Produces: `GameController.loadGame({required String id, required String name, required GameMode mode, required List<String> sanHistory, Side? playerSide, int? skillLevel})` (`Future<void>`).

Nota: `loadGame` recebe campos primitivos, não um `SavedGame` — mantém `game_controller.dart` sem depender da feature `saves` (o mapeamento de `SavedGame` para esses parâmetros é feito por quem chama, na tela de partidas salvas e no diálogo de retomar).

- [ ] **Step 1: Escrever os testes que falham**

Em `app/test/features/play/game_controller_test.dart`, substituir:

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

  test('detecta xeque-mate ao final da sequência de lances', () async {
```

por:

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

  test('loadGame reconstrói uma partida vs. engine salva', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);

    await controller.loadGame(
      id: 'saved-1',
      name: 'Partida salva',
      mode: GameMode.playVsEngine,
      sanHistory: const ['e4', 'e5', 'Nf3'],
      playerSide: Side.black,
      skillLevel: 5,
    );

    final state = container.read(gameControllerProvider);
    expect(state.gameId, 'saved-1');
    expect(state.gameName, 'Partida salva');
    expect(state.mode, GameMode.playVsEngine);
    expect(state.sanHistory, ['e4', 'e5', 'Nf3']);
    expect(state.playerSide, Side.black);
    expect(state.skillLevel, 5);
    expect(state.orientation, Side.black);
    expect(state.position.turn, Side.black);
  });

  test('loadGame reconstrói uma partida de análise salva', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);

    await controller.loadGame(
      id: 'saved-2',
      name: 'Análise salva',
      mode: GameMode.analysis,
      sanHistory: const ['d4', 'd5'],
    );

    final state = container.read(gameControllerProvider);
    expect(state.mode, GameMode.analysis);
    expect(state.orientation, Side.white);
    expect(state.sanHistory, ['d4', 'd5']);
  });

  test('loadGame trunca o histórico num lance inválido sem travar', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);

    await controller.loadGame(
      id: 'saved-3',
      name: 'Corrompida',
      mode: GameMode.analysis,
      sanHistory: const ['e4', 'e5', 'lixo-invalido', 'Nf3'],
    );

    final state = container.read(gameControllerProvider);
    expect(state.sanHistory, ['e4', 'e5']);
    expect(state.lastMove, isNotNull);
  });

  test('loadGame aplica o skillLevel no engine quando vs. engine', () async {
    final engine = FakeEngine('e7e5');
    final container = makeContainer(engine);
    final controller = container.read(gameControllerProvider.notifier);

    await controller.loadGame(
      id: 'saved-4',
      name: 'Skill customizado',
      mode: GameMode.playVsEngine,
      sanHistory: const [],
      playerSide: Side.white,
      skillLevel: 15,
    );

    expect(engine.skillLevels, contains(15));
  });

  test('detecta xeque-mate ao final da sequência de lances', () async {
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: FAIL — `loadGame` não existe (erro de compilação).

- [ ] **Step 3: Implementar**

Em `app/lib/features/play/game_controller.dart`, adicionar após `flipBoard()`:

```dart
  /// Carrega uma partida salva, substituindo a partida corrente. Recebe
  /// campos primitivos (não `SavedGame`) para este arquivo não depender da
  /// feature `saves` — quem chama (tela de partidas salvas, diálogo de
  /// retomar) faz o mapeamento.
  Future<void> loadGame({
    required String id,
    required String name,
    required GameMode mode,
    required List<String> sanHistory,
    Side? playerSide,
    int? skillLevel,
  }) async {
    Position position = Chess.initial;
    Move? lastMove;
    final replayed = <String>[];
    for (final san in sanHistory) {
      final move = position.parseSan(san);
      if (move == null) break;
      final (next, sanApplied) = position.makeSan(move);
      lastMove = move;
      position = next;
      replayed.add(sanApplied);
    }
    final resolvedPlayerSide = mode == GameMode.playVsEngine
        ? (playerSide ?? Side.white)
        : state.playerSide;
    final resolvedSkillLevel = mode == GameMode.playVsEngine
        ? (skillLevel ?? 10)
        : state.skillLevel;
    final orientation = mode == GameMode.playVsEngine
        ? resolvedPlayerSide
        : Side.white;
    state = GameState(
      position: position,
      sanHistory: replayed,
      playerSide: resolvedPlayerSide,
      skillLevel: resolvedSkillLevel,
      mode: mode,
      orientation: orientation,
      gameId: id,
      gameName: name,
      lastMove: lastMove,
    );
    if (mode == GameMode.playVsEngine) {
      final engine = await ref.read(engineProvider.future);
      await engine?.setSkillLevel(resolvedSkillLevel);
    }
  }
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: PASS (arquivo inteiro)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/play/game_controller.dart test/features/play/game_controller_test.dart
git commit -m "feat: adiciona GameController.loadGame"
```

---

### Task 5: `GameController.renameCurrentGame()` + `resetIfActiveGame()`

**Files:**
- Modify: `app/lib/features/play/game_controller.dart`
- Test: `app/test/features/play/game_controller_test.dart`

**Interfaces:**
- Produces: `GameController.renameCurrentGame(String name)` (`void`); `GameController.resetIfActiveGame(String deletedId)` (`Future<void>`).

- [ ] **Step 1: Escrever os testes que falham**

Em `app/test/features/play/game_controller_test.dart`, substituir:

```dart
  test('loadGame aplica o skillLevel no engine quando vs. engine', () async {
    final engine = FakeEngine('e7e5');
    final container = makeContainer(engine);
    final controller = container.read(gameControllerProvider.notifier);

    await controller.loadGame(
      id: 'saved-4',
      name: 'Skill customizado',
      mode: GameMode.playVsEngine,
      sanHistory: const [],
      playerSide: Side.white,
      skillLevel: 15,
    );

    expect(engine.skillLevels, contains(15));
  });

  test('detecta xeque-mate ao final da sequência de lances', () async {
```

por:

```dart
  test('loadGame aplica o skillLevel no engine quando vs. engine', () async {
    final engine = FakeEngine('e7e5');
    final container = makeContainer(engine);
    final controller = container.read(gameControllerProvider.notifier);

    await controller.loadGame(
      id: 'saved-4',
      name: 'Skill customizado',
      mode: GameMode.playVsEngine,
      sanHistory: const [],
      playerSide: Side.white,
      skillLevel: 15,
    );

    expect(engine.skillLevels, contains(15));
  });

  test('renameCurrentGame atualiza só o gameName', () {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    final before = container.read(gameControllerProvider);

    controller.renameCurrentGame('Novo nome');

    final after = container.read(gameControllerProvider);
    expect(after.gameName, 'Novo nome');
    expect(after.gameId, before.gameId);
  });

  test('resetIfActiveGame não faz nada se o id não é o ativo', () async {
    final container = makeContainer(FakeEngine('e7e5'));
    final controller = container.read(gameControllerProvider.notifier);
    final before = container.read(gameControllerProvider);

    await controller.resetIfActiveGame('outro-id-qualquer');

    expect(container.read(gameControllerProvider), same(before));
  });

  test(
    'resetIfActiveGame reinicia em Modo Análise quando o id ativo bate',
    () async {
      final container = makeContainer(FakeEngine('e7e5'));
      final controller = container.read(gameControllerProvider.notifier);
      controller.startAnalysisMode();
      final activeId = container.read(gameControllerProvider).gameId;

      await controller.resetIfActiveGame(activeId);

      final state = container.read(gameControllerProvider);
      expect(state.mode, GameMode.analysis);
      expect(state.sanHistory, isEmpty);
      expect(state.gameId, isNot(activeId));
    },
  );

  test(
    'resetIfActiveGame reinicia em playVsEngine preservando playerSide',
    () async {
      final container = makeContainer(FakeEngine('e2e4'));
      final controller = container.read(gameControllerProvider.notifier);
      await controller.newGame(playerSide: Side.black, skillLevel: 8);
      final activeId = container.read(gameControllerProvider).gameId;

      await controller.resetIfActiveGame(activeId);

      final state = container.read(gameControllerProvider);
      expect(state.mode, GameMode.playVsEngine);
      expect(state.playerSide, Side.black);
      expect(state.skillLevel, 8);
      // newGame com playerSide preto reabre com o lance do engine.
      expect(state.sanHistory, ['e4']);
      expect(state.gameId, isNot(activeId));
    },
  );

  test('detecta xeque-mate ao final da sequência de lances', () async {
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: FAIL — `renameCurrentGame`/`resetIfActiveGame` não existem (erro de compilação).

- [ ] **Step 3: Implementar**

Em `app/lib/features/play/game_controller.dart`, adicionar após `loadGame()`:

```dart
  /// Renomeia a partida corrente — persistida pelo AutosaveController como
  /// qualquer outra mudança de estado, sem chamada direta ao repositório
  /// aqui.
  void renameCurrentGame(String name) {
    state = state.copyWith(gameName: name);
  }

  /// Se [deletedId] for a partida ativa, reinicia para uma partida nova no
  /// mesmo modo — evita que o autosave recrie o arquivo recém-apagado no
  /// próximo lance.
  Future<void> resetIfActiveGame(String deletedId) async {
    if (state.gameId != deletedId) return;
    if (state.mode == GameMode.analysis) {
      startAnalysisMode();
    } else {
      await newGame(playerSide: state.playerSide, skillLevel: state.skillLevel);
    }
  }
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `cd app && flutter test test/features/play/game_controller_test.dart`
Expected: PASS (arquivo inteiro)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/play/game_controller.dart test/features/play/game_controller_test.dart
git commit -m "feat: adiciona renameCurrentGame e resetIfActiveGame"
```

---

### Task 6: `AutosaveController`

**Files:**
- Create: `app/lib/features/saves/autosave_controller.dart`
- Test: `app/test/features/saves/autosave_controller_test.dart`

**Interfaces:**
- Consumes: `gameControllerProvider` (Tasks 1/4/5), `gamesRepositoryProvider` (Task 3), `SavedGame.fromGameState` (Task 2).
- Produces: `autosaveControllerProvider` (`NotifierProvider<AutosaveController, int>`) — `state` é a contagem de saves concluídos (só para dar sinal observável aos testes); `AutosaveController.idle` (`Future<void>`, `@visibleForTesting`).

- [ ] **Step 1: Escrever os testes que falham**

Criar `app/test/features/saves/autosave_controller_test.dart`:

```dart
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';
import 'package:xadrez_fun/features/saves/autosave_controller.dart';
import 'package:xadrez_fun/features/saves/games_repository.dart';
import 'package:xadrez_fun/features/saves/saved_game.dart';

class FakeEngine implements ChessEngineApi {
  FakeEngine(this.reply);

  final String? reply;

  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => reply;

  @override
  Future<EngineEval?> evaluateFen(String fen) async => null;

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      const [];

  @override
  Future<void> dispose() async {}
}

class FakeGamesRepository implements GamesRepository {
  final saved = <String, SavedGame>{};

  @override
  Future<void> save(SavedGame game) async {
    saved[game.id] = game;
  }

  @override
  Future<SavedGame?> load(String id) async => saved[id];

  @override
  Future<List<SavedGameSummary>> listGames() async {
    return [
      for (final game in saved.values)
        SavedGameSummary(
          id: game.id,
          name: game.name,
          mode: game.mode,
          moveCount: game.sanHistory.length,
          timestamp: game.timestamp,
        ),
    ];
  }

  @override
  Future<void> delete(String id) async => saved.remove(id);

  @override
  Future<void> rename(String id, String name) async {
    final game = saved[id];
    if (game != null) saved[id] = game.copyWith(name: name);
  }
}

ProviderContainer makeContainer({
  ChessEngineApi? engine,
  required FakeGamesRepository repository,
}) {
  final container = ProviderContainer(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(engine)),
      gamesRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('não salva enquanto o histórico está vazio', () async {
    final repository = FakeGamesRepository();
    final container = makeContainer(repository: repository);
    container.read(autosaveControllerProvider);

    await container.read(autosaveControllerProvider.notifier).idle;

    expect(repository.saved, isEmpty);
  });

  test('salva após um lance', () async {
    final repository = FakeGamesRepository();
    final container = makeContainer(
      engine: FakeEngine('e7e5'),
      repository: repository,
    );
    container.read(autosaveControllerProvider);

    final game = container.read(gameControllerProvider.notifier);
    await game.playUserMove(Move.parse('e2e4')!);
    await container.read(autosaveControllerProvider.notifier).idle;

    final id = container.read(gameControllerProvider).gameId;
    expect(repository.saved[id]?.sanHistory, ['e4', 'e5']);
  });

  test('salva após undoMove (histórico ainda não vazio)', () async {
    final repository = FakeGamesRepository();
    final container = makeContainer(repository: repository);
    container.read(autosaveControllerProvider);

    final game = container.read(gameControllerProvider.notifier);
    game.startAnalysisMode();
    await game.playUserMove(Move.parse('e2e4')!);
    await game.playUserMove(Move.parse('e7e5')!);
    await container.read(autosaveControllerProvider.notifier).idle;

    game.undoMove();
    await container.read(autosaveControllerProvider.notifier).idle;

    final id = container.read(gameControllerProvider).gameId;
    expect(repository.saved[id]?.sanHistory, ['e4']);
  });

  test('salva após flipBoard (mesmo histórico, mesma persistência)', () async {
    final repository = FakeGamesRepository();
    final container = makeContainer(repository: repository);
    container.read(autosaveControllerProvider);

    final game = container.read(gameControllerProvider.notifier);
    game.startAnalysisMode();
    await game.playUserMove(Move.parse('e2e4')!);
    await container.read(autosaveControllerProvider.notifier).idle;
    final savesBeforeFlip = container.read(autosaveControllerProvider);

    game.flipBoard();
    await container.read(autosaveControllerProvider.notifier).idle;

    expect(
      container.read(autosaveControllerProvider),
      greaterThan(savesBeforeFlip),
    );
  });

  test('salva a partida carregada por loadGame', () async {
    final repository = FakeGamesRepository();
    final container = makeContainer(repository: repository);
    container.read(autosaveControllerProvider);

    final game = container.read(gameControllerProvider.notifier);
    await game.loadGame(
      id: 'carregada-1',
      name: 'Partida carregada',
      mode: GameMode.analysis,
      sanHistory: const ['d4', 'd5'],
    );
    await container.read(autosaveControllerProvider.notifier).idle;

    expect(repository.saved['carregada-1']?.sanHistory, ['d4', 'd5']);
  });
}
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `cd app && flutter test test/features/saves/autosave_controller_test.dart`
Expected: FAIL — `package:xadrez_fun/features/saves/autosave_controller.dart` não existe.

- [ ] **Step 3: Implementar**

Criar `app/lib/features/saves/autosave_controller.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../play/game_controller.dart';
import 'games_repository.dart';
import 'saved_game.dart';

final autosaveControllerProvider =
    NotifierProvider<AutosaveController, int>(AutosaveController.new);

/// Observa a partida e salva automaticamente a cada mudança de estado
/// relevante — mesmo padrão reativo do AnalysisController, sem acoplar
/// persistência à lógica do GameController. O estado (contagem de saves)
/// só existe para dar aos testes um sinal observável.
class AutosaveController extends Notifier<int> {
  Future<void> _inFlight = Future.value();

  /// Conclui quando o save em andamento termina (para testes).
  @visibleForTesting
  Future<void> get idle => _inFlight;

  @override
  int build() {
    ref.listen(gameControllerProvider, (_, next) => _maybeSave(next));
    return 0;
  }

  void _maybeSave(GameState game) {
    if (game.sanHistory.isEmpty) return;
    final repository = ref.read(gamesRepositoryProvider);
    _inFlight = repository.save(SavedGame.fromGameState(game)).then((_) {
      state++;
    });
  }
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `cd app && flutter test test/features/saves/autosave_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/saves/autosave_controller.dart test/features/saves/autosave_controller_test.dart
git commit -m "feat: adiciona AutosaveController"
```

---

### Task 7: `SavedGamesScreen`

**Files:**
- Create: `app/lib/features/saves/saved_games_screen.dart`
- Test: `app/test/features/saves/saved_games_screen_test.dart`

**Interfaces:**
- Consumes: `gamesRepositoryProvider` (Task 3), `gameControllerProvider`/`loadGame`/`renameCurrentGame`/`resetIfActiveGame` (Tasks 4/5).
- Produces: `SavedGamesScreen` (widget, sem parâmetros).

- [ ] **Step 1: Escrever os testes que falham**

Criar `app/test/features/saves/saved_games_screen_test.dart`:

```dart
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';
import 'package:xadrez_fun/features/saves/games_repository.dart';
import 'package:xadrez_fun/features/saves/saved_game.dart';
import 'package:xadrez_fun/features/saves/saved_games_screen.dart';

class FakeGamesRepository implements GamesRepository {
  final saved = <String, SavedGame>{};

  @override
  Future<void> save(SavedGame game) async => saved[game.id] = game;

  @override
  Future<SavedGame?> load(String id) async => saved[id];

  @override
  Future<List<SavedGameSummary>> listGames() async {
    final list = [
      for (final game in saved.values)
        SavedGameSummary(
          id: game.id,
          name: game.name,
          mode: game.mode,
          moveCount: game.sanHistory.length,
          timestamp: game.timestamp,
        ),
    ];
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Future<void> delete(String id) async => saved.remove(id);

  @override
  Future<void> rename(String id, String name) async {
    final game = saved[id];
    if (game != null) saved[id] = game.copyWith(name: name);
  }
}

Widget _makeApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: SavedGamesScreen()),
  );
}

ProviderContainer _makeContainer(FakeGamesRepository repository) {
  final container = ProviderContainer(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(null)),
      gamesRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  testWidgets('mostra mensagem quando não há partidas salvas', (
    tester,
  ) async {
    final container = _makeContainer(FakeGamesRepository());
    await tester.pumpWidget(_makeApp(container));
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma partida salva ainda.'), findsOneWidget);
  });

  testWidgets('lista as partidas salvas', (tester) async {
    final repository = FakeGamesRepository();
    repository.saved['id1'] = SavedGame(
      id: 'id1',
      name: 'Minha partida',
      mode: GameMode.analysis,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const ['e4', 'e5'],
    );
    final container = _makeContainer(repository);
    await tester.pumpWidget(_makeApp(container));
    await tester.pumpAndSettle();

    expect(find.text('Minha partida'), findsOneWidget);
    expect(find.textContaining('Modo Análise'), findsOneWidget);
    expect(find.textContaining('2 lances'), findsOneWidget);
  });

  testWidgets('tocar numa partida carrega e fecha a tela', (tester) async {
    final repository = FakeGamesRepository();
    repository.saved['id1'] = SavedGame(
      id: 'id1',
      name: 'Minha partida',
      mode: GameMode.analysis,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const ['e4', 'e5'],
    );
    final container = _makeContainer(repository);
    await tester.pumpWidget(_makeApp(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Minha partida'));
    await tester.pumpAndSettle();

    final state = container.read(gameControllerProvider);
    expect(state.gameId, 'id1');
    expect(state.sanHistory, ['e4', 'e5']);
    expect(find.byType(SavedGamesScreen), findsNothing);
  });

  testWidgets('renomear atualiza a lista', (tester) async {
    final repository = FakeGamesRepository();
    repository.saved['id1'] = SavedGame(
      id: 'id1',
      name: 'Nome antigo',
      mode: GameMode.analysis,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const ['e4'],
    );
    final container = _makeContainer(repository);
    await tester.pumpWidget(_makeApp(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Renomear'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Nome novo');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Nome novo'), findsOneWidget);
    expect(repository.saved['id1']?.name, 'Nome novo');
  });

  testWidgets('deletar remove da lista', (tester) async {
    final repository = FakeGamesRepository();
    repository.saved['id1'] = SavedGame(
      id: 'id1',
      name: 'Vai sumir',
      mode: GameMode.analysis,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const ['e4'],
    );
    final container = _makeContainer(repository);
    await tester.pumpWidget(_makeApp(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Deletar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deletar'));
    await tester.pumpAndSettle();

    expect(find.text('Vai sumir'), findsNothing);
    expect(repository.saved.containsKey('id1'), isFalse);
  });

  testWidgets(
    'deletar a partida ativa reseta o GameController para uma nova',
    (tester) async {
      final repository = FakeGamesRepository();
      final container = _makeContainer(repository);
      final activeId = container.read(gameControllerProvider).gameId;
      repository.saved[activeId] = SavedGame(
        id: activeId,
        name: 'Partida ativa',
        mode: GameMode.playVsEngine,
        timestamp: DateTime.utc(2026, 7, 17),
        sanHistory: const ['e4'],
        playerSide: Side.white,
        skillLevel: 10,
      );
      await tester.pumpWidget(_makeApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Deletar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deletar'));
      await tester.pumpAndSettle();

      final state = container.read(gameControllerProvider);
      expect(state.gameId, isNot(activeId));
      expect(state.sanHistory, isEmpty);
    },
  );
}
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `cd app && flutter test test/features/saves/saved_games_screen_test.dart`
Expected: FAIL — `package:xadrez_fun/features/saves/saved_games_screen.dart` não existe.

- [ ] **Step 3: Implementar**

Criar `app/lib/features/saves/saved_games_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../play/game_controller.dart';
import 'games_repository.dart';
import 'saved_game.dart';

/// Tela de "Partidas salvas": lista, carrega, renomeia e deleta partidas.
class SavedGamesScreen extends ConsumerStatefulWidget {
  const SavedGamesScreen({super.key});

  @override
  ConsumerState<SavedGamesScreen> createState() => _SavedGamesScreenState();
}

class _SavedGamesScreenState extends ConsumerState<SavedGamesScreen> {
  late Future<List<SavedGameSummary>> _gamesFuture;

  @override
  void initState() {
    super.initState();
    _gamesFuture = ref.read(gamesRepositoryProvider).listGames();
  }

  void _reload() {
    setState(() {
      _gamesFuture = ref.read(gamesRepositoryProvider).listGames();
    });
  }

  Future<void> _load(SavedGameSummary summary) async {
    final repository = ref.read(gamesRepositoryProvider);
    final data = await repository.load(summary.id);
    if (data == null || !mounted) return;
    await ref
        .read(gameControllerProvider.notifier)
        .loadGame(
          id: data.id,
          name: data.name,
          mode: data.mode,
          sanHistory: data.sanHistory,
          playerSide: data.playerSide,
          skillLevel: data.skillLevel,
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _rename(SavedGameSummary summary) async {
    final controller = TextEditingController(text: summary.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear partida'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || !mounted) return;

    final repository = ref.read(gamesRepositoryProvider);
    if (ref.read(gameControllerProvider).gameId == summary.id) {
      ref.read(gameControllerProvider.notifier).renameCurrentGame(newName);
    } else {
      await repository.rename(summary.id, newName);
    }
    _reload();
  }

  Future<void> _delete(SavedGameSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deletar partida?'),
        content: Text('"${summary.name}" será apagada permanentemente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final repository = ref.read(gamesRepositoryProvider);
    await repository.delete(summary.id);
    await ref
        .read(gameControllerProvider.notifier)
        .resetIfActiveGame(summary.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partidas salvas')),
      body: FutureBuilder<List<SavedGameSummary>>(
        future: _gamesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final games = snapshot.data!;
          if (games.isEmpty) {
            return const Center(child: Text('Nenhuma partida salva ainda.'));
          }
          return ListView.builder(
            itemCount: games.length,
            itemBuilder: (context, index) {
              final summary = games[index];
              final modeName = summary.mode == GameMode.analysis
                  ? 'Modo Análise'
                  : 'vs. Stockfish';
              return ListTile(
                title: Text(summary.name),
                subtitle: Text('$modeName · ${summary.moveCount} lances'),
                onTap: () => _load(summary),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Renomear',
                      onPressed: () => _rename(summary),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      tooltip: 'Deletar',
                      onPressed: () => _delete(summary),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `cd app && flutter test test/features/saves/saved_games_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/saves/saved_games_screen.dart test/features/saves/saved_games_screen_test.dart
git commit -m "feat: adiciona SavedGamesScreen"
```

---

### Task 8: Botão "Partidas salvas" em `GameControls`

**Files:**
- Modify: `app/lib/features/board/game_controls.dart`
- Test: `app/test/features/board/game_controls_test.dart`

**Interfaces:**
- Consumes: `SavedGamesScreen` (Task 7).

- [ ] **Step 1: Escrever o teste que falha**

Em `app/test/features/board/game_controls_test.dart`, substituir o bloco de imports:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/board/game_controls.dart';

class FakeEngine implements ChessEngineApi {
```

por:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/board/game_controls.dart';
import 'package:xadrez_fun/features/saves/games_repository.dart';
import 'package:xadrez_fun/features/saves/saved_game.dart';
import 'package:xadrez_fun/features/saves/saved_games_screen.dart';

class _FakeGamesRepository implements GamesRepository {
  @override
  Future<void> save(SavedGame game) async {}

  @override
  Future<SavedGame?> load(String id) async => null;

  @override
  Future<List<SavedGameSummary>> listGames() async => const [];

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> rename(String id, String name) async {}
}

class FakeEngine implements ChessEngineApi {
```

E substituir:

```dart
Widget _makeControls() {
  return ProviderScope(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(FakeEngine())),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(height: 1000, child: GameControls()),
        ),
      ),
    ),
  );
}
```

por:

```dart
Widget _makeControls() {
  return ProviderScope(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(FakeEngine())),
      gamesRepositoryProvider.overrideWithValue(_FakeGamesRepository()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(height: 1000, child: GameControls()),
        ),
      ),
    ),
  );
}
```

Depois, dentro do `main()`, adicionar após o teste `'Desfazer e Virar tabuleiro só aparecem em Modo Análise'`:

```dart
  testWidgets('botão Partidas salvas abre a tela de partidas', (
    tester,
  ) async {
    await tester.pumpWidget(_makeControls());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Partidas salvas'));
    await tester.pumpAndSettle();

    expect(find.byType(SavedGamesScreen), findsOneWidget);
  });
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `cd app && flutter test test/features/board/game_controls_test.dart`
Expected: FAIL — não existe texto `'Partidas salvas'` na árvore de widgets.

- [ ] **Step 3: Implementar**

Em `app/lib/features/board/game_controls.dart`, adicionar aos imports (entre `play` e `strategy`, ordem alfabética):

```dart
import '../analysis/analysis_panel.dart';
import '../play/game_controller.dart';
import '../strategy/strategy_panel.dart';
```

por:

```dart
import '../analysis/analysis_panel.dart';
import '../play/game_controller.dart';
import '../saves/saved_games_screen.dart';
import '../strategy/strategy_panel.dart';
```

E substituir:

```dart
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
                    Text(
                      'Lances',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
```

por:

```dart
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
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SavedGamesScreen(),
                        ),
                      ),
                      child: const Text('Partidas salvas'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Lances',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `cd app && flutter test test/features/board/game_controls_test.dart`
Expected: PASS (arquivo inteiro)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/board/game_controls.dart test/features/board/game_controls_test.dart
git commit -m "feat: botão Partidas salvas em GameControls"
```

---

### Task 9: Retomar ao abrir o app

**Files:**
- Create: `app/lib/features/saves/resume_prompt.dart`
- Modify: `app/lib/features/board/board_screen.dart`
- Test: `app/test/features/board/board_screen_test.dart`

**Interfaces:**
- Consumes: `gamesRepositoryProvider` (Task 3), `autosaveControllerProvider` (Task 6), `loadGame` (Task 4).
- Produces: `resumeCandidateProvider` (`FutureProvider<SavedGameSummary?>`).

- [ ] **Step 1: Escrever os testes que falham**

Em `app/test/features/board/board_screen_test.dart`, substituir o bloco de imports e a classe `FakeEngine`/`makeApp`:

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

class FakeEngine implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => 'e7e5';

  @override
  Future<EngineEval?> evaluateFen(String fen) async => null;

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      const [];

  @override
  Future<void> dispose() async {}
}

Widget makeApp(ChessEngineApi? engine, {EngineStatus? status}) {
  return ProviderScope(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(engine)),
      engineStatusProvider.overrideWithValue(
        status ??
            (engine == null ? const EngineNotFound() : const EngineReady()),
      ),
    ],
    child: const MaterialApp(home: BoardScreen()),
  );
}
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
import 'package:xadrez_fun/features/saves/games_repository.dart';
import 'package:xadrez_fun/features/saves/saved_game.dart';

class FakeEngine implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => 'e7e5';

  @override
  Future<EngineEval?> evaluateFen(String fen) async => null;

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      const [];

  @override
  Future<void> dispose() async {}
}

class _FakeGamesRepository implements GamesRepository {
  final saved = <String, SavedGame>{};

  @override
  Future<void> save(SavedGame game) async => saved[game.id] = game;

  @override
  Future<SavedGame?> load(String id) async => saved[id];

  @override
  Future<List<SavedGameSummary>> listGames() async {
    final list = [
      for (final game in saved.values)
        SavedGameSummary(
          id: game.id,
          name: game.name,
          mode: game.mode,
          moveCount: game.sanHistory.length,
          timestamp: game.timestamp,
        ),
    ];
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Future<void> delete(String id) async => saved.remove(id);

  @override
  Future<void> rename(String id, String name) async {
    final game = saved[id];
    if (game != null) saved[id] = game.copyWith(name: name);
  }
}

Widget makeApp(
  ChessEngineApi? engine, {
  EngineStatus? status,
  GamesRepository? repository,
}) {
  return ProviderScope(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(engine)),
      engineStatusProvider.overrideWithValue(
        status ??
            (engine == null ? const EngineNotFound() : const EngineReady()),
      ),
      gamesRepositoryProvider.overrideWithValue(
        repository ?? _FakeGamesRepository(),
      ),
    ],
    child: const MaterialApp(home: BoardScreen()),
  );
}
```

Depois, dentro do `main()`, adicionar após o teste `'Modo Análise: virar tabuleiro muda a orientação do Chessboard'` (antes do `}` que fecha `main()`):

```dart
  testWidgets('sem partida salva, não mostra diálogo de retomar', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp(FakeEngine()));
    await tester.pumpAndSettle();

    expect(find.text('Partida anterior encontrada'), findsNothing);
  });

  testWidgets(
    'com partida salva, mostra diálogo e Continuar carrega a partida',
    (tester) async {
      final repository = _FakeGamesRepository();
      repository.saved['id1'] = SavedGame(
        id: 'id1',
        name: 'Partida antiga',
        mode: GameMode.analysis,
        timestamp: DateTime.utc(2026, 7, 17),
        sanHistory: const ['e4', 'e5'],
      );
      await tester.pumpWidget(makeApp(FakeEngine(), repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Partida anterior encontrada'), findsOneWidget);

      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(BoardScreen));
      final state = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(gameControllerProvider);
      expect(state.sanHistory, ['e4', 'e5']);
    },
  );

  testWidgets('"Nova partida" no diálogo não apaga a partida salva', (
    tester,
  ) async {
    final repository = _FakeGamesRepository();
    repository.saved['id1'] = SavedGame(
      id: 'id1',
      name: 'Partida antiga',
      mode: GameMode.analysis,
      timestamp: DateTime.utc(2026, 7, 17),
      sanHistory: const ['e4', 'e5'],
    );
    await tester.pumpWidget(makeApp(FakeEngine(), repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nova partida'));
    await tester.pumpAndSettle();

    expect(repository.saved.containsKey('id1'), isTrue);
    final context = tester.element(find.byType(BoardScreen));
    final state = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(gameControllerProvider);
    expect(state.sanHistory, isEmpty);
  });
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `cd app && flutter test test/features/board/board_screen_test.dart`
Expected: FAIL — `makeApp` não aceita `repository:`; diálogo nunca aparece.

- [ ] **Step 3: Implementar**

Criar `app/lib/features/saves/resume_prompt.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'games_repository.dart';
import 'saved_game.dart';

/// Partida mais recente com lances, candidata a retomar ao abrir o app —
/// null se não houver nenhuma partida salva com histórico.
final resumeCandidateProvider = FutureProvider<SavedGameSummary?>((
  ref,
) async {
  final repository = ref.watch(gamesRepositoryProvider);
  final games = await repository.listGames();
  if (games.isEmpty || games.first.moveCount == 0) return null;
  return games.first;
});
```

Em `app/lib/features/board/board_screen.dart`, adicionar aos imports:

```dart
import '../../engine/engine_provider.dart';
import '../play/game_controller.dart';
import 'game_controls.dart';
```

por:

```dart
import '../../engine/engine_provider.dart';
import '../play/game_controller.dart';
import '../saves/autosave_controller.dart';
import '../saves/games_repository.dart';
import '../saves/resume_prompt.dart';
import '../saves/saved_game.dart';
import 'game_controls.dart';
```

Adicionar o campo `_resumePromptShown` e o método `_showResumeDialog` à `_BoardScreenState`, substituindo:

```dart
class _BoardScreenState extends ConsumerState<BoardScreen> {
  late final ChessboardController _boardController;

  @override
  void initState() {
```

por:

```dart
class _BoardScreenState extends ConsumerState<BoardScreen> {
  late final ChessboardController _boardController;
  bool _resumePromptShown = false;

  @override
  void initState() {
```

E, logo antes do método `_onMove`, substituir:

```dart
  void _onMove(Move move, {bool? viaDragAndDrop}) {
    ref.read(gameControllerProvider.notifier).playUserMove(move);
  }
```

por:

```dart
  void _onMove(Move move, {bool? viaDragAndDrop}) {
    ref.read(gameControllerProvider.notifier).playUserMove(move);
  }

  Future<void> _showResumeDialog(SavedGameSummary summary) async {
    final modeName = summary.mode == GameMode.analysis
        ? 'Modo Análise'
        : 'vs. Stockfish';
    final continuar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Partida anterior encontrada'),
        content: Text(
          '${summary.name} — $modeName, ${summary.moveCount} lances.\n'
          'Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nova partida'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (continuar != true || !mounted) return;
    final repository = ref.read(gamesRepositoryProvider);
    final data = await repository.load(summary.id);
    if (data == null || !mounted) return;
    await ref
        .read(gameControllerProvider.notifier)
        .loadGame(
          id: data.id,
          name: data.name,
          mode: data.mode,
          sanHistory: data.sanHistory,
          playerSide: data.playerSide,
          skillLevel: data.skillLevel,
        );
  }
```

Por fim, no início do `build`, substituir:

```dart
  @override
  Widget build(BuildContext context) {
    final engineAvailable = ref.watch(engineProvider).value != null;
    final status = ref.watch(engineStatusProvider);
```

por:

```dart
  @override
  Widget build(BuildContext context) {
    final engineAvailable = ref.watch(engineProvider).value != null;
    final status = ref.watch(engineStatusProvider);
    ref.watch(autosaveControllerProvider);
    ref.listen<AsyncValue<SavedGameSummary?>>(resumeCandidateProvider, (
      previous,
      next,
    ) {
      final summary = next.value;
      if (_resumePromptShown || summary == null) return;
      _resumePromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showResumeDialog(summary);
      });
    });
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `cd app && flutter test test/features/board/board_screen_test.dart`
Expected: PASS (arquivo inteiro)

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/features/saves/resume_prompt.dart lib/features/board/board_screen.dart test/features/board/board_screen_test.dart
git commit -m "feat: diálogo de retomar partida ao abrir o app"
```

---

### Task 10: Verificação final

**Files:** nenhum (apenas verificação — sem alterações de código)

- [ ] **Step 1: Rodar a suíte completa**

Run: `cd app && flutter test`
Expected: PASS — todos os testes, incluindo os das Tasks 1-9.

- [ ] **Step 2: Rodar o analisador estático**

Run: `cd app && dart analyze`
Expected: `No issues found!`

- [ ] **Step 3: Confirmar formatação**

Run: `cd app && dart format --output=none --set-exit-if-changed .`
Expected: exit code 0 (nenhum arquivo precisa de reformatação).

- [ ] **Step 4: Corrigir divergências, se houver**

Se qualquer um dos steps 1-3 falhar, corrigir o problema no arquivo indicado e repetir o step até passar. Prestar atenção especial a interações entre tasks que só aparecem rodando a suíte inteira (ex.: `ref.watch(autosaveControllerProvider)`/`resumeCandidateProvider` agora materializados em todo teste que monta `BoardScreen` — qualquer suíte fora deste plano que monte `BoardScreen` sem override de `gamesRepositoryProvider` vai quebrar e precisa do mesmo tratamento do `makeApp` da Task 9).

- [ ] **Step 5: Commit final (se houver correções do Step 4)**

```bash
cd app && git add -A
git commit -m "chore: ajustes finais de verificação de Partidas Salvas"
```

Se nenhuma correção foi necessária, não há o que commitar neste step.

**Observação:** smoke test manual (`cd app && flutter run -d macos`, testar criar partidas, salvar, listar, renomear, deletar e retomar ao reabrir) fica a critério do usuário rodar depois, como já é o padrão deste projeto.
