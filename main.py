#!/usr/bin/env python3
"""
Xadrez Terminal - Interface de xadrez com análise em tempo real.

Jogue contra o Stockfish com análise de posição, probabilidades de vitória
e sugestões de melhores jogadas.
"""

import sys
import re
import chess
from board_display import (
    render_board,
    format_legal_moves,
    parse_move_input,
    show_game_status,
)
from engine import ChessEngine
from analysis import get_position_analysis, format_top_moves
from scenarios import VariationTree, WhatIfAnalyzer, MonteCarloSimulator
from strategy import (
    ThreatAnalyzer, WeaknessAnalyzer, PawnStructureAnalyzer,
    CenterControlAnalyzer, KingSafetyAnalyzer, PieceAnalyzer,
    TacticsDetector, PlanSuggester, FullAnalyzer
)
from save_manager import SaveManager


def clear_screen():
    """Limpa a tela do terminal."""
    print('\033[2J\033[H', end='')


def print_header():
    """Imprime o cabeçalho do jogo."""
    print("=" * 60)
    print("       ♔ XADREZ TERMINAL - Análise em Tempo Real ♚")
    print("=" * 60)
    print()


def print_analysis(analysis: dict, show_top_moves: bool = True):
    """Imprime a análise da posição."""
    eval_bar = analysis.get('eval_bar')
    if eval_bar:
        print(f"  ⬜[{eval_bar}]⬛  {analysis['eval_str']}")
    else:
        print(f"  📊 {analysis['eval_str']}")
    print(f"  {analysis['probs_str']}")
    if show_top_moves:
        print(f"  💡 {format_top_moves(analysis['top_moves'])}")


def get_player_color() -> chess.Color:
    """Pergunta ao jogador qual cor ele quer jogar."""
    while True:
        print("\nQual cor você quer jogar?")
        print("  [1] Brancas (você começa)")
        print("  [2] Pretas (engine começa)")
        choice = input("\nEscolha (1/2): ").strip()

        if choice == '1':
            return chess.WHITE
        elif choice == '2':
            return chess.BLACK
        else:
            print("Opção inválida! Digite 1 ou 2.")


def get_skill_level() -> int:
    """Pergunta o nível de dificuldade."""
    while True:
        print("\nNível de dificuldade do Stockfish (0-20):")
        print("  0-5:   Iniciante")
        print("  6-10:  Intermediário")
        print("  11-15: Avançado")
        print("  16-20: Mestre")
        choice = input("\nNível [10]: ").strip()

        if not choice:
            return 10

        try:
            level = int(choice)
            if 0 <= level <= 20:
                return level
            else:
                print("Nível deve ser entre 0 e 20!")
        except ValueError:
            print("Digite um número válido!")


def get_game_mode() -> str:
    """Pergunta qual modo o usuário quer."""
    while True:
        print("\nEscolha o modo:")
        print("  [1] Jogar contra Stockfish")
        print("  [2] Modo Análise (inserir jogadas manualmente)")
        choice = input("\nModo (1/2): ").strip()

        if choice == '1':
            return 'play'
        elif choice == '2':
            return 'analysis'
        else:
            print("Opção inválida! Digite 1 ou 2.")


