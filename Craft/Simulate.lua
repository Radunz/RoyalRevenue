local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L
local P = ns.Pricing

-- ===== Simulador de reagentes =====
-- "qual é a melhor opção entre craftar com os materiais mais vagabundos contra os melhores, e todas
-- as combinações, e quanto isso afeta a concentração e quantas vezes eu conseguiria craftar."
--
-- Cada slot com várias qualidades é uma escolha. A combinação muda três coisas ao mesmo tempo, e é
-- por isso que não dá para decidir de cabeça:
--   1. o CUSTO dos reagentes;
--   2. a PERÍCIA, e com ela a qualidade que sai sem gastar concentração;
--   3. o CUSTO DE CONCENTRAÇÃO para subir uma qualidade — e a concentração é o recurso escasso,
--      então reagente barato que exige mais concentração pode render MENOS no total.
-- A conta de cada combinação vem da API do jogo (a mesma que o painel de profissão usa), não de
-- fórmula própria: é o único jeito de bater com o que o jogo vai fazer.
local Sim = {}
ns.Simulate = Sim

local MAX_COMBOS = 243   -- 3^5: acima disso são chamadas demais à API para uma tela sob demanda

-- qualidade (1..3) de um reagente, pela posição no slot
local function QualIndex(p, id)
	for i, v in ipairs(p.qualityItems or {}) do if v == id then return i end end
	return 1
end

-- Tabela de reagentes para a API com uma qualidade escolhida por slot.
-- O BuildReagentTbl do Scanner só faz "base x topo"; aqui cada slot pode ir em qualquer qualidade.
function Sim.ReagentTbl(parts, combo)
	local tbl = {}
	for i, p in ipairs(parts or {}) do
		if p.slot then
			local opts = p.qualityItems or { p.itemID }
			local escolhido = opts[combo[i] or 1] or opts[1]
			if #opts > 1 then
				for _, id in ipairs(opts) do
					table.insert(tbl, { reagent = { itemID = id },
						quantity = (id == escolhido) and (p.qty or 1) or 0, dataSlotIndex = p.slot })
				end
			end
		end
	end
	return tbl
end

