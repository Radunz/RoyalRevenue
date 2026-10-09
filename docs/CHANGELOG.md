# Royal Revenue v1.1.0 — aba Compras (04/10/2026)

Continuação de claude/RoyalRevenue-v1.0.md (estrutura, testes e pendências anteriores continuam lá).

- Escopo (decisão do Rafael): **só os materiais do Plano de concentração** (Plan.Build → it.used → parts). Culinária fica fora, como no plano.
- Arquivo novo Craft\Buy.lua (no TOC depois de Plan.lua; mudou o TOC → reiniciar o WoW). TAB = { LIST 1, PLAN 2, BUY 3, QUEUE 4, INVEST 5, SALVAGE 6, SETTINGS 7 } (Compras logo depois do Plano). /rr compras, /lucro compras (/lucro fila continua na Fila), botão no menu do minimapa.
- Histórico de preço (por item comprado = p.buyItem):
  1. Auctionator.Database:GetPriceHistory (menor preço de cada dia, 21 dias na config dele). Dia = SCAN_DAY_0 + rawDay×86400.
  2. Histórico diário do scan próprio (LucroCraftDB.ah[reino].items[id].d, dia UTC).
  3. Amostras com hora em LucroCraftDB.buyHist.items[id] = { t = {...}, p = {...} } (60 dias, até 400 por item, amostras a menos de 10 min viram uma com o menor preço). Entram por: COMMODITY_SEARCH_RESULTS_UPDATED (qualquer busca na AH), scan próprio (Own Process → Buy.RecordScan) e varredura do Auctionator (a cada 30 s com a AH aberta e ao fechar: se o preço guardado m de hoje mudou, anota com a hora; buyHist.atrM guarda o último m; no login só marca a base).
- Análise (Buy.Analyze): série diária = menor preço de cada dia (todas as fontes). Cada dia ÷ média dos dias com preço em ±3 dias (precisa de 4) → razão; média por dia da semana − 1, centrada. Confiança "ok" com 14+ dias, 7 dias da semana e 2+ amostras em cada; "low" com 4+ dias da semana; senão sem melhor dia.
  - Horário: amostras com hora ÷ a mesma média → 6 faixas de 4 h; aparece com 3+ dias diferentes em 2+ faixas.
  - Típico = média dos últimos 7 dias (sem dados: Pricing.Reference). Agora = amostra própria < 3 h → Auctionator de hoje → Pricing.MarketNow → Cost. Vendedor (VendorBuy ≤ AH) = sem padrão.
  - Selo: COMPRE se agora ≤ típico −4% (ou hoje é o melhor dia e ≤ +2%); ESPERE se ≥ +6%; senão NORMAL.
- Quantidade: precisa − (bolsa + banco do personagem); o banco do bando é um só, gasto na ordem dos grupos (logado primeiro). Alts só no tooltip (Plan.Count exposto no Plan.lua; Plan.ResetCounts).
- Tela: cartões (comprar hoje, no melhor dia + economia, quantos com selo verde, dias de histórico) · faixa com os 7 dias para a lista toda (custo típico × índice de cada material, ponderado pelo custo) · faixa de horário · grupos por personagem (ícones das profissões e custo) com ícone/qtd a comprar, preço agora vs típico, selo, 7 células coloridas (verde mais barato / vermelho mais caro, melhor dia com borda dourada) e custo. Materiais que já tem ficam no fim, apagados.
- Botões: "Escanear AH" (Own.StartScan, funciona com qualquer fonte de preço) e "Lista no Auctionator" (lista "Royal Revenue - Compras" com o que falta comprar, somado entre personagens).
- Backups: LucroCraft_backups\RoyalRevenue-v1.0.15-antes-compras.zip e RoyalRevenue-v1.1.0-2026-10-04.zip.
- Testes (container): /tmp/claude-0/t/harness.lua (novo harness: API simulada + SavedVariables reais + ordem do TOC) e t2–t5.lua: Auctionator falso com terça −10%, sábado +8% e alta de 1%/dia → a análise acha terça −9,5% e sábado +8,1% (tendência removida); faixas de horário; busca na AH; troca de todas as abas; inglês; sem Auctionator.
- A conferir no jogo: COMMODITY_SEARCH_RESULTS_UPDATED dispara com o itemID e GetCommoditySearchResultInfo(id, 1).unitPrice; a aba abre e desenha com os dados reais do Auctionator.

## v1.1.1 — comprar para X dias de craft (pedido do Rafael)
- Seletor no topo da aba Compras: agora / 1 / 2 / 3 / 5 / 7 / 14 dias (LucroCraftDB.config.buyDays, 0–30). Também /rr compras N e /lucro compras N.
- Plan.Build(days): orçamento de concentração = estimada agora + days × 24 × Rate() (≈252/dia), sem limitar a 1000 (supõe que fabrica antes de encher). Mesmo Allocate guloso. Plan.Build() sem argumento = Plano de concentração igual a antes. Plan.Rate exposto. item.budget / item.regen.
- Cartão "Comprar hoje" diz para quantos dias; cabeçalho do personagem mostra fabricações e lucro; tooltip da profissão mostra concentração usada (agora + regenerando). "Lucro previsto" ao lado do seletor.
- Teste (/tmp/claude-0/t/t6.lua, SavedVariables reais): 1 dia = 20 fabricações / 37 materiais; 3 dias = 51 / 52; 7 dias = 112 / 52. Plano sem mudança.
- Backup: LucroCraft_backups\RoyalRevenue-v1.1.1-2026-10-04.zip.

## v1.1.2 — andamento do scan da AH (pergunta do Rafael: como sei o progresso e se terminou)
- Antes: só "escaneando..." e "scan concluído: N anúncios" no chat; se a AH fechasse antes de o servidor responder, o scan ficava preso (scanning = true para sempre).
- Own.lua: estado scan = { phase "wait"|"read", i, n, t0 } e Own.ScanStatus(). Ticker de 1 s durante o scan; cancela se a AH fecha na espera ou após 120 s sem resposta (mensagem no chat). Process ignora REPLICATE_ITEM_LIST_UPDATE repetido. Avisa ns.Buy.ScanProgress a cada passo de 4000 anúncios.
- Aba Compras: barra ao lado do botão: "aguardando o servidor… N s" → "lendo N%" → "último scan há X min" (verde enquanto o próximo não está liberado). Botão: "Escaneando…" / "Escanear (N min)" / "Escanear AH". Tooltip com as etapas, hora do último scan e quando libera. No fim a aba é redesenhada (preços novos). Atualiza só a barra e o botão, sem redesenhar a aba.
- Teste: /tmp/claude-0/t/t7.lua (espera, leitura 44% → 88%, fim, cancelamento ao fechar a AH).

## v1.2.0 — aba Vender (pedido do Rafael: "faz para vendas agora")
- Arquivo novo Craft\Sell.lua (TOC depois de Buy.lua → reiniciar o WoW). TAB = { LIST 1, PLAN 2, BUY 3, SELL 4, QUEUE 5, INVEST 6, SALVAGE 7, SETTINGS 8 }. Nome "Vender" (o "Vendas" do Livro-caixa é o histórico). /rr vender [dias], /lucro vender [dias], menu do minimapa.
- Itens: saída de cada craft planejado (r.concItemID ou r.itemID) × crafts × r.expQty, com os mesmos dias da aba Compras (Buy.Days compartilhado) + o que já tem do item (personagem; banco do bando só no primeiro grupo).
- Mesma análise (Buy.Analyze); novo a.bestSell = dia de índice MAIS ALTO. Buy.Tracked passou a incluir as saídas (r.itemID, r.concItemID), então buscas/scans também registram os preços de venda.
- Selo: VENDA se agora ≥ típico +4% (ou hoje é o melhor dia de venda e ≥ −2%); SEGURE se ≤ −6%; NORMAL. Cores invertidas (verde = preço acima da média).
- Tela: cartões (vender hoje − corte da AH, no melhor dia, quantos com VENDA, histórico), 7 dias da lista toda (melhor = maior receita), horário, grupos por personagem com fabrica/tem/vende por dia, preço agora vs típico, selo, 7 células e receita líquida. Barra de scan também nesta aba (Buy.DrawScan por chave). "Lista de venda no Auctionator" (Royal Revenue - Vender).
- Refatoração no Buy.lua: Buy.DrawDays, Buy.DrawScan, Buy.UI (utilidades de desenho), MiniDays(..., sell). Cartão "No melhor dia" diz "hoje já está mais barato/rende mais" quando o preço de agora já bate o melhor dia.
- Teste: /tmp/claude-0/t/t8.lua (sábado +8% → melhor dia de venda; terça continua o de compra; 8 abas abrem; inglês).
- Backup: LucroCraft_backups\RoyalRevenue-v1.2.0-2026-10-04.zip.
- Limitação: equipamento fabricado não é commodity; o Auctionator guarda por link (ilvl), então esses itens aparecem "sem dados"/"SEM PREÇO" no padrão por dia.

## v1.2.1 — Vender = itens da BOLSA + item sendo anunciado (pedido do Rafael, com print da aba)
- A aba deixou de usar o plano: lista os itens da bolsa do personagem logado (bolsas 0..ReagentBag) que podem ir para a AH: não vinculados (info.isBound), qualidade ≥ 1 (sem cinzas), classe ≠ 12 (missão). Empilháveis agrupados por itemID; não empilháveis (equipamento) por link. Itens sem preço nenhum ficam ocultos (contados). Até 80 linhas, ordem por receita. "no plano" marca itens do Plano de concentração. O seletor de dias saiu desta aba.
- Item sendo anunciado (Sell.FindPosting, conferido a cada 0,5 s com a AH aberta): Auctionator = AuctionHouseFrame.AuctionatorSellingFrame.SaleItemFrame.itemInfo (itemLink, count, location); Blizzard = AuctionHouseFrame.CommoditiesSellFrame / ItemSellFrame :GetItem() (ItemLocation). Mudou → se a janela do Royal Revenue está aberta, troca para a aba Vender (config sellFocus, padrão ligado) e mostra o cartão "Anunciando agora": ícone, tem N, vende/dia, conselho (venda agora / segure até X / normal), preço agora × típico, selo, 7 dias grandes com %, receita. A linha do item na lista fica destacada.
- Equipamento: histórico do Auctionator é por link (nível de item), então só o preço da fonte (Pricing.SaleByLink → TSM), sem padrão por dia.
- Buy.ExtraTracked (definido em Sell.lua): itens empilháveis da bolsa entram no registro de preços (buscas, scans, Auctionator). BAG_UPDATE_DELAYED redesenha a aba.
- Teste: /tmp/claude-0/t/t9.lua (bolsa simulada: vinculado, missão e cinza fora; equipamento sem padrão; slot de venda da Blizzard e do Auctionator; troca automática para a aba). t8.lua é da versão por plano (não vale mais).
- Backup: LucroCraft_backups\RoyalRevenue-v1.2.1-2026-10-04.zip.
- A conferir no jogo: nomes dos frames (AuctionatorSellingFrame como filho de AuctionHouseFrame; CommoditiesSellFrame:GetItem) e se info.isBound pega os itens "vinculados ao bando".

## v1.3.0 — histórico de preço do item selecionado (parte de baixo da aba Vender)
- Pedido do Rafael + "veja como outros softwares de venda apresentam esses dados". Referências (04/10): TSM (site: períodos 1S/1M/3M/6M, valor de mercado com % de tendência, taxa de venda, vendidos/dia), The Undermine Journal (gráfico de linhas 7/14/30/90 dias/tudo com mínimo, máximo, média, mediana), BootyBayBroker (séries liga/desliga: mínimo, média, valor de mercado; gráfico de volume em barras; distribuição dos anúncios atuais).
- Seleção: clique numa linha da lista (ou no cartão "Anunciando agora"); padrão = item anunciado, senão o de maior receita. Sell.selected = itemID (empilhável) ou link (equipamento). Item novo no slot de venda limpa a seleção.
- Buy.History(id): dia a dia { min, max, avail, src{atr, own, samp}, samples{t,p} } juntando Auctionator (minSeen/maxSeen/available), scan próprio (l, a) e amostras com hora.
- Desenho: cabeçalho com período 7d/14d/30d/Tudo · 6 resumos (agora vs típico; média 7 dias com seta e % vs semana anterior; menor e maior do período com data e dia; vendas/dia; disponível) · séries liga/desliga (Menor, Maior, Média 7 dias, Típico tracejado, Volume) · gráfico de linhas 150 px (fundo verde no melhor dia de venda, linha branca = hoje, tooltip por dia com amostras com hora) · volume em barras · datas no eixo · tabela dia a dia recolhível. Config em LucroCraftDB.config.sellHist { range, show{}, table }.
- Canvas:Line (Visual.lua, pool "line", CreateLine + SetStartPoint/SetEndPoint). Setas por textura (Interface\Buttons\Arrow-Up-Up/Arrow-Down-Up); "…" e "–" trocados por "..." e "-" (fonte do jogo).
- Teste: /tmp/claude-0/t/t10.lua (30d, 7d + tabela, tudo sem a série Menor, equipamento sem histórico).
- Backup: LucroCraft_backups\RoyalRevenue-v1.3.0-2026-10-04.zip.