def play_game(engine: ChessEngine, player_color: chess.Color, save_manager: SaveManager,
              skill_level: int, restore_data: dict = None):
    """Loop principal do jogo."""
    board = chess.Board()
    last_move = None
    move_history = []

    # Restaurar estado se fornecido
    if restore_data:
        move_history = restore_data.get('move_history', [])
        # Reconstruir tabuleiro
        for san in move_history:
            try:
                move = board.parse_san(san)
                board.push(move)
                last_move = move
            except ValueError:
                break
        print(f"\n✅ Partida restaurada ({len(move_history)} jogadas)")
        input("Pressione Enter para continuar...")

    while not board.is_game_over():
        clear_screen()
        print_header()

        # Mostrar tabuleiro da perspectiva do jogador
        print(render_board(board, perspective_white=(player_color == chess.WHITE), last_move=last_move))
        print()

        # Status do jogo
        print(show_game_status(board))
        print()

        # Análise da posição (melhores jogadas só no turno do jogador)
        try:
            analysis = get_position_analysis(engine, board)
            print_analysis(analysis, show_top_moves=(board.turn == player_color))
        except Exception as e:
            print(f"⚠️  Erro na análise: {e}")

        # Histórico de jogadas
        if move_history:
            print(f"\n📜 Histórico: {' '.join(move_history[-10:])}")

        print()

        if board.turn == player_color:
            # Turno do jogador
            print("Jogadas disponíveis:")
            print(format_legal_moves(board))
            print()

            while True:
                try:
                    user_input = input("🎯 Sua jogada (ou 'sair'): ").strip()
                except EOFError:
                    print("\nJogo encerrado.")
                    return

                if user_input.lower() in ('sair', 'quit', 'exit', 'q'):
                    print("\nJogo encerrado pelo jogador.")
                    return

                if user_input.lower() == 'hint':
                    if analysis and analysis.get('top_moves'):
                        best = analysis['top_moves'][0]
                        print(f"💡 Sugestão: {best['san']} ({best['eval_str']})")
                    continue

                move = parse_move_input(board, user_input)
                if move:
                    san = board.san(move)
                    board.push(move)
                    last_move = move

                    # Adicionar ao histórico
                    move_num = (board.fullmove_number - 1) if board.turn == chess.WHITE else board.fullmove_number
                    if board.turn == chess.BLACK:
                        move_history.append(f"{move_num}.{san}")
                    else:
                        move_history.append(san)

                    # Auto-save
                    save_manager.save_game(move_history, player_color, skill_level)
                    break
                else:
                    print("❌ Jogada inválida! Use formato UCI (e2e4) ou SAN (e4, Nf3)")

        else:
            # Turno do engine
            print("🤖 Stockfish está pensando...")
            try:
                move = engine.get_best_move(board)
                san = board.san(move)
                board.push(move)
                last_move = move

                # Adicionar ao histórico
                move_num = board.fullmove_number if board.turn == chess.WHITE else board.fullmove_number
                if board.turn == chess.WHITE:
                    move_history.append(f"{move_num}.{san}")
                else:
                    move_history.append(san)

                # Auto-save
                save_manager.save_game(move_history, player_color, skill_level)

                print(f"🤖 Stockfish jogou: {san}")
                input("\nPressione Enter para continuar...")

            except Exception as e:
                print(f"❌ Erro do engine: {e}")
                return

    # Fim de jogo
    clear_screen()
    print_header()
    print(render_board(board, perspective_white=(player_color == chess.WHITE), last_move=last_move))
    print()
    print("=" * 60)
    print("                    FIM DE JOGO!")
    print("=" * 60)
    print()
    print(show_game_status(board))

    result = board.result()
    if result == '1-0':
        print("\n🏆 Brancas vencem!")
    elif result == '0-1':
        print("\n🏆 Pretas vencem!")
    else:
        print("\n🤝 Empate!")

    print(f"\n📜 Histórico completo: {' '.join(move_history)}")