-- slots que têm escolha de qualidade, na ordem das partes
function Sim.Slots(r)
	local out = {}
	for i, p in ipairs(r and r.parts or {}) do
		if p.slot and p.qualityItems and #p.qualityItems > 1 then
			table.insert(out, { idx = i, part = p, n = #p.qualityItems })
		end
	end
	return out
end

-- todas as combinações de qualidade (produto cartesiano), limitadas a MAX_COMBOS
function Sim.Combos(slots)
	local total = 1
	for _, s in ipairs(slots) do total = total * s.n end
	local cortou = total > MAX_COMBOS
	local out, atual = {}, {}
	for _, s in ipairs(slots) do atual[s.idx] = 1 end
	local function passo(k)
		if #out >= MAX_COMBOS then return end
		if k > #slots then
			local c = {}
			for i, v in pairs(atual) do c[i] = v end
			table.insert(out, c)
			return
		end
		local s = slots[k]
		for q = 1, s.n do
			atual[s.idx] = q
			passo(k + 1)
		end
	end
	passo(1)
	return out, total, cortou
end

-- quantos crafts os reagentes desta combinação dão, com o que o personagem tem
local function CraftsPorEstoque(r, combo)
	if not ns.Stock or not ns.Stock.Usable then return nil end
	local menor
	for i, p in ipairs(r.parts or {}) do
		local qtd = p.qty or 1
		if qtd > 0 then
			local opts = p.qualityItems or { p.itemID }
			local id = opts[combo[i] or 1] or opts[1]
			local tem = ns.Stock.Usable(id) or 0
			local n = math.floor(tem / qtd)
			if not menor or n < menor then menor = n end
		end
	end
	return menor
end

-- Avalia UMA combinação. `conc` = concentração disponível agora.
function Sim.Avaliar(r, e, combo, conc)
	local tbl = Sim.ReagentTbl(r.parts, combo)
	local op = ns.Scanner.TryOp and ns.Scanner.TryOp(r.recipeID, tbl)
	local linha = { combo = combo }

	-- custo dos reagentes desta combinação
	local custo, semPreco = 0, false
	local rotulos, escolhidos = {}, {}
	for i, p in ipairs(r.parts or {}) do
		local opts = p.qualityItems or { p.itemID }
		local id = opts[combo[i] or 1] or opts[1]
		local unit = P.Cost(id)
		if unit then custo = custo + unit * (p.qty or 1) else semPreco = true end
		if #opts > 1 then
			local q = QualIndex(p, id)
			table.insert(rotulos, ns.QIcon(q, #opts))
			-- a tela desenha o ícone do item com a marca de qualidade; o rótulo em texto fica para
			-- a ordenação e para os testes, que não leem textura
			table.insert(escolhidos, { itemID = id, q = q, maxQ = #opts, qty = p.qty or 1, unit = unit })
		end
	end
	linha.cost = custo
	linha.semPreco = semPreco or nil
	linha.label = table.concat(rotulos)
	linha.reagentes = escolhidos

	if not op then linha.semOp = true return linha end

	linha.skill = (op.baseSkill or 0) + (op.bonusSkill or 0)
	linha.quality = op.craftingQuality
	linha.conc = op.concentrationCost
	linha.ingRefund = op.ingenuityRefund

	-- rendimento e custo esperados usam os mesmos ajustes do resto do addon (multicraft,
	-- resourcefulness, ingenuity), senão esta tela diria um número e a lista diria outro
	local st = r.stats
	linha.expQty = ns.Scanner.ExpectedItems(r.qty or 1, st, r.recipeID, ns.CharKey(), e and e.sig) or (r.qty or 1)
	linha.expCost = ns.Scanner.ExpectedCost(custo, st) or custo

	-- venda na qualidade que sai, e na de cima (com concentração)
	local qIDs = r.qIDs or {}
	local idSaida = qIDs[linha.quality] or r.itemID
	linha.sale = P.Sale(idSaida)
	linha.saleProj = ns.Scanner.Projected and ns.Scanner.Projected(linha.sale, r.trend) or linha.sale
	linha.profit = ns.NetProfit(linha.saleProj, linha.expQty, linha.expCost)

	if linha.conc and linha.conc > 0 and linha.quality and r.maxQuality and linha.quality < r.maxQuality then
		linha.concQuality = linha.quality + 1
		local idConc = qIDs[linha.concQuality]
		linha.concSale = idConc and P.Sale(idConc) or nil
		linha.concSaleProj = ns.Scanner.Projected and ns.Scanner.Projected(linha.concSale, r.concTrend) or linha.concSale
		linha.concEff = ns.Scanner.EffectiveConc(linha.conc, st, linha.ingRefund)
		linha.concProfit = ns.NetProfit(linha.concSaleProj, linha.expQty, linha.expCost)
		if linha.concProfit and linha.concEff and linha.concEff > 0 then
			linha.perConc = linha.concProfit / linha.concEff
			-- É AQUI que a pergunta "quantas vezes eu conseguiria craftar" é respondida: para COMEÇAR
			-- um craft o jogo exige o custo cheio; o gasto médio é o efetivo (a engenhosidade devolve
			-- parte depois). Reagente barato que pede mais concentração rende menos crafts.
			if conc and conc > 0 and linha.conc <= conc then
				linha.crafts = math.floor((conc - linha.conc) / linha.concEff) + 1
				linha.totalGold = linha.crafts * linha.concProfit
			else
				linha.crafts = 0
				linha.totalGold = 0
			end
		end
	else
		-- Não precisa de concentração: esta linha NÃO é limitada por ela. O limite passa a ser
		-- material e ouro, que se compram — então "quantos crafts" aqui não se compara com os das
		-- linhas que gastam concentração, e dizer 0 porque o estoque está vazio seria mentir.
		linha.semConc = true
		local porEstoque = CraftsPorEstoque(r, combo)
		linha.estoqueCrafts = porEstoque
		linha.crafts = (porEstoque and porEstoque > 0) and porEstoque or nil
		linha.totalGold = (linha.crafts and linha.profit) and (linha.crafts * linha.profit) or nil
	end
	linha.estoque = CraftsPorEstoque(r, combo)
	return linha
end

-- Roda a simulação inteira. Devolve (linhas, totalCombinacoes, cortou).
function Sim.Run(r, e)
	if not (r and r.parts and ns.Scanner and ns.Scanner.TryOp) then return {}, 0, false end
	local slots = Sim.Slots(r)
	if #slots == 0 then return {}, 0, false end
	local combos, total, cortou = Sim.Combos(slots)
	local conc = e and e.conc and ns.Plan and ns.Plan.EstimatedConc and select(1, ns.Plan.EstimatedConc(e)) or nil
	local linhas = {}
	for _, c in ipairs(combos) do
		local ok, linha = pcall(Sim.Avaliar, r, e, c, conc)
		if ok and linha then table.insert(linhas, linha) end
	end
	return linhas, total, cortou, conc
end

-- ===== ordenação =====
local CHAVES = {
	cost = function(x) return x.cost or math.huge end,
	quality = function(x) return x.quality or 0 end,
	conc = function(x) return x.conc or 0 end,
	profit = function(x) return math.max(x.concProfit or -math.huge, x.profit or -math.huge) end,
	perConc = function(x) return x.perConc or 0 end,
	crafts = function(x) return x.crafts or 0 end,
	total = function(x) return x.totalGold or 0 end,
}
Sim.CHAVES = CHAVES

function Sim.Sort()
	local s = LucroCraftDB.config and LucroCraftDB.config.simSort
	if type(s) ~= "table" or not CHAVES[s.key] then return { key = "total", desc = true } end
	return s
end

function Sim.SetSort(key)
	if not CHAVES[key] then return end
	local s = Sim.Sort()
	LucroCraftDB.config = LucroCraftDB.config or {}
	if s.key == key then
		LucroCraftDB.config.simSort = { key = key, desc = not s.desc }
	else
		LucroCraftDB.config.simSort = { key = key, desc = true }
	end
end

function Sim.SortRows(linhas)
	local s = Sim.Sort()
	local f = CHAVES[s.key] or CHAVES.total
	table.sort(linhas, function(a, b)
		local va, vb = f(a), f(b)
		if va == vb then return (a.label or "") < (b.label or "") end
		if s.desc then return va > vb end
		return va < vb
	end)
end

-- ===== tela =====
-- Colunas: Reagentes · Custo · Perícia · Qualidade · Concentração · Lucro · Lucro/ponto · Crafts · Total
-- Larguras folgadas de propósito: a aba usa a janela inteira e sobrava espaço morto. Número de
-- ouro apertado é número que se lê errado.
local COL = { cost = 92, skill = 62, quality = 60, conc = 72, profit = 102, perConc = 96, crafts = 64, total = 112 }
local ORDEM = { "cost", "skill", "quality", "conc", "profit", "perConc", "crafts", "total" }
local GAP, REAG_MIN = 8, 120
local ICON, ICON_GAP = 26, 6   -- ícone do reagente e o espaço entre eles
Sim.ICON, Sim.LINHA = ICON, 32

function Sim.Cols(W, nSlots)
	local c, x = { w = COL }, W - 8
	for i = #ORDEM, 1, -1 do
		local k = ORDEM[i]
		x = x - COL[k]
		c[k] = x
		x = x - GAP
	end
	c.reag = 8
	-- a coluna dos reagentes cabe os ícones de todos os slots; sobra tela, não precisa apertar
	local preciso = 8 + (nSlots or 1) * (ICON + ICON_GAP)
	c.reagW = math.max(REAG_MIN, math.min(preciso, c.cost - GAP - 8))
	return c
end

local function Faixa(cv, y, W, titulo, direita)
	cv:Box(0, y, W, 18, 0.08, 0.13, 0.24, 0.95)
	cv:Box(0, y + 17, W, 1, 0.83, 0.69, 0.22, 0.6)
	cv:Text(8, y + 2, "|cffd4af37" .. titulo .. "|r", GameFontNormalSmall)
	if direita then cv:Text(8, y + 2, "|cff9d9d9d" .. direita .. "|r", GameFontDisableSmall, W - 16, "RIGHT") end
	return y + 22
end

function Sim.Render(cv)
	local W = cv:Width()
	local G, V = P.FormatGold, ns.Visual
	cv:Begin()
	local out = ns.auditOut
	local r = out and out.row
	if not r then
		cv:Text(8, 8, L["Selecione uma receita (clique na lista ou na janela da profissão) para simular as combinações de reagentes aqui."],
			GameFontHighlight, W - 16)
		cv:End(40)
		return
	end
	local e = out.e
	local linhas, total, cortou, conc = Sim.Run(r, e)

	-- cabeçalho
	cv:Box(0, 0, W, 48, 0.17, 0.36, 0.66, 0.18)
	cv:Box(0, 0, 3, 48, 0.70, 0.13, 0.20, 0.9)
	cv:Icon(8, 7, 34, V.ItemIcon(r.itemID, r.icon), { link = r.saleLink })
	cv:Text(50, 5, r.name or "?", GameFontNormalLarge, W - 320)
	cv:Text(50, 27, string.format(L["|cff9d9d9d%d combinações · perícia atual %s · %s disponível|r"],
		#linhas, tostring(r.skill or "?"),
		conc and ns.ConcStr(math.floor(conc), e and e.professionID) or L["sem dado de concentração"]),
		GameFontDisableSmall, W - 320)

	if #linhas == 0 then
		cv:Text(8, 56, L["|cff9d9d9dEsta receita não tem reagente com escolha de qualidade: não há o que simular.|r"],
			GameFontHighlight, W - 16)
		cv:End(90)
		return
	end

	-- melhor de cada critério, para o resumo
	Sim.SortRows(linhas)
	local maisBarata, melhorTotal
	for _, x in ipairs(linhas) do
		if not maisBarata or (x.cost or math.huge) < (maisBarata.cost or math.huge) then maisBarata = x end
		if not melhorTotal or (x.totalGold or 0) > (melhorTotal.totalGold or 0) then melhorTotal = x end
	end
	local y = 52
	if maisBarata and melhorTotal and maisBarata ~= melhorTotal and (melhorTotal.totalGold or 0) > 0 then
		-- "rende X a mais que o mais barato" vira conversa estranha quando o mais barato não rende
		-- NADA: ele não cabe na concentração que você tem. Aí o que interessa é dizer isso.
		if (maisBarata.crafts or 0) == 0 and not maisBarata.semConc then
			cv:Text(8, y, string.format(
				L["|cffff9e40O conjunto mais barato não cabe na sua concentração|r |cff9d9d9d(pede %s, você tem %s)|r · |cff55ff55o melhor rende %s em %s crafts|r"],
				ns.ConcStr(maisBarata.conc or 0, e and e.professionID),
				conc and tostring(math.floor(conc)) or "?",
				G(melhorTotal.totalGold or 0, true), tostring(melhorTotal.crafts or "?")),
				GameFontHighlightSmall, W - 16)
		else
			local ganho = (melhorTotal.totalGold or 0) - (maisBarata.totalGold or 0)
			cv:Text(8, y, string.format(
				L["|cff55ff55O melhor conjunto rende %s a mais que o mais barato|r |cff9d9d9d(%s crafts contra %s)|r"],
				G(ganho, true), tostring(melhorTotal.crafts or "?"), tostring(maisBarata.crafts or "?")),
				GameFontHighlightSmall, W - 16)
		end
		y = y + 18
	end

	-- cabeçalho da tabela
	local c = Sim.Cols(W, #Sim.Slots(r))
	local s = Sim.Sort()
	local function Head(x0, w, key, rotulo, just)
		local seta = (s.key == key) and (s.desc and " v" or " ^") or ""
		cv:Header(x0, y, w, 16, "|cffd4af37" .. L[rotulo] .. seta .. "|r", just or "RIGHT",
			{ onClick = function() Sim.SetSort(key); ns.UI.RefreshTab(ns.UI.TAB.SIM) end,
			  tip = function(tt) tt:SetText(L[rotulo]); tt:AddLine(L["Clique: ordenar por esta coluna"], 1, 1, 1) end })
	end
	cv:Text(c.reag, y + 2, "|cffd4af37" .. L["Reagentes"] .. "|r", GameFontNormalSmall, c.reagW)
	Head(c.cost, COL.cost, "cost", "Custo")
	Head(c.skill, COL.skill, "skill", "Perícia")
	Head(c.quality, COL.quality, "quality", "Qualidade", "CENTER")
	Head(c.conc, COL.conc, "conc", "Conc", "CENTER")
	Head(c.profit, COL.profit, "profit", "Lucro")
	Head(c.perConc, COL.perConc, "perConc", "Lucro/ponto")
	Head(c.crafts, COL.crafts, "crafts", "Crafts")
	Head(c.total, COL.total, "total", "Total")
	y = y + 18

	local ALT = Sim.LINHA
	for i, x in ipairs(linhas) do
		root.Zebra(cv, i, 0, y - 1, W, ALT)
		-- a melhor pelo total ganha fundo verde
		if x == melhorTotal and (x.totalGold or 0) > 0 then cv:Box(0, y - 1, W, ALT, 0.3, 1, 0.3, 0.12) end
		-- ícone de cada reagente escolhido, com a marca de qualidade: dá para ler a combinação de
		-- relance, sem decifrar estrelas
		local rx = c.reag
		for _, g in ipairs(x.reagentes or {}) do
			cv:Icon(rx, y + 2, ICON, V.ItemIcon(g.itemID), {
				qTier = g.q, qMax = g.maxQ,
				count = tostring(g.qty),
				rarity = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(g.itemID) or nil,
				link = select(2, C_Item.GetItemInfo(g.itemID)),
				tip = function(tt)
					tt:SetItemByID(g.itemID)
					tt:AddLine(" ")
					tt:AddDoubleLine(L["Precisa"], tostring(g.qty), 1, 0.82, 0, 1, 1, 1)
					tt:AddDoubleLine(L["Custo"], g.unit and G(g.unit * g.qty) or L["sem preço"], 1, 0.82, 0, 1, 1, 1)
				end })
			rx = rx + ICON + ICON_GAP
		end
		local ty = y + math.floor((ALT - 12) / 2)
		cv:Text(c.cost, ty, x.cost and G(x.cost) or "—", GameFontHighlightSmall, COL.cost, "RIGHT")
		cv:Text(c.skill, ty, tostring(x.skill or "—"), GameFontDisableSmall, COL.skill, "RIGHT")
		cv:Text(c.quality, ty, x.quality and ns.QIcon(x.quality, r.maxQuality) or "—",
			GameFontHighlightSmall, COL.quality, "CENTER")
		local concTxt = "—"
		if x.semConc then
			concTxt = L["|cff55ff55não usa|r"]
		elseif x.conc then
			concTxt = ns.ConcStr(x.conc, e and e.professionID)
		end
		cv:Text(c.conc, ty, concTxt, GameFontHighlightSmall, COL.conc, "CENTER")
		local lucro = x.concProfit or x.profit
		cv:Text(c.profit, ty, lucro and G(lucro, true) or "—", GameFontHighlightSmall, COL.profit, "RIGHT")
		cv:Text(c.perConc, ty, x.perConc and P.FormatMoney(x.perConc) or "—", GameFontHighlightSmall, COL.perConc, "RIGHT")
		-- sem concentração o limite é material/ouro: marca como livre em vez de competir no mesmo eixo
		local craftsTxt = x.crafts and tostring(x.crafts) or (x.semConc and L["|cff55ff55livre|r"] or "—")
		cv:Text(c.crafts, ty, craftsTxt, GameFontHighlightSmall, COL.crafts, "RIGHT")
		cv:Text(c.total, ty, x.totalGold and G(x.totalGold, true) or "—", GameFontNormalSmall, COL.total, "RIGHT")
		-- a área de tooltip da linha começa depois dos ícones, que têm o seu próprio
		cv:Hit(c.cost - GAP, y - 1, W - (c.cost - GAP), ALT, nil, function(tt)
			tt:SetText(r.name or "?")
			tt:AddLine(" ")
			for j, p in ipairs(r.parts or {}) do
				local opts = p.qualityItems or { p.itemID }
				if #opts > 1 then
					local id = opts[x.combo[j] or 1] or opts[1]
					local unit = P.Cost(id)
					tt:AddDoubleLine(string.format("%dx %s", p.qty or 1, V.ItemName(id) or tostring(id)),
						unit and G(unit * (p.qty or 1)) or L["sem preço"], 1, 1, 1, 0.8, 0.8, 0.8)
				end
			end
			tt:AddLine(" ")
			tt:AddDoubleLine(L["Custo"], G(x.cost or 0), 1, 0.82, 0, 1, 1, 1)
			if x.expQty then tt:AddDoubleLine(L["Itens esperados"], string.format("%.2f", x.expQty), 1, 0.82, 0, 1, 1, 1) end
			if x.conc and x.concEff then
				tt:AddDoubleLine(L["Concentração"], string.format(L["%s (efetiva %.1f)"],
					tostring(x.conc), x.concEff), 1, 0.82, 0, 1, 1, 1)
			end
			if x.estoque then tt:AddDoubleLine(L["Dá para fabricar com o que você tem"], tostring(x.estoque), 1, 0.82, 0, 1, 1, 1) end
			if x.semConc then
				tt:AddLine(L["Não gasta concentração: o limite aqui é material e ouro, não a barra."], 0.4, 0.8, 1, true)
			end
			if x.semPreco then tt:AddLine(L["Algum reagente está sem preço: o custo está incompleto."], 1, 0.6, 0.2, true) end
			if x.semOp then tt:AddLine(L["O jogo não respondeu a operação desta combinação (abra a profissão)."], 1, 0.6, 0.2, true) end
		end)
		y = y + ALT
	end

	if cortou then
		cv:Text(8, y + 4, string.format(L["|cff9d9d9dMostrando %d de %d combinações.|r"], #linhas, total),
			GameFontDisableSmall, W - 16)
		y = y + 18
	end
	cv:End(y + 10)
end
