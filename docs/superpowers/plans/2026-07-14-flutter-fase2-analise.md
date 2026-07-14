# Fase 2 — Análise (Flutter macOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar ao app Flutter a análise de posição do app Python (avaliação cp/mate, probabilidades de vitória, eval bar e top 3 lances via MultiPV) e cumprir os compromissos do spec deferidos da Fase 1 (reinício automático do engine após crash e banner de status preciso).

**Architecture:** O cliente UCI ganha `evaluateFen` e `topMovesFromFen` (MultiPV), com serialização interna de comandos para o processo único do Stockfish. Um `AnalysisController` (Riverpod Notifier) observa a partida e reanalisa a posição quando é a vez do jogador. A matemática de probabilidades/formatação é port 1:1 de `analysis.py`. O `engineProvider` vira um `EngineManager` que respawna o processo em crash e expõe um `EngineStatus` para o banner.

**Tech Stack:** Flutter macOS, dartchess 0.13.1, chessground 10.1.1, flutter_riverpod 3.3.2, Stockfish do sistema via UCI (`Process`).

## Global Constraints

- Referência de comportamento: código Python do repositório (`analysis.py`, `engine.py`) — port 1:1 da semântica, incluindo textos.
- Profundidade de busca: `depth 12` (decisão da Fase 1, mantida para lances E análise).
- Sem dependências novas no `pubspec.yaml`; manter `dependency_overrides: meta: ^1.18.0`.
- Textos de UI em pt-BR com acentuação correta.
- Convenções de avaliação: `evaluateFen` retorna avaliação na **perspectiva das brancas** (como `stockfish` pip / `get_evaluation`); `topMovesFromFen` retorna avaliação na **perspectiva de quem joga** (como a saída pós-flip de `engine.py::get_top_moves`). Nota: o score UCI cru (`info ... score`) já vem na perspectiva de quem joga — logo top moves usa o valor cru, e `evaluateFen` inverte o sinal quando as pretas jogam.
- Todo commit passa por: `dart format` nos arquivos tocados, `flutter analyze` limpo, `flutter test` verde (rodar dentro de `app/`).
- Commits na branch `flutter-fase1` (mesma branch da Fase 1).

## File Structure

- Modify: `app/lib/engine/engine_api.dart` — modelos `EngineEval`/`EngineLine` + novos métodos da interface (Tasks 1, 2, 6)
- Modify: `app/lib/engine/uci_engine.dart` — serialização, `evaluateFen`, `topMovesFromFen`, resiliência a crash (Tasks 1, 2, 6)
- Modify: `app/lib/engine/engine_provider.dart` — `EngineManager` com restart + `EngineStatus` (Task 6)
- Create: `app/lib/features/analysis/analysis_math.dart` — probabilidades, formatação, ratio da eval bar (Task 3)
- Create: `app/lib/features/analysis/analysis_controller.dart` — `TopMove`, `AnalysisState`, `AnalysisController` (Task 4)
- Create: `app/lib/features/analysis/analysis_panel.dart` — painel de análise (Task 5)
- Modify: `app/lib/features/board/game_controls.dart` — insere o painel (Task 5)
- Modify: `app/lib/features/board/board_screen.dart` — banner por `EngineStatus` (Task 6)
- Modify: `app/lib/features/play/game_controller.dart` — reaplica skill level quando o engine é trocado (Task 6)
- Tests espelhando cada arquivo em `app/test/`.

Decisão registrada: o minor da Fase 1 "`_skill` não re-sincroniza de `state.skillLevel`" **não será corrigido** — o slider é uma seleção pendente para a *próxima* partida; `state.skillLevel` só muda via `newGame` a partir do próprio slider. Comportamento correto.

---

### Task 1: Avaliação de posição no cliente UCI (com serialização de comandos)

**Files:**
- Modify: `app/lib/engine/engine_api.dart`
- Modify: `app/lib/engine/uci_engine.dart`
- Test: `app/test/engine/uci_engine_test.dart`
- Modify (manter compilando): `app/test/features/play/game_controller_test.dart`, `app/test/features/board/board_screen_test.dart`

**Interfaces:**
- Consumes: `EngineIo` e `UciEngine` existentes (Fase 1).
- Produces: `sealed class EngineEval` com `CpEval(int cp)` e `MateEval(int moves)` (igualdade por valor, getter `flipped`); método `Future<EngineEval?> evaluateFen(String fen)` em `ChessEngineApi` (perspectiva das brancas); serialização interna `_serialized` no `UciEngine` (Tasks 2 e 4 dependem dela).

- [ ] **Step 1: Escrever os testes que falham**

Adicionar ao final de `app/test/engine/uci_engine_test.dart` (dentro de `main`, após os testes existentes):

```dart
  test('evaluateFen retorna cp na perspectiva das brancas (brancas jogam)',
      () async {
    final io = FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      'go depth': [
        'info depth 10 score cp 20 pv e2e4',
        'info depth 12 seldepth 16 multipv 1 score cp 31 nodes 5000 pv e2e4',
        'bestmove e2e4 ponder e7e5',
      ],
    });
    final engine = UciEngine(io);
    await engine.init();

    const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    final eval = await engine.evaluateFen(fen);

    // Usa a ÚLTIMA linha info antes de bestmove (maior profundidade).
    expect(eval, const CpEval(31));
    expect(io.sent, contains('position fen $fen'));
  });

  test('evaluateFen inverte o sinal quando as pretas jogam', () async {
    final io = FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      'go depth': [
        'info depth 12 score cp 40 pv e7e5',
        'bestmove e7e5',
      ],
    });
    final engine = UciEngine(io);
    await engine.init();

    // cp 40 para quem joga (pretas) = -40 na perspectiva das brancas.
    final eval = await engine.evaluateFen(
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1');
    expect(eval, const CpEval(-40));
  });

  test('evaluateFen com mate mantém a semântica de perspectiva', () async {
    final io = FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      'go depth': [
        'info depth 12 score mate 2 pv d8h4',
        'bestmove d8h4',
      ],
    });
    final engine = UciEngine(io);
    await engine.init();

    // Mate em 2 para as pretas (que jogam) = -2 na perspectiva das brancas.
    final eval = await engine
        .evaluateFen('rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2');
    expect(eval, const MateEval(-2));
  });

  test('evaluateFen sem linha de score retorna null', () async {
    final io = FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      'go depth': ['bestmove (none)'],
    });
    final engine = UciEngine(io);
    await engine.init();
    final eval = await engine.evaluateFen('8/8/8/8/8/8/8/k1K5 b - - 0 1');
    expect(eval, isNull);
  });

  test('comandos concorrentes são serializados (não intercalam)', () async {
    final io = standardIo();
    final engine = UciEngine(io);
    await engine.init();

    const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    // Dispara duas operações sem await entre elas.
    final f1 = engine.bestMoveFromFen(fen);
    final f2 = engine.evaluateFen(fen);
    await Future.wait([f1, f2]);

    // A segunda operação só enviou comandos após o bestmove da primeira:
    // sequência esperada de sends pós-handshake:
    // position, go, position, go (nunca position position go go).
    final sends = io.sent.where((c) => c.startsWith('position') || c.startsWith('go')).toList();
    expect(sends, [
      'position fen $fen',
      'go depth 12',
      'position fen $fen',
      'go depth 12',
    ]);
  });
```

Atenção: o teste de serialização exige que o `FakeEngineIo` responda a **cada** `go depth` (o fake existente já responde por prefixo a cada send — sem mudanças).

- [ ] **Step 2: Rodar e verificar falha**

Run (em `app/`): `flutter test test/engine/uci_engine_test.dart`
Expected: FAIL — erros de compilação (`evaluateFen`, `CpEval`, `MateEval` não definidos).

- [ ] **Step 3: Implementar**

Substituir o conteúdo inteiro de `app/lib/engine/engine_api.dart` por:

