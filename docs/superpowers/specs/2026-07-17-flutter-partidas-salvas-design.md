# Partidas Salvas (Flutter) — Design

## Contexto

O app Python tem, no `web.py` + `save_manager.py`, um sistema de múltiplas partidas salvas: cada partida vira um JSON em `~/.xadrez-terminal/games/<id>.json` (nome, modo, histórico de lances, etc.), listável, carregável, renomeável e deletável — uma partida ativa por vez (não é execução concorrente de várias engines), com autosave silencioso a cada lance. É essa biblioteca de "gavetas salvas" que o usuário quer no app Flutter (`app/`), para poder criar partidas separadas e retomá-las depois.

Achado durante a exploração: o `main.py` (CLI do terminal) está atualmente quebrado nesse ponto — chama `save_manager.has_save()`/`get_save_info()`/`clear()`, métodos que não existem na classe `SaveManager` atual (só `web.py` usa a API certa: `list_games()`, `save_analysis(game_id, ...)`, `save_game(game_id, ...)`, `load(id)`, `delete(id)`, `rename(id, ...)`). Isso não afeta o Flutter — é só contexto de por que `web.py` foi a referência usada aqui, não `main.py`.

**Decisões confirmadas com o usuário:**
- Não é concorrência real: uma partida ativa por vez, várias salvas em paralelo como "gavetas".
- Formato/local de armazenamento é próprio do Flutter — não compartilha arquivos com o Python.
- Autosave silencioso a cada lance (sem botão "Salvar").
- Tela separada para a lista de partidas salvas (não embutida no `GameControls`).
- Ao abrir o app, se houver uma partida salva com lances, pergunta automaticamente se quer continuar (diferente do Python: recusar **não apaga** a partida — ela continua na lista).

Fora de escopo: cenários (what-if, variações, Monte Carlo) do Python (`scenarios.py`) — ficam para uma fase futura separada, como já estava mapeado.

## Arquitetura

Autosave como observador reativo separado (`AutosaveController`), não uma chamada direta de `GameController` para o repositório — mesmo padrão já usado por `AnalysisController`/`StrategyPanel` para reagir ao `GameState` sem acoplamento direto. `GameController` continua responsável só pela lógica do jogo (posição, engine); persistência é um efeito colateral observado de fora.

### `GamesRepository`

Interface abstrata (Repository Pattern, mesmo espírito do `ChessEngineApi` já usado para o engine):

```dart
abstract interface class GamesRepository {
  Future<List<SavedGameSummary>> listGames();
  Future<SavedGame?> load(String id);
  Future<void> save(SavedGame game);
  Future<void> delete(String id);
  Future<void> rename(String id, String name);
}
```

- `SavedGameSummary` — dados leves pra lista (id, name, mode, moveCount, timestamp), análogo ao dict de `list_games()` do Python.
- `SavedGame` — dados completos pra carregar (id, name, mode, timestamp, sanHistory, e conforme o modo: playerSide+skillLevel para `playVsEngine`, ou nada extra para `analysis`, já que `orientation` não precisa ser persistida — ao carregar, a partida volta com `orientation` no padrão do modo, igual a uma partida nova).

**Implementação em arquivo** (`FileGamesRepository`): usa o pacote `path_provider` (novo — entra no `pubspec.yaml`) para achar o diretório de suporte do app (`getApplicationSupportDirectory()`), grava um JSON por partida em `<dir>/games/<id>.json`. `listGames()` lê todos os arquivos do diretório, ordenados por `timestamp` decrescente (mesmo critério do Python). Local e schema são próprios do Flutter — sem relação com `~/.xadrez-terminal/`.

**Nos testes**: `FakeGamesRepository` em memória (`Map<String, SavedGame>`), mesmo padrão do `FakeEngine` em `game_controller_test.dart` — nenhum teste toca o disco de verdade.

### Identidade da partida (`GameState`)

Dois campos novos: `gameId` (String, gerado uma vez por partida) e `gameName` (String, nome automático tipo `"Partida 17/07 14:30"`, sem prompt bloqueando o fluxo). Setados em `GameState.initial()`, `newGame()` e `startAnalysisMode()` — cada partida nova ganha identidade nova. `gameId` não precisa de um pacote `uuid`: um identificador derivado de `DateTime.now()` (microssegundos + um componente aleatório) é suficiente, já que não há requisito de unicidade distribuída.

