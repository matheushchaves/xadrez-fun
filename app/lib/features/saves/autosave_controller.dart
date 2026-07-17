import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../play/game_controller.dart';
import 'games_repository.dart';
import 'saved_game.dart';

final autosaveControllerProvider = NotifierProvider<AutosaveController, int>(
  AutosaveController.new,
);

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