```dart
import 'package:flutter/foundation.dart';

/// Avaliação de uma posição pelo engine.
///
/// A perspectiva (brancas ou quem joga) é definida por quem produz o valor —
/// veja [ChessEngineApi.evaluateFen] e [ChessEngineApi.topMovesFromFen].
@immutable
sealed class EngineEval {
  const EngineEval();

  /// Mesma avaliação com o sinal invertido (troca de perspectiva).
  EngineEval get flipped;
}

/// Avaliação em centipawns (positivo = melhor para a perspectiva adotada).
final class CpEval extends EngineEval {
  const CpEval(this.cp);

  final int cp;

  @override
  CpEval get flipped => CpEval(-cp);

  @override
  bool operator ==(Object other) => other is CpEval && other.cp == cp;

  @override
  int get hashCode => cp.hashCode;

  @override
  String toString() => 'CpEval($cp)';
}

/// Mate em [moves] lances (positivo = a perspectiva adotada dá mate).
final class MateEval extends EngineEval {
  const MateEval(this.moves);

  final int moves;

  @override
  MateEval get flipped => MateEval(-moves);

  @override
  bool operator ==(Object other) => other is MateEval && other.moves == moves;

  @override
  int get hashCode => moves.hashCode;

  @override
  String toString() => 'MateEval($moves)';
}

/// Interface do engine de xadrez, injetável para permitir fakes em teste.
abstract interface class ChessEngineApi {
  /// Define o nível de habilidade (0-20).
  Future<void> setSkillLevel(int level);

  /// Melhor lance (UCI, ex.: "e2e4") para a posição, ou null se não houver.
  Future<String?> bestMoveFromFen(String fen);

  /// Avaliação da posição na perspectiva das BRANCAS (positivo = brancas
  /// melhor), como `ChessEngine.get_evaluation` do app Python.
  /// Null se o engine não emitir score (ex.: stream fechado).
  Future<EngineEval?> evaluateFen(String fen);

  /// Encerra o engine.
  Future<void> dispose();
}
```

Em `app/lib/engine/uci_engine.dart`, substituir a classe `UciEngine` inteira por (mantém `EngineIo`/`ProcessEngineIo` como estão):

```dart
/// Cliente UCI: handshake, skill level, melhor lance e avaliação.
class UciEngine implements ChessEngineApi {
  UciEngine(this._io, {this.depth = 12});

  final EngineIo _io;

  /// Profundidade de busca usada nas consultas ao engine.
  final int depth;

  Future<void> _queue = Future.value();

  static final _scoreRe = RegExp(r'score (cp|mate) (-?\d+)');

  /// Serializa operações UCI: o Stockfish é um processo único e comandos
  /// intercalados de chamadas concorrentes corromperiam as respostas.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

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
  Future<String?> bestMoveFromFen(String fen) => _serialized(() async {
        _io.send('position fen $fen');
        _io.send('go depth $depth');
        final line =
            await _io.lines.firstWhere((l) => l.startsWith('bestmove'));
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2 || parts[1] == '(none)') return null;
        return parts[1];
      });

  @override
  Future<EngineEval?> evaluateFen(String fen) => _serialized(() async {
        _io.send('position fen $fen');
        _io.send('go depth $depth');
        EngineEval? last;
        await for (final line in _io.lines) {
          final match = _scoreRe.firstMatch(line);
          if (match != null) {
            final value = int.parse(match.group(2)!);
            last = match.group(1) == 'cp' ? CpEval(value) : MateEval(value);
          }
          if (line.startsWith('bestmove')) break;
        }
        if (last == null) return null;
        // O score UCI vem na perspectiva de quem joga; convertemos para a
        // perspectiva das brancas (semântica do app Python).
        final blackToMove = fen.split(' ')[1] == 'b';
        return blackToMove ? last.flipped : last;
      });

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

Manter compilando os fakes existentes — adicionar a cada `FakeEngine*` (em `app/test/features/play/game_controller_test.dart`: classe `FakeEngine`; em `app/test/features/board/board_screen_test.dart`: classes `FakeEngine`, `FakeEngineOpeningE4`, `FakeEngineNeverReplies`):

```dart
  @override
  Future<EngineEval?> evaluateFen(String fen) async => null;
```

(Em `board_screen_test.dart` o import de `engine_api.dart` já existe; em `game_controller_test.dart` também.)

- [ ] **Step 4: Rodar e verificar que passa**

Run (em `app/`): `flutter test`
Expected: PASS — todos os testes, incluindo os 5 novos.

- [ ] **Step 5: Verificar formato e análise estática**

Run (em `app/`): `dart format lib test && flutter analyze`
Expected: sem erros nem warnings.

- [ ] **Step 6: Commit**

```bash
git add app/lib/engine/engine_api.dart app/lib/engine/uci_engine.dart app/test
git commit -m "feat: avaliação de posição no cliente UCI com serialização de comandos"
```

---

### Task 2: Top moves via MultiPV no cliente UCI

**Files:**
- Modify: `app/lib/engine/engine_api.dart`
- Modify: `app/lib/engine/uci_engine.dart`
- Test: `app/test/engine/uci_engine_test.dart`
- Modify (manter compilando): `app/test/features/play/game_controller_test.dart`, `app/test/features/board/board_screen_test.dart`

**Interfaces:**
- Consumes: `EngineEval` (`CpEval`/`MateEval`) e `_serialized` da Task 1.
- Produces: `final class EngineLine { const EngineLine({required this.uci, required this.eval}); final String uci; final EngineEval eval; }` e método `Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3})` em `ChessEngineApi` — avaliação na **perspectiva de quem joga**, ordenada por multipv (melhor primeiro).

- [ ] **Step 1: Escrever os testes que falham**

Adicionar ao final de `app/test/engine/uci_engine_test.dart` (dentro de `main`):

```dart
  test('topMovesFromFen configura MultiPV, coleta linhas e restaura', () async {
    final io = FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      'go depth': [
        'info depth 11 multipv 1 score cp 30 pv e2e4 e7e5',
        'info depth 12 multipv 1 score cp 35 nodes 9000 pv e2e4 e7e5',
        'info depth 12 multipv 2 score cp 20 nodes 9000 pv d2d4 d7d5',
        'info depth 12 multipv 3 score mate 5 nodes 9000 pv g1f3 g8f6',
        'bestmove e2e4 ponder e7e5',
      ],
    });
    final engine = UciEngine(io);
    await engine.init();

    const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    final lines = await engine.topMovesFromFen(fen, count: 3);

    expect(io.sent, contains('setoption name MultiPV value 3'));
    expect(io.sent, contains('setoption name MultiPV value 1'));
    expect(lines, hasLength(3));
    // Última linha info de cada multipv vence (maior profundidade).
    expect(lines[0].uci, 'e2e4');
    expect(lines[0].eval, const CpEval(35));
    expect(lines[1].uci, 'd2d4');
    expect(lines[1].eval, const CpEval(20));
    expect(lines[2].uci, 'g1f3');
    expect(lines[2].eval, const MateEval(5));
  });

  test('topMovesFromFen mantém a perspectiva de quem joga (pretas)', () async {
    final io = FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      'go depth': [
        'info depth 12 multipv 1 score cp 25 pv e7e5 g1f3',
        'bestmove e7e5',
      ],
    });
    final engine = UciEngine(io);
    await engine.init();

    final lines = await engine.topMovesFromFen(
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1');
    // Sem flip: cp 25 é bom para as pretas, que jogam.
    expect(lines.single.eval, const CpEval(25));
  });

  test('topMovesFromFen com promoção no pv', () async {
    final io = FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      'go depth': [
        'info depth 12 multipv 1 score cp 900 pv e7e8q d8e8',
        'bestmove e7e8q',
      ],
    });
    final engine = UciEngine(io);
    await engine.init();
    final lines =
        await engine.topMovesFromFen('4k3/4P3/8/8/8/8/8/4K3 w - - 0 1');
    expect(lines.single.uci, 'e7e8q');
  });

  test('topMovesFromFen sem linhas retorna lista vazia', () async {
    final io = FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      'go depth': ['bestmove (none)'],
    });
    final engine = UciEngine(io);
    await engine.init();
    final lines =
        await engine.topMovesFromFen('8/8/8/8/8/8/8/k1K5 b - - 0 1');
    expect(lines, isEmpty);
  });
```

- [ ] **Step 2: Rodar e verificar falha**

Run (em `app/`): `flutter test test/engine/uci_engine_test.dart`
Expected: FAIL — `topMovesFromFen` e `EngineLine` não definidos.

- [ ] **Step 3: Implementar**

Em `app/lib/engine/engine_api.dart`, adicionar após a classe `MateEval`:

```dart
/// Uma variação sugerida pelo engine: primeiro lance (UCI) e avaliação.
@immutable
final class EngineLine {
  const EngineLine({required this.uci, required this.eval});