def analysis_mode(engine: ChessEngine, save_manager: SaveManager, restore_data: dict = None):
    """Modo de análise - usuário insere todas as jogadas."""
    board = chess.Board()
    last_move = None
    move_history = []
    perspective_white = True

    # Inicializar ferramentas de cenários
    var_tree = VariationTree()
    what_if = WhatIfAnalyzer(engine)
    monte_carlo = MonteCarloSimulator()

    # Inicializar analisadores estratégicos
    threat_analyzer = ThreatAnalyzer()
    weakness_analyzer = WeaknessAnalyzer()
    pawn_analyzer = PawnStructureAnalyzer()
    center_analyzer = CenterControlAnalyzer()
    king_analyzer = KingSafetyAnalyzer()
    piece_analyzer = PieceAnalyzer()
    tactics_detector = TacticsDetector()
    plan_suggester = PlanSuggester(engine)
    full_analyzer = FullAnalyzer(engine)

    # Restaurar estado se fornecido
    if restore_data:
        move_history = restore_data.get('move_history', [])
        perspective_white = restore_data.get('perspective_white', True)
        # Restaurar variações se existirem
        var_data = restore_data.get('variation_tree', {})
        if var_data.get('main_line'):
            var_tree.main_line = var_data['main_line']
        if var_data.get('branches'):
            var_tree.branches = var_data['branches']

        # Reconstruir tabuleiro
        for san in move_history:
            try:
                move = board.parse_san(san)
                board.push(move)
                last_move = move
            except ValueError:
                break

        print(f"\n✅ Partida restaurada ({len(move_history)} jogadas)")
        input("Pressione Enter para continuar...")

    print("\n" + "=" * 60)
    print("              MODO ANÁLISE")
    print("=" * 60)
    print("\nComandos disponíveis:")
    print("  - Digite jogadas em UCI (e2e4) ou SAN (e4, Nf3)")
    print("  - Múltiplas jogadas: 'e4 e5 Nf3 Nc6' ou '1.e4 e5 2.Nf3 Nc6'")
    print("  - 'undo'  - voltar última jogada")
    print("  - 'flip'  - alternar perspectiva do tabuleiro")
    print("  - 'fen'   - mostrar FEN da posição")
    print("  - 'pgn'   - mostrar PGN da partida")
    print("  - 'reset' - reiniciar tabuleiro")
    print("\nCenários e Estatísticas:")
    print("  - 'what'  - E se? (melhores respostas do oponente)")
    print("  - 'var'   - criar variação")
    print("  - 'back'  - voltar para linha principal")
    print("  - 'vars'  - listar variações")
    print("  - 'tree'  - mostrar árvore de variações")
    print("  - 'sim N' - simulação Monte Carlo (N partidas)")
    print("\nAnálise Estratégica:")
    print("  - 'threats' - ameaças (suas e do oponente)")
    print("  - 'weak'    - fraquezas posicionais")
    print("  - 'plan'    - plano estratégico sugerido")
    print("  - 'pieces'  - análise de cada peça")
    print("  - 'pawns'   - estrutura de peões")
    print("  - 'center'  - controle do centro")
    print("  - 'king'    - segurança dos reis")
    print("  - 'tactics' - táticas (pins, forks, etc)")
    print("  - 'full'    - análise completa (tudo)")
    print("  - 'sair'    - encerrar")
    input("\nPressione Enter para começar...")

    while True:
        clear_screen()
        print_header()
        print("[ MODO ANÁLISE ]")
        print()

        # Mostrar tabuleiro
        print(render_board(board, perspective_white=perspective_white, last_move=last_move))
        print()

        # Status do jogo
        print(show_game_status(board))
        print()

        # Análise da posição
        if not board.is_game_over():
            try:
                analysis = get_position_analysis(engine, board)
                print_analysis(analysis)
            except Exception as e:
                print(f"⚠️  Erro na análise: {e}")
                analysis = None
        else:
            print("─" * 60)
            result = board.result()
            if result == '1-0':
                print("🏆 Fim de jogo: Brancas vencem!")
            elif result == '0-1':
                print("🏆 Fim de jogo: Pretas vencem!")
            else:
                print("🤝 Fim de jogo: Empate!")
            print("─" * 60)
            analysis = None

        # Histórico
        if move_history:
            # Formatar histórico em notação padrão
            formatted = []
            for i, san in enumerate(move_history):
                if i % 2 == 0:
                    formatted.append(f"{i//2 + 1}.{san}")
                else:
                    formatted.append(san)
            print(f"\n📜 Partida: {' '.join(formatted)}")

        print()

        # Jogadas disponíveis
        if not board.is_game_over():
            turn = "Brancas" if board.turn == chess.WHITE else "Pretas"
            print(f"Jogadas disponíveis para {turn}:")
            print(format_legal_moves(board))
            print()

        # Input
        try:
            prompt = "⚪" if board.turn == chess.WHITE else "⚫"
            user_input = input(f"{prompt} Jogada: ").strip()
        except EOFError:
            print("\nSessão encerrada.")
            return

        # Processar comandos
        cmd = user_input.lower()

        if cmd in ('sair', 'quit', 'exit', 'q'):
            print("\nSessão de análise encerrada.")
            return

        elif cmd == 'undo':
            if board.move_stack:
                board.pop()
                if move_history:
                    move_history.pop()
                var_tree.undo_move()  # Atualizar árvore de variações
                last_move = board.move_stack[-1] if board.move_stack else None
                # Auto-save após undo
                var_tree_data = {
                    'main_line': var_tree.main_line,
                    'branches': var_tree.branches,
                }
                save_manager.save_analysis(move_history, perspective_white, var_tree_data)
                print("↩️  Jogada desfeita!")
            else:
                print("❌ Nenhuma jogada para desfazer!")
            input("Pressione Enter...")
            continue

        elif cmd == 'flip':
            perspective_white = not perspective_white
            continue

        elif cmd == 'fen':
            print(f"\n📋 FEN: {board.fen()}")
            input("\nPressione Enter...")
            continue

        elif cmd == 'pgn':
            if move_history:
                formatted = []
                for i, san in enumerate(move_history):
                    if i % 2 == 0:
                        formatted.append(f"{i//2 + 1}. {san}")
                    else:
                        formatted.append(san)
                print(f"\n📋 PGN: {' '.join(formatted)}")
            else:
                print("\n📋 Nenhuma jogada ainda.")
            input("\nPressione Enter...")
            continue

        elif cmd == 'reset':
            board = chess.Board()
            last_move = None
            move_history = []
            var_tree = VariationTree()  # Resetar árvore de variações
            save_manager.clear()  # Limpar auto-save
            print("🔄 Tabuleiro reiniciado!")
            input("Pressione Enter...")
            continue

        elif cmd == 'hint':
            if analysis and analysis.get('top_moves'):
                best = analysis['top_moves'][0]
                print(f"💡 Sugestão: {best['san']} ({best['eval_str']})")
            input("Pressione Enter...")
            continue

        elif cmd in ('what', 'whatif'):
            # Análise "E se?"
            if board.is_game_over():
                print("❌ Jogo já terminou!")
            else:
                print("\n🔮 Analisando cenários...")
                results = what_if.analyze_moves(board, num_moves=5)
                print()
                print(what_if.format_analysis(results))
            input("\nPressione Enter...")
            continue

        elif cmd == 'var':
            # Criar nova variação
            name = var_tree.create_branch()
            print(f"📁 Variação '{name}' criada na jogada {len(move_history)//2 + 1}")
            input("Pressione Enter...")
            continue

        elif cmd == 'back':
            # Voltar para linha principal
            if var_tree.current_branch:
                var_tree.switch_to_main()
                # Reconstruir tabuleiro da linha principal
                board = chess.Board()
                move_history = []
                for san in var_tree.main_line:
                    move = board.parse_san(san)
                    board.push(move)
                    move_history.append(san)
                last_move = board.move_stack[-1] if board.move_stack else None
                print("↩️  Voltando para linha principal")
            else:
                print("📍 Já está na linha principal")
            input("Pressione Enter...")
            continue

        elif cmd == 'vars':
            # Listar variações
            branches = var_tree.get_branch_names()
            if branches:
                print("\n📂 Variações:")
                for name in branches:
                    marker = " (atual)" if var_tree.current_branch == name else ""
                    print(f"  - {name}{marker}")
            else:
                print("\n📂 Nenhuma variação criada")
            if not var_tree.current_branch:
                print("  📍 Linha principal (atual)")
            input("\nPressione Enter...")
            continue

        elif cmd == 'tree':
            # Mostrar árvore de variações
            print("\n🌳 Árvore de variações:")
            print(var_tree.to_tree_string())
            input("\nPressione Enter...")
            continue

        elif cmd.startswith('sim'):
            # Simulação Monte Carlo
            parts = cmd.split()
            n_games = 1000
            if len(parts) > 1:
                try:
                    n_games = int(parts[1])
                except ValueError:
                    pass

            if board.is_game_over():
                print("❌ Jogo já terminou!")
            else:
                print(f"\n🎲 Simulando {n_games} partidas...")
                results = monte_carlo.simulate(board, n_games=n_games)
                print()
                print(monte_carlo.format_results(results))
            input("\nPressione Enter...")
            continue

        elif cmd == 'threats':
            # Análise de ameaças
            perspective = chess.WHITE if perspective_white else chess.BLACK
            analysis = threat_analyzer.analyze(board)
            print()
            print(threat_analyzer.format(analysis, perspective))
            input("\nPressione Enter...")
            continue

        elif cmd == 'weak':
            # Análise de fraquezas
            perspective = chess.WHITE if perspective_white else chess.BLACK
            analysis = weakness_analyzer.analyze(board)
            print()
            print(weakness_analyzer.format(analysis, perspective))
            input("\nPressione Enter...")
            continue

        elif cmd == 'plan':
            # Plano estratégico
            if board.is_game_over():
                print("❌ Jogo já terminou!")
            else:
                print("\n📋 Analisando posição...")
                analysis = plan_suggester.suggest(board)
                print()
                print(plan_suggester.format(analysis))
            input("\nPressione Enter...")
            continue

        elif cmd == 'pieces':
            # Análise de peças
            analysis = piece_analyzer.analyze(board)
            print()
            print(piece_analyzer.format(analysis))
            input("\nPressione Enter...")
            continue

        elif cmd == 'pawns':
            # Estrutura de peões
            analysis = pawn_analyzer.analyze(board)
            print()
            print(pawn_analyzer.format(analysis))
            input("\nPressione Enter...")
            continue

        elif cmd == 'center':
            # Controle do centro
            analysis = center_analyzer.analyze(board)
            print()
            print(center_analyzer.format(analysis))
            input("\nPressione Enter...")
            continue

        elif cmd == 'king':
            # Segurança do rei
            analysis = king_analyzer.analyze(board)
            print()
            print(king_analyzer.format(analysis))
            input("\nPressione Enter...")
            continue

        elif cmd == 'tactics':
            # Detecção de táticas
            analysis = tactics_detector.analyze(board)
            print()
            print(tactics_detector.format(analysis))
            input("\nPressione Enter...")
            continue

        elif cmd == 'full':
            # Análise completa
            if board.is_game_over():
                print("❌ Jogo já terminou!")
            else:
                perspective = chess.WHITE if perspective_white else chess.BLACK
                print("\n" + "=" * 60)
                print("         ANÁLISE ESTRATÉGICA COMPLETA")
                print("=" * 60)
                print()
                print(full_analyzer.analyze_all(board, perspective))
            input("\nPressione Enter...")
            continue

        elif not cmd:
            continue

        # Tentar interpretar como jogada(s)
        if board.is_game_over():
            print("❌ O jogo já terminou! Use 'reset' para reiniciar.")
            input("Pressione Enter...")
            continue

        # Processar múltiplas jogadas separadas por espaço
        # Remove números de lance como "1." "2." etc.
        tokens = user_input.split()
        moves_to_process = []
        for token in tokens:
            # Ignorar números de lance (1. 2. 15. etc)
            if re.match(r'^\d+\.$', token):
                continue
            # Remover número do início se colado (1.e4 -> e4)
            clean = re.sub(r'^\d+\.', '', token)
            if clean:
                moves_to_process.append(clean)

        if not moves_to_process:
            continue

        # Processar cada jogada
        moves_made = 0
        for move_str in moves_to_process:
            if board.is_game_over():
                break
            move = parse_move_input(board, move_str)
            if move:
                san = board.san(move)
                board.push(move)
                last_move = move
                move_history.append(san)
                var_tree.add_move(san)  # Adicionar à árvore de variações
                moves_made += 1
            else:
                print(f"❌ Jogada inválida: '{move_str}'")
                input("Pressione Enter...")
                break

        # Auto-save após jogadas
        if moves_made > 0:
            var_tree_data = {
                'main_line': var_tree.main_line,
                'branches': var_tree.branches,
            }
            save_manager.save_analysis(move_history, perspective_white, var_tree_data)

        if moves_made > 1:
            print(f"✅ {moves_made} jogadas executadas!")
            input("Pressione Enter...")