## v1.3.1 — lista da bolsa com rolagem própria + grupos minimizáveis (pedido do Rafael, prints da aba Vender)
- Visual.lua: V.CreateSub(cv) = área com rolagem DENTRO de outra tela (ScrollFrame filho do canvas + Slider vertical à direita, polegar dourado proporcional, roda do mouse). Canvas:Place(x, y, w, h), Canvas:UpdateBar; End de sub não força altura mínima. Show/Hide também mostram/escondem a barra.
- Sell.lua: lista da bolsa desenhada em DrawRows(sub, ...) dentro de cv._sellList, altura máx. LIST_H = 360 (9 linhas), encolhe se tiver menos. Sell.Group = cabeçalho minimizável igual ao do Investimento (+/−, faixa azul, filete dourado; LucroCraftDB.config.sellCollapsed[bag|hist]). Grupo "Bolsa de X" com "N itens · receita"; grupo "Histórico de preço · item" com os botões 7d/14d/30d/Tudo no próprio cabeçalho.
- Teste: /tmp/claude-0/t/t11.lua (36 itens → conteúdo 1440 px em 360 px com barra; minimizar/expandir os dois grupos).
- Backup: LucroCraft_backups\RoyalRevenue-v1.3.1-2026-10-04.zip.

## v1.3.2 — lista da bolsa por expansão > profissão de origem (pedidos do Rafael)
- Expansão = 15º retorno de C_Item.GetItemInfo (expansionID); nome = _G["EXPANSION_NAME"..x] (idioma do cliente) com reserva em inglês. Ordem: expansão ATUAL no topo (GetExpansionLevel, ou a maior vista), depois as demais por lançamento (Classic → ... → The War Within); sem expansão = "Outros" no fim. Só aparecem expansões/profissões com itens.
- Profissão de origem (Sell.SourceProf): 1) item que alguma receita sua fabrica (CraftMap: r.itemID/r.concItemID → e.parentID, de todas as profissões salvas); 2) pela classe/subclasse: reagente (7) tecido→Alfaiataria, couro→Esfolamento, metal e pedra→Mineração, erva→Herborismo, culinária→Culinária, encantamento→Encantamento, escrivania→Escrivania, joalheria→Joalheria, peças→Engenharia; consumível (0) poção/elixir/frasco→Alquimia, comida→Culinária, pergaminho/runa Vantus→Escrivania, melhoria→Encantamento, bandagem→Alfaiataria, explosivo→Engenharia; gema→Joalheria; melhoria de item (8)→Encantamento; glifo→Escrivania; equipamento de profissão (19) e receita (9) pela subclasse; resto = "Outros". Nome pelo C_TradeSkillUI.GetTradeSkillDisplayName (reserva PT/EN). Profissões em ordem ALFABÉTICA, "Outros" no fim.
- Grupos minimizáveis: expansão (Sell.Group, chave "x:N") e profissão (ProfHeader, "x:N:p:skillLine"), com "N itens · receita". Linha do item = DrawRow.
- Testes: /tmp/claude-0/t/t12.lua e t13.lua (Midnight, Classic, Dragonflight, The War Within; Alquimia, Encantamento, Herborismo, Outros).
- Atenção ao instalar: um commit para o mesmo nome de arquivo no PC ficou com o conteúdo antigo; usar nome novo (v1.3.2b) e conferir md5.
- Backup: LucroCraft_backups\RoyalRevenue-v1.3.2-2026-10-04.zip.

## v1.3.3 — ordem das expansões (pedido do Rafael)
- Atual no topo; depois da mais recente para a mais antiga (Midnight → The War Within → Dragonflight → ... → Classic); "Outros" no fim. Profissões continuam em ordem alfabética.
- Backup: LucroCraft_backups\RoyalRevenue-v1.3.3-2026-10-04.zip.

## v1.4.0 — reorganização da navegação (pedidos do Rafael)
- Menu de cima (Shell.Decorate): **Craft | Mercado | Livro-caixa**. Craft e Mercado usam a mesma janela (LucroCraftFrame); só muda o grupo de abas e o título ("Royal Revenue — Craft/Mercado"). root.UpdateNav(frame, atual) destaca o módulo. root.Switch(nil, destino) descobre a origem; Craft↔Mercado não esconde a janela. RoyalRevenueDB.last = craft | mercado | livro.
- Abas: TAB = { LIST 1, PLAN 2, INVEST 3, SALVAGE 4, QUEUE 5, SETTINGS 6, BUY 7, SELL 8 }. Craft = Receitas, Plano de concentração, Investimento, Destruir, Fila de craft (rótulo novo; EN "Craft queue"). Mercado = Compras, Vender. UI.ModeOf(id), UI.LayoutTabs(mode) (mostra/encadeia só as do grupo), UI.Mode(), UI.LastTab(mode) (lembra a última de cada grupo).
- Abas no TOPO: penduradas acima da janela (BOTTOMLEFT da 1ª aba no TOPLEFT da janela), nas duas janelas (Craft/Mercado e Livro-caixa). Modelo PanelTopTabButtonTemplate se C_XMLUtil.GetTemplateInfo achar (root.TopTabTemplate no Brand.lua); senão o de baixo. SetClampRectInsets(0, 0, 30, 0) para as abas não saírem da tela.
- Configurações do Craft saíram das abas: engrenagem no título (como no Livro-caixa, TOPRIGHT −30,−4). Clique abre, clique de novo volta para a aba anterior; não troca o grupo (ModeOf(SETTINGS) = grupo atual).
- Comandos: /rr mercado; /rr compras|vender [dias] abrem no Mercado; menu do minimapa com seção Mercado.
- Teste: /tmp/claude-0/t/t14.lua (troca Craft/Mercado/Livro, última aba de cada grupo, comandos, engrenagem nos dois grupos). Harness: campos minúsculos ausentes agora são nil.
- A conferir no jogo: aparência do PanelTopTabButtonTemplate e se o PanelTemplates não reposiciona as abas.
- Backup: LucroCraft_backups\RoyalRevenue-v1.4.0-2026-10-04.zip.

## v1.4.1 — menu Craft | Mercado | Livro-caixa acima das abas (print do Rafael)
- Shell.Decorate: botões do menu 96×20, primeiro com BOTTOMLEFT no TOPLEFT da janela (+10, +30): ficam numa linha acima das abas (que continuam penduradas logo acima da janela). SetClampRectInsets(0, 0, 56, 0) nas duas janelas.
- Backup: LucroCraft_backups\RoyalRevenue-v1.4.1-2026-10-04.zip.

## v1.4.2 — menu de cima como barra (print do Rafael: "ficou estranho")
- Os 3 botões UIPanelButton soltos acima das abas viraram uma barra (frame.rrBar): faixa azul-noite da largura da janela, presa em cima das abas (BOTTOM na janela +28, altura 26), filete dourado em cima e embaixo, ícone do addon + "Royal Revenue" + separador, módulos como texto (Craft | Mercado | Livro-caixa); o atual em dourado com fundo azul e sublinhado dourado. root.UpdateNav atualizado.
- Backup: LucroCraft_backups\RoyalRevenue-v1.4.2-2026-10-04.zip.

## v1.5.0 — menu e abas DENTRO da janela (print do Rafael: "ainda estranho")
- Barra de título: ícone + "Royal Revenue" + separador + Craft · Mercado · Livro-caixa (texto, atual em dourado com fundo azul e sublinhado); o título antigo "Royal Revenue — X" fica escondido (frame.titleFS). Engrenagem e fechar continuam à direita.
- Faixa de abas dentro da janela, logo abaixo do título (root.MakeTabStrip: y −23, 25 px, azul-noite escuro, filete dourado embaixo). Abas planas root.MakeTab (texto, ativo dourado + sublinhado), root.SelectTab no lugar do PanelTemplates (removido nas duas janelas). Sem SetClampRectInsets.
- Conteúdo desceu 26 px: Craft (linha de controles −56, lista −102, cabeçalhos −82, pane −56/−82, barra da Fila −54, canvas da Fila −82, Visual.Create −56, Settings −56, altura padrão 128 + linhas, cálculo de slots −128); Livro (entidade/período −58, fundo/linha −94/−93, canvas −100).
- Teste: t14 (navegação), t11 (lista com rolagem), t15 (abas do Livro).
- Backup: LucroCraft_backups\RoyalRevenue-v1.5.0-2026-10-04.zip.

## v1.5.1 — números no formato 000.000.000,00 (pedido do Rafael)
- root.Num(n, casas) no Brand.lua: milhar com ponto, decimal com vírgula; zero nunca sai negativo. Vale em qualquer idioma do cliente.
- Ouro (Craft Pricing.FormatGold, Livro P.FormatGold e P.Acct) sempre com 2 casas: 12.761,00o; valores menores que 0,005o sem sinal.
- Todos os string.format("%.Nf", x) de exibição em Craft e Livro (exceto Locale) viraram root.Num(x, N); BreakUpLargeNumbers → root.Num(x, 0). Mercado: "tem/precisa/comprar/bando" com root.Num; tooltips e histórico (disponível, volume máx.) também.
- Teste: t16.lua (0 → 0,00; 42632 → 42.632; 1234567,891 → 1.234.567,89; −12761,5 → −12.761,50).
- Backup: LucroCraft_backups\RoyalRevenue-v1.5.1-2026-10-04.zip.

## v1.6.0 — Plano: SEGURE a concentração para a receita mais lucrativa (caso do Madunz)
- Problema: Allocate é guloso; sem concentração para a receita de maior ouro/ponto, gastava na próxima (pior), queimando pontos que rendem mais esperando.
- Plan.Build: best = 1ª receita (ordem ouro/ponto) cujo concCost cabe na barra (≤ max). Com planHold (padrão ligado, Configurações > Plano de concentração), o Allocate só usa a best e as que rendem até HOLD_TOL = 5% a menos por ponto.
  - Sem concentração para a best mas o guloso faria algo: item.hold = { row, need = concCost, waitH = (need − orçamento)/Rate, altGain/altUsed/altPts (o que o guloso faria), extra = altPts × best.perConc − altGain }.
  - Fez crafts e sobrou: item.kept = { pts, row, waitH } (a sobra fica para o próximo craft da best).
- Plano (visual): ícone da best apagado com borda dourada + selo SEGURE + "até X de concentração · ~Yh" + "+Zg vs. gastar agora em <receita>"; tooltip com o que o guloso faria e o ganho por esperar. "guarda ~N / próximo em Xh" no lugar de "sobram ~N". Texto: linha "SEGURE até…".
- Compras/Vender (Plan.Build(dias)) usam a mesma regra.
- Teste: /tmp/claude-0/t/t17.lua (300 de conc. → SEGURE até 600, ~29h, +13.500g; 900 → 1× boa e guarda 350; desligado → 3× pior).
- Backup: LucroCraft_backups\RoyalRevenue-v1.6.0-2026-10-04.zip.

## v1.6.1 — DRE: receitas de atividades em colunas Ouro | Itens + linhas coloridas (pedido do Rafael)
- Livro/UI.lua RenderDRE: colunas Ouro | Itens | Período | AV % | Anterior | AH % (Ouro/Itens só preenchidas nas receitas de atividades). 3.1 "Receitas de atividades" = ouro + itens; uma linha por atividade (código 3.1.xx) com as duas formas lado a lado e o total; tooltip com ouro, itens e os itens recebidos. A antiga seção 3.2 sumiu da DRE (o Diário continua com os códigos 3.2.xx nos lançamentos de itens). 3.3 continua 3.3.
- StmtRow (todas as demonstrações do Livro): faixa dourada nos grupos principais, faixa azul nos subgrupos (código, recuo 1), zebra azul leve nas linhas de detalhe; recomeça a cada desenho.
- Percentuais no formato BR (P.Pct e % de vendas da lista de receitas): 64,0%.
- Teste: /tmp/claude-0/t/t18.lua (DRE com SavedVariables reais).
- Backup: LucroCraft_backups\RoyalRevenue-v1.6.1-2026-10-04.zip.

## v1.6.2 — zebra padrão em todas as listas longas (pedido do Rafael)
- Brand.lua: root.ZEBRA = azul pomerano a 10% e root.Zebra(cv, i, x, y, w, h) (pinta as linhas pares).
- Aplicado em: Receitas (linhas da lista principal, antes branco 4%), tabelas da aba Destruir (V.Table), Fila de craft (fila e lista de compras, antes branco 3%), Compras (materiais), Vender (itens da bolsa, recomeça em cada profissão; tabela dia a dia do histórico). Livro-caixa: COL.alt passou a 10% (Painel, Centros, Diário, Vendas etc.); StmtRow só faz a zebra automática quando a tela não passa alt (evita pintar duas vezes).
- Teste: t19.lua (todas as abas do Craft/Mercado sem erro), t2, t11, t12, t14, t18.
- Backup: LucroCraft_backups\RoyalRevenue-v1.6.2-2026-10-05.zip.

