import 'dart:convert';
import 'dart:io';

/// Carrega `strategy_fixtures.json` (gerado por
/// `generate_strategy_fixtures.py`) como um mapa `nome do caso -> dados`.
///
/// Caminho relativo à raiz do pacote `app/` (onde `flutter test` roda).
Map<String, dynamic> loadStrategyFixtures() {
  final file = File('test/fixtures/strategy_fixtures.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}
