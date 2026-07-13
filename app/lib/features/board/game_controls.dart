import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../play/game_controller.dart';

/// Painel lateral: status da partida, nível do engine, nova partida
/// e histórico de lances.
class GameControls extends ConsumerStatefulWidget {
  const GameControls({super.key});

  @override
  ConsumerState<GameControls> createState() => _GameControlsState();
}

class _GameControlsState extends ConsumerState<GameControls> {
  double _skill = 10;

  String _statusText(GameState state) {
    final result = state.resultText;
    if (result != null) return result;
    if (state.engineThinking) return 'Stockfish pensando…';
    final isPlayerTurn = state.position.turn == state.playerSide;
    return isPlayerTurn ? 'Sua vez.' : 'Vez do adversário.';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameControllerProvider);
    final controller = ref.read(gameControllerProvider.notifier);

    return SizedBox(
      width: 280,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _statusText(state),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            Text('Nível do Stockfish: ${_skill.round()}'),
            Slider(
              value: _skill,
              min: 0,
              max: 20,
              divisions: 20,
              label: '${_skill.round()}',
              onChanged: (value) => setState(() => _skill = value),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => controller.newGame(
                playerSide: Side.white,
                skillLevel: _skill.round(),
              ),
              child: const Text('Jogar de brancas'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => controller.newGame(
                playerSide: Side.black,
                skillLevel: _skill.round(),
              ),
              child: const Text('Jogar de pretas'),
            ),
            const SizedBox(height: 24),
            Text('Lances', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < state.sanHistory.length; i++)
                      Text(
                        i.isEven
                            ? '${i ~/ 2 + 1}. ${state.sanHistory[i]}'
                            : state.sanHistory[i],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