## v1.7.0 — materiais próprios usados em pedidos de fabricação (pergunta do Rafael)
- Antes: o Livro-caixa só lançava consumíveis usados (classe 0, 4.5.01); reagentes que saíam da bolsa num pedido sumiam sem custo (comissão 3.3.03 parecia lucro inteiro).
- Material do cliente: nunca passa pelas bolsas do artesão (fica no pedido e é consumido direto) → não é lançado, e está certo. Recompensas de pedidos de NPC (itens, Moxie) chegam pelo correio e entram como Pedidos de fabricação · itens (3.1.13, coluna Itens) quando a carta é aberta; a comissão em ouro entra na entrega (3.3.03).
- Livro/Ledger.lua: TRADE_SKILL_CRAFT_BEGIN(receita) com C_CraftingOrders.GetClaimedOrder() da mesma receita → fotografa as bolsas (BagAll); UNIT_SPELLCAST_SUCCEEDED do player marca feito; no BAG_UPDATE_DELAYED seguinte (ou CRAFTINGORDERS_FULFILL_ORDER_RESPONSE) o que diminuiu = material próprio. Cada item → Diário 4.5.02 "Materiais próprios em pedidos de fabricação" (histórico = nome do item do pedido, a preço de mercado P.Value) e day.act.orders.cost.mat (+ sub por pedido). Interrompido/falhou → descarta. O consumo de consumíveis não conta durante o craft do pedido.
- Visão gerencial (como os consumíveis), não entra na DRE: o material já entrou na DRE quando foi comprado (4.3) ou ganho (3.1 itens).
- Centros de resultado: nova faixa "Serviços" com "Pedidos de fabricação" = comissão (m.inc.order) − materiais próprios (act.orders.mat), tooltip por pedido. Agregações (dia/período/merge) somam .mat.
- Teste: /tmp/claude-0/t/t20.lua (pedido usando 4+2 reagentes → 2 lançamentos 4.5.02; outra receita com pedido reivindicado não conta) e t21.lua (Centros: 3.3.03 11.227,06 − 6,00 = 11.221,06).
- A conferir no jogo: TRADE_SKILL_CRAFT_BEGIN passa o spellID da receita; GetClaimedOrder().spellID igual; reagentes consumidos antes do BAG_UPDATE_DELAYED seguinte ao SUCCEEDED.
- Backup: LucroCraft_backups\RoyalRevenue-v1.7.0-2026-10-05.zip.

## v1.8.0 — Investimento > Segunda profissão (pedido do Rafael)
- Arquivo novo Craft\SecondProf.lua (TOC depois de InvestView → reiniciar o WoW). Grupo minimizável "Segunda profissão" no fim da aba Investimento (também na tela de coleta e quando não há profissão aberta). Só aparece se o personagem logado tem menos de 2 profissões principais (GetProfessions/GetProfessionInfo → skillLine).
- Candidatas: as 11 principais menos as que ele tem (sem repetir).
  - Fabricação: lucro por semana com a concentração = Invest.WeeklyValue(entrada) na MELHOR entrada da conta com aquela profissão (e.parentID); racial de perícia = WeeklyValue(e, { skill = bônus }) − base. Tooltip com as melhores receitas e de qual personagem vêm os dados (aviso: conhecimento/equipamento daquele personagem).
  - Coleta: valor por hora = Gather.Analyze(valor de 100 coletas / 100 × coletas/h) dos registros de todos os personagens; racial de Fineza = fin.per × pontos / 100 × coletas/h; Destreza 25% conta metade (parte do tempo é deslocamento).
  - Ranking por total (valor + racial), em duas listas (semana × hora não se comparam). "combina com X" quando completa a profissão que ele tem (Herborismo↔Alquimia/Escrivania, Mineração↔Ferraria/Joalheria/Engenharia, Esfolamento↔Couraria, Encantamento↔Alfaiataria). Sem dados → apagado, "abra esta profissão em algum personagem".
- Raciais (UnitRace raceFile; pesquisa warcraft.wiki.gg 05/10, valores desde o 10.0.2): Draenei Joalheria +5; Gnomo Engenharia +5; Elfo Sangrento Encantamento +5; Goblin Alquimia +5; Filho da Noite Escrivania +5; Draeneiano Forjado a Luz Ferraria +5 (com a Forja da Luz invocada); Anão Ferro Negro Ferraria +5 e +10% velocidade; Tauren Herborismo +5 e +25% Destreza; Tauren Altamontês Mineração +5 e +25% Destreza; Worgen Esfolamento +5 e +25% Destreza; Kultireno +2 em todas; Terrano +25 Fineza (coletas); Mecagnomo ferramentas próprias (sem valor em ouro). Pandaren Culinária +5 fica fora (secundária).
- Teste: /tmp/claude-0/t/t22.lua (Gnomo com Alquimia: Ferraria 1.784/sem, Escrivania, Joalheria, Encantamento, Engenharia +7 racial, Couraria, Alfaiataria; coleta Herborismo 462/h combina com Alquimia, Mineração; com 2 profissões o grupo some).
- Backup: LucroCraft_backups\RoyalRevenue-v1.8.0-2026-10-05.zip.

## v1.8.1 — Destruir: recuperação da Culinária (print do Rafael: Practically Pork)
- Midnight tem receitas de recuperação na Culinária (Practically Pork de partes de animais, Thalassian Fillet, Plant Protein; saída depende da perícia). A captura já pegava qualquer isSalvageRecipe, mas o filtro da aba (ns.MyProfessions) só olhava as 2 principais. Agora inclui as secundárias (GetProfessions: arqueologia, pesca, culinária).
- No SavedVariables de 05/10 nenhuma receita de Culinária estava capturada: entra ao abrir a Culinária (scan) ou ao selecionar a receita.
- Teste: /tmp/claude-0/t/t23.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.8.1-2026-10-05.zip.

## v1.8.2 — Destruir: Desenvoltura medida (pedido do Rafael, druida Radunz fazendo recuperação na Culinária)
- Diagnóstico (SavedVariables 05/10): Radunz tinha 170 recuperações de Plant Protein (1296450) e 6 de Practically Pork (1296449) registradas com casts e saídas, mas nenhum registro do material devolvido. O custo por destruição usava sempre a quantidade cheia (perCast) → Desenvoltura = 0. As receitas normais de Culinária têm res 8,78% no scan (ok); o problema era só na aba Destruir.
- Salvage.lua: duas medições por receita × material, em salvage.obs[char][receita][material]:
  - bolsa: na chamada de CraftSalvage guarda a quantidade do material na bolsa (pend.base); a cada destruição (UNIT_SPELLCAST_SUCCEEDED) pend.n++; no BAG_UPDATE_DELAYED soma bagCasts/bagUsed (diferenças acumuladas; ignora se entrou material de outro lugar).
  - jogo: TRADE_SKILL_ITEM_CRAFTED_RESULT.resourcesReturned (uma vez por destruição) → saved; savedCasts conta toda destruição; só vale se o campo já apareceu (resSeen).
- S.UsePerCast(receita, material, perCast): com 5+ destruições medidas, gasto real = bagUsed/bagCasts (preferido) ou perCast − saved/savedCasts. Custo da linha = preço × gasto real. Tabela: "Qtd" mostra o gasto real (2 casas) e coluna nova com o nome da Desenvoltura do cliente = % economizado ("—" sem medição). Stats dos alts somam a medição.
- As 170 destruições antigas não têm a medição; conta a partir de agora.
- Teste: /tmp/claude-0/t/t24.lua (10 destruições, 2 sem gastar → 0,80 por destruição, 20%). Backup: LucroCraft_backups\RoyalRevenue-v1.8.2-2026-10-05.zip.

## v1.8.3 — Desenvoltura 100% na aba Destruir (print do Rafael: addon 100%, jogo 9%)
- SavedVariables 05/10 (Radunz, Practically Pork 1296449): Gamey Flank 57 destruições bagUsed=0 / resourcesReturned 1 (1,8%); Folded Wing 55 bagUsed=0 / 4 devolvidos (7,3%). resourcesReturned funciona e bate com os ~9% do jogo; a medição pela bolsa conferia no BAG_UPDATE_DELAYED, que chega ANTES de o material sair → 0 gasto → 100%.
- Correções: (1) bolsa confere 3 s depois da última destruição (C_Timer) ou na próxima chamada de CraftSalvage, não mais no BAG_UPDATE; (2) resourcesReturned (jogo) tem prioridade; bolsa só se não houver o campo e bagUsed > 0; (3) limpeza única (salvage.bagFix1) apaga bagCasts/bagUsed gravados pela v1.8.2.
- Teste: /tmp/claude-0/t/t25.lua (dados reais → 1,8% e 7,3% "game"; simulação com consumo atrasado e uma chamada por destruição → 10 destruições, 9 gastas, 10%). Backup: LucroCraft_backups\RoyalRevenue-v1.8.3-2026-10-05.zip.

## v1.9.0 — vender direto pela aba Vender + o addon segue a casa de leilões (pedido do Rafael)
- Proteção: colocar o item no slot de venda não é protegido (AuctionHouseFrame:SetPostItem, como Auctionator/TSM); postar (C_AuctionHouse.PostCommodity/PostItem) precisa de clique do jogador → só pelo botão.
- Sell.lua: BagItems guarda bag/slot da maior pilha de cada item. Com a AH aberta (e fora de combate):
  - clique na linha → Sell.PutOnAH: SetPostItem(ItemLocation) (reserva: SetDisplayMode + SellFrame:SetItem); 0,6 s e 1,8 s depois aplica PriceInput:SetAmount(preço sugerido) e QuantityInput:SetQuantity(qtd) (a Blizzard ajusta o preço quando a busca volta). Também seleciona o histórico.
  - botão "Postar" na linha (selo ≠ SEM PREÇO) → Sell.Post: commodity PostCommodity(loc, 24 h, qtd, preço/un.); equipamento PostItem(loc, 24 h, 1, nil, preço). Eventos: AUCTION_HOUSE_AUCTION_CREATED (chat "anunciado: Nx item a preço"), POST_WARNING (confirmar na janela da AH), POST_ERROR.
  - Preço sugerido (Sell.SuggestPrice): menor anúncio de agora; selo SEGURE → preço típico; commodity em múltiplos de 1 prata. Quantidade: GetAvailablePostCount (limitado ao que tem na bolsa); equipamento 1.
- AUCTION_HOUSE_SHOW → abre o addon em Mercado > Compras (config ahAutoOpen, padrão ligado, Configurações > Geral). Hook em AuctionHouseFrame:SetDisplayMode: CommoditiesSell/ItemSell → Vender; Buy/ItemBuy/CommoditiesBuy → Compras (só com a janela do addon aberta). OnShow da aba Selling do Auctionator → Vender.
- Teste: /tmp/claude-0/t/t26.lua (AH abre → Compras; modos da AH → Vender/Compras; PutOnAH com preço 30.100 e qtd 30; PostCommodity(slot 1, 24 h, 30, 30.100); PostItem do equipamento; 3 botões Postar). Harness: GetMoneyString.
- A conferir no jogo: nomes PriceInput/QuantityInput nos SellFrames; se SetPostItem existe com esse nome; avisos de preço.
- Backup: LucroCraft_backups\RoyalRevenue-v1.9.0-2026-10-05.zip.

## v1.10.0 — Mercado > Comprar receitas (pedido do Rafael: comprar no servidor populoso receitas que os alts não têm)
- Arquivo novo Craft\RecipeShop.lua (TOC depois de Sell.lua → reiniciar o WoW). TAB.RECIPES = 9, grupo Mercado (Compras · Vender · Comprar receitas). /rr livros (ou /rr recipes), menu do minimapa.
- Faltando = receita em algum e.unknown e em nenhum e.rows de toda a conta. Origem (texto da receita): Drop/Tesouro/Criaturas/sem origem → "ah"; Vendedor → "vendor" (mostra onde comprar); treinador, especialização, descoberta, missão, pesca etc. ficam ocultas (contadas). SV 05/10: 143 compráveis (37 drop, 106 vendedor), 71 ocultas.
- Quem aprende = personagem com aquela profissão (e.unknown) de maior WeeklyValue. Ganho/semana = concentração da semana (Invest.ConcPerWeek, exposto) passa da melhor receita atual (info.perConc) para a nova se lucro/ponto for maior, limitada a vendas/dia × 7: n × (lucro − concCost × perConc atual). Sem concentração → lucro por craft.
- Receita não é commodity: memória por servidor LucroCraftDB.recipeAH[reino] = { name, scanT, items[recipeID] = { item, min, n, t } }. Entra pelo scan completo (Own Process: todo anúncio cujo nome tem ":" e casa "Receita: <nome>" com uma faltante; o scan substitui a lista do reino) e pelas buscas (AUCTION_HOUSE_BROWSE_RESULTS_UPDATED/ADDED → GetBrowseResults).
- Tela: cartões (faltando, à venda aqui + hora do scan, melhor ganho/semana, servidores vistos) · filtros "Mostrar de vendedor" / "Só com anúncio aqui" (config rsVendor/rsOnlyHere) · grupos por profissão (alfabético, minimizáveis) com zebra: ícone, nome, "aprende: Alt · origem", lucro/craft, ganho/semana, preço aqui (qtd) ou o de outro servidor, "paga em" (semanas ou crafts), selo COMPRE (≤4 sem ou ≤10 crafts) / NORMAL / CARO (>12 sem ou >50 crafts) / SEM PREÇO / VENDEDOR. Tooltip: quem aprende, origem, outros servidores (preço, há quanto tempo), dica do banco do bando. Clique no nome com a AH aberta busca a receita. Botões Escanear AH e "Lista no Auctionator" (Royal Revenue - Receitas, só as de drop, não exata).
- Teste: /tmp/claude-0/t/t27.lua (scan com "Recipe: Puffer Plate" → COMPRE, 5,7 crafts; outro servidor no tooltip; busca da navegação captura 12,34g; aba 9 no Mercado; inglês).
- Instalação: unzip no PC não sobrescreve ("cannot delete old") → extrair com python (open 'wb'); md5 do conjunto conferido.
- A conferir no jogo: nome do anúncio no GetReplicateItemInfo ("Receita: X" / "Pattern: X" bate com o nome da receita), AUCTION_HOUSE_BROWSE_RESULTS_UPDATED com receitas.
- Backup: LucroCraft_backups\RoyalRevenue-v1.10.0-2026-10-05.zip.