  /// Primeiro lance da variação em notação UCI (ex.: "e2e4", "e7e8q").
  final String uci;

  /// Avaliação na perspectiva de QUEM JOGA (positivo = bom para quem joga),
  /// como a saída de `ChessEngine.get_top_moves` do app Python.
  final EngineEval eval;
}
```

E adicionar à interface `ChessEngineApi`, após `evaluateFen`:

```dart
  /// As [count] melhores variações via MultiPV, melhor primeiro.
  /// Avaliação na perspectiva de quem joga. Lista vazia se não houver lances.
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3});
```

Em `app/lib/engine/uci_engine.dart`, adicionar os regex estáticos junto a `_scoreRe`:

```dart
  static final _multipvRe = RegExp(r'\bmultipv (\d+)\b');
  static final _pvRe = RegExp(r'\bpv ([a-h][1-8][a-h][1-8][qrbn]?)');
```

E o método na classe `UciEngine`, após `evaluateFen`:

```dart
  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) =>
      _serialized(() async {
        _io.send('setoption name MultiPV value $count');
        _io.send('position fen $fen');
        _io.send('go depth $depth');
        final collected = <int, EngineLine>{};
        await for (final line in _io.lines) {
          final pvMatch = _pvRe.firstMatch(line);
          final scoreMatch = _scoreRe.firstMatch(line);
          if (pvMatch != null && scoreMatch != null) {
            final index =
                int.parse(_multipvRe.firstMatch(line)?.group(1) ?? '1');
            final value = int.parse(scoreMatch.group(2)!);
            collected[index] = EngineLine(
              uci: pvMatch.group(1)!,
              eval: scoreMatch.group(1) == 'cp'
                  ? CpEval(value)
                  : MateEval(value),
            );
          }
          if (line.startsWith('bestmove')) break;
        }
        _io.send('setoption name MultiPV value 1');
        final indices = collected.keys.toList()..sort();
        return [for (final i in indices) collected[i]!];
      });
```

Manter compilando os fakes — adicionar a cada `FakeEngine*` dos dois arquivos de teste de features:

```dart
  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      const [];
```

- [ ] **Step 4: Rodar e verificar que passa**

Run (em `app/`): `flutter test`
Expected: PASS.

- [ ] **Step 5: Verificar formato e análise estática**

Run (em `app/`): `dart format lib test && flutter analyze`
Expected: sem erros nem warnings.

- [ ] **Step 6: Commit**

```bash
git add app/lib/engine app/test
git commit -m "feat: top moves via MultiPV no cliente UCI"
```

---

### Task 3: Probabilidades de vitória e formatação (port de analysis.py)

**Files:**
- Create: `app/lib/features/analysis/analysis_math.dart`
- Test: `app/test/features/analysis/analysis_math_test.dart`

**Interfaces:**
- Consumes: `EngineEval`/`CpEval`/`MateEval` de `package:xadrez_fun/engine/engine_api.dart`.
- Produces: `typedef WinProbabilities = ({double white, double draw, double black})`; funções puras `WinProbabilities evalToWinProbability(int centipawns)`, `WinProbabilities mateToProbability(int mateIn)`, `WinProbabilities winProbabilities(EngineEval eval)`, `String formatEvaluation(EngineEval eval)`, `String signedPawns(int cp)`, `double evalBarRatio(EngineEval eval)`. Tudo na perspectiva das brancas.

- [ ] **Step 1: Escrever os testes que falham**

Criar `app/test/features/analysis/analysis_math_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/features/analysis/analysis_math.dart';

void main() {
  group('evalToWinProbability (valores validados contra analysis.py)', () {
    test('posição igual (cp 0): empate máximo de 35%', () {
      final p = evalToWinProbability(0);
      expect(p.white, closeTo(0.325, 0.0005));
      expect(p.draw, closeTo(0.35, 0.0005));
      expect(p.black, closeTo(0.325, 0.0005));
    });

    test('vantagem de 1 peão (cp 100)', () {
      final p = evalToWinProbability(100);
      expect(p.white, closeTo(0.5042, 0.0005));
      expect(p.draw, closeTo(0.2123, 0.0005));
      expect(p.black, closeTo(0.2835, 0.0005));
    });

    test('vantagem de 4 peões (cp 400)', () {
      final p = evalToWinProbability(400);
      expect(p.white, closeTo(0.8660, 0.0005));
      expect(p.draw, closeTo(0.0474, 0.0005));
      expect(p.black, closeTo(0.0866, 0.0005));
    });

    test('simetria: cp negativo espelha branco/preto', () {
      final plus = evalToWinProbability(150);
      final minus = evalToWinProbability(-150);
      expect(minus.white, closeTo(plus.black, 1e-9));
      expect(minus.black, closeTo(plus.white, 1e-9));
      expect(minus.draw, closeTo(plus.draw, 1e-9));
    });

    test('probabilidades somam 1', () {
      for (final cp in [-800, -200, 0, 50, 300, 1200]) {
        final p = evalToWinProbability(cp);
        expect(p.white + p.draw + p.black, closeTo(1.0, 1e-9));
      }
    });
  });

  group('mateToProbability', () {
    test('mate positivo: brancas 100%', () {
      expect(mateToProbability(3), (white: 1.0, draw: 0.0, black: 0.0));
    });

    test('mate negativo ou zero: pretas 100%', () {
      expect(mateToProbability(-2).black, 1.0);
      // mate 0 = quem joga está em mate; segue a semântica do Python
      // (value > 0 é o único caso de brancas).
      expect(mateToProbability(0).black, 1.0);
    });
  });

  group('winProbabilities (despacho por tipo)', () {
    test('CpEval usa a fórmula logística', () {
      expect(winProbabilities(const CpEval(0)).draw, closeTo(0.35, 0.0005));
    });

    test('MateEval usa probabilidade de mate', () {
      expect(winProbabilities(const MateEval(4)).white, 1.0);
    });
  });

  group('formatEvaluation (mesmos textos do analysis.py)', () {
    test('mate', () {
      expect(formatEvaluation(const MateEval(3)), 'Mate em 3 (Brancas)');
      expect(formatEvaluation(const MateEval(-2)), 'Mate em 2 (Pretas)');
    });

    test('faixas de centipawns', () {
      expect(formatEvaluation(const CpEval(10)), '+0.10 (Posição igual)');
      expect(formatEvaluation(const CpEval(30)), '+0.30 (Posição equilibrada)');
      expect(
          formatEvaluation(const CpEval(80)), '+0.80 (Brancas ligeiramente melhor)');
      expect(
          formatEvaluation(const CpEval(200)), '+2.00 (Brancas com clara vantagem)');
      expect(formatEvaluation(const CpEval(350)),
          '+3.50 (Brancas com vantagem decisiva)');
      expect(formatEvaluation(const CpEval(-80)),
          '-0.80 (Pretas ligeiramente melhor)');
      expect(formatEvaluation(const CpEval(-200)),
          '-2.00 (Pretas com clara vantagem)');
      expect(formatEvaluation(const CpEval(-350)),
          '-3.50 (Pretas com vantagem decisiva)');
    });
  });

  group('signedPawns', () {
    test('formata com sinal e duas casas', () {
      expect(signedPawns(35), '+0.35');
      expect(signedPawns(-120), '-1.20');
      expect(signedPawns(0), '+0.00');
    });
  });

  group('evalBarRatio', () {
    test('cp 0 fica no meio', () {
      expect(evalBarRatio(const CpEval(0)), closeTo(0.5, 1e-9));
    });

    test('clamp em ±1000', () {
      expect(evalBarRatio(const CpEval(2000)),
          closeTo(evalBarRatio(const CpEval(1000)), 1e-9));
      expect(evalBarRatio(const CpEval(1000)), closeTo(0.9968, 0.0005));
      expect(evalBarRatio(const CpEval(-1000)), closeTo(0.0032, 0.0005));
    });

    test('mate enche a barra do lado vencedor', () {
      expect(evalBarRatio(const MateEval(2)), 1.0);
      expect(evalBarRatio(const MateEval(-2)), 0.0);
      expect(evalBarRatio(const MateEval(0)), 0.0);
    });
  });
}
```

- [ ] **Step 2: Rodar e verificar falha**

Run (em `app/`): `flutter test test/features/analysis/analysis_math_test.dart`
Expected: FAIL — arquivo `analysis_math.dart` não existe.

- [ ] **Step 3: Implementar**

Criar `app/lib/features/analysis/analysis_math.dart`:

```dart
import 'dart:math';

