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
    // Emit responses asynchronously to allow listeners to be set up
    Future.microtask(() {
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
