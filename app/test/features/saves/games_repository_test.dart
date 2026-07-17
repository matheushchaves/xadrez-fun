import 'dart:convert';
import 'dart:io';

// `dartchess` também exporta um `File` (coluna do tabuleiro) que colide com
// `dart:io`'s `File`; escondemos o da dartchess já que só usamos `Side`.
import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:xadrez_fun/features/play/game_controller.dart';
import 'package:xadrez_fun/features/saves/games_repository.dart';
import 'package:xadrez_fun/features/saves/saved_game.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory tempDir;
  late FileGamesRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('xadrez_fun_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    repository = FileGamesRepository();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  SavedGame makeGame({String id = 'id1', String name = 'Partida teste'}) {
    return SavedGame(
      id: id,
      name: name,
      mode: GameMode.playVsEngine,
      timestamp: DateTime.utc(2026, 7, 17, 10),
      sanHistory: const ['e4', 'e5'],
      playerSide: Side.white,
      skillLevel: 10,
    );
  }

  test('save + load faz roundtrip', () async {
    final game = makeGame();
    await repository.save(game);

    final loaded = await repository.load(game.id);

    expect(loaded, isNotNull);
    expect(loaded!.id, game.id);
    expect(loaded.name, game.name);
    expect(loaded.sanHistory, game.sanHistory);
  });

  test('load com id inexistente retorna null', () async {
    final loaded = await repository.load('nao-existe');
    expect(loaded, isNull);
  });

  test('listGames retorna vazio quando não há partidas', () async {
    final games = await repository.listGames();
    expect(games, isEmpty);
  });

  test('listGames ordena por timestamp decrescente', () async {
    await repository.save(
      SavedGame(
        id: 'old',
        name: 'Antiga',
        mode: GameMode.playVsEngine,
        timestamp: DateTime.utc(2026, 7, 1),
        sanHistory: const ['e4'],
        playerSide: Side.white,
        skillLevel: 10,
      ),
    );
    await repository.save(
      SavedGame(
        id: 'new',
        name: 'Recente',
        mode: GameMode.playVsEngine,
        timestamp: DateTime.utc(2026, 7, 17),
        sanHistory: const ['d4'],
        playerSide: Side.white,
        skillLevel: 10,
      ),
    );

    final games = await repository.listGames();

    expect(games.map((g) => g.id), ['new', 'old']);
  });

  test('listGames ignora arquivos corrompidos', () async {
    await repository.save(makeGame());
    final gamesDir = Directory('${tempDir.path}/games');
    await File('${gamesDir.path}/corrupto.json').writeAsString('{not json');

    final games = await repository.listGames();

    expect(games, hasLength(1));
    expect(games.single.id, 'id1');
  });

  test('listGames ignora arquivo com campos do tipo errado', () async {
    await repository.save(makeGame());
    final gamesDir = Directory('${tempDir.path}/games');
    await File('${gamesDir.path}/tipo_errado.json').writeAsString(
      jsonEncode({
        'id': 'x',
        'name': 'y',
        'mode': 'playVsEngine',
        'timestamp': '2026-07-17T00:00:00.000Z',
        'sanHistory': 'not-a-list',
        'playerSide': 'white',
        'skillLevel': 10,
      }),
    );

    final games = await repository.listGames();

    expect(games, hasLength(1));
    expect(games.single.id, 'id1');
  });

  test('delete remove a partida', () async {
    final game = makeGame();
    await repository.save(game);

    await repository.delete(game.id);

    expect(await repository.load(game.id), isNull);
  });

  test('delete de id inexistente não lança erro', () async {
    await repository.delete('nao-existe');
  });

  test('rename atualiza o nome preservando o resto', () async {
    final game = makeGame();
    await repository.save(game);

    await repository.rename(game.id, 'Nome novo');

    final loaded = await repository.load(game.id);
    expect(loaded!.name, 'Nome novo');
    expect(loaded.sanHistory, game.sanHistory);
  });

  test('rename de id inexistente não lança erro', () async {
    await repository.rename('nao-existe', 'Nome novo');
  });

  test('load retorna null quando arquivo tem campo do tipo errado', () async {
    final dir = await Directory(
      '${tempDir.path}/games',
    ).create(recursive: true);
    await File('${dir.path}/tipo_errado.json').writeAsString(
      jsonEncode({
        'id': 'x',
        'name': 'y',
        'mode': 'playVsEngine',
        'timestamp': '2026-07-17T00:00:00.000Z',
        'sanHistory': 'not-a-list',
        'playerSide': 'white',
        'skillLevel': 10,
      }),
    );

    final loaded = await repository.load('tipo_errado');

    expect(loaded, isNull);
  });
}
