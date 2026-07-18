import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'saved_game.dart';

/// Acesso a partidas salvas, injetável para permitir fakes em teste.
abstract interface class GamesRepository {
  /// Lista as partidas salvas, mais recente primeiro.
  Future<List<SavedGameSummary>> listGames();

  /// Carrega os dados completos de uma partida, ou null se não existir ou
  /// estiver corrompida.
  Future<SavedGame?> load(String id);

  /// Grava (cria ou sobrescreve) uma partida.
  Future<void> save(SavedGame game);

  /// Remove uma partida, se existir.
  Future<void> delete(String id);

  /// Renomeia uma partida existente. Não faz nada se ela não existir.
  Future<void> rename(String id, String name);
}

/// Implementação em arquivo: um JSON por partida em
/// `<diretório de suporte do app>/games/<id>.json`. Formato e local
/// próprios do Flutter — não relacionados aos saves do app Python.
class FileGamesRepository implements GamesRepository {
  Future<Directory> _gamesDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/games');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File _fileFor(Directory dir, String id) => File('${dir.path}/$id.json');

  @override
  Future<void> save(SavedGame game) async {
    final dir = await _gamesDir();
    await _fileFor(dir, game.id).writeAsString(jsonEncode(game.toJson()));
  }

  @override
  Future<SavedGame?> load(String id) async {
    final dir = await _gamesDir();
    final file = _fileFor(dir, id);
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return SavedGame.fromJson(json);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  @override
  Future<List<SavedGameSummary>> listGames() async {
    final dir = await _gamesDir();
    final summaries = <SavedGameSummary>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        summaries.add(SavedGameSummary.fromJson(json));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      } on ArgumentError {
        continue;
      }
    }
    summaries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return summaries;
  }

  @override
  Future<void> delete(String id) async {
    final dir = await _gamesDir();
    final file = _fileFor(dir, id);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> rename(String id, String name) async {
    final data = await load(id);
    if (data == null) return;
    await save(data.copyWith(name: name));
  }
}

/// Repositório de partidas salvas global do app. Sobrescrito em testes com
/// um fake em memória.
final gamesRepositoryProvider = Provider<GamesRepository>(
  (ref) => FileGamesRepository(),
);