## v1.10.1 — Comprar receitas: grupos por expansão + lucro realista (pedido do Rafael: "alguns não vendem por esse preço")
- Grupos expansão > profissão como na aba Vender (atual no topo, depois da mais recente à mais antiga; profissões em ordem alfabética; minimizáveis "rx:N" / "rx:N:p:prof"). Expansão = e.expansion do scan da profissão; linhas com nome de continente (Dragon Isles, Khaz Algar, Kul Tiran/Zandalari, Draenor...) mapeadas. Sell.Group/ProfHeader aceitam onToggle; Sell.ProfHeader/ProfIcon exportados.
- Preço realista = menor entre: preço do scan da profissão, preço × (1 + tendência) quando a tendência (DBRecent vs DBHistorical) cai mais de 5%, e Pricing.FlipReference (DBMarket / DBRegionMarketAvg / DBRegionSaleAvg). Lucro/craft e ganho/semana usam esse preço; o do scan aparece embaixo em cinza quando é bem maior. Ex.: Thalassian Competitor's Cloth Leggings 3.999g no scan, tendência −87% → 533g, lucro 3.779g → 486g.
- Coluna Vende/dia (região; laranja se vende pouco). "Vende pouco" = vendas/dia < minSoldPerDay ou DBRegionSaleRate < 5% → selo VENDE POUCO (laranja) no lugar de COMPRE/NORMAL. Tooltip: preço do scan, preço realista e por quê, lucro no preço do scan, vendas/dia, chance de vender.
- Teste: /tmp/claude-0/t/t28.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.10.1-2026-10-05.zip.

## v1.10.2 — Comprar receitas: preço no NPC + preço visto na AH + "não vai para a AH" (print do Rafael)
- Coluna "Preço NPC / AH" (2 linhas): NPC = custo do texto da origem (1º vendedor; moedas/itens com ícone 12 px; ouro vira cobre e entra no "paga em") ou o preço lido no próprio vendedor; AH = preço aqui (qtd) · outro servidor (preço, "há X" se não estava no último scan) · "AH x · há X" (já esteve aqui) · "não está à venda aqui" · "nunca vista na AH" · laranja "vinculada: não vai para a AH" / "vinculada ao bando: sem AH".
- Memória por servidor guarda o último visto: item sumido no scan fica n=0 com seenMin/seenT. Receitas de vendedor também entram no índice de nomes (AH e buscas).
- LucroCraftDB.recipeInfo[recipeID] = { item, bind (14º retorno do GetItemInfo), vendor (cobre), vendorT }: preenchido no MERCHANT_SHOW/UPDATE (GetMerchantItemLink "[Receita: X]" + C_MerchantFrame.GetItemInfo price) e a cada anúncio visto. bind 1/4 = vinculada ao pegar; 7/8/9 = ao bando/conta → sem AH.
- "Paga em" usa o mais barato entre AH daqui e NPC em ouro. Origem na linha sem "Cost:" e só o 1º vendedor. Colunas reposicionadas (preço 180 px).
- Teste: /tmp/claude-0/t/t29.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.10.2-2026-10-05.zip.

## v1.10.3 — Comprar receitas: mais barato entre os servidores (pedido do Rafael)
- m.cheap = menor preço entre os servidores com anúncio no último scan (aqui + outros com n > 0); m.ahRealms = quantos. Linha AH: "AH preço (qtd)" + "aqui" (cinza) ou nome do servidor em verde quando o mais barato é em outro. "Paga em" e selo usam o mais barato (ou o NPC em ouro, se menor). Tooltip: "Mais barato: preço · servidor".
- Teste: /tmp/claude-0/t/t30.lua (aqui 999g, Stormrage 400g → Stormrage). Backup: LucroCraft_backups\RoyalRevenue-v1.10.3-2026-10-05.zip.

## v1.11.0 — Transmutações (análise do craft do Madunz, 05/10 17:47)
- Dado real: Transmute: Mote of Light (10 Primal Energy + 2× 242651 → 8 Light), mc 6,4%, saiu 18 (proc +10). Esperado 8,67.
- Problemas achados: (1) 242651 é VINCULADO → custava 0. Sai da recuperação "Recycle Potions" (1233129; Madunz 16× com 268954 → 32, 2 por destruição, 3 entradas). (2) Entrada dos transmutes custada pelo "fabricado" de outro transmute (ciclo Light ← Primal ← Void ← Wild ← Light) também com o 242651 a 0.
- Salvage.lua: S.BoundCost(itemID) = min sobre as receitas de recuperação que já deram o item e suas entradas de (S.UnitCost(entrada) × S.UsePerCast) ÷ saída medida por destruição (por entrada com 3+ destruições, senão média da receita). Cache 30 s. Hoje ≈ 3,9g por 242651.
- Scanner.lua: ApplyBoundCost (p.boundCost, p.boundSrc, r.boundExtra) antes da 1ª passada (r.cost = buyCost + boundExtra) e em FinalizeUnknown; ApplyCraftedReagents usa boundCost para vinculados (mesmo com useCrafted desligado), guarda de ciclo (fonte que consome o item desta receita) e transmutação não usa outra transmutação como fonte; usesCrafted só quando trocou por fabricado. ns.IsTransmute(r) (nome começa com "transmut").
- Afeta também Voidlight Potion Cauldron (5×), Primal Philosopher's Stone (2×), Bouquet of Herbs, Box of Rocks.
- Receitas: grupo novo "Transmutações" (posição 4; desconhecidas foi para 5; config.collapsed migrado uma vez com secMig5). Tooltip: chance de multicraft, lucro sem proc / esperado / com proc (qty + extra/mc) e "empata com N itens"; vinculado mostra custo e "feito em: <recuperação> (aba Destruir)".
- Resultado com preços do audit: Light −10,7g/craft esperado (antes +1,47g), Primal −7,3g, Void −13,9g, Wild −9,8g; empate do Light ≈ 32,6 motes.
- Teste: /tmp/claude-0/t/t31.lua (sv5 = SavedVariables 05/10 17:48). Backup: LucroCraft_backups\RoyalRevenue-v1.11.0-2026-10-05.zip.

## v1.11.1 — transmutações sem "Transmute:" no nome (Rafael: "tenho mais 2 receitas que são transmutação")
- Candidatas na Alquimia de Midnight (usam o 242651 e viram outro tipo de material): Bouquet of Herbs (1230892), Box of Rocks (1230891), School of Gems (1230893). Não confirmado quais são as 2.
- Scanner: cada receita guarda category / categoryParent (C_TradeSkillUI.GetCategoryInfo do info.categoryID) no scan. ns.IsTransmute: marcação manual (config.transmute[recipeID]) > nome/categoria/categoria-pai contendo "transmut".
- Lista de Receitas: Ctrl+Shift+clique marca/desmarca como transmutação (reprecifica e redesenha). Dica no tooltip.
- Teste: /tmp/claude-0/t/t32.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.11.1-2026-10-05.zip.

## v1.11.2 — cargas das transmutações (Rafael: com os pontos do Madunz só 1 transmute por dia)
- Scanner: no scan, C_TradeSkillUI.GetRecipeCooldown(recipeID) → r.cd = { cool (s até a próxima), day, charges, max, t } quando há cargas ou recarga.
- ns.Charges(r): cargas agora estimadas desde o scan (1ª recarga = cool, depois 1 a cada 24 h), máximo, segundos até a próxima, cargas/dia.
- Grupo Transmutações: título com "cargas X/Y (+1 em Hh)" e "use em: <transmutação de maior lucro esperado>" ou "nenhuma dá lucro hoje". Tooltip: cargas, lucro por dia (esperado × cargas/dia), aviso de que a carga é o limite.
- A conferir no jogo: retorno do GetRecipeCooldown nas transmutações (cool = até a próxima carga?) e se as cargas são compartilhadas entre todas.
- Teste: /tmp/claude-0/t/t33.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.11.2-2026-10-05.zip.

## v1.12.0 — transmutações na aba Destruir (ideia do Rafael: mesmo tratamento do salvage, só muda o limite de cargas)
- Salvage.lua: S.IsCraftDestroy também aceita transmutação (IsTransmuteInfo: nome, categoria/categoria-pai da janela de profissão ou marcação manual) → capturada como kind "craft": entrada = 1º reagente obrigatório (perCast = qtd), outItem/outQty.
- r.extras = demais reagentes básicos obrigatórios; S.ExtraCost(r) = AH/vendedor ou, se vinculado, S.BoundCost (custo de fazer). Custo/vez da linha = entrada × gasto + extras. Cabeçalho mostra "+ por vez: 2x <catalisador> Xg (vinculado: custo de fazer)"; tooltip da linha lista os extras.
- r.transmute e r.cdBy[char] = GetRecipeCooldown na captura; S.Charges(r) → cabeçalho "cargas X/Y (+1 em Hh)". Sem cargas = sem limite (salvage normal).
- Saída: registros reais de cada transmutação (TRADE_SKILL_ITEM_CRAFTED_RESULT, quantidade já com multicraft); sem registro, a quantidade esperada do scan da profissão (expQty do personagem) em vez da fixa.
- O grupo Transmutações da aba Receitas continua (resumo + melhor uso da carga).
- Teste: /tmp/claude-0/t/t34.lua (Mote of Light: 10 Primal 0,42g + 2× catalisador 3,89g → custo 11,97g, retorno 3,87g, lucro −8,10g; cargas 0/1 +1 em 3h). Backup: LucroCraft_backups\RoyalRevenue-v1.12.0-2026-10-05.zip.

## v1.13.0 — pontos de especialização que dão cargas (pergunta do Rafael)
- O jogo descreve os dentes em texto (C_ProfSpecs.GetDescriptionForPerk). Vistos no SavedVariables: "Gain an additional charge of Wondrous Synergist", "Gain 2 additional charges of ...", "... recharges quicker" (Synthesis Synergy, aba Transmutation Authority), "Gain a second/third charge of Sharpen Your Knife". Os textos das cargas de transmutação do Madunz ainda não estavam salvos (só guardava descrição de dente sem dados do CraftSim).
- Invest.lua: a descrição agora é lida sempre. ChargePerk(desc, nó) → { kind = cap (mais cargas) | rate (recarrega mais rápido), n, target (nome entre as cores ou "transmut" pelo nome do nó), text }; t.cd, node.cdPerks. Invest.ChargePerks(entry[, filtro]) lista os dentes não conquistados por pontos (nó bloqueado +1); Invest.ChargeValue(entry, alvo) = lucro esperado da melhor receita afetada (0 se prejuízo); Invest.NextCharge = a mais barata das transmutações.
- Sem valor em ouro/semana: carga a mais só aumenta o acumulado; recarga mais rápida aumenta por dia, mas o jogo não diz quanto.
- InvestView: seção "Cargas e recarga" (até 8, zebra): rótulo, nó (aba), pontos, "1 carga = Xg (receita)" ou "1 carga dá prejuízo hoje". Nó com dente de carga aparece na árvore com "<rótulo> em N pts". Destruir (transmutação): "próximo: <rótulo> em <nó> (N pts)".
- Teste: /tmp/claude-0/t/t35.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.13.0-2026-10-05.zip.

## v1.14.0 — transmutações que viram baú (Box of Rocks, Bouquet of Herbs, School of Gems)
- Rafael: fora os motes, essas transmutações fazem um baú; os itens finais saem ao abrir. As 3 (1230891/1230892/1230893) agora são transmutação por padrão (KNOWN_TRANSMUTE em ns.IsTransmute).
- Arquivo novo Craft\Containers.lua (TOC depois de Pricing.lua → reiniciar o WoW). Aprende o conteúdo ao abrir: (1) janela de saque com origem "Item-..." (GetLootSourceInfo) → conteúdo direto; (2) sem janela: item com hasLoot diminui na bolsa e outros aumentam no mesmo BAG_UPDATE_DELAYED (ou em até 8 s). LucroCraftDB.containers[itemID] = { opens, out, seen, t }.
- CT.Value(itemID) = soma(qtd média × Pricing.Sale do conteúdo); Pricing.Sale cai nisso quando o item não tem preço próprio (TSM/Auctionator/scan); SoldPerDay (com TSM) usa o do conteúdo de maior valor. Assim o lucro das transmutações de baú, a aba Destruir e o resto do addon passam a ter valor depois das primeiras aberturas.
- Destruir: saída que é baú mostra "Ao abrir X (N aberturas): vale Y em média" + tabela do conteúdo (chance, média, preço, valor); sem aberturas, avisa para abrir alguns.
- Teste: /tmp/claude-0/t/t36.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.14.0-2026-10-05.zip.

## v1.14.1 — validação dos custos com o SavedVariables de 05/10 18:43 (após reload)
- Conferido: Mote of Light 10× Primal 0,63g + 2× catalisador 1,47g = 9,29g (lucro esperado −5,01g); Primal −1,74g; Pure Void −8,96g; Wild Magic −4,18g. Bouquet of Herbs 1× catalisador + 20× 243599 0,88g + 4× 243602 2,06g = 27,31g. Box of Rocks 8× 238525 94,78g + 18× 238520 + 18× 238518 + 1 catalisador = 993,05g.
- Catalisador 242651 caiu de 3,89g para 1,47g: o Radunz reciclou 1 Silvermoon Health Potion (241305, ~1g) → 3 catalisadores; o addon usa a poção mais barata da Recycle Potions com a saída média da receita (35 em 17 destruições = 2,06).
- Baú aprendido: Bouquet of Herbs (245650) aberto 1×: 9× 236778 + 17× 236761 ≈ 37,24g (1 amostra). Box of Rocks/School of Gems sem aberturas.
- Cargas lidas: motes 0/1 (próxima em ~17 h 26), baús 0/2 (~17 h 04) — dois grupos separados.
- O jogo põe também Wondrous Synergist e Composite Flora na categoria Transmutações (entram como transmutação).
- Correções: material principal na aba Destruir = espaço negociável de maior quantidade (Bouquet = 20 ervas, não o catalisador vinculado do 1º espaço); S.UnitCost cai no BoundCost para vinculado (fonte "fazer"), com proteção contra recursão.
- Teste: /tmp/claude-0/t/t37.lua (sv6). Backup: LucroCraft_backups\RoyalRevenue-v1.14.1-2026-10-05.zip.

