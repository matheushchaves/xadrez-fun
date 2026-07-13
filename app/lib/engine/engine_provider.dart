import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'stockfish_locator.dart';
import 'uci_engine.dart';

/// Engine global do app. `null` quando o Stockfish não está instalado.
final engineProvider = FutureProvider<ChessEngineApi?>((ref) async {
  final path = findStockfishPath();
  if (path == null) return null;
  final engine = await UciEngine.spawn(path);
  ref.onDispose(engine.dispose);
  return engine;
});
