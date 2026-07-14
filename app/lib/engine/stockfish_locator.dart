import 'dart:io';

/// Localiza o executável do Stockfish no sistema.
///
/// Espelha a lógica de `find_stockfish_path()` do engine.py:
/// primeiro o PATH, depois caminhos comuns de instalação.
String? findStockfishPath({
  Map<String, String>? environment,
  bool Function(String path)? isFile,
}) {
  final env = environment ?? Platform.environment;
  final checkFile = isFile ?? (String p) => File(p).existsSync();
  final home = env['HOME'] ?? '';

  final pathDirs = (env['PATH'] ?? '').split(':').where((d) => d.isNotEmpty);

  final candidates = [
    for (final dir in pathDirs) '$dir/stockfish',
    '/usr/local/bin/stockfish',
    '/usr/bin/stockfish',
    '/opt/homebrew/bin/stockfish',
    '/opt/local/bin/stockfish',
    '$home/stockfish/stockfish',
  ];

  for (final candidate in candidates) {
    if (checkFile(candidate)) return candidate;
  }
  return null;
}
