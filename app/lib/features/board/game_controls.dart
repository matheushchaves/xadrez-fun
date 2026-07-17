import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/analysis_panel.dart';
import '../play/game_controller.dart';
import '../saves/saved_games_screen.dart';
import '../strategy/strategy_panel.dart';

/// Painel lateral: status da partida, nível do engine, nova partida e
/// histórico de lances (fixos), com abas de Análise/Estratégia abaixo.
class GameControls extends ConsumerStatefulWidget {
  const GameControls({super.key});

  @override
  ConsumerState<GameControls> createState() => _GameControlsState();
}

class _GameControlsState extends ConsumerState<GameControls>
    with SingleTickerProviderStateMixin {
  double _skill = 10;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _statusText(GameState state) {
    final result = state.resultText;
    if (result != null) return result;
    if (state.mode == GameMode.analysis) {
      return state.position.turn == Side.white
          ? 'Vez das brancas.'
          : 'Vez das pretas.';
    }
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
            Flexible(
              child: SingleChildScrollView(
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
                      onPressed: state.engineThinking
                          ? null
                          : () => controller.newGame(
                              playerSide: Side.white,
                              skillLevel: _skill.round(),
                            ),
                      child: const Text('Jogar de brancas'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: state.engineThinking
                          ? null
                          : () => controller.newGame(
                              playerSide: Side.black,
                              skillLevel: _skill.round(),
                            ),
                      child: const Text('Jogar de pretas'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: state.engineThinking
                          ? null
                          : () => controller.startAnalysisMode(),
                      child: const Text('Modo Análise'),
                    ),
                    if (state.mode == GameMode.analysis) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: state.sanHistory.isEmpty
                                  ? null
                                  : controller.undoMove,
                              child: const Text('Desfazer'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: controller.flipBoard,
                              child: const Text('Virar tabuleiro'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SavedGamesScreen(),
                        ),
                      ),
                      child: const Text('Partidas salvas'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Lances',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 72,
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
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Análise'),
                Tab(text: 'Estratégia'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  SingleChildScrollView(child: AnalysisPanel()),
                  StrategyPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
