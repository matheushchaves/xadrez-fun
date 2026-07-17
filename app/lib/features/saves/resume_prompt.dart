import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'games_repository.dart';
import 'saved_game.dart';

/// Partida mais recente com lances, candidata a retomar ao abrir o app —
/// null se não houver nenhuma partida salva com histórico.
final resumeCandidateProvider = FutureProvider<SavedGameSummary?>((ref) async {
  final repository = ref.watch(gamesRepositoryProvider);
  final games = await repository.listGames();
  if (games.isEmpty || games.first.moveCount == 0) return null;
  return games.first;
});