import 'package:xadrez_fun/engine/engine_api.dart';

/// Probabilidades (brancas vencem, empate, pretas vencem). Somam 1.
typedef WinProbabilities = ({double white, double draw, double black});

/// Converte avaliação em centipawns (perspectiva das brancas) em
/// probabilidades de resultado. Port 1:1 de
/// `analysis.eval_to_win_probability`.
WinProbabilities evalToWinProbability(int centipawns) {
  final pawns = centipawns / 100;

  // Fórmula logística: win_prob = 1 / (1 + 10^(-eval/400))
  final winProb = 1 / (1 + pow(10, -pawns / 4));

  // Probabilidade de empate decai com a vantagem (máx. ~35% em posições
  // iguais).
  final drawProb = 0.35 * exp(-pawns.abs() / 2);

  final remaining = 1 - drawProb;
  return (
    white: winProb * remaining,
    draw: drawProb,
    black: (1 - winProb) * remaining,
  );
}

/// Mate em N: certeza para o lado que dá mate. Port 1:1 de
/// `analysis.mate_to_probability` (value > 0 é o único caso de brancas).
WinProbabilities mateToProbability(int mateIn) {
  return mateIn > 0
      ? (white: 1.0, draw: 0.0, black: 0.0)
      : (white: 0.0, draw: 0.0, black: 1.0);
}

/// Despacha para a fórmula certa conforme o tipo da avaliação
/// (perspectiva das brancas).
WinProbabilities winProbabilities(EngineEval eval) => switch (eval) {
      CpEval(:final cp) => evalToWinProbability(cp),
      MateEval(:final moves) => mateToProbability(moves),
    };

/// Centipawns como peões com sinal e duas casas, ex.: "+0.35", "-1.20".
String signedPawns(int cp) {
  final value = cp / 100;
  final text = value.abs().toStringAsFixed(2);
  return value < 0 ? '-$text' : '+$text';
}

/// Texto da avaliação (perspectiva das brancas), mesmos textos de
/// `analysis.format_evaluation`.
String formatEvaluation(EngineEval eval) => switch (eval) {
      MateEval(:final moves) => moves > 0
          ? 'Mate em $moves (Brancas)'
          : 'Mate em ${moves.abs()} (Pretas)',
      CpEval(:final cp) => '${signedPawns(cp)} (${_cpDescription(cp)})',
    };

String _cpDescription(int cp) {
  final pawns = cp / 100;
  if (pawns.abs() < 0.2) return 'Posição igual';
  if (pawns > 3) return 'Brancas com vantagem decisiva';
  if (pawns > 1.5) return 'Brancas com clara vantagem';
  if (pawns > 0.5) return 'Brancas ligeiramente melhor';
  if (pawns < -3) return 'Pretas com vantagem decisiva';
  if (pawns < -1.5) return 'Pretas com clara vantagem';
  if (pawns < -0.5) return 'Pretas ligeiramente melhor';
  return 'Posição equilibrada';
}

/// Fração da barra de avaliação ocupada pelas brancas, em [0, 1].
/// Mesma curva de `analysis.format_eval_bar` (clamp em ±1000);
/// mate enche a barra do lado vencedor.
double evalBarRatio(EngineEval eval) => switch (eval) {
      MateEval(:final moves) => moves > 0 ? 1.0 : 0.0,
      CpEval(:final cp) =>
        1 / (1 + pow(10, -cp.clamp(-1000, 1000) / 400)),
    };
```

- [ ] **Step 4: Rodar e verificar que passa**

Run (em `app/`): `flutter test test/features/analysis/analysis_math_test.dart`
Expected: PASS.

- [ ] **Step 5: Rodar todos os testes, formato e análise estática**

Run (em `app/`): `flutter test && dart format lib test && flutter analyze`
Expected: tudo verde/limpo.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/analysis app/test/features/analysis
git commit -m "feat: probabilidades de vitória e formatação da avaliação (port de analysis.py)"
```

---

### Task 4: Estado de análise reativo à partida (AnalysisController)

**Files:**
- Create: `app/lib/features/analysis/analysis_controller.dart`
- Test: `app/test/features/analysis/analysis_controller_test.dart`

**Interfaces:**
- Consumes: `ChessEngineApi.evaluateFen`/`topMovesFromFen` (Tasks 1–2); `analysis_math.dart` (Task 3); `gameControllerProvider`/`GameState` e `engineProvider` (Fase 1).
- Produces: `TopMove { String san; String uci; String evalText; }`; `AnalysisState { bool analyzing; EngineEval? eval; String? evalText; WinProbabilities? probabilities; List<TopMove> topMoves; }`; `analysisControllerProvider` (`NotifierProvider<AnalysisController, AnalysisState>`); getter `@visibleForTesting Future<void> get idle` para os testes aguardarem a análise em andamento.

Regras de disparo (decisões de design):
- Analisa a posição **quando é a vez do jogador** ou quando a partida terminou — evita gastar o engine analisando a posição intermediária enquanto o Stockfish pensa a resposta (as consultas são serializadas com o `bestmove`).
- Nunca analisa a mesma FEN duas vezes seguidas (`_lastAnalyzedFen`).
- Resultado é descartado se a posição mudou durante a análise (comparação de FEN).
- Sem engine (`null`): estado permanece vazio.

- [ ] **Step 1: Escrever os testes que falham**

Criar `app/test/features/analysis/analysis_controller_test.dart`:

```dart
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/analysis/analysis_controller.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';

/// Engine fake com respostas de análise roteirizadas.
class FakeAnalysisEngine implements ChessEngineApi {
  FakeAnalysisEngine({
    this.bestMove,
    this.eval = const CpEval(31),
    this.lines = const [EngineLine(uci: 'e2e4', eval: CpEval(31))],
  });

  final String? bestMove;
  final EngineEval? eval;
  final List<EngineLine> lines;
  final evaluatedFens = <String>[];

  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => bestMove;

  @override
  Future<EngineEval?> evaluateFen(String fen) async {
    evaluatedFens.add(fen);
    return eval;
  }

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      lines;

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

/// Drena microtasks até a análise corrente terminar.
Future<void> settle(ProviderContainer container) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
    await container.read(analysisControllerProvider.notifier).idle;
  }
}

void main() {
  test('analisa a posição inicial quando o engine está pronto', () async {
    final engine = FakeAnalysisEngine();
    final container = makeContainer(engine);

    // Materializa o provider (dispara a análise inicial).
    container.read(analysisControllerProvider);
    await settle(container);

    final state = container.read(analysisControllerProvider);
    expect(state.eval, const CpEval(31));
    expect(state.evalText, '+0.31 (Posição equilibrada)');
    expect(state.probabilities, isNotNull);
    expect(state.topMoves.single.san, 'e4');
    expect(state.topMoves.single.evalText, '+0.31');
    expect(state.analyzing, isFalse);
  });

  test('sem engine, estado permanece vazio', () async {
    final container = makeContainer(null);
    container.read(analysisControllerProvider);
    await settle(container);

    final state = container.read(analysisControllerProvider);
    expect(state.eval, isNull);
    expect(state.topMoves, isEmpty);
  });

  test('reanalisa após o ciclo lance do jogador + resposta do engine',
      () async {
    final engine = FakeAnalysisEngine(bestMove: 'e7e5');
    final container = makeContainer(engine);
    container.read(analysisControllerProvider);
    await settle(container);
    engine.evaluatedFens.clear();

    final game = container.read(gameControllerProvider.notifier);
    await game.playUserMove(Move.parse('e2e4')!);
    await settle(container);

    // Analisou a posição resultante (vez do jogador de novo, após e5),
    // e NÃO a intermediária (vez do engine).
    final fenAfterReply =
        container.read(gameControllerProvider).position.fen;
    expect(engine.evaluatedFens, [fenAfterReply]);
  });

  test('não repete análise da mesma posição', () async {
    final engine = FakeAnalysisEngine();
    final container = makeContainer(engine);
    container.read(analysisControllerProvider);
    await settle(container);
    await settle(container);

    expect(engine.evaluatedFens, hasLength(1));
  });

  test('mate na avaliação vira texto e probabilidade de mate', () async {
    final engine = FakeAnalysisEngine(
      eval: const MateEval(-2),
      // g1f3 é legal na posição inicial (o lance em si não importa aqui,
      // mas precisa ser legal para virar TopMove).
      lines: const [EngineLine(uci: 'g1f3', eval: MateEval(2))],
    );
    final container = makeContainer(engine);
    container.read(analysisControllerProvider);
    await settle(container);

    final state = container.read(analysisControllerProvider);
    expect(state.evalText, 'Mate em 2 (Pretas)');
    expect(state.probabilities!.black, 1.0);
    // Top move na perspectiva de quem joga: M2.
    expect(state.topMoves.single.evalText, 'M2');
  });
}
```

