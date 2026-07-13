import 'package:flutter_test/flutter_test.dart';
import 'package:xadrez_fun/engine/stockfish_locator.dart';

void main() {
  test('encontra stockfish no PATH', () {
    final path = findStockfishPath(
      environment: {'PATH': '/foo/bin:/bar/bin', 'HOME': '/Users/x'},
      isFile: (p) => p == '/bar/bin/stockfish',
    );
    expect(path, '/bar/bin/stockfish');
  });

  test('cai nos caminhos comuns quando não está no PATH', () {
    final path = findStockfishPath(
      environment: {'PATH': '/foo/bin', 'HOME': '/Users/x'},
      isFile: (p) => p == '/opt/homebrew/bin/stockfish',
    );
    expect(path, '/opt/homebrew/bin/stockfish');
  });

  test('inclui ~/stockfish/stockfish como candidato', () {
    final path = findStockfishPath(
      environment: {'PATH': '', 'HOME': '/Users/x'},
      isFile: (p) => p == '/Users/x/stockfish/stockfish',
    );
    expect(path, '/Users/x/stockfish/stockfish');
  });

  test('retorna null quando não encontra', () {
    final path = findStockfishPath(
      environment: {'PATH': '/foo', 'HOME': '/Users/x'},
      isFile: (_) => false,
    );
    expect(path, isNull);
  });

  test('PATH tem prioridade sobre caminhos comuns', () {
    final path = findStockfishPath(
      environment: {'PATH': '/meu/bin', 'HOME': '/Users/x'},
      isFile: (p) =>
          p == '/meu/bin/stockfish' || p == '/opt/homebrew/bin/stockfish',
    );
    expect(path, '/meu/bin/stockfish');
  });
}
