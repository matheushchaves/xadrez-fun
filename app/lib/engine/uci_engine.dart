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