- [ ] **Step 2: Rodar e verificar falha**

Run (em `app/`): `flutter test test/features/analysis/analysis_controller_test.dart`
Expected: FAIL — `analysis_controller.dart` não existe.

- [ ] **Step 3: Implementar**

Criar `app/lib/features/analysis/analysis_controller.dart`:

```dart
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_api.dart';
import '../../engine/engine_provider.dart';
import '../play/game_controller.dart';
import 'analysis_math.dart';

/// Lance sugerido pelo engine, pronto para exibição.
@immutable
class TopMove {
  const TopMove({required this.san, required this.uci, required this.evalText});

  final String san;
  final String uci;

  /// Avaliação na perspectiva de quem joga, ex.: "+0.35" ou "M3".
  final String evalText;
}

/// Estado da análise da posição corrente (perspectiva das brancas).
@immutable
class AnalysisState {
  const AnalysisState({
    this.analyzing = false,
    this.eval,
    this.evalText,
    this.probabilities,
    this.topMoves = const [],
  });

  final bool analyzing;
  final EngineEval? eval;
  final String? evalText;
  final WinProbabilities? probabilities;
  final List<TopMove> topMoves;

  AnalysisState copyWith({bool? analyzing}) {
    return AnalysisState(
      analyzing: analyzing ?? this.analyzing,
      eval: eval,
      evalText: evalText,
      probabilities: probabilities,
      topMoves: topMoves,
    );
  }
}

final analysisControllerProvider =
    NotifierProvider<AnalysisController, AnalysisState>(
        AnalysisController.new);

/// Observa a partida e mantém a análise da posição que o jogador enfrenta.
class AnalysisController extends Notifier<AnalysisState> {
  String? _lastAnalyzedFen;
  Future<void> _inFlight = Future.value();

  /// Conclui quando a análise em andamento termina (para testes).
  @visibleForTesting
  Future<void> get idle => _inFlight;

  @override
  AnalysisState build() {
    ref.listen(gameControllerProvider, (_, next) => _maybeAnalyze(next));
    ref.listen(engineProvider, (_, next) {
      if (next.hasValue) _maybeAnalyze(ref.read(gameControllerProvider));
    });
    Future.microtask(() => _maybeAnalyze(ref.read(gameControllerProvider)));
    return const AnalysisState();
  }

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

  Future<void> _analyze(String fen, Position position) async {
    final engine = await ref.read(engineProvider.future);
    if (engine == null) {
      _lastAnalyzedFen = null; // permite reanalisar quando o engine chegar
      return;
    }
    state = state.copyWith(analyzing: true);
    try {
      final eval = await engine.evaluateFen(fen);
      final lines = await engine.topMovesFromFen(fen, count: 3);
      // Descarta resultado obsoleto: a posição mudou durante a análise.
      if (ref.read(gameControllerProvider).position.fen != fen) return;
      if (eval == null) {
        state = const AnalysisState();
        return;
      }
      state = AnalysisState(
        eval: eval,
        evalText: formatEvaluation(eval),
        probabilities: winProbabilities(eval),
        topMoves: [
          for (final line in lines)
            if (_toTopMove(line, position) case final move?) move,
        ],
      );
    } finally {
      if (state.analyzing) state = state.copyWith(analyzing: false);
    }
  }

  TopMove? _toTopMove(EngineLine line, Position position) {
    final move = Move.parse(line.uci);
    if (move == null || !position.isLegal(move)) return null;
    final (_, san) = position.makeSan(move);
    return TopMove(san: san, uci: line.uci, evalText: _evalText(line.eval));
  }

  /// Mesmo formato de `engine.py::get_top_moves` (perspectiva de quem joga).
  String _evalText(EngineEval eval) => switch (eval) {
        MateEval(:final moves) =>
          moves > 0 ? 'M$moves' : '-M${moves.abs()}',
        CpEval(:final cp) => signedPawns(cp),
      };
}
```

- [ ] **Step 4: Rodar e verificar que passa**

Run (em `app/`): `flutter test test/features/analysis/analysis_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Rodar todos os testes, formato e análise estática**

Run (em `app/`): `flutter test && dart format lib test && flutter analyze`
Expected: tudo verde/limpo.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/analysis app/test/features/analysis
git commit -m "feat: estado de análise reativo à partida"
```

---

### Task 5: Painel de análise (eval bar, probabilidades, top moves)

**Files:**
- Create: `app/lib/features/analysis/analysis_panel.dart`
- Modify: `app/lib/features/board/game_controls.dart`
- Test: `app/test/features/analysis/analysis_panel_test.dart`

**Interfaces:**
- Consumes: `analysisControllerProvider`/`AnalysisState`/`TopMove` (Task 4); `evalBarRatio`/`WinProbabilities` (Task 3); `engineProvider` (Fase 1).
- Produces: widgets `AnalysisPanel`, `EvalBar { double ratio }`, `ProbabilityBar { WinProbabilities probabilities }` — usados por `GameControls`.

- [ ] **Step 1: Escrever os testes que falham**

Criar `app/test/features/analysis/analysis_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_api.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/features/analysis/analysis_controller.dart';
import 'package:xadrez_fun/features/analysis/analysis_panel.dart';

class FakeEngine implements ChessEngineApi {
  @override
  Future<void> setSkillLevel(int level) async {}

  @override
  Future<String?> bestMoveFromFen(String fen) async => null;

  @override
  Future<EngineEval?> evaluateFen(String fen) async => null;

  @override
  Future<List<EngineLine>> topMovesFromFen(String fen, {int count = 3}) async =>
      const [];

  @override
  Future<void> dispose() async {}
}

/// Controller stub: devolve um estado fixo, sem ouvir a partida.
class StubAnalysisController extends AnalysisController {
  StubAnalysisController(this._stub);

  final AnalysisState _stub;

  @override
  AnalysisState build() => _stub;
}

Widget makePanel(AnalysisState state, {ChessEngineApi? engine}) {
  return ProviderScope(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(engine)),
      analysisControllerProvider
          .overrideWith(() => StubAnalysisController(state)),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 280, child: AnalysisPanel()),
      ),
    ),
  );
}

void main() {
  const analyzedState = AnalysisState(
    eval: CpEval(31),
    evalText: '+0.31 (Posição equilibrada)',
    probabilities: (white: 0.4, draw: 0.3, black: 0.3),
    topMoves: [
      TopMove(san: 'e4', uci: 'e2e4', evalText: '+0.31'),
      TopMove(san: 'd4', uci: 'd2d4', evalText: '+0.20'),
    ],
  );

  testWidgets('mostra avaliação, barra, probabilidades e top moves',
      (tester) async {
    await tester.pumpWidget(makePanel(analyzedState, engine: FakeEngine()));
    await tester.pumpAndSettle();

    expect(find.text('+0.31 (Posição equilibrada)'), findsOneWidget);
    expect(find.byType(EvalBar), findsOneWidget);
    expect(find.byType(ProbabilityBar), findsOneWidget);
    expect(find.textContaining('⬜ 40%'), findsOneWidget);
    // Primeiro lance destacado com estrela; segundo sem.
    expect(find.text('★ e4 (+0.31)'), findsOneWidget);
    expect(find.text('d4 (+0.20)'), findsOneWidget);
  });

  testWidgets('sem engine, o painel some', (tester) async {
    await tester.pumpWidget(makePanel(analyzedState, engine: null));
    await tester.pumpAndSettle();

    expect(find.byType(EvalBar), findsNothing);
    expect(find.text('Análise'), findsNothing);
  });

  testWidgets('enquanto analisa, mostra indicador de progresso',
      (tester) async {
    const analyzing = AnalysisState(analyzing: true);
    await tester.pumpWidget(makePanel(analyzing, engine: FakeEngine()));
    // Sem pumpAndSettle: o indicador anima para sempre.
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Aguardando análise…'), findsOneWidget);
  });

  testWidgets('mate enche a barra do lado vencedor', (tester) async {
    const mateState = AnalysisState(
      eval: MateEval(3),
      evalText: 'Mate em 3 (Brancas)',
      probabilities: (white: 1.0, draw: 0.0, black: 0.0),
    );
    await tester.pumpWidget(makePanel(mateState, engine: FakeEngine()));
    await tester.pumpAndSettle();

    final bar = tester.widget<EvalBar>(find.byType(EvalBar));
    expect(bar.ratio, 1.0);
    expect(find.text('Mate em 3 (Brancas)'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Rodar e verificar falha**

Run (em `app/`): `flutter test test/features/analysis/analysis_panel_test.dart`
Expected: FAIL — `analysis_panel.dart` não existe.

- [ ] **Step 3: Implementar o painel**

Criar `app/lib/features/analysis/analysis_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_provider.dart';
import 'analysis_controller.dart';
import 'analysis_math.dart';

