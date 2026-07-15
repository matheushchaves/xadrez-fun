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
    expect(
      container.read(engineManagerProvider).requireValue.status,
      const EngineReady(),
    );
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

  test('crashes repetidos além do limite desistem com EngineFailed', () async {
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