### `AutosaveController`

Novo `Notifier` (materializado uma vez, ex. dentro do `BoardScreen`, igual ao `AnalysisController` hoje): no `build()`, `ref.listen(gameControllerProvider, ...)` e, a cada mudança onde `sanHistory` não está vazio, monta um `SavedGame` a partir do `GameState` corrente e chama `GamesRepository.save(...)` — fire-and-forget, sem bloquear a UI, sem debounce (lances em xadrez não disparam em alta frequência, escrever a cada um é aceitável, igual ao Python). Estados sem nenhum lance ainda não são salvos (evita lotar o diretório de partidas vazias a cada clique em "Jogar de brancas").

### Carregar, renomear e deletar

- **Carregar**: `GameController.loadGame(SavedGame data)` — reconstrói a posição via replay do `sanHistory` a partir de `Chess.initial` (mesma técnica já usada em `undoMove()`), define `mode`/`playerSide`/`skillLevel`/`orientation` conforme os dados salvos, e `gameId`/`gameName` a partir do save. Chamado pela `SavedGamesScreen` e pelo diálogo de retomar-ao-abrir.
- **Renomear a partida ativa**: `GameController.renameCurrentGame(String name)` atualiza `gameState.gameName` — a persistência acontece pelo caminho normal do `AutosaveController` (que reage a qualquer mudança de estado), sem a tela de partidas salvas falar com o repositório diretamente nesse caso.
- **Renomear/deletar uma partida que NÃO é a ativa**: a `SavedGamesScreen` fala direto com `GamesRepository.rename`/`delete`, já que `GameController` não sabe da existência dessas partidas.
- **Deletar a partida ativa**: se o usuário deletar, na lista, a partida que está jogando agora, o `GameController` reseta para uma partida nova (`GameState.initial()` com identidade nova) — evita que o `AutosaveController` recrie o arquivo recém-apagado no próximo lance.

## UI

- **Botão "Partidas salvas"** no `GameControls`, ao lado dos botões de nova partida, abre uma tela nova (`SavedGamesScreen`, navegação via `Navigator.push`) com a lista de `SavedGameSummary` (nome, modo, nº de lances, data), mais recente primeiro. Cada item tem toque-para-carregar e ações de renomear (diálogo com campo de texto) e deletar (com confirmação `AlertDialog`).
- **Retomar ao abrir**: um `FutureProvider` consulta `GamesRepository.listGames()` na inicialização; se a mais recente tiver `moveCount > 0`, um `AlertDialog` aparece sobre a tela inicial assim que o primeiro frame renderiza — *"Partida anterior encontrada (Modo Análise, 12 lances) — Continuar?"* — com **Continuar** (chama `loadGame`) e **Nova partida** (só fecha o diálogo; a partida salva permanece intacta na lista, diferente do comportamento de "limpar" do Python).

## Testes

Estende o padrão já usado no projeto (fakes em vez de mocks, sem I/O real nos testes):

- `GamesRepository`/`FileGamesRepository`: testes unitários usando um diretório temporário real (via `path_provider_platform_interface`'s test mock, análogo ao que Flutter recomenda pra testar código que usa `path_provider`) — cobre save/load/list/delete/rename e o roundtrip completo de serialização.
- `GameController`: novos testes de `loadGame` (reconstrução de posição, campos aplicados corretamente para os dois modos) e `renameCurrentGame`, usando `FakeGamesRepository` onde a suíte precisar overridar o provider do repositório.
- `AutosaveController`: testes com `FakeGamesRepository`, verificando que lances disparam save, que estado sem lances não salva, e que `loadGame`/`undoMove`/`flipBoard` também disparam save (qualquer mudança de estado relevante).
- `SavedGamesScreen`: testes de widget cobrindo lista vazia, lista com itens, carregar, renomear e deletar (com `FakeGamesRepository`).
- Fluxo de retomar ao abrir: teste de widget cobrindo os dois casos (com e sem partida recente) e a ação "Nova partida" **não apagando** a entrada.