/// Painel de análise: eval bar, avaliação, probabilidades e top moves.
class AnalysisPanel extends ConsumerWidget {
  const AnalysisPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(analysisControllerProvider);
    final engineAvailable = ref.watch(engineProvider).value != null;
    if (!engineAvailable) return const SizedBox.shrink();

    final eval = analysis.eval;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Análise', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (analysis.analyzing)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (eval == null)
          const Text('Aguardando análise…')
        else ...[
          EvalBar(ratio: evalBarRatio(eval)),
          const SizedBox(height: 4),
          Text(analysis.evalText ?? ''),
          if (analysis.probabilities case final probs?) ...[
            const SizedBox(height: 8),
            ProbabilityBar(probabilities: probs),
          ],
          if (analysis.topMoves.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Melhores lances',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (final (i, move) in analysis.topMoves.indexed)
              Text(
                i == 0
                    ? '★ ${move.san} (${move.evalText})'
                    : '${move.san} (${move.evalText})',
              ),
          ],
        ],
      ],
    );
  }
}

/// Barra horizontal de avaliação: fração branca à esquerda, resto preto.
class EvalBar extends StatelessWidget {
  const EvalBar({super.key, required this.ratio});

  /// Fração da barra ocupada pelas brancas, em [0, 1].
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 12,
        color: Colors.black87,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: ratio.clamp(0.0, 1.0),
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );
  }
}

/// Barra de probabilidades (brancas/empate/pretas) com legenda percentual.
class ProbabilityBar extends StatelessWidget {
  const ProbabilityBar({super.key, required this.probabilities});

  final WinProbabilities probabilities;

