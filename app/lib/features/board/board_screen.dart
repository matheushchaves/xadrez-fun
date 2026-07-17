import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_provider.dart';
import '../play/game_controller.dart';
import '../saves/autosave_controller.dart';
import '../saves/games_repository.dart';
import '../saves/resume_prompt.dart';
import '../saves/saved_game.dart';
import 'game_controls.dart';

/// Tela principal: tabuleiro à esquerda, controles à direita.
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  late final ChessboardController _boardController;
  bool _resumePromptShown = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(gameControllerProvider);
    final engineAvailable = ref.read(engineProvider).value != null;
    _boardController = ChessboardController(
      game: _gameData(state, engineAvailable),
    );
  }

  @override
  void dispose() {
    _boardController.dispose();
    super.dispose();
  }

  GameData _gameData(GameState state, bool engineAvailable) {
    final PlayerSide playerSide;
    if (state.isGameOver || state.engineThinking) {
      playerSide = PlayerSide.none;
    } else if (state.mode == GameMode.analysis || !engineAvailable) {
      playerSide = PlayerSide.both;
    } else {
      playerSide = state.playerSide == Side.white
          ? PlayerSide.white
          : PlayerSide.black;
    }
    return GameData(
      fen: state.position.fen,
      lastMove: state.lastMove,
      playerSide: playerSide,
      sideToMove: state.position.turn,
      kingSquareInCheck: state.position.isCheck
          ? state.position.board.kingOf(state.position.turn)
          : null,
      validMoves: makeLegalMoves(state.position),
    );
  }

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    ref.read(gameControllerProvider.notifier).playUserMove(move);
  }

  Future<void> _showResumeDialog(SavedGameSummary summary) async {
    final modeName = summary.mode == GameMode.analysis
        ? 'Modo Análise'
        : 'vs. Stockfish';
    final continuar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Partida anterior encontrada'),
        content: Text(
          '${summary.name} — $modeName, ${summary.moveCount} lances.\n'
          'Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nova partida'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (continuar != true || !mounted) return;
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
  }

  @override
  Widget build(BuildContext context) {
    final engineAvailable = ref.watch(engineProvider).value != null;
    final status = ref.watch(engineStatusProvider);
    ref.watch(autosaveControllerProvider);
    ref.listen<AsyncValue<SavedGameSummary?>>(resumeCandidateProvider, (
      previous,
      next,
    ) {
      final summary = next.value;
      if (_resumePromptShown || summary == null) return;
      _resumePromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showResumeDialog(summary);
      });
    });
    final (bannerText, bannerIsError) = switch (status) {
      EngineNotFound() => (
        'Stockfish não encontrado — instale com: brew install stockfish. '
            'Tabuleiro livre habilitado.',
        true,
      ),
      EngineFailed(:final message) => (
        'Stockfish falhou ao iniciar: $message — tabuleiro livre '
            'habilitado.',
        true,
      ),
      EngineRestarted() => (
        'Stockfish reiniciado após uma falha. A partida continua.',
        false,
      ),
      EngineSearching() || EngineReady() => (null, false),
    };

    ref.listen(gameControllerProvider, (previous, next) {
      _boardController.updatePosition(_gameData(next, engineAvailable));
    });

    final state = ref.watch(gameControllerProvider);
    final orientation = state.orientation;

    return Scaffold(
      body: Column(
        children: [
          if (bannerText != null)
            Container(
              width: double.infinity,
              color: bannerIsError
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.tertiaryContainer,
              padding: const EdgeInsets.all(12),
              child: Text(bannerText),
            ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = constraints.biggest.shortestSide;
                        return Chessboard(
                          controller: _boardController,
                          size: size,
                          orientation: orientation,
                          onMove: _onMove,
                        );
                      },
                    ),
                  ),
                ),
                const GameControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
