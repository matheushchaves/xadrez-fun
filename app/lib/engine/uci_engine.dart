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

/// Cliente UCI: handshake, skill level, melhor lance e avaliação.
class UciEngine implements ChessEngineApi {
  UciEngine(this._io, {this.depth = 12});

  final EngineIo _io;

  /// Profundidade de busca usada nas consultas ao engine.
  final int depth;

  Future<void> _queue = Future.value();

  static final _scoreRe = RegExp(r'score (cp|mate) (-?\d+)');
  static final _multipvRe = RegExp(r'\bmultipv (\d+)\b');
  static final _pvRe = RegExp(r'\bpv ([a-h][1-8][a-h][1-8][qrbn]?)');

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
    final line = await _io.lines.firstWhere((l) => l.startsWith('bestmove'));
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
  Future<List<EngineLine>> topMovesFromFen(
    String fen, {
    int count = 3,
  }) => _serialized(() async {
    _io.send('setoption name MultiPV value $count');
    _io.send('position fen $fen');
    _io.send('go depth $depth');
    final collected = <int, EngineLine>{};
    await for (final line in _io.lines) {
      final pvMatch = _pvRe.firstMatch(line);
      final scoreMatch = _scoreRe.firstMatch(line);
      if (pvMatch != null && scoreMatch != null) {
        final index = int.parse(_multipvRe.firstMatch(line)?.group(1) ?? '1');
        final value = int.parse(scoreMatch.group(2)!);
        collected[index] = EngineLine(
          uci: pvMatch.group(1)!,
          eval: scoreMatch.group(1) == 'cp' ? CpEval(value) : MateEval(value),
        );
      }
      if (line.startsWith('bestmove')) break;
    }
    _io.send('setoption name MultiPV value 1');
    final indices = collected.keys.toList()..sort();
    return [for (final i in indices) collected[i]!];
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