def main():
    """Função principal."""
    clear_screen()
    print_header()

    print("Bem-vindo ao Xadrez Terminal!")
    print("Análise de xadrez em tempo real com Stockfish.\n")

    # Inicializar SaveManager
    save_manager = SaveManager()

    # Inicializar engine
    print("Inicializando Stockfish...")
    try:
        engine = ChessEngine(skill_level=10)
        print("✅ Stockfish carregado com sucesso!")
    except RuntimeError as e:
        print(f"\n❌ Erro: {e}")
        print("\nPara instalar o Stockfish:")
        print("  macOS:  brew install stockfish")
        print("  Ubuntu: sudo apt install stockfish")
        sys.exit(1)

    # Verificar se existe save anterior
    restore_data = None
    if save_manager.has_save():
        save_info = save_manager.get_save_info()
        if save_info:
            print(f"\n💾 Partida anterior encontrada ({save_info['mode_name']}, {save_info['move_count']} jogadas)")
            print(f"   Última jogada: {save_info['timestamp']}")

            while True:
                choice = input("\n   Deseja continuar? (s/n): ").strip().lower()
                if choice in ('s', 'sim', 'y', 'yes'):
                    restore_data = save_manager.load()
                    break
                elif choice in ('n', 'nao', 'não', 'no'):
                    save_manager.clear()
                    break
                else:
                    print("   Digite 's' para sim ou 'n' para não.")

    try:
        if restore_data:
            # Restaurar partida anterior
            if restore_data.get('mode') == 'analysis':
                analysis_mode(engine, save_manager, restore_data)
            else:
                # Modo play - restaurar configurações
                player_color = chess.WHITE if restore_data.get('player_color') == 'white' else chess.BLACK
                skill_level = restore_data.get('skill_level', 10)
                engine.set_skill_level(skill_level)
                play_game(engine, player_color, save_manager, skill_level, restore_data)
        else:
            # Escolher modo normalmente
            game_mode = get_game_mode()

            if game_mode == 'analysis':
                analysis_mode(engine, save_manager)
            else:
                # Modo jogar contra engine
                skill_level = get_skill_level()
                engine.set_skill_level(skill_level)

                player_color = get_player_color()
                color_name = "Brancas" if player_color == chess.WHITE else "Pretas"
                print(f"\n✅ Você joga de {color_name}!")
                print("\nComandos durante o jogo:")
                print("  - Digite a jogada em UCI (e2e4) ou SAN (e4, Nf3)")
                print("  - 'hint' para ver sugestão")
                print("  - 'sair' para encerrar")

                input("\nPressione Enter para começar...")
                play_game(engine, player_color, save_manager, skill_level)
    finally:
        engine.quit()

    print("\nObrigado por jogar! Até a próxima! ♔")


if __name__ == '__main__':
    main()