## v1.15.0 — Destruir/transmutação: todos os materiais, combinação mais barata e projeção com concentração (print do Rafael, Bouquet of Herbs)
- Transmutação: as entradas eram listadas por qualidade (Eversinging Dust q1 e q2) → fica só a combinação mais barata (cada espaço na qualidade mais barata). Bloco novo "Materiais por vez (qualidade mais barata)": todos os espaços com qtd, preço un. (fonte), total e soma. O texto "+ por vez" do cabeçalho (cortado) saiu.
- Projeção com concentração: S.ScanRow (linha do scan do personagem) + S.ConcProjection: com concItemID/concCost, valor da qualidade de cima = preço/aberturas do baú de cima; sem isso, Containers.ProjectHigher = mesmo conteúdo do baú comum com cada item trocado pela qualidade de cima (mapa q1→q2 tirado dos qualityItems das receitas salvas). Mostra sem/com concentração (valor, lucro), ganho por craft e por ponto, e de onde veio o valor.
- Scanner.PriceRow: sem concSale e com baú aprendido → concSale = projeção (r.concProjected), então Receitas/Plano de concentração também enxergam o baú com concentração.
- Bouquet of Herbs (1 abertura): sem conc. valor 37,24g, lucro ~10g; com conc. (449 pts) projeção 209g (17× Tranquility Bloom q2 1,90g + 9× Mana Lily q2 19,66g), lucro ~174g, +163g por craft = 0,36g/ponto. Atenção: Mana Lily q2 a 19,66g puxa quase tudo.
- Teste: /tmp/claude-0/t/t38.lua (sv6). Backup: LucroCraft_backups\RoyalRevenue-v1.15.0-2026-10-05.zip.

## v1.15.1 — Destruir: ordem (pedido do Rafael)
- Primeiro o conteúdo do baú ("Ao abrir X…"), depois o bloco "Com concentração". Backup: LucroCraft_backups\RoyalRevenue-v1.15.1-2026-10-05.zip.

## v1.15.2 — Receitas: grupo Transmutações removido (pedido do Rafael: a parte dedicada fica na aba Destruir)
- Transmutações voltam para Volume / Baixo volume / Sem lucro conforme o lucro. collapsed migrado de volta (secMig6). As cargas e a projeção com concentração ficam na aba Destruir.
- "Não calcula": Box of Rocks e School of Gems ainda sem nenhuma abertura registrada (SavedVariables 19:29: só Bouquet of Herbs, 1×). Sem conteúdo conhecido não há valor; os motes calculam (prejuízo) e estavam abaixo na rolagem.
- Backup: LucroCraft_backups\RoyalRevenue-v1.15.2-2026-10-05.zip.

## v1.15.3 — Destruir: layout próprio da transmutação (print do Rafael: sobrava a tabela antiga "o que pode ser destruído" com 1 material)
- Transmutação: cabeçalho "transmutação: todos os materiais da receita"; a tabela de entradas não aparece; seção "Materiais por craft" (cada espaço na qualidade mais barata, total) + "Com o que você tem dá para fazer N"; parte 2 = "O que pode sair de <receita>" com "Retorno por craft". Destruições/Estilhaçar continuam iguais.
- Backup: LucroCraft_backups\RoyalRevenue-v1.15.3-2026-10-05.zip.

## v1.15.4 — Destruir: lista do meio com rolagem própria (pedido do Rafael)
- Tabela "O que pode ser destruído" desenhada num V.CreateSub (cv._salvIn) com barra; altura = janela − topo − parte de baixo (medida no desenho; 2ª passada quando muda, mínimo 120 px). Topo (botões das receitas, cabeçalho) e parte de baixo (o que sai, baú, concentração) ficam visíveis. Transmutação não usa a lista.
- Teste: /tmp/claude-0/t/t40.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.15.4-2026-10-05.zip.

## v1.15.5 — Destruir: só os botões da profissão/expansão aberta (pedido do Rafael)
- S.OpenSkillLine(): ProfessionsFrame aberto → C_TradeSkillUI.GetChildProfessionInfo().professionID (expansão escolhida no filtro da janela, ex.: 2906 Midnight Alchemy); fechado → LucroCraftDB.last.professionID. S.Recipes filtra r.skillLine == essa linha (Desencantar com qualquer expansão do Encantamento, pai 333). Sem receita naquela expansão → aviso para trocar profissão/expansão.
- Eventos TRADE_SKILL_SHOW/CLOSE/LIST_UPDATE redesenham quando a linha muda.
- Teste: /tmp/claude-0/t/t41.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.15.5-2026-10-05.zip.

## v1.15.6 — janela fora da tela ao redimensionar (Rafael perdeu o canto)
- SetClampedToScreen só segura ao mover; redimensionar passava da tela. Brand.lua: root.FitToScreen(f) (encolhe para caber e traz para dentro) e root.ScreenMax(f). Craft e Livro-caixa: limite máximo do redimensionamento = tamanho da tela; FitToScreen ao soltar a alça e ao abrir a janela (salva pos/tamanho corrigidos).
- /rr reset: tamanho padrão e centro da tela nas duas janelas. Sem o addon novo: /run LucroCraftDB.size=nil LucroCraftDB.pos=nil ReloadUI()
- Teste: /tmp/claude-0/t/t42.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.15.6-2026-10-06.zip.

## v1.15.7 — DRE: reparo por atividade (pedido do Rafael)
- Abaixo de 4.1.01 Reparo: uma linha por atividade com reparo rateado (m.act[k].repair, com período anterior/AH) + "Sem origem" (out.repair − rateado). Tooltip da atividade lista as instâncias (sub.repair). Livro/UI.lua RenderDRE; traduções no Livro/Locale.lua.
- Ex. (save 05/10 19:29): Masmorra 2.616,77g · Mundo aberto 707,91g · Imersão 448,68g · Sem origem 6.366,18g de 10.164,42g.
- Teste: /tmp/claude-0/t/t43.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.15.7-2026-10-06.zip.

## v1.15.8 — DRE: centros de custo liga/desliga (pedido do Rafael)
- Caixa "Centros de custo nas contas" na linha de cabeçalho das colunas da DRE (LucroLivroDB.config.dreCenters, padrão desligado). Ligado: abre o reparo (4.1.01) por atividade + Sem origem, como na v1.15.7. Hoje só o reparo tem rateio por atividade.
- Backup: LucroCraft_backups\RoyalRevenue-v1.15.8-2026-10-06.zip.

## v1.16.0 — Compras com histórico de preço + Fila: pegar pedidos de fabricação (pedidos do Rafael)
- Sell.DrawHistory(cv, y, W, m, refresh, key) reutilizável. Compras: clique na linha do material seleciona (Buy.selected; padrão = 1º a comprar), destaque azul, e o mesmo bloco de histórico (grupo "bhist") no fim da aba. Cores do histórico seguem a lógica de venda (verde = acima do típico).
- Fila: botão "Pegar pedidos" na barra. Queue.ReadOrders lê C_CraftingOrders.GetCrafterOrders() (lista carregada na janela de pedidos: Público/Guilda/Pessoal/Patrono); por pedido: comissão − corte do consórcio + recompensas do patrono (preço de venda) − materiais que você põe (espaços que o cliente não preencheu, custo da receita). Seção "Pedidos de fabricação" na fila (até 15, receitas conhecidas primeiro, por lucro) com botão "Pegar pedido" (C_CraftingOrders.ClaimOrder(orderID, profissão) + 1 na fila manual). Shift+clique no botão da barra pega direto o de maior lucro.
- A conferir no jogo: campos do CraftingOrderInfo (reagents, npcOrderRewards, consortiumCut) e se ClaimOrder funciona fora do botão da Blizzard.
- Teste: /tmp/claude-0/t/t44.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.16.0-2026-10-06.zip.

## v1.16.1 — Compras: lista do meio com rolagem própria (como a aba Vender)
- Grupos por personagem desenhados num V.CreateSub (cv._buyList), altura máx. 360 px (encolhe se tiver menos); cartões/dias em cima e histórico embaixo ficam fora da rolagem. X_COST = W − 144 (barra de 14 px).
- Backup: LucroCraft_backups\RoyalRevenue-v1.16.1-2026-10-06.zip.

## v1.17.0 — Fila: controle de pedidos e da ordem (print do Rafael, Uriuri pegou Skinner's Cap; "como o outro addon")
- Problemas vistos: pedido pego continuava na lista de disponíveis e não aparecia na fila.
- LucroCraftDB.queue.claimed[orderID] = { recipeID, char, prof, profEnum, type, customer, tip, cut, rew, profit, given, exp, crafted }. Pegar pedido grava aqui e tira da lista. Pedido pego pela janela do jogo entra via GetClaimedOrder (TRADE_SKILL_SHOW / CRAFTINGORDERS_* events). Expirado sai.
- Queue.Build: pedidos pegos primeiro (source "pedido"). Botões na linha: Fabricar (C_TradeSkillUI.CraftRecipe(receita, 1, só os espaços que você preenche, nil, orderID)) → depois do cast vira Entregar (C_CraftingOrders.FulfillOrder(orderID, "", profissão)); Soltar (Shift, ReleaseOrder); x tira só da fila. FULFILL/RELEASE_RESPONSE (0) remove.
- Fila manual: ^ / v reordenam, > fabrica aquela linha agora (Queue.CraftItem), - + x como antes. Fabricar próximo usa CraftItem (pedido primeiro).
- Pedidos disponíveis: tooltip mostra cada material como "cliente" ou o seu custo; LucroCraftDB.ordersDebug guarda os 8 primeiros pedidos lidos (campos do jogo) para conferir o cálculo.
- Teste: /tmp/claude-0/t/t45.lua (sv8). Backup: LucroCraft_backups\RoyalRevenue-v1.17.0-2026-10-07.zip.

## v1.17.1 — pedidos lidos presos na fila (print do Rafael, Dakael com 3 pedidos de receitas que não sabe)
- Botão "Limpar" no cabeçalho "Pedidos de fabricação" (Queue.ClearOrders). Pedidos de receitas que o personagem não sabe ficam ocultos ("+N ... (ocultos)"). A lista some ao trocar de personagem e ao abrir outra profissão (Queue.ordersChar / ordersProf).
- Teste: /tmp/claude-0/t/t46.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.17.1-2026-10-07.zip.

## v1.18.0 — Fila de craft em 3 partes (pedido do Rafael)
- Painel (cartões) em cima; Fila (esquerda) e Lista de compras (direita), cada uma com a própria barra de rolagem (V.CreateSub: cv._qList / cv._sList; altura = janela − painel; empilhadas se a janela tiver menos de 900 px).
- A barra de botões antiga (frame.queueBar) fica escondida; canvas da Fila volta para −56. Botões dentro de cada parte: Fila = incluir plano · Fabricar próximo · Pegar pedidos · Limpar manuais; Compras = Lista no Auctionator · Copiar p/ TSM.
- Teste: /tmp/claude-0/t/t47.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.18.0-2026-10-07.zip.

## v1.18.1 — pedido com qualidade mínima falhava (Rafael: "quando a ordem tem que usar concentration o craft falha")
- Queue.CraftOrder passava applyConcentration = false sempre. Agora Queue.OrderPlan(c): GetCraftingOperationInfoForOrder(receita, seus reagentes, orderID, conc) (reserva GetCraftingOperationInfo) sem e com concentração; se a qualidade sem < c.minQ e com ≥ minQ → fabrica com concentração (avisa os pontos); se nem com concentração chega → não fabrica e avisa. Linha do pedido mostra "concentração N" ou "qualidade mínima inalcançável".
- Teste: /tmp/claude-0/t/t48.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.18.1-2026-10-07.zip.

## v1.18.2 — pedido na fila cobrava materiais do cliente (print do Rafael, Saalla: Sunforged Skinning Knife)
- Jogo: cliente manda 2 Majestic Claw, 20 Fused Vitality, 5 Sterling Alloy; você põe só 2 Dazzling Thorium. O lucro do addon (50,98g = sua parte 64,91g − 2 Dazzling Thorium) já estava certo, mas a lista de compras e o "faltam 2" usavam todos os materiais da receita (Sterling Alloy 256g, Majestic Claw 127g).
- Queue.Build: item de pedido leva it.parts = só os espaços que você preenche (c.given). Needs (lista de compras) e Plan.Materials (materiais ok/faltam) usam it.parts.
- Teste: /tmp/claude-0/t/t49.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.18.2-2026-10-07.zip.