  @override
  Widget build(BuildContext context) {
    final white = (probabilities.white * 1000).round();
    final draw = (probabilities.draw * 1000).round();
    final black = (probabilities.black * 1000).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (white > 0)
                  Expanded(
                    flex: white,
                    child: const ColoredBox(color: Colors.white),
                  ),
                if (draw > 0)
                  Expanded(
                    flex: draw,
                    child: const ColoredBox(color: Colors.grey),
                  ),
                if (black > 0)
                  Expanded(
                    flex: black,
                    child: const ColoredBox(color: Colors.black87),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '⬜ ${(probabilities.white * 100).round()}%   '
          '= ${(probabilities.draw * 100).round()}%   '
          '⬛ ${(probabilities.black * 100).round()}%',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
```

Em `app/lib/features/board/game_controls.dart`, adicionar o import (junto aos existentes):

```dart
import '../analysis/analysis_panel.dart';
```

E inserir o painel na `Column`, entre o segundo `FilledButton.tonal` e a seção "Lances" — o trecho:

```dart
            const SizedBox(height: 24),
            Text('Lances', style: Theme.of(context).textTheme.titleSmall),
```

vira:

```dart
            const SizedBox(height: 24),
            const AnalysisPanel(),
            const SizedBox(height: 24),
            Text('Lances', style: Theme.of(context).textTheme.titleSmall),
```

- [ ] **Step 4: Rodar e verificar que passa**

Run (em `app/`): `flutter test test/features/analysis/analysis_panel_test.dart`
Expected: PASS.

- [ ] **Step 5: Rodar todos os testes, formato e análise estática**

Run (em `app/`): `flutter test && dart format lib test && flutter analyze`
Expected: tudo verde/limpo. Atenção: os testes existentes de `board_screen_test.dart` agora renderizam o painel dentro de `GameControls`; os fakes deles retornam `evaluateFen == null`, então o painel mostra "Aguardando análise…" sem quebrar os asserts existentes. Se algum teste existente falhar por `pumpAndSettle` (indicador de progresso animando), trocar aquele `pumpAndSettle` por dois `pump()` e registrar no relatório.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features app/test/features
git commit -m "feat: painel de análise (eval bar, probabilidades, top moves)"
```

---

### Task 6: Reinício automático do engine após crash + banner de status preciso

**Files:**
- Modify: `app/lib/engine/uci_engine.dart`
- Modify: `app/lib/engine/engine_provider.dart`
- Modify: `app/lib/features/board/board_screen.dart`
- Modify: `app/lib/features/play/game_controller.dart`
- Test: `app/test/engine/uci_engine_test.dart`, `app/test/engine/engine_provider_test.dart` (novo), `app/test/features/board/board_screen_test.dart`

**Interfaces:**
- Consumes: `UciEngine`, `EngineIo`, `engineProvider` e consumidores existentes.
- Produces: `EngineIo.onExit` (`Future<void>`); `UciEngine.onExit` e `UciEngine.isDisposed`; `sealed class EngineStatus` (`EngineSearching`, `EngineReady`, `EngineNotFound`, `EngineFailed(String message)`, `EngineRestarted(int count)`); `EngineSession { ChessEngineApi? engine; EngineStatus status; }`; providers `engineManagerProvider`, `stockfishPathProvider`, `engineFactoryProvider`, `engineStatusProvider`; `engineProvider` mantém tipo `FutureProvider<ChessEngineApi?>` (compatível com overrides existentes nos testes).

Decisões:
- `onExit`/`isDisposed` ficam no **`UciEngine` concreto** (não na interface `ChessEngineApi`) — o `EngineManager` é o único consumidor, e assim os fakes de `ChessEngineApi` dos outros testes não mudam.
- Limite de `kMaxEngineRestarts = 5` reinícios automáticos; depois disso, `EngineFailed` e tabuleiro livre (evita loop infinito de respawn se o binário morrer sempre na largada).
- Ao trocar de engine (reinício), o `GameController` reaplica o skill level da partida em curso via `ref.listen(engineProvider, ...)`.

- [ ] **Step 1: Adicionar testes que falham**

Em `app/test/engine/uci_engine_test.dart`, atualizar o `FakeEngineIo` para suportar exit — adicionar os membros abaixo à classe (o `kill()` existente passa a completar o exit):

```dart
  final _exit = Completer<void>();

  @override
  Future<void> get onExit => _exit.future;

  /// Simula crash do processo: fecha o stdout e sinaliza exit.
  Future<void> crash() async {
    if (!_exit.isCompleted) _exit.complete();
    await _controller.close();
  }
```

E alterar `kill()` para:

```dart
  @override
  Future<void> kill() async {
    killed = true;
    if (!_exit.isCompleted) _exit.complete();
    await _controller.close();
  }
```

Adicionar ao final do `main` de `uci_engine_test.dart`:

```dart
  test('bestMoveFromFen retorna null se o engine morre no meio da consulta',
      () async {
    final io = FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      // sem resposta ao 'go depth': a consulta fica pendente
    });
    final engine = UciEngine(io);
    await engine.init();

    final pending = engine.bestMoveFromFen(
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
    await io.crash();

    expect(await pending, isNull);
  });

  test('isDisposed distingue encerramento intencional de crash', () async {
    final io = standardIo();
    final engine = UciEngine(io);
    await engine.init();

    expect(engine.isDisposed, isFalse);
    await engine.dispose();
    expect(engine.isDisposed, isTrue);
  });

  test('onExit conclui quando o processo termina', () async {
    final io = standardIo();
    final engine = UciEngine(io);
    await engine.init();

    var exited = false;
    unawaited(engine.onExit.then((_) => exited = true));
    await engine.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(exited, isTrue);
  });
```

(Adicionar `import 'dart:async';` já existe no arquivo — conferir; `unawaited` vem de `dart:async`.)

Criar `app/test/engine/engine_provider_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/engine_provider.dart';
import 'package:xadrez_fun/engine/uci_engine.dart';

/// Fake de EngineIo com respostas roteirizadas e crash simulável
/// (mesma estrutura do fake de uci_engine_test.dart).
class FakeEngineIo implements EngineIo {
  FakeEngineIo(this.responses);

  final Map<String, List<String>> responses;
  final sent = <String>[];
  final _controller = StreamController<String>.broadcast();
  final _exit = Completer<void>();
  bool killed = false;

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Future<void> get onExit => _exit.future;

  @override
  void send(String command) {
    sent.add(command);
    Future.microtask(() {
      if (_controller.isClosed) return;
      for (final entry in responses.entries) {
        if (command.startsWith(entry.key)) {
          entry.value.forEach(_controller.add);
        }
      }
    });
  }

  @override
  Future<void> kill() async {
    killed = true;
    if (!_exit.isCompleted) _exit.complete();
    await _controller.close();
  }

  Future<void> crash() async {
    if (!_exit.isCompleted) _exit.complete();
    await _controller.close();
  }
}

FakeEngineIo _standardIo() => FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      'go depth': ['bestmove e2e4'],
    });

/// Drena microtasks para o manager processar exits e respawns.
/// (Nome próprio para não colidir com o `pumpEventQueue` do flutter_test.)
Future<void> drainMicrotasks() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late List<FakeEngineIo> ios;
  var spawnCalls = 0;

  Future<UciEngine> fakeFactory(String path) async {
    spawnCalls++;
    final io = _standardIo();
    ios.add(io);
    final engine = UciEngine(io);
    await engine.init();
    return engine;
  }

  ProviderContainer makeContainer({
    String? path = '/fake/stockfish',
    Future<UciEngine> Function(String)? factory,
  }) {
    final container = ProviderContainer(
      overrides: [
        stockfishPathProvider.overrideWithValue(() => path),
        engineFactoryProvider.overrideWithValue(factory ?? fakeFactory),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    ios = [];
    spawnCalls = 0;
  });

  test('binário ausente: EngineNotFound e engine null', () async {
    final container = makeContainer(path: null);
    final session = await container.read(engineManagerProvider.future);
    expect(session.engine, isNull);
    expect(session.status, const EngineNotFound());
    expect(await container.read(engineProvider.future), isNull);
  });

  test('spawn ok: EngineReady e engine disponível', () async {
    final container = makeContainer();
    final session = await container.read(engineManagerProvider.future);
    expect(session.engine, isNotNull);
    expect(session.status, const EngineReady());
    expect(container.read(engineStatusProvider), const EngineReady());
    expect(spawnCalls, 1);
  });

  test('crash: respawna, status EngineRestarted e engine novo', () async {
    final container = makeContainer();
    final first = await container.read(engineManagerProvider.future);

    await ios.first.crash();
    await drainMicrotasks();

    final session = container.read(engineManagerProvider).requireValue;
    expect(session.status, const EngineRestarted(1));
    expect(session.engine, isNotNull);
    expect(identical(session.engine, first.engine), isFalse);
    expect(spawnCalls, 2);
    expect(await container.read(engineProvider.future), session.engine);
  });

  test('dispose intencional não dispara respawn', () async {
    final container = makeContainer();
    final session = await container.read(engineManagerProvider.future);

    await (session.engine! as UciEngine).dispose();
    await drainMicrotasks();

    expect(spawnCalls, 1);
    expect(container.read(engineManagerProvider).requireValue.status,
        const EngineReady());
  });

  test('falha de spawn: EngineFailed com a mensagem', () async {
    final container = makeContainer(
      factory: (path) async => throw Exception('boom'),
    );
    final session = await container.read(engineManagerProvider.future);
    expect(session.engine, isNull);
    expect(session.status, isA<EngineFailed>());
    expect((session.status as EngineFailed).message, contains('boom'));
  });

  test('crashes repetidos além do limite desistem com EngineFailed',
      () async {
    final container = makeContainer();
    await container.read(engineManagerProvider.future);

    for (var i = 0; i < kMaxEngineRestarts + 1; i++) {
      await ios.last.crash();
      await drainMicrotasks();
    }

    final status = container.read(engineManagerProvider).requireValue.status;
    expect(status, isA<EngineFailed>());
    expect(spawnCalls, 1 + kMaxEngineRestarts);
  });
}
```

Nota: `EngineNotFound`/`EngineReady`/`EngineRestarted` precisam de igualdade por valor para os `expect` acima — implementar `==`/`hashCode` (ou usar `const` + campos finais; classes const sem campos comparam por identidade canônica de const, o que basta para `EngineNotFound()`/`EngineReady()`; `EngineRestarted` precisa de `==` por `count`).

Em `app/test/features/board/board_screen_test.dart`, substituir `makeApp` por:

```dart
Widget makeApp(ChessEngineApi? engine, {EngineStatus? status}) {
  return ProviderScope(
    overrides: [
      engineProvider.overrideWith((ref) => Future.value(engine)),
      engineStatusProvider.overrideWithValue(status ??
          (engine == null ? const EngineNotFound() : const EngineReady())),
    ],
    child: const MaterialApp(home: BoardScreen()),
  );
}
```

(o import de `engine_provider.dart` já existe) e adicionar ao final do `main`:

```dart
  testWidgets('falha de spawn mostra mensagem específica', (tester) async {
    await tester.pumpWidget(
        makeApp(null, status: const EngineFailed('ProcessException: boom')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Stockfish falhou ao iniciar'), findsOneWidget);
    expect(find.textContaining('brew install stockfish'), findsNothing);
  });

  testWidgets('engine reiniciado mostra aviso e mantém o jogo', (tester) async {
    await tester.pumpWidget(
        makeApp(FakeEngine(), status: const EngineRestarted(1)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Stockfish reiniciado'), findsOneWidget);
    expect(find.byType(Chessboard), findsOneWidget);
  });
```

Em `app/test/features/play/game_controller_test.dart`, adicionar ao final do `main` (e no topo do arquivo, junto aos outros helpers, o notifier auxiliar):

```dart
/// Permite trocar o engine em tempo de teste (simula reinício pós-crash).
final _engineHolderProvider =
    NotifierProvider<_EngineHolder, ChessEngineApi?>(_EngineHolder.new);

class _EngineHolder extends Notifier<ChessEngineApi?> {
  @override
  ChessEngineApi? build() => null;

  void set(ChessEngineApi? engine) => state = engine;
}
```

```dart
  test('engine trocado (reinício) recebe o skill level da partida em curso',
      () async {
    final engineA = FakeEngine('e7e5');
    final engineB = FakeEngine('e7e5');
    final container = ProviderContainer(
      overrides: [
        engineProvider
            .overrideWith((ref) async => ref.watch(_engineHolderProvider)),
      ],
    );
    addTearDown(container.dispose);
    container.read(_engineHolderProvider.notifier).set(engineA);

    final controller = container.read(gameControllerProvider.notifier);
    await controller.newGame(playerSide: Side.white, skillLevel: 7);

    // Simula o reinício: o manager publica um engine novo.
    container.read(_engineHolderProvider.notifier).set(engineB);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(engineB.skillLevels, contains(7));
  });
```

- [ ] **Step 2: Rodar e verificar falha**

Run (em `app/`): `flutter test`
Expected: FAIL — `onExit` não existe em `EngineIo`, `engine_provider_test.dart` não compila (`engineManagerProvider` etc.), banner e reaplicação de skill não implementados.

- [ ] **Step 3: Implementar**

**3a. `app/lib/engine/uci_engine.dart`:**

Adicionar à interface `EngineIo`:

```dart
  /// Conclui quando o processo do engine termina (crash ou encerramento).
  Future<void> get onExit;
```

No `ProcessEngineIo`, adicionar o campo e a inicialização no construtor:

```dart
  ProcessEngineIo(Process process)
      : _process = process,
        onExit = process.exitCode.then((_) {}),
        lines = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .asBroadcastStream();
```

```dart
  @override
  final Future<void> onExit;
```

No `UciEngine`:

```dart
  bool _disposed = false;

  /// True após [dispose] — distingue encerramento intencional de crash.
  bool get isDisposed => _disposed;

  /// Conclui quando o processo termina (crash ou dispose).
  Future<void> get onExit => _io.onExit;
```

Envolver o corpo de `bestMoveFromFen` em proteção contra stream fechado (processo morto):

```dart
  @override
  Future<String?> bestMoveFromFen(String fen) => _serialized(() async {
        try {
          _io.send('position fen $fen');
          _io.send('go depth $depth');
          final line =
              await _io.lines.firstWhere((l) => l.startsWith('bestmove'));
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length < 2 || parts[1] == '(none)') return null;
          return parts[1];
        } on StateError {
          // Stream fechado sem bestmove: o processo morreu no meio.
          return null;
        }
      });
```

(`evaluateFen` e `topMovesFromFen` usam `await for`, que termina naturalmente quando o stream fecha — sem mudança.)

E `dispose` marca o encerramento intencional:

```dart
  @override
  Future<void> dispose() async {
    _disposed = true;
    _io.send('quit');
    await _io.kill();
  }
```

**3b. Substituir o conteúdo inteiro de `app/lib/engine/engine_provider.dart` por:**

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'stockfish_locator.dart';
import 'uci_engine.dart';

/// Estado de vida do engine, para o banner da UI.
sealed class EngineStatus {
  const EngineStatus();
}

final class EngineSearching extends EngineStatus {
  const EngineSearching();
}

final class EngineReady extends EngineStatus {
  const EngineReady();
}

final class EngineNotFound extends EngineStatus {
  const EngineNotFound();
}

final class EngineFailed extends EngineStatus {
  const EngineFailed(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is EngineFailed && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// Engine reiniciado automaticamente após crash ([count] reinícios).
final class EngineRestarted extends EngineStatus {
  const EngineRestarted(this.count);

  final int count;

  @override
  bool operator ==(Object other) =>
      other is EngineRestarted && other.count == count;

  @override
  int get hashCode => count.hashCode;
}

/// Engine corrente + status de vida.
@immutable
class EngineSession {
  const EngineSession({this.engine, required this.status});

  final ChessEngineApi? engine;
  final EngineStatus status;
}

/// Máximo de reinícios automáticos antes de desistir (evita loop de
/// respawn quando o binário morre sempre na largada).
const kMaxEngineRestarts = 5;

/// Localizador do binário (injetável em teste).
final stockfishPathProvider =
    Provider<String? Function()>((ref) => findStockfishPath);

/// Fábrica do engine (injetável em teste).
final engineFactoryProvider =
    Provider<Future<UciEngine> Function(String path)>(
        (ref) => UciEngine.spawn);

final engineManagerProvider =
    AsyncNotifierProvider<EngineManager, EngineSession>(EngineManager.new);

/// Spawna o Stockfish e o reinicia automaticamente se o processo morrer.
class EngineManager extends AsyncNotifier<EngineSession> {
  int _restarts = 0;

  @override
  Future<EngineSession> build() async {
    final path = ref.watch(stockfishPathProvider)();
    if (path == null) {
      return const EngineSession(status: EngineNotFound());
    }
    return _spawn(path, const EngineReady());
  }

  Future<EngineSession> _spawn(
    String path,
    EngineStatus statusOnSuccess,
  ) async {
    final UciEngine engine;
    try {
      engine = await ref.read(engineFactoryProvider)(path);
    } on Exception catch (error) {
      return EngineSession(status: EngineFailed('$error'));
    }
    ref.onDispose(engine.dispose);
    unawaited(engine.onExit.then((_) => _onEngineExit(engine, path)));
    return EngineSession(engine: engine, status: statusOnSuccess);
  }

  Future<void> _onEngineExit(UciEngine engine, String path) async {
    if (engine.isDisposed) return; // encerramento intencional
    if (state.value?.engine != engine) return; // já substituído
    _restarts++;
    if (_restarts > kMaxEngineRestarts) {
      state = const AsyncData(
        EngineSession(
          status: EngineFailed('Stockfish falhou repetidamente.'),
        ),
      );
      return;
    }
    state = AsyncData(await _spawn(path, EngineRestarted(_restarts)));
  }
}

/// Engine global do app. `null` quando indisponível.
final engineProvider = FutureProvider<ChessEngineApi?>((ref) async {
  final session = await ref.watch(engineManagerProvider.future);
  return session.engine;
});

/// Status do engine para o banner da tela.
final engineStatusProvider = Provider<EngineStatus>((ref) {
  final session = ref.watch(engineManagerProvider);
  return session.value?.status ?? const EngineSearching();
});
```

**3c. `app/lib/features/board/board_screen.dart`:**

No `build`, substituir a declaração `final engineReady = ...` e o bloco do banner. Trocar:

```dart
    final engineAvailable = ref.watch(engineProvider).value != null;
    final engineReady = !ref.watch(engineProvider).isLoading;
```

por:

```dart
    final engineAvailable = ref.watch(engineProvider).value != null;
    final status = ref.watch(engineStatusProvider);
    final (bannerText, bannerIsError) = switch (status) {
      EngineNotFound() => (
          'Stockfish não encontrado — instale com: brew install stockfish. '
              'Tabuleiro livre habilitado.',
          true,
        ),
      EngineFailed(:final message) => (
          'Stockfish falhou ao iniciar: $message — tabuleiro livre '
              'habilitado.',
          true,
        ),
      EngineRestarted() => (
          'Stockfish reiniciado após uma falha. A partida continua.',
          false,
        ),
      EngineSearching() || EngineReady() => (null, false),
    };
```

E trocar o bloco do banner na `Column`:

```dart
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
```

por:

```dart
          if (bannerText != null)
            Container(
              width: double.infinity,
              color: bannerIsError
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.tertiaryContainer,
              padding: const EdgeInsets.all(12),
              child: Text(bannerText),
            ),
```

**3d. `app/lib/features/play/game_controller.dart`:**

Adicionar `import 'dart:async';` no topo e trocar o `build` por:

```dart
  @override
  GameState build() {
    ref.listen(engineProvider, (previous, next) {
      final engine = next.value;
      if (engine != null && !identical(previous?.value, engine)) {
        // Engine novo (primeiro spawn ou reinício pós-crash): reaplica o
        // nível de habilidade da partida em curso.
        unawaited(engine.setSkillLevel(state.skillLevel));
      }
    });
    return GameState.initial();
  }
```

- [ ] **Step 4: Rodar tudo e verificar que passa**

Run (em `app/`): `flutter test`
Expected: PASS — todos os testes (os existentes de `game_controller_test.dart` seguem passando: o listener só adiciona um `setSkillLevel(10)` inicial inofensivo).

- [ ] **Step 5: Verificar formato e análise estática**

Run (em `app/`): `dart format lib test && flutter analyze`
Expected: sem erros nem warnings.

- [ ] **Step 6: Build final e smoke test manual**

Run (em `app/`): `flutter build macos --debug`
Expected: build conclui sem erro.

Smoke test manual (com Stockfish instalado): `flutter run -d macos` → jogar 1. e4 → painel mostra avaliação, barra, probabilidades e 3 top moves com estrela no primeiro; matar o processo do Stockfish (`pkill -f stockfish`) → banner "Stockfish reiniciado" aparece e a partida continua respondendo.

- [ ] **Step 7: Commit**

```bash
git add app/lib app/test
git commit -m "feat: reinício automático do engine após crash e banner de status preciso"
```
