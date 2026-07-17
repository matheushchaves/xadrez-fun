import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../play/game_controller.dart';
import 'games_repository.dart';
import 'saved_game.dart';

/// Tela de "Partidas salvas": lista, carrega, renomeia e deleta partidas.
class SavedGamesScreen extends ConsumerStatefulWidget {
  const SavedGamesScreen({super.key});

  @override
  ConsumerState<SavedGamesScreen> createState() => _SavedGamesScreenState();
}

class _SavedGamesScreenState extends ConsumerState<SavedGamesScreen> {
  late Future<List<SavedGameSummary>> _gamesFuture;

  @override
  void initState() {
    super.initState();
    _gamesFuture = ref.read(gamesRepositoryProvider).listGames();
  }

  void _reload() {
    setState(() {
      _gamesFuture = ref.read(gamesRepositoryProvider).listGames();
    });
  }

  Future<void> _load(SavedGameSummary summary) async {
    final repository = ref.read(gamesRepositoryProvider);
    final data = await repository.load(summary.id);
    if (data == null || !mounted) return;
    await ref
        .read(gameControllerProvider.notifier)
        .loadGame(
          id: data.id,
          name: data.name,
          mode: data.mode,
          sanHistory: data.sanHistory,
          playerSide: data.playerSide,
          skillLevel: data.skillLevel,
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _rename(SavedGameSummary summary) async {
    final controller = TextEditingController(text: summary.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear partida'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || !mounted) return;

    final repository = ref.read(gamesRepositoryProvider);
    if (ref.read(gameControllerProvider).gameId == summary.id) {
      ref.read(gameControllerProvider.notifier).renameCurrentGame(newName);
    } else {
      await repository.rename(summary.id, newName);
    }
    if (!mounted) return;
    _reload();
  }

  Future<void> _delete(SavedGameSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deletar partida?'),
        content: Text('"${summary.name}" será apagada permanentemente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final repository = ref.read(gamesRepositoryProvider);
    await repository.delete(summary.id);
    await ref
        .read(gameControllerProvider.notifier)
        .resetIfActiveGame(summary.id);
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partidas salvas')),
      body: FutureBuilder<List<SavedGameSummary>>(
        future: _gamesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final games = snapshot.data!;
          if (games.isEmpty) {
            return const Center(child: Text('Nenhuma partida salva ainda.'));
          }
          return ListView.builder(
            itemCount: games.length,
            itemBuilder: (context, index) {
              final summary = games[index];
              final modeName = summary.mode == GameMode.analysis
                  ? 'Modo Análise'
                  : 'vs. Stockfish';
              return ListTile(
                title: Text(summary.name),
                subtitle: Text('$modeName · ${summary.moveCount} lances'),
                onTap: () => _load(summary),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Renomear',
                      onPressed: () => _rename(summary),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      tooltip: 'Deletar',
                      onPressed: () => _delete(summary),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