## v1.18.3 — Vender: preço sugerido dava undercut (Rafael)
- Causas: (1) o preço sugerido usava o "agora" guardado (Auctionator/TSM/scan, pode estar velho) e sobrescrevia, 0,6 s e 1,8 s depois, o preço que a Blizzard acabou de pegar da busca; (2) commodity arredondava PARA BAIXO na prata.
- Sell.LivePrice(m): menor anúncio ao vivo (GetCommoditySearchResultInfo(id,1).unitPrice; equipamento: GetItemKeyFromItem + GetItemSearchResultInfo). Sell.SuggestPrice: ao vivo > guardado > típico; iguala o menor (sem undercut); commodity arredonda para cima na prata; SEGURE nunca abaixo do típico; piso 85% do típico (avisa no chat quando segura). PutOnAH recalcula a cada aplicação.
- Teste: /tmp/claude-0/t/t50.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.18.3-2026-10-07.zip.

## v1.18.4 — Destruir: saída pela bolsa (Shatter Essence não registrava o que saía)
- SV 07/10: Shatter Essence (1235731, Radünz-Medivh) com 6 destruições (1 por mote + 274777/274781) e out vazio → o jogo não manda TRADE_SKILL_ITEM_CRAFTED_RESULT. Radiant Shatter ok (4 → 12 Eversinging Dust).
- Salvage.lua: BagAll(); pend.snap no CraftSalvage; CommitOut 3 s depois da última destruição: se nenhum CRAFTED_RESULT chegou no lote (pend.evt), o que entrou na bolsa (menos o material) vira saída (o.out/o.seen, o.bagOut). Limpeza única (clean2): destruições sem saída registrada zeram casts.
- Teste: /tmp/claude-0/t/t51.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.18.4-2026-10-07.zip.

## v1.18.5 — Shatter Essence fora da aba Destruir (Rafael: não dá item, só buffa o encantador)
- Salvage.lua: NoItemRecipe (1235731 Midnight, 445466 TWW, nome "Shatter Essence"/"Estilhaçar Essência"): não é capturada (e a já salva é apagada) e não aparece nos botões. Radiant Shatter / Dawn Shatter / Desencantar continuam.
- Backup: LucroCraft_backups\RoyalRevenue-v1.18.5-2026-10-07.zip.

## v1.18.6 — Pedidos: materiais na lista de compras já no "Pegar pedidos" + recompensas / conhecimento
- Queue.ShopItems(items): fila + pedidos lidos (que você sabe fazer, ainda não pegos) com só os materiais que VOCÊ põe (os do cliente ficam de fora). Usado pela lista de compras da tela, pelo texto, pela lista do Auctionator e pela cópia para TSM. Ao pegar (claim) o pedido sai de Queue.orders e entra pela fila → não conta duas vezes.
- Queue.KnowledgeOf(link, id): lê o tooltip do item de recompensa (C_TooltipInfo.GetHyperlink) e procura "knowledge"/"conhecimento" + número ("by 2" / "em 2"); senão, nome com Treatise/Tratado/Notes/Anotações = 1. Cache por item.
- Eval: rewList = { link, id, n, v, kp, icon }; x.kp = total de pontos de conhecimento.
- Ordem dos pedidos: sabe fazer → mais conhecimento → maior lucro.
- Linha do pedido: "+N conhecimento" em verde e até 4 ícones de recompensa (borda verde se dá conhecimento; tooltip com o item, pontos e valor na AH).
- Teste: /tmp/claude-0/t/t52.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.18.6-2026-10-07.zip.

## v1.18.7 — Fabricar pela fila confere a bolsa (pedido do Nazdru falhou)
- Causa (registro do Nazdru 07/10): Smuggler's Leather Tunic pede 15× Hide q1 (238513); só havia 3 q1 + q2 na bolsa. O addon mandava 15× q1 → o jogo recusa. A lista de compras conta o estoque de todos os personagens/banco do bando, então "não comprar" não garante material na bolsa de quem fabrica. Pela janela da Blizzard deu certo porque ela completa com q2.
- Scanner.FitToBags(tbl, parts): por espaço, mantém o planejado onde há; o que faltar vem da outra qualidade disponível (C_Item.GetItemCount com banco, banco de reagentes e banco do bando). Confere também reagentes de uma qualidade só. Faltou → avisa "faltam materiais para X: item tem/precisa" e não tenta.
- CraftOrder e CraftItem usam CheckBags antes de CraftRecipe.
- Registro (/rr log): "fila: ..." para pegar, fabricar (reagentes enviados, concentração), entregar, resposta da entrega/soltar e erros do jogo (UI_ERROR_MESSAGE, UNIT_SPELLCAST_FAILED/INTERRUPTED) até 5 s depois do comando.
- Teste: /tmp/claude-0/t/t53.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.18.7-2026-10-07.zip.

## v1.18.8 — Lista do Auctionator se atualiza sozinha (como o CraftSim)
- Stock.lua: Stock.Terms(rows), Stock.LiveList(nome, kind, terms), Stock.RegisterListBuilder(kind, fn); LucroCraftDB.liveLists[nome] = { kind, sig }.
- Ao exportar (Fila → "Royal Revenue"; Mercado > Comprar → "Royal Revenue - Compras") a lista fica "viva": BAG_UPDATE_DELAYED / MAIL_CLOSED (1,5 s de espera) → recalcula o que falta (estoque recontado) e recria a lista com o mesmo nome se mudou. Item comprado por completo some; compra parcial baixa a quantidade; nada a comprar → DeleteShoppingList e aviso "tudo comprado". Persiste entre /reload.
- Queue.ExportAuctionator / Buy.ExportAuctionator usam QueueRows / BuyRows (mesmos geradores da atualização).
- Teste: /tmp/claude-0/t/t54.lua. Backup: LucroCraft_backups\RoyalRevenue-v1.18.8-2026-10-07.zip.

## v1.19.0 — DRE reestruturada (modelo contábil) + Gear Upgrade
Estrutura (Livro > DRE):
1. Receita operacional bruta: 3.1/3.2 atividades (ouro + itens a valor de mercado), 3.3 comerciais (AH bruto, vendedor, pedidos, troca, outras).
2. (-) Deduções: 3.4.01 comissão da AH (5%).
3. (=) Receita operacional líquida.
4. (-) CPV (decisão do Rafael: por consumo): 4.0.01 material gasto em pedidos, 4.0.02 material gasto na fabricação própria, 4.0.09 "ah" antigo (compras + depósitos antes da v1.19).
5. (=) Lucro bruto + margem bruta.
6. (-) Despesas operacionais: 4.1 Manutenção (reparo), 4.2 Logística (voos), 4.3 Compras para uso (vendedor não-reagente, item comprado na AH via PlaceBid), 4.4 Taxas e serviços (4.4.07 depósito da AH, correio, treinador, transmog, barbeiro, taxa de pedido, troca), 4.5 Consumíveis usados (só dias v2), 4.6 Gear Upgrade, 4.9 Outras.
7. (=) Resultado operacional (EBIT). 8. (=) Lucro ou prejuízo líquido (= EBIT; sem juros nem impostos no jogo) + margem líquida.
Fora do resultado: 5.4 Material comprado para o estoque (5.4.01 AH commodity, 5.4.02 reagente no vendedor), transferências, ajustes.

Captura nova (Ledger.lua):
- AH: ganchos PostItem/PostCommodity → "ahdep"; Start/ConfirmCommoditiesPurchase → "ahbuy" (estoque); PlaceBid → "ahitem". Sem marca (15 s) → "ahbuy".
- Vendedor: gancho BuyMerchantItem; reagente de profissão (GetItemInfo 17º retorno) → "vendmat" (estoque), senão "vendor".
- Craft (todo craft, não só pedido): TRADE_SKILL_CRAFT_BEGIN guarda as bolsas; UNIT_SPELLCAST_SUCCEEDED da receita + BAG_UPDATE_DELAYED → gasto a valor de mercado = CPV (d.cpv.orders/craft, d.cpvProf[profissão], act orders cost.mat por pedido); produzido → c.made. Item de c.made gasto depois sai sem custo (inclusive como consumível). Receita fica "armada" 15 s para crafts em sequência.
- day.v2 = true: dias com o controle novo. CPV e consumíveis na DRE só desses dias (evita contar duas vezes com o "ah" antigo).
- Ledger.DRE: cpv, grossProfit, grossMargin, netIncome, netMargin, stock, cashOut (todo ouro pago; usado no Fluxo de caixa e nas conciliações no lugar de d.out).
- Centros de custo (liga/desliga) continuam: CPV pedidos por item, CPV fabricação por profissão, reparo por atividade (+ Sem origem), consumíveis por atividade.
- NPC com conta fixa: Ledger.NPC_CAT = { Cuzolth = "upgrade" } (+ LucroLivroDB.config.npcCat). Migração única fixNpc1: 194 lançamentos antigos do Cuzolth (4.9.01) → 4.6.01 Gear Upgrade, dias corrigidos (8.140g em 30 dias na base de 07/10).
- Teste: /tmp/claude-0/t/t55.lua (DRE com dados reais), t56.lua (CPV de craft + c.made).

## v1.19.1 — Reclassificação dos lançamentos antigos (casada com o TSM)
- Livro/Reclass.lua (ns.RECLASS1, 461 linhas): gerado offline casando cada lançamento 4.3.02/4.3.01 do diário (desde 01/10) com o csvBuys do TSM de todos os reinos (Goldrinn, Medivh, Illidan, Stormrage, Azralon), mesmo personagem, janela -20 s/+5 s, somando até cobrir o valor. Commodity/reagente (Multiple Sellers, qtd > 1 ou item de receita) → ahbuy; item avulso → ahitem; sem compra → ahdep. Resultado: material 98.958g, itens de uso 9.736g (enchant scrolls, armor kit, receita, arma), depósitos 1.353g (302), vendedor material 6g. Sobram ~94g no "ah" antigo.
- FixReclass (uma vez, LucroLivroDB.fixReclass1): troca o código no diário e move o valor de day.out.ah/vendor para a chave nova.
- Corte do controle de consumo: LucroLivroDB.v2From = dia seguinte à instalação; dias anteriores ficam sem v2 (o dia da troca teve crafts sem registro).
- Dia antigo: material comprado (ahbuy/vendmat) entra no CPV do dia da compra (4.0.08 "Material comprado (antes do controle de consumo)"), não no estoque. Collect → t.stockLegacy; DRE: cpvLegacyMat + cpvLegacyAH; estoque = compras de material só dos dias v2.
- DRE 30 dias na base de 07/10 22h: receita bruta 287.316g · CPV 99.058g · lucro bruto 184.048g (64,1%) · despesas 42.503g · EBIT/lucro líquido 141.545g (49,3%).
- Teste: /tmp/claude-0/t/t57.lua (sv11 = SV de 07/10 22:24Z), gerador rc.lua.

## v1.19.2 — Diferença não conciliada de 33.356g resolvida
Origem (tudo no dia 01/10, instalação):
- 30.320g: Riwariel e Drafael sem saldo de abertura em 01/10 (dia criado por correção antiga) → o personagem saía da soma de saldos mas os movimentos (7.961g + 22.359g) entravam na variação. Não era ouro perdido.
- 2.857g: Radunz 01/10 com inc.ahsale 3.014,62g no total do dia, mas só 157,84g no Diário — a correção v0.5.x (correio preso) passou os lançamentos para "Saque · Reclassified (stuck mailbox)" no Diário e não tirou do total do dia → vendas na AH contadas duas vezes.
- 200g: Nazdru 01/10 com transferência recebida de 200,39g sem lançamento no Diário.
- 20,6g: "ah" antigo sem lançamento (Radunz 9,49g, Nazdru 11,14g).
Prova: o saldo corrido do Diário do Radunz em 01/10 (abertura + lançamentos com ouro) fecha exatamente no cashClose (225.551,51g), e bate com o goldLog do TSM.
FixCashDays (uma vez, fixCash1): para cada dia em que o total NÃO fecha com o saldo e o Diário fecha, as contas 3.3, 4.x/5.4 e transferências passam a valer o Diário (venda de item de atividade ao vendedor: 3.3.02 do Diário − inc.itemsale). Dia sem abertura: abertura = abertura do dia seguinte − movimento do dia. Ledger.DayMv(day). Resultado: diferença 0, todos os personagens conciliados. Receita bruta 30 dias cai ~3.000g (AH contada em dobro).
Cuidado aprendido: o Diário nem sempre está completo nos primeiros dias (Saalla 01/10 tinha 207g de vendas ao vendedor só no total) → só corrigir quando o Diário fecha e o total não.
Teste: t65.lua (debug FIX), t58.lua (fluxo de caixa), t66.lua (DRE).

## v1.20.0 — Investimento das profissões de coleta: modificadores por hora
Captura nova (Gather.lua):
- Nome do nó pelo UNIT_SPELLCAST_SENT (alvo) → rec.n; objectID do GUID → rec.o.
- Extras do nó: CHAT_MSG_LOOT do próprio personagem (LOOT_ITEM_SELF*/PUSHED*/CREATED*) até 45 s depois (120 s com Overload); desconta o que já veio no saque do nó; só classe 7 ou motes → rec.x (orbes do Lightfused/Primal, bichos do Wild, orbes do Overload).
- Overload: UNIT_SPELLCAST_SUCCEEDED com nome "Overload"/"Sobrecarg" → marca a coleta (até 20 s antes/depois) rec.ov e guarda o recarregamento (C_Spell.GetSpellCooldown) rec.ovcd.
- Gather.Classify(g): modificador pelo nome (Lightfused/Wild/Primal/Voidbound) ou pelo mote no saque (236949 Light, 236951 Wild, 236950 Primal, 236952 Void) — funciona para as coletas antigas; tipo Rich/Lush/Seam só pelo nome.
Análise: valor do nó = saque + extras; grupos por modificador/tipo/Overload; vs nó comum; Gather.NodesPerHour(prof) = ajuste do jogador (config.gatherRate) > medido (sessões, pausas > 5 min) > 60.
Tela (Investimento, profissão de coleta): "Por hora" com nós/h ajustável (-10/+10, "usar medido"), valor por hora, +10 nós/h; "Modificadores dos nós": % dos nós, valor/nó, vs comum, ganho/h = nós/h × % × delta, amostra; Overload por modificador (ganho × min(nós desse tipo/h, 3600/recarga)); Wild Perception (+150 Perception × 5 min de nós). Buffs temporários usam o mesmo nós/h.
Dados em 07/10: erva 127 coletas (Drafael, ~91 nós/h, 25 Lightfused pelo mote); minério 129 (~66 nós/h, 19 Lightfused, 2 Wild). Coletas antigas não têm os extras (orbes) → Lightfused subestimado até juntar coletas novas.
Teste: /tmp/claude-0/t/t67.lua.

