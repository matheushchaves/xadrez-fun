import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_provider.dart';
import '../play/game_controller.dart';

/// Tela principal: tabuleiro à esquerda, controles à direita.
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  late final ChessboardController _boardController;

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
    } else if (!engineAvailable) {
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

  @override
  Widget build(BuildContext context) {
    final engineAvailable = ref.watch(engineProvider).value != null;
    final engineReady = !ref.watch(engineProvider).isLoading;

    ref.listen(gameControllerProvider, (previous, next) {
      _boardController.updatePosition(_gameData(next, engineAvailable));
    });

    final state = ref.watch(gameControllerProvider);
    final orientation = state.playerSide == Side.black
        ? Side.black
        : Side.white;

    return Scaffold(
      body: Column(
        children: [
          if (engineReady && !engineAvailable)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Stockfish não encontrado — instale com: brew install stockfish. '
                'Tabuleiro livre habilitado.',
              ),
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
                // Task 6 substitui por GameControls.
                const SizedBox(width: 280),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
