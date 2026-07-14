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

    const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
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

  test(
    'evaluateFen retorna cp na perspectiva das brancas (brancas jogam)',
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
    },
  );

  test('evaluateFen inverte o sinal quando as pretas jogam', () async {
    final io = FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      'go depth': ['info depth 12 score cp 40 pv e7e5', 'bestmove e7e5'],
    });
    final engine = UciEngine(io);
    await engine.init();

    // cp 40 para quem joga (pretas) = -40 na perspectiva das brancas.
    final eval = await engine.evaluateFen(
      'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
    );
    expect(eval, const CpEval(-40));
  });

  test('evaluateFen com mate mantém a semântica de perspectiva', () async {
    final io = FakeEngineIo({
      'uci': ['uciok'],
      'isready': ['readyok'],
      'go depth': ['info depth 12 score mate 2 pv d8h4', 'bestmove d8h4'],
    });
    final engine = UciEngine(io);
    await engine.init();

    // Mate em 2 para as pretas (que jogam) = -2 na perspectiva das brancas.
    final eval = await engine.evaluateFen(
      'rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2',
    );
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
    final sends = io.sent
        .where((c) => c.startsWith('position') || c.startsWith('go'))
        .toList();
    expect(sends, [
      'position fen $fen',
      'go depth 12',
      'position fen $fen',
      'go depth 12',
    ]);
  });
}