## v1.21.0 — Coleta: usar buffs da bolsa, pontos de conhecimento em ouro/h, WoW Token no painel
- Buffs temporários (Investimento, coleta): contagem na bolsa (C_Item.GetItemCount), fundo verde = melhor de cada grupo (comida/frasco/pedra) entre os que você tem com saldo positivo ("USAR"), borda azul + "ativo" quando o buff do item está ativo (C_Item.GetItemSpell → C_UnitAuras.GetPlayerAuraBySpellID). Clique no ícone USA o item: Canvas:SecureItem (SecureActionButtonTemplate, type=item, pedra com target-slot = ferramenta da profissão via Gather.ToolSlot). Só cria/move fora de combate; redesenha em BAG_UPDATE_DELAYED / UNIT_AURA / PLAYER_REGEN_ENABLED.
- Pontos de conhecimento (coleta): Invest._ReadGatherSpec lê a árvore do jogo (C_ProfSpecs, sem CraftSim para coleta na Midnight); atributos tirados do texto do nó (por ponto) e dos dentes (GatherTextStats: Finesse/Perception/Deftness/Skill em EN/PT; flags montado/Overload). Próximo dente de cada nó: pontos, o que dá, ganho/h = atributo × valor de 1 ponto por nó (an.fin/an.per ÷ 100) × nós/h, e por ponto. Deftness/montado: entram via nós/h (texto explica). Perícia só se medida.
- Livro > Painel: card "WoW Token" (C_WowTokenPublic.UpdateMarketPrice a cada 5 min + TOKEN_MARKET_PRICE_UPDATED), variação vs. preço anterior (>1 h), resultado do período e caixa em fichas. LucroLivroDB.token = { price, prev, t, asked }.
- Teste: t68.lua (árvore simulada + buffs), t69.lua (painel).

## v1.21.1 — WoW Token movido para o topo da lista de compras
- Saiu do Livro > Painel. Agora é o primeiro grupo da lista de materiais em Mercado > Comprar (Buy.DrawToken), minimizável (Sell.Group, chave "buyToken" em config.sellCollapsed).
- Resumo no cabeçalho: preço + variação 24 h. Aberto: ícone (item 122284), preço, 24 h, faixa de 7 dias (mín/máx + barra de posição: verde perto do mínimo, vermelho perto do máximo), seu ouro em fichas (soma do lastMoney de todos os personagens).
- Buy.TokenPrice: C_WowTokenPublic.UpdateMarketPrice a cada 5 min + TOKEN_MARKET_PRICE_UPDATED; LucroCraftDB.token = { price, t, asked, hist = {t, p} por hora, 14 dias }.
- Teste: t70.lua.

## v1.21.2 — WoW Token como item comum
- O preço do C_WowTokenPublic vira amostra normal (Buy.Record(122284, preço)) no histórico de compras (LucroCraftDB.buyHist.items[122284]); o histórico da v1.21.1 (token.hist) é migrado uma vez.
- Linha do token igual à de um material: preço agora × típico 7 dias, selo (COMPRE/NORMAL/ESPERE), faixa dos dias da semana e melhor dia, custo de 1; "seu ouro = N fichas". Clique na linha → Buy.selected = 122284 → gráfico "Histórico de preço" embaixo (Sell.DrawHistory), como os materiais.
- Continua no grupo minimizável "WoW Token" no topo da lista. Amostra nova quando o preço muda ou a cada 10 min.
- Teste: t71.lua.

## v1.21.3 — Ícones que não carregavam
- V.ItemIcon (usado em todas as abas): aceita link ou id; se GetItemIconByID não devolve (item nunca visto pelo cliente, ex.: recompensa de pedido), tenta GetItemInfoInstant e pede o item (C_Item.RequestLoadItemDataByID); em ITEM_DATA_LOAD_RESULT/GET_ITEM_INFO_RECEIVED redesenha a aba aberta (lote, 0,3 s).
- Pedidos: id da recompensa tirado do próprio link (formato novo "|cnIQ1:|Hitem:...|h[]|h|r", às vezes sem nome); ícone calculado na hora de desenhar (não mais guardado no Eval); tooltip pelo id.
- KnowledgeOf: nome "[]" vazio cai para GetItemNameByID; item ainda não carregado não grava "não dá conhecimento" no cache; no desenho, recompensa sem avaliação é conferida de novo e soma em x.kp.

## v1.21.4 — Lista de compras: só bolsa + banco do bando; some ao comprar
- Stock.Usable(id) = C_Item.GetItemCount(id, false, false, false, true): bolsas (com a de reagentes) + banco do bando, leitura direta (sem cache/TSM). Alts e banco do personagem não contam (Rafael: não estão disponíveis para craftar).
- Queue.Shopping: tem = Stock.Usable; tooltip "Tem para usar N (bolsa · bando)" + "Em alts (não conta)". Faixa da lista: "descontando bolsa + banco do bando". Scanner.Usable (FitToBags) idem.
- Causa provável de não sumir: o estoque vinha do TSM (GetPlayerTotals), que atualiza depois do BAG_UPDATE_DELAYED → a recontagem via o número velho e não mudava a lista. Agora: leitura direta + passes em 1 s e 4 s; também COMMODITY_PURCHASE_SUCCEEDED, AUCTION_HOUSE_PURCHASE_COMPLETED, ITEM_PURCHASED, PLAYERBANKSLOTS_CHANGED, BANKFRAME_CLOSED.
- Aba Fila/Comprar aberta redesenha 1 s depois de BAG_UPDATE_DELAYED (lista da tela também encolhe).
- Teste: t72.lua (harness antigo; timers do Scanner ignorados no teste porque o rescan simulado esvazia as receitas).

## v1.21.5 — Lista de compras atualiza no ato da compra na AH
- Stock.lua: gancho C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, qtd) guarda a compra pendente; COMMODITY_PURCHASE_SUCCEEDED confirma → Stock.Usable soma a quantidade comprada na hora (antes de chegar na bolsa) e AfterBuy recria a lista do Auctionator e redesenha Fila/Comprar. COMMODITY_PURCHASE_FAILED descarta. A soma sai sozinha quando a bolsa alcança base + comprado (ou 2 min).
- Item não-commodity (PlaceBid) continua pela bolsa (não dá o itemID na compra).
- Teste: t75.lua (harness_ah.lua com ConfirmCommoditiesPurchase).

## v1.22.0 — Lista de compras vai para Mercado > Comprar; compra direta; comprar × fabricar
- Auctionator fora da compra: botões "Lista no Auctionator" removidos da Fila e do Comprar (RecipeShop mantém o dele, receitas não são commodities). Stock.UpdateLists desligado e LucroCraftDB.liveLists apagado.
- Fila (aba Fila de craft): o painel da direita virou resumo (nº de materiais, total, 5 mais caros) + botão "Comprar em Mercado > Comprar".
- Comprar: grupo "Fila e pedidos" no topo (depois do WoW Token), feito de Queue.Shopping (fila + pedidos lidos/pegos; estoque = bolsa + banco do bando); os grupos do plano continuam embaixo.
- Compra direta (AH aberta): botão "Comprar N" na linha → C_AuctionHouse.StartCommoditiesPurchase → COMMODITY_PRICE_UPDATED → botão "Confirmar <total>" (vermelho se > 30% acima do típico; "x" cancela) → ConfirmCommoditiesPurchase → COMMODITY_PURCHASE_SUCCEEDED (amostra de preço gravada; Stock conta na hora). Falhas/sem oferta avisam no chat. Só commodities (GetItemCommodityStatus); preço vale 50 s. Cabeçalho mostra se a AH está aberta.
- Comprar × fabricar: Scanner.BuildCraftMap() (receita mais barata de qualquer personagem) → m.craft {unit, name, char}; fabricar < 97% do preço agora → selo azul "FABRIQUE", texto "fabricar Xg/un (-N%)" na linha, tooltip com quem fabrica e quanto economiza na compra.
- Teste: t76.lua.

## v1.22.1 — Mensagens do addon vão para a aba de chat "Log"
- Brand.lua: root.Out(...) escreve na aba de chat chamada Log/Logs/Royal Revenue/RR/Registro (ou a escolhida com /rr log <nome>, RoyalRevenueDB.logTab); sem aba assim, chat padrão. root.LogFrame() procura via GetChatWindowInfo (cache 30 s).
- Todos os print do addon (Craft/Core ns.Print e depuração, Alerts, Livro Core/Ledger/Minimap, Shell) passam por um print local = root.Out.
- /rr log mostra a aba em uso; /rr log <nome> escolhe outra.
- Teste: t77.lua.

## v1.22.2 — Pedidos: concentração mostrada e descontada do lucro
- Bug: "qualidade mínima inalcançável" no Flask of the Shattered Sun (Radunz). Queue.OrderPlan pedia a qualidade com applyConcentration=true, mas a API devolve a mesma qualidade (concentrationCost é o custo para subir 1 nível — o Scanner já tratava assim). Agora: com concentração = q0 + 1 se concentrationCost > 0. O craft do pedido também passa a usar a concentração certo.
- Queue.ConcPointValue(char, prof): valor de 1 ponto = maior r.perConc das receitas do personagem/profissão (custo de oportunidade: o que a melhor receita renderia com os pontos).
- Queue.OrderConc(x, c): concPts, concPer, concFrom, concValue; unreach. Eval (ao ler pedidos) desconta concValue do lucro; claim e SyncClaimed guardam. Pedido pego antes da versão: desconta na hora de desenhar.
- Tela: lista de pedidos "conc N" (azul) ou "qualidade inalcançável"; tooltip "Concentração (N pontos) −Xg" + de onde vem o valor por ponto. Fila (pedido pego): "concentração N (≈Xg)".
- Teste: t78.lua (188 pts × 5,74g/pt = 1.079g).

## v1.23.0 — Comprar: barra de listas + clique procura na AH
- Barra de listas no topo de Mercado > Comprar (config.buyList): "Plano de concentração" (padrão: só o personagem logado; caixa "Mostrar todos os personagens" = config.buyAllChars), "Fila de craft" (grupo da fila + pedidos) e "Consumíveis" (WoW Token como item comum + histórico; espaço para outros itens). Buy.Build filtra os grupos pela lista → cartões, melhor dia e horário são da lista escolhida. "Comprar para: N dias" só no plano.
- Clique num material: além do histórico embaixo, Buy.ShowInAH → AuctionHouseFrame:SetDisplayMode(Buy) + SelectBrowseResult({ itemKey = MakeItemKey(id) }) (abre a lista de preços do item na AH); plano B: escreve o nome na busca e pesquisa.
- Botão da Fila "Comprar em Mercado > Comprar" abre direto a lista "Fila de craft".
- Teste: t79.lua.

## v1.23.1 — Lista "Consumíveis": reposição do que cada personagem usa
- Buy.ConsGroups: lê o Diário do livro-caixa (conta 4.5.01 = consumível usado, com item e quantidade; só o que foi pago — o ganho de graça não entra) dos últimos 14 dias; ritmo pelo período jogado (3 a 14 dias); repor para N dias (3/7/14, config.consDays, padrão 7) − o que tem (bolsa/banco do personagem + bando). Grupo por personagem; "Mostrar todos os personagens" vale aqui também.
- "Esconder poções" (config.consHidePots): tira classe 0 subclasse 1 (poções), deixa frascos, comida, tambores, itens de reviver etc.
- WoW Token continua no topo da lista Consumíveis; linhas dos consumíveis iguais às de material (preço × típico, selo, dias, comprar direto, clique procura na AH, fabricar × comprar).
- Limite: só registra itens de classe Consumível (0) que somem da bolsa fora de vendedor/AH/correio/banco/troca; item com cargas que não some (ex.: aparelho de engenharia) não aparece.
- Dados de 07/10: Radunz 98 + 28 poções, 51 de 212264, frasco 241325 etc.; 11 personagens com consumo.
- Teste: t80.lua.

## v1.23.2 — Consumíveis: só masmorra, raide e imersão
- Ledger (consumível usado): o lançamento 4.5.01 grava a atividade (e.k = raid/dungeon/delve/world/...).
- Buy.ConsGroups: só conta lançamentos com atividade dungeon/raid/delve. Lançamentos antigos (sem e.k): atividade achada pela subconta do dia com o mesmo nome (h) e custo de consumível.
- Resultado em 07/10: some o uso de profissão/mundo (Radunz 98 + 28 de 241301/241305, chás/frascos de coleta do Drafael, 268954 do Madunz, 241307 do Zaubeber); fica Radunz 35 de 212264, frasco 241325, 243733, 242306; 8 personagens.

