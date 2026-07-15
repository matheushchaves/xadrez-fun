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
final stockfishPathProvider = Provider<String? Function()>(
  (ref) => findStockfishPath,
);

/// Fábrica do engine (injetável em teste).
final engineFactoryProvider = Provider<Future<UciEngine> Function(String path)>(
  (ref) => UciEngine.spawn,
);

final engineManagerProvider =
    AsyncNotifierProvider<EngineManager, EngineSession>(EngineManager.new);

/// Spawna o Stockfish e o reinicia automaticamente se o processo morrer.
class EngineManager extends AsyncNotifier<EngineSession> {
  int _restarts = 0;

  /// O engine mais recente já spawnado (ou null se nenhum spawn teve
  /// sucesso ainda). Usado só pelo callback de dispose — ver [build].
  UciEngine? _currentEngine;

  @override
  Future<EngineSession> build() async {
    // Registrado uma única vez por toda a vida do notifier: no dispose,
    // encerra o engine ATUAL (não cada engine que já existiu). Não pode ler
    // `state` aqui dentro — o Riverpod proíbe usar o Ref/notifier a partir
    // de um callback de ciclo de vida — por isso guardamos a referência em
    // um campo simples, atualizado em [_spawn].
    ref.onDispose(() => _currentEngine?.dispose());
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
    _currentEngine = engine;
    unawaited(engine.onExit.then((_) => _onEngineExit(engine, path)));
    return EngineSession(engine: engine, status: statusOnSuccess);
  }

  Future<void> _onEngineExit(UciEngine engine, String path) async {
    if (engine.isDisposed) return; // encerramento intencional
    if (state.value?.engine != engine) return; // já substituído
    _restarts++;
    if (_restarts > kMaxEngineRestarts) {
      state = const AsyncData(
        EngineSession(status: EngineFailed('Stockfish falhou repetidamente.')),
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
