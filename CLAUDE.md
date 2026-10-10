# Royal Revenue — addon de WoW (Midnight, Interface 120100)

Addon do Rafael que calcula qual craft da expansão atual dá mais lucro na casa de leilões (AH) e mantém um livro-caixa contábil de tudo que cada personagem ganha e gasta.

Versão atual: **1.25.1** (ver `RoyalRevenue/RoyalRevenue.toc`). Histórico completo de cada versão, decisões e motivos: `docs/CHANGELOG.md`. Leia a seção da área antes de mexer nela.

## Como falar com o Rafael
- Português do Brasil, informal, direto e curto. Depois de decidido o caminho, respostas práticas.
- Preferências de interface que ele já pediu várias vezes:
  - mais ícones e menos texto;
  - agrupar por personagem;
  - grupos minimizáveis (cabeçalho com +/−);
  - linhas zebradas (`root.Zebra`);
  - números no formato BR `000.000.000,00` (`root.Num`), ouro sempre com 2 casas.
- Ele testa no jogo e manda print. Bug relatado → achar a causa no código, explicar em 2–3 frases, corrigir, testar e lançar versão nova.

## Onde fica no PC dele (Windows)
- Addon: `C:\Blizzard\World of Warcraft\_retail_\Interface\AddOns\RoyalRevenue`.
- SavedVariables: `_retail_\WTF\Account\REDSHARKBR\SavedVariables\RoyalRevenue.lua`, com as tabelas `LucroCraftDB`, `LucroLivroDB` e `RoyalRevenueDB`.
- Backups e zips antigos: `_retail_\LucroCraft_backups\`.
- Instalar uma versão: extrair o zip por cima da pasta do addon. O `unzip` do Windows às vezes não sobrescreve ("cannot delete old"); extrair com python resolve (abrir cada arquivo com `'wb'`). Depois, conferir o md5.
- **Mudou o `.toc`** (arquivo novo ou removido): precisa reiniciar o WoW. **Só código**: `/reload` basta.
- Reinos: US-Goldrinn (principal) + Medivh, Illidan, Stormrage, Azralon. Personagens: Radunz (druida; Alquimia/Escrivania), Riwariel, Uriuri (Couro/Esfolamento), Dakael, Saalla/Dunraz (Ferraria), Zadrun, Madunz/Zaubeber (Alquimia), Radünz-Medivh, Lafaer, Drafael (coleta), Nazdru.
- Usa TSM, Auctionator (opcional) e CraftSim (opcional). O addon precisa funcionar sem nenhum deles; em último caso usa o scan próprio da AH.

## Estrutura
A raiz do repositório É a pasta do addon (precisa ser assim pro BigWigs Packager, que
publica no CurseForge — ele espera o `.toc` junto do `.git`). `.pkgmeta` na raiz ignora
`docs/`, `tests/`, `tools/` etc. na hora de empacotar.
```
RoyalRevenue.toc       ordem de carga — arquivo novo precisa entrar aqui
Brand.lua              1º: paleta, root.Num, root.Out (log), caches compartilhados
Craft/*.lua            módulo de lucro de craft (ns = root.Craft)
Livro/*.lua            módulo livro-caixa (ns = root.Livro)
Shell.lua              último: janela, barra Craft | Mercado | Livro-caixa, comandos /rr, escala
Media/icon.tga
.pkgmeta               ignore list pro empacotamento (CurseForge/BigWigs Packager)
docs/CHANGELOG.md      decisões e mudanças versão a versão (v1.1 → atual)
docs/CURSEFORGE.md     texto da página do CurseForge (PT e EN)
tests/                 harness com API do WoW simulada + testes de regressão
tools/                 check.sh (sintaxe), build.sh (zip local), reclass_gen.lua (gerador do Livro/Reclass.lua)
.github/workflows/     release.yml: tag vX.Y.Z → empacota, publica no CurseForge e cria release no GitHub
```
Pra instalar no jogo, copia-se só `RoyalRevenue.toc`, `Brand.lua`, `Shell.lua`, `Craft/`,
`Livro/` e `Media/` para `Interface\AddOns\RoyalRevenue\` — não a raiz do repo inteira.

Todo arquivo começa com:
```lua
local ADDON, root = ...
local ns = root.Craft   -- ou root.Livro
```
Os dois módulos são isolados: cada um tem seu `ns.L`, `ns.UI` e `ns.CharKey`. O que é comum fica em `root` (Brand.lua).

### Craft (abas: Craft = Receitas, Plano, Investimento, Destruir, Fila · Mercado = Comprar, Vender, Comprar receitas)
- **Pricing.lua**
  - Fontes de preço: TSM > Auctionator > scan próprio (`Pricing.Mode`).
  - Funções: `Sale`, `Cost`, `SoldPerDay`, `Trend`, `Reference`, `FlipReference`.
  - `ns.Cfg(chave)` com `ns.DEFAULTS`.
- **Scanner.lua**
  - Lê as receitas da profissão aberta e calcula custo, lucro, qualidade, concentração e curva ABC.
  - `Finalize`, `Reprice`/`RepriceAll`.
  - `BuildCraftMap`: o que vale mais fabricar do que comprar.
  - Rendimento real de multicraft por personagem e perfil (`yieldBy`).
- **Plan.lua**: plano de concentração. Guloso por ouro/ponto, com "SEGURE" para a melhor receita.
- **Buy.lua**: Mercado > Comprar.
  - Barra de listas (Plano / Fila / Consumíveis).
  - `Buy.Analyze`: preço típico pela mediana; índice do dia da semana e da faixa de horário; anúncio fora do normal.
  - Compra direta na AH; comprar × fabricar.
  - WoW Token como item comum.
- **Consum.lua**: sugestão de consumíveis por classe e spec. Tambor e Emergency Soul Link pela classe.
- **Sell.lua**: Mercado > Vender. Itens da bolsa, preço sugerido, postar e histórico de preço.
- **Queue.lua**: fila de craft e pedidos de fabricação.
  - Ler pedidos, pegar, fabricar, entregar.
  - Concentração do pedido no lucro.
  - Reagentes do cliente (`custR`); `FitToBags` troca qualidade.
- **Stock.lua**: `Stock.Usable` = bolsa + banco do personagem LOGADO + banco do bando (alts não contam). Também conta a compra na AH no ato.
- **Invest.lua / InvestView.lua / SecondProf.lua**: investimento (equipamento, especialização, buffs, coleta por hora) e segunda profissão.
- **Gather.lua**: captura de coletas (modificadores dos nós, Overload, extras pelo chat).
- **Salvage.lua**: aba Destruir (recuperação, Estilhaçar, Desencantar, transmutações com cargas). Aprende as saídas observando.
- **Containers.lua**: aprende o conteúdo dos baús ao abrir.
- **Own.lua**: scan próprio da AH (ReplicateItems, em lotes de 4000), vendedores e retrato de estoque.

### Livro (abas: Painel, DRE, Fluxo de caixa, Centros de resultado, Diário, Vendas)
- **Ledger.lua**: captura tudo por eventos e ganchos e grava em `LucroLivroDB.chars[char]`.
  - `journal`: Diário, com lançamentos `{t, a=código, h, v, c, i, q, k}`.
  - `days[AAAA-MM-DD]`: totais do dia `act / inc / out / cpv / time / cashOpen / cashClose`.
- **Plano de contas**:
  - 3.1/3.2: atividades (ouro / itens);
  - 3.3: receitas comerciais;
  - 3.4.01: comissão da AH;
  - 4.0.x: CPV por consumo;
  - 4.1: reparo; 4.2: logística; 4.3: compras para uso; 4.4: taxas (4.4.07 depósito da AH); 4.5: consumíveis; 4.6: Gear Upgrade (NPC Cuzolth); 4.9: outras;
  - 5.4: material para estoque; 5.x: transferências e conversões; 9.1: ajuste.
- **DRE**: Receita bruta → Deduções → Receita líquida → CPV → Lucro bruto → Despesas operacionais → EBIT → Lucro líquido.
  - Centros de custo (liga/desliga) abrem CPV, reparo e consumíveis por atividade.
- `day.v2` / `LucroLivroDB.v2From`: dias a partir do controle de consumo. Dia antigo põe a compra de material direto no CPV.
- **Correções únicas** (`FixNpcCat`, `FixReclass`, `FixCashDays`...): rodam uma vez, controladas por flags no SavedVariables. Nunca rodar de novo sem flag nova.

## Regras de código (aprendidas a duras penas)
1. **Lua 5.1**: nada de `goto`/labels, `//`, bitwise nativo. Checar com `tools/check.sh` (`luac5.1 -p`).
2. **Escopo**: `local` usado por função definida ANTES dele vira global nil. Declare antes, ou chame pela tabela (`Ledger.X`).
3. **Textos**: a chave é o texto em PT (`L["..."]`). Toda chave nova precisa da tradução EN em `Craft/Locale.lua` ou `Livro/Locale.lua`. `%` literal em `string.format` = `%%`.
4. **Fonte do jogo** não tem `−`, `▲▼` nem `…`: usar `-` e `...`. Setas são texturas.
5. **Valores secretos (Midnight)**: em combate e instância, argumentos de evento, nomes de NPC, tooltips e auras podem vir "secretos". Comparar ou concatenar um deles dá erro.
   - Todo handler que compara argumento começa com `if root.AnySecret(a1, a2, ...) then return end`.
   - No Livro, usar `Ledger.Safe(v)`.
6. **Combate**: botão seguro (`Canvas:SecureItem`, `SecureActionButtonTemplate`) só é criado ou movido fora de combate (`InCombatLockdown`).
7. **Saída de texto**: nunca `print` direto. Usar `root.Out` / `ns.Print` / `ns.Log`, que vão para a aba de chat "Log". Os arquivos que imprimem têm `local print = function(...) return root.Out(...) end`.
8. **Desempenho** (v1.25.0): não desfazer os caches sem motivo.
   - `root.TSMPrice` / `root.AtrPrice`: preço do TSM e do Auctionator por 60 s.
   - `root.BagCounts()`: uma leitura das bolsas por quadro. Tabela compartilhada, **só leitura**.
   - `root.DayKey(t)`: `date("%Y-%m-%d")` com cache.
   - `Ledger.rev`: sobe a cada evento do livro; o Livro/UI guarda o Collect/DRE e o Diário enquanto não mudar.
   - `Scanner.gen`: sobe a cada Finalize; `Invest.WeeklyValue` base é guardado por entrada.
   - `Scanner.CraftMapAll()`.
   - `ns.CharKey` e `RealmKey`: guardados na sessão.
   - Scan da profissão: espera o fim da sequência de crafts (Core.lua).
9. Evento frequente (`BAG_UPDATE_DELAYED`, `CHAT_MSG_LOOT`, `UNIT_AURA`, `GET_ITEM_INFO_RECEIVED`) → handler barato, com `C_Timer.After` de debounce e redesenho só se a aba estiver aberta.
10. **Item ainda não carregado pelo cliente**:
    - ícone: `ns.Visual.ItemIcon(id)`;
    - nome: `ns.Visual.ItemName(id)`.
    
    As duas pedem o item ao servidor e redesenham a aba quando ele chega. Nunca usar só `GetItemNameByID(id) or "item "..id`.
11. Interface desenhada com o canvas próprio (`Craft/Visual.lua`: `Text`, `Box`, `Icon`, `Hit`, `Button`, `Line`, `CreateSub` para rolagem interna, `Table`); no Livro, `Livro/Canvas.lua`. As abas visuais redesenham por inteiro (`UI.RefreshTab`).

## Testes (sem o jogo)
- `tests/harness*.lua` simulam a API do WoW, carregam um SavedVariables real de `tests/fixtures/` e todos os arquivos na ordem do `.toc`, e disparam ADDON_LOADED / PLAYER_LOGIN / PLAYER_ENTERING_WORLD.
  - `FIRE(evento, ...)` dispara um evento; cada FIRE é um quadro novo (`GetTime` +0,0001).
  - `RUNTIMERS()` roda os `C_Timer.After` pendentes.
- **Harness por fixture**: `harness11.lua`, `harness11d.lua` e `harness12.lua` usam sv11 (o mais novo, 07/10; o 12 expõe `ALLF` = todos os frames); `harness10.lua` usa sv10; `harness.lua` e `harness_ah.lua` (com `ConfirmCommoditiesPurchase`) usam o sv antigo. Os testes que só dão `dofile` em `svN.lua` usam a fixture da época. Os testes `tN.lua` são numerados pela ordem em que foram criados (próximo: **t94.lua**).
- **Os testes são de regressão por diff, não de passa/falha.** Fluxo para qualquer mudança:
  ```bash
  cp -r RoyalRevenue baseline/RoyalRevenue          # antes de mexer (ou extrair o zip da versão anterior)
  ./tests/run_all.sh ../baseline/RoyalRevenue/ out_base
  # ... mudanças ...
  ./tools/check.sh && ./tests/run_all.sh && ./tests/diff.sh out_base out
  ```
  Toda diferença precisa ser explicada (esperada pela mudança) antes de lançar.
- **Atenção à data**: vários testes dependem do dia de hoje (períodos do Livro, concentração que enche com o tempo). Rode a base e a versão nova no mesmo dia/sessão.
- **Testes velhos** já terminam em erro, por causa de funcionalidades que mudaram depois: t2–t26 (exceto alguns), t47, t48, t50, t54, t71, t72, t79. Eles valem só como diff.
- Mudança nova → criar um `tN.lua` focado que imprime os números relevantes. Exemplos: t89 (Diário intercalado), t92 (agendamento do scan), t93 (anúncio absurdo).
- Perfil de desempenho: `lua5.1 prof.lua` (tempo de cada aba), `lua5.1 -e 'TARGET=9' prof2.lua` (perfil inclusivo de uma aba do Craft), `lua5.1 -e 'MODE="livro"; TAB=5' prof3.lua`.
- **As fixtures são o SavedVariables real da conta do Rafael** (personagens, ouro, transações). Não publicar o repositório.

## Diagnosticar número errado numa receita (o caminho mais rápido)
O SavedVariables **já traz o rastro do cálculo** — na maioria das vezes não precisa pedir nada no jogo.
Ler direto o arquivo (`_retail_\WTF\Account\REDSHARKBR\SavedVariables\RoyalRevenue.lua`) com `lua5.1`
(caminho no formato do Windows, `[[C:\...]]`, que o Lua for Windows entende):
- `r.audit` de cada receita: `opMode`, `opError`, **`reagentsSent`** (exatamente o que foi mandado para a
  API: `slot N: Qx ID`) e `formula` (custo, itens esperados, venda, lucro, stats e o bloco de concentração).
  Foi `reagentsSent` que resolveu a v1.32.0: dizia `1x 244636` enquanto a receita guardava `244635`.
- Comparar `r.skill` / `r.concCost` / `r.quality` com o painel do jogo (ou do CraftSim) aponta se a
  divergência é da operação (perícia) ou só da exibição.
- `r.parts[i]`: `itemID` (qualidade escolhida), `buyItem` (a que a AH escolheu no scan), `unit`
  (valor fracionário = custo de FABRICAR, não preço de AH) e `slot`.
- `LucroCraftDB.ordersDebug`: cópia crua dos pedidos lidos (5 níveis), com `minQuality`, `reagents` e
  `npcOrderRewards`. Recompensa em moeda vem como `{ count, currencyType }`, **sem** `itemLink`.

## Lançar uma versão (o fluxo de sempre)
1. Subir `## Version:` no `RoyalRevenue/RoyalRevenue.toc` (patch = correção, minor = funcionalidade).
2. Rodar `./tools/check.sh` e os testes, e explicar o diff.
3. Rodar `./tools/build.sh`, que gera `dist/RoyalRevenue-vX.Y.Z.zip`.
4. Acrescentar ao fim de `docs/CHANGELOG.md` uma seção no estilo das anteriores:
   ```
   ## vX.Y.Z — título curto (pedido/print do Rafael)
   - Causa: ...
   - O que mudou (arquivo/função): ...
   - Teste: tN.lua (...)
   ```
5. Contar ao Rafael em poucas linhas o que mudou e o que precisa conferir no jogo.

## Pendências e coisas a conferir no jogo
- **Proposta em aberto** (v1.25.1, aguardando o "sim" do Rafael):
  - usar a lista completa da busca na AH (preço + quantidade de cada anúncio) para calcular o custo real de comprar N unidades e avisar quando falta oferta;
  - corrigir `DailySeries`, que usa `h.maxSeen` do Auctionator quando falta `minSeen` (pode trazer preço absurdo).
- Conferir no jogo:
  - ganho de desempenho da v1.25.0 (scan da profissão adiado durante crafts em sequência);
  - nomes de frames da AH usados na venda e na compra direta (`PriceInput`, `QuantityInput`, `SetPostItem`, `SelectBrowseResult`).
- Decisão antiga sem fechar: tirar a dependência do CraftSim (mapa nó → receitas e curva de concentração).
- O histórico das versões 0.x–1.0 (LucroCraft e LucroLivro separados) está nos docs do projeto "WOW Addon" no claude.ai; o essencial está resumido aqui.