## v1.24.0 — Sugestão de consumíveis (abaixo dos usados, lista Consumíveis)
- Craft/Consum.lua (novo, depois de Buy.lua no TOC). Perfil do personagem ao entrar/trocar spec/equip (LucroCraftDB.charInfo[char] = role, atributo principal, ratings de crit/haste/mastery/vers, maior e 2º secundário, tipo de arma).
- Por personagem, o melhor de cada tipo (ids conferidos nos SVs em 08/10): frasco do maior secundário (Magisters 241323 maestria, Blood Knights 241325 haste, Shattered Sun 241327 crit, Thalassian Resistance 241321 vers); poção de combate (Recklessness 241289 se o maior secundário ≥ 15% acima do 2º, senão Light's Potential 241309); vida (Concentrated Silvermoon 271883/271884); mana (curador ou classe de mana com INT, Lightfused 241300/241301); comida (Hearty Royal Roast 242747 / Royal Roast 242275); arma (tanque/curador Oil of Dawn 243735/6; INT/hunter/ranged Thalassian Phoenix Oil 243733/4; impacto Weightstone 237367; lâmina Whetstone 237370); runa Void-Touched 259085.
- Itens de grupo (caixa "Itens de grupo" = config.consGroup, ou se o personagem já usou): Void-Touched Drums 244639, Emergency Soul Link 248486/269586, Void-Shrouded Tincture 241303, Cauldron of Sin'dorei Flasks 241319, banquetes Silvermoon Parade 255845 / Harandar Celebration 255846.
- Quantidade: horas em dungeon/raid/delve (day.time) nos últimos 14 dias → 1/h para frasco, comida, arma, runa; chefes mortos (act.n) → 1 poção de combate por chefe, 1 de vida a cada 2; tudo pelos dias de reposição (3/7/14). Mínimo 1.
- Qualidade: entre as do item, a melhor que custa até 50% acima da mais barata (Consum.Pick). Item já na lista de usados do personagem não repete.
- Linha mostra a categoria em azul ("Frasco · Maestria") + tooltip com o porquê. Cabeçalho "Sugestão · Personagem · X h e N chefes".
- Teste: t81.lua (Radunz BM simulado: 2,9 h e 37 chefes em 7,6 dias).

## v1.24.1 — Tambor e battle res pela classe
- Consum.HAS_LUST = Shaman, Mage, Hunter (pet), Evoker; HAS_BRES = Druid, Death Knight, Warlock, Paladin.
- Classe sem Heroísmo/Bloodlust → Void-Touched Drums sempre na sugestão; classe sem reviver em combate → Emergency Soul Link sempre. Quantidade = chefes/3 (mín. 1). A caixa "Itens de grupo" continua para invisibilidade, caldeirão, banquete (e tambor/Soul Link para quem já tem a habilidade).
- Ex.: Hunter → Soul Link; Druid/Paladin → tambor; Warrior → os dois; Shaman → Soul Link.

## v1.24.2 — Mago recebia tambor
- Causa: a caixa "Itens de grupo" estava marcada (config.consGroup = true) e ela forçava tambor/Soul Link mesmo para classe que tem Heroísmo/reviver.
- Agora tambor e Soul Link seguem só a classe (sem a habilidade → sempre) ou o histórico (já usou → aparece). A caixa vale só para invisibilidade, caldeirão e banquete.

## v1.24.3 — Pedido com todos os materiais no vermelho (beta tester) + tamanho da janela
- Causa provável: a qualidade do pedido era calculada só com os SEUS reagentes (GetCraftingOperationInfoForOrder recebia a tabela sem os do cliente). Com o cliente mandando tudo em qualidade máxima, a tabela ia vazia → qualidade baixa → "precisa de concentração" → o valor dos pontos (~200g) saía do lucro.
- Agora: Eval guarda os reagentes do cliente (x.custR = itemID, quantidade, dataSlotIndex) e OrderReagentsFull manda seus + do cliente para a API. Pedido pego antes desta versão sem essa lista e com tudo fornecido: não pede concentração. Claim/SyncClaimed guardam custR.
- Tooltip do pedido: "Sai sem concentração: ★N (reagentes do cliente + os seus)" e "O cliente mandou todos os materiais.".
- Tamanho da janela: botões A- / A+ na barra de título (5% por clique, 50–150%), /rr escala 80; vale para Craft/Mercado e Livro-caixa (RoyalRevenueDB.scale), mantém o canto de cima no lugar e cabe na tela.
- Teste: t83.lua.

## v1.24.4 — Lista de compras ignorava reagente de outra qualidade (beta tester)
- Causa: Queue.Shopping conferia o estoque só do item mais barato (qualidade de baixo); 6 mil da qualidade máxima no banco não contavam → mandava comprar a inferior.
- Agora Needs guarda todas as qualidades do espaço (x.qual) e o "tem" soma bolsa + banco do bando de todas (Stock.Usable de cada uma); tooltip em Comprar (lista Fila) mostra quanto tem de cada qualidade. O plano já somava as qualidades (m.ids).
- Lembrete: banco do personagem não conta (só bolsa + banco do bando), como pedido antes.
- Teste: t84.lua (6.000 da qualidade de cima → comprar 0).

## v1.24.5 — Banco do personagem logado conta
- Stock.Usable: bolsas + banco do personagem LOGADO (GetItemCount includeBank/includeReagentBank, sempre do personagem atual) + banco do bando. Alts continuam fora. Scanner.Usable (conferência antes de craftar) idem.
- Textos: "descontando bolsa, banco e banco do bando"; tooltip "N (bolsa+banco X · bando Y)".
- Teste: t85.lua (5 bolsa + 100 banco + 7 bando = 112).

## v1.24.6 — Warlock recebia pedra de afiar (poder de ataque) na sugestão de arma
- Causa: a escolha da arma dependia só do atributo principal lido (info.primary == 4); personagem ainda não lido (ou leitura sem atributo) caía no "else" → Refulgent Whetstone.
- Consum.lua: CASTER_CLASS (Mage, Warlock, Priest, Evoker) = sempre Intelecto → Thalassian Phoenix Oil (ou Oil of Dawn se curador). PHYS_CLASS (Warrior, Rogue, DK, DH, Hunter) = físico. Híbrido (Druida, Xamã, Paladino, Monge) sem leitura fica sem sugestão de arma até entrar no personagem. ReadMe: se a spec não der o atributo, usa o maior UnitStat (For/Agi/Int); classe caster grava 4.
- Poção de mana usa a mesma regra (classe de mana com Intelecto).
- Teste: t86.lua (Warlock sem leitura / com leitura errada → óleo; Priest curador → Oil of Dawn; Druida sem leitura → nada; Druida INT → óleo; Druida feral → weightstone; Rogue → whetstone).

## v1.24.7 — erro "secret string" em raide (Gather.lua:291, 3229x)
- Midnight: em combate/instância o nome do alvo do UNIT_SPELLCAST_SENT chega como valor secreto; o código comparava a2 ~= "" ANTES de conferir issecretvalue → erro a cada cast.
- Brand.lua: root.AnySecret(...) (true se algum argumento é secreto). Os handlers de evento que comparam argumentos ignoram o evento nesse caso: Gather (SENT/SUCCEEDED/CHAT_MSG_LOOT), Ledger (UNIT_SPELLCAST_* e CHAT_MSG_LOOT), Queue (craft concluído e registro de erros), Salvage, InvestView (UNIT_AURA), Consum (troca de spec).
- Teste: t88.lua (AnySecret) e t87.lua (todos os handlers com argumentos secretos, sem erro).

## v1.25.0 — otimização de desempenho (revisão do código todo)
Medido no harness com o SavedVariables real (sv11, 9 MB), base v1.24.7 → v1.25.0:
- Reprecificar todos os personagens (login e depois do scan da AH): 259 → 107 ms no total; pior passo 40 → 12 ms. BuildCraftMap não monta mais entradas/"é transmutação" de todo item (só de quem é consultado, SourceInfo); ns.IsTransmute guarda o resultado por linha (tabela fraca, confere nome/categoria; marcação manual sempre conferida).
- Profissão aberta: TRADE_SKILL_LIST_UPDATE chega a cada craft e disparava o scan completo (todas as receitas) a cada um. Agora (Core.lua): fabricando em sequência, espera 3 s sem eventos e não repete antes de 8 s (no máx. 30 s); abrir a janela ou trocar profissão/expansão escaneia logo. Teste t92: 10 crafts em 20 s → 0 scans extras (antes 10).
- Mercado > Comprar: 6,1 → 1,4 ms (Scanner.CraftMapAll guarda o mapa até o próximo Finalize).
- Comprar receitas: 29 → 18 ms (WeeklyValue de cada profissão uma vez por montagem; Invest.WeeklyValue base guardado por entrada até Scanner.gen mudar, troca de personagem ou 30 s).
- Livro-caixa: Painel 12 → 5,6 ms, DRE 8,8 → 3,0, Fluxo 10,4 → 4,4, Centros 12,1 → 4,6 (Collect+Merge+DRE do período atual e anterior guardados enquanto Ledger.rev não muda, máx. 10 s). Diário 93 → 26 ms: root.DayKey (date() com cache de 15 min) e listas por personagem já em ordem intercaladas em vez de ordenar ~9 mil lançamentos; resultado guardado por Ledger.rev.
- Preço: root.TSMPrice / root.AtrPrice (Brand.lua) guardam o valor do TSM/Auctionator por 60 s (Craft Pricing e Livro Price). Não aparece no harness (sem TSM); no jogo é a chamada mais cara das telas.
- Bolsas: root.BagCounts() = uma leitura por quadro para Livro (consumíveis, venda ao NPC, CPV do craft), Destruir e Baús (tabelas compartilhadas, só leitura; relidas a cada BAG_UPDATE). Classe do item (consumível?) guardada por itemID.
- ns.CharKey (Craft e Livro) e RealmKey (Own, RecipeShop) guardados na sessão. Ledger.rev sobe a cada evento do livro e no Tick.
- Testes: suíte inteira (88 arquivos) igual à v1.24.7 (só horários/linhas). Harness: GetTime avança 0,0001 s a cada FIRE (quadro novo); _ResetCharKey nos testes que trocam de personagem. Novos: t89 (Diário intercalado = varredura simples; fora de ordem cai no sort), t90 (custo dos eventos), t91 (reprecificação), t92 (agendamento do scan); prof.lua/prof2/prof3 = perfis.

## v1.25.1 — Comprar: anúncio absurdo (print do Rafael: Sienna Ink 11.111,06g, +591%, "Tuesday -106%")
- Causa: tinta com mercado vazio → o menor anúncio era um preço de provocação (11.111,06g). Ele virava o "agora", entrava na média dos 7 dias (típico 1.608g) e na média de cada dia da semana; o índice era média aritmética centrada → passava de −100%. A linha cobrava 14 × 11.111g (155.554g) mesmo com o selo FABRIQUE.
- Buy.Analyze: típico = MEDIANA dos mínimos diários dos últimos 7 dias; "dias em volta" (Around) também mediana; razão de cada dia em log, limitada a 1/3..3x; índice = média geométrica centrada (nunca abaixo de −100%). Faixas de horário usam a mesma razão limitada.
- a.outlier: agora > 2,5x o típico → selo ESPERE, preço em laranja + "anúncio fora do normal" e o típico; tooltip explica. Custo da linha = custo de fabricar se FABRIQUE, senão o típico (com anúncio absurdo) ou o agora. Economia de fabricar comparada com esse preço de referência e mostrada no máx. "-99%".
- Nome de item ainda não carregado ("item 274781"): V.ItemName pede ao servidor e redesenha a aba quando chega (como os ícones). Usado em Comprar, Fila, Plano, Vender e Receitas.
- Teste: t93.lua (14 dias a 20g com 3 dias de 11.111g e agora 11.111g → típico 20g, fora do normal, ESPERE, dias entre −21% e +93%). t2 (terça −10% / sábado +8%) continua igual.

## v1.26.0 — Consumíveis: botão de qualidade na barra "Sugestão" (pedido do Rafael)
- Causa: `Consum.Pick` escolhia a melhor qualidade comparando `GetItemCraftedQualityByItemInfo`, mas os consumíveis com 2 IDs (poção de vida, de mana, comida, óleo de arma, Emergency Soul Link, banquete) não são itens de qualidade fabricada — a API sempre devolve 0 para os dois, então a comparação nunca decidia e a função ficava sempre com `ids[1]` (a 1ª qualidade).
- 1ª tentativa (revertida: "ficou muito ruim"): mostrar as duas qualidades lado a lado em cada linha. Trocado por um botão só, na barra "Sugestão".
- Consum.lua: `Consum.Quality()`/`SetQuality(n)` (1 ou 2, `LucroCraftDB.config.consQuality`, padrão 1). `Pick(ids)` usa essa escolha quando o item tem as 2 (senão a única que existir). "Tem"/"precisa" somam as duas qualidades (uma vale pela outra), mas a linha mostra só a qualidade escolhida (`m.ids = { id }`, como antes da v1.26.0); `m.hasQuality` marca que esse consumível tem escolha.
- Buy.lua (`Render`): botão "Qualidade: 1/2" na barra "Sugestão" (clique alterna; vale pra todos os personagens, é uma configuração só). Linha de cada material volta a ter 1 ícone/preço/selo/custo/botão de comprar, como antes.
- Teste: conferido com o SavedVariables real (sv11) — trocar a qualidade muda o item escolhido (poção de vida 271883 ↔ 271884, comida 242747 ↔ 242275) e a aba continua desenhando sem erro nas duas qualidades.
