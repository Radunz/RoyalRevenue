local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- ===== Aba Vender =====
-- Itens da BOLSA do personagem que podem ir para a casa de leilões (não vinculados, não lixo, não de missão):
-- quanto rendem hoje, melhor dia (e horário) para vender e se vale vender agora ou segurar.
-- O item que você coloca para vender (aba Vender da Blizzard ou aba Selling do Auctionator) aparece em destaque no topo.
-- Usa a mesma análise da aba Compras (Buy.Analyze): o melhor dia para vender é o de preço MAIS ALTO.
local Sell = {}
ns.Sell = Sell

local P = ns.Pricing
local Buy = ns.Buy
local U = Buy.UI
local G, CellColor, MiniDays, Card = U.G, U.CellColor, U.MiniDays, U.Card
local WD_SHORT, WD_LONG = Buy.WD_SHORT, Buy.WD_LONG
local SELL_NOW, HOLD = 0.04, -0.06   -- preço agora contra o típico
local MAX_ROWS = 80
local LIST_H = 360   -- altura da lista da bolsa (rola dentro)

-- grupo minimizável (como as outras abas): LucroCraftDB.config.sellCollapsed[chave] = true
function Sell.Group(cv, y, W, key, title, summary, rightPad, onToggle)
	local c = LucroCraftDB.config.sellCollapsed
	local col = c and c[key] or false
	cv:Box(0, y, W, 24, 0.17, 0.36, 0.66, 0.30)
	cv:Box(0, y, 3, 24, 0.70, 0.13, 0.20, 0.95)
	cv:Box(0, y + 23, W, 1, 0.83, 0.69, 0.22, 0.55)
	local icon = col and "|TInterface\\Buttons\\UI-PlusButton-Up:14:14|t " or "|TInterface\\Buttons\\UI-MinusButton-Up:14:14|t "
	cv:Text(8, y + 5, icon .. "|cffd4af37" .. title .. "|r", GameFontNormal, W - (rightPad or 0) - 220)
	if summary then cv:Text(8, y + 6, summary, GameFontHighlightSmall, W - 16 - (rightPad or 0), "RIGHT") end
	cv:Hit(0, y, W - (rightPad or 0), 24, function()
		LucroCraftDB.config.sellCollapsed = LucroCraftDB.config.sellCollapsed or {}
		LucroCraftDB.config.sellCollapsed[key] = not col or nil
		;(onToggle or Sell.Refresh)()
	end, function(tt)
		tt:SetText(title)
		tt:AddLine(col and L["Clique para expandir"] or L["Clique para minimizar"], 1, 1, 1)
	end)
	return y + 30, col
end

if not ns.isPT then
	local T = {
		["Vender"] = "Sell",
		["Mercado"] = "Market",
		["Fila de craft"] = "Craft queue",
		["itens"] = "items",
		["Itens da bolsa que podem ir para a AH · melhor dia para vender"] = "Bag items that can go to the AH · best day to sell",
		["Vender hoje"] = "Sell today",
		["Venda agora"] = "Sell now",
		["itens com preço acima do típico agora"] = "items priced above typical now",
		["Melhor dia para vender a bolsa toda"] = "Best day to sell the whole bag",
		["Receita da bolsa em cada dia (preço típico × padrão do dia)"] = "Bag revenue on each day (typical price × day pattern)",
		["Ponderado pela receita de cada item."] = "Weighted by each item's revenue.",
		["VENDA"] = "SELL",
		["SEGURE"] = "HOLD",
		["Verde = acima do típico (venda). Amarelo = normal. Vermelho = abaixo (segure até o melhor dia)."] = "Green = above typical (sell). Yellow = normal. Red = below (hold until the best day).",
		["Barras: verde = dia em que o preço fica acima da média da semana (bom para vender), vermelho = abaixo."] = "Bars: green = day the price is above the week's average (good to sell), red = below.",
		["tem %s"] = "have %s",
		["vende ~%s/dia"] = "sells ~%s/day",
		["Na bolsa"] = "In bags",
		["Receita (− corte da AH)"] = "Revenue (− AH cut)",
		["segure: %s"] = "hold: %s",
		["+%s no melhor dia"] = "+%s on the best day",
		["hoje já rende mais: venda agora"] = "today already pays more: sell now",
		["Nada para vender: nenhum item na bolsa pode ir para a casa de leilões."] = "Nothing to sell: no item in your bags can go to the auction house.",
		["Vendas/dia"] = "Sales/day",
		["Receita líquida"] = "Net revenue",
		["Melhor horário para vender"] = "Best time to sell",
		["Lista de venda no Auctionator"] = "Auctionator sell list",
		["Royal Revenue - Vender"] = "Royal Revenue - Sell",
		["Cria a lista \"Royal Revenue - Vender\" no Auctionator (para conferir os preços)."] = "Creates the \"Royal Revenue - Sell\" list in Auctionator (to check prices).",
		["Sem preço: item não é commodity ou ainda não foi visto na AH."] = "No price: not a commodity or not seen on the AH yet.",
		["Anunciando agora"] = "Posting now",
		["Coloque um item na aba Vender da casa de leilões (ou Selling do Auctionator) para ver aqui o melhor dia para ele."] = "Put an item in the auction house Sell tab (or Auctionator's Selling) to see its best day here.",
		["Venda agora: o preço está %s acima do típico."] = "Sell now: the price is %s above typical.",
		["Segure até %s: hoje está %s do típico; no melhor dia costuma ficar %s."] = "Hold until %s: today is %s vs. typical; on the best day it's usually %s.",
		["Preço normal. Melhor dia: %s (%s)."] = "Normal price. Best day: %s (%s).",
		["Preço normal."] = "Normal price.",
		["Sem histórico deste item (equipamento ou ainda não visto)."] = "No history for this item (gear or not seen yet).",
		["Receita agora"] = "Revenue now",
		["No melhor dia"] = "On the best day",
		["equipamento: preço pela fonte de preços (sem padrão por dia)"] = "gear: price from the price source (no day pattern)",
		["%d itens sem preço na AH ocultos"] = "%d items with no AH price hidden",
		["mais %d itens (mostrando os %d de maior receita)"] = "%d more items (showing the top %d by revenue)",
		["Bolsa de %s"] = "%s's bags",
		["no plano"] = "in plan",
		["Clique para ver o histórico de preço embaixo."] = "Click to see the price history below.",
		["Clique: coloca na aba Vender da casa de leilões"] = "Click: puts it in the auction house Sell tab",
		["Preço sugerido"] = "Suggested price",
		["Quantidade"] = "Quantity",
		["O histórico de preço aparece embaixo."] = "The price history shows below.",
		["Postar"] = "Post",
		["Postar agora"] = "Post now",
		["Preço"] = "Price",
		["Preço por unidade"] = "Price per unit",
		["Duração"] = "Duration",
		["24 horas"] = "24 hours",
		["Selo SEGURE: o preço sugerido é o típico, não o menor anúncio."] = "HOLD tag: the suggested price is the typical one, not the lowest listing.",
		["Um clique = um anúncio. O jogo cobra o depósito normal."] = "One click = one listing. The game charges the normal deposit.",
		["item não encontrado na bolsa (atualize a aba)."] = "item not found in bags (refresh the tab).",
		["não deu para colocar o item na casa de leilões."] = "couldn't put the item in the auction house.",
		["abra a casa de leilões para postar."] = "open the auction house to post.",
		["o jogo recusou o anúncio: "] = "the game refused the listing: ",
		["o jogo recusou o anúncio."] = "the game refused the listing.",
		["anunciado: %sx %s a %s."] = "posted: %sx %s at %s.",
		["o jogo pediu confirmação do preço: confirme na janela da casa de leilões."] = "the game asked to confirm the price: confirm it in the auction house window.",
		["Histórico de preço"] = "Price history",
		["|cff9d9d9d%s a %s · %d dias com preço · %d amostras com hora|r"] = "|cff9d9d9d%s to %s · %d days with price · %d timed samples|r",
		["menor %s · média %s · maior %s"] = "lowest %s · average %s · highest %s",
		["típico"] = "typical",
		["Menor"] = "Lowest",
		["Maior"] = "Highest",
		["Disponível"] = "Available",
		["vs. média"] = "vs. average",
		["barra azul = do menor ao maior preço do dia · traço = menor preço (verde acima da média, vermelho abaixo) · fundo verde = melhor dia para vender"] = "blue bar = day's lowest to highest price · mark = lowest price (green above average, red below) · green background = best day to sell",
		["Data"] = "Date",
		["Dia"] = "Day",
		["Amostras"] = "Samples",
		["Fontes"] = "Sources",
		["buscas/scans"] = "searches/scans",
		["Outros"] = "Other",
		["%d itens · %s"] = "%d items · %s",
		["Tudo"] = "All",
		["Média 7 dias"] = "7-day average",
		["Típico"] = "Typical",
		["Volume"] = "Volume",
		["Sem preço neste período."] = "No price in this period.",
		["vs. semana anterior"] = "vs. previous week",
		["Menor do período"] = "Period low",
		["Maior do período"] = "Period high",
		["Clique para mostrar/esconder."] = "Click to show/hide.",
		["máx. %s"] = "max %s",
		["Fundo verde = melhor dia para vender · linha branca vertical = hoje · passe o mouse num dia para ver os detalhes e as amostras com hora"] = "Green background = best day to sell · white vertical line = today · hover a day to see details and timed samples",
		["Esconder tabela dia a dia"] = "Hide day-by-day table",
		["Mostrar tabela dia a dia"] = "Show day-by-day table",
		["Item do Plano de concentração (o que você fabrica)."] = "Concentration plan item (something you craft).",
	}
	for k, v in pairs(T) do L[k] = v end
end

-- ===== item sendo anunciado (Blizzard ou Auctionator) =====
local function InfoFromLocation(loc)
	if not (loc and loc.IsValid and loc:IsValid()) then return nil end
	local okI, id = pcall(C_Item.GetItemID, loc)
	local okL, link = pcall(C_Item.GetItemLink, loc)
	if not (okI and id) then return nil end
	local okC, count = pcall(C_Item.GetStackCount, loc)
	return { id = id, link = okL and link or nil, count = okC and count or 1 }
end

function Sell.FindPosting()
	local ah = AuctionHouseFrame
	if not (ah and ah:IsShown()) then return nil end
	-- Auctionator (aba Selling)
	local af = ah.AuctionatorSellingFrame or _G.AuctionatorSellingFrame
	local sif = af and af.IsShown and af:IsShown() and af.SaleItemFrame
	local info = sif and sif.itemInfo
	if info and info.itemLink then
		local id = (info.location and InfoFromLocation(info.location) or {}).id
			or (C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(info.itemLink))
		if id then return { id = id, link = info.itemLink, count = info.count or 1 } end
	end
	-- Blizzard (aba Vender: commodity ou item)
	for _, k in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
		local f = ah[k]
		if f and f.IsShown and f:IsShown() and f.GetItem then
			local ok, loc = pcall(f.GetItem, f)
			local p = ok and InfoFromLocation(loc)
			if p then return p end
		end
	end
	return nil
end

-- ===== itens da bolsa que podem ir para a AH =====
local function PlanItems()
	local set = {}
	local ok, list = pcall(ns.Plan.Build)
	if not ok then return set end
	for _, it in ipairs(list or {}) do
		for _, u in ipairs(it.used or {}) do
			local r = u.row
			if r.concItemID then set[r.concItemID] = true end
			if r.itemID then set[r.itemID] = true end
		end
	end
	return set
end

-- ===== expansão e profissão de origem =====
local PROF = {   -- skillLine → nomes (reserva quando o cliente não dá o nome no idioma escolhido)
	[171] = { "Alquimia", "Alchemy" }, [164] = { "Ferraria", "Blacksmithing" }, [333] = { "Encantamento", "Enchanting" },
	[202] = { "Engenharia", "Engineering" }, [182] = { "Herborismo", "Herbalism" }, [773] = { "Escrivania", "Inscription" },
	[755] = { "Joalheria", "Jewelcrafting" }, [165] = { "Couraria", "Leatherworking" }, [186] = { "Mineração", "Mining" },
	[393] = { "Esfolamento", "Skinning" }, [197] = { "Alfaiataria", "Tailoring" }, [185] = { "Culinária", "Cooking" },
	[356] = { "Pesca", "Fishing" },
}
local PROF_ORDER = { 171, 164, 333, 202, 773, 755, 165, 197, 185, 182, 186, 393, 356 }
-- Reagente de profissão (classe 7) por subclasse
local TRADE_SUB = { [1] = 202, [4] = 755, [5] = 197, [6] = 393, [7] = 186, [8] = 185, [9] = 182, [12] = 333, [16] = 773 }
-- Consumível (classe 0) por subclasse
local CONS_SUB = { [0] = 202, [1] = 171, [2] = 171, [3] = 171, [4] = 773, [5] = 185, [6] = 333, [7] = 197, [9] = 773 }
-- Equipamento de profissão (classe 19) por subclasse
local TOOL_SUB = { [0] = 164, [1] = 165, [2] = 171, [3] = 182, [4] = 185, [5] = 186, [6] = 197, [7] = 202, [8] = 333, [9] = 356, [10] = 393, [11] = 755, [12] = 773 }
-- Receita (classe 9) por subclasse
local RECIPE_SUB = { [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171, [8] = 333, [9] = 356, [10] = 755, [11] = 773 }

function Sell.ProfName(id)
	if not id or id == 0 then return L["Outros"] end
	if ns.isPT == ns.clientPT and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
		local ok, n = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, id)
		if ok and type(n) == "string" and n ~= "" then return n end
	end
	local f = PROF[id]
	return f and (ns.isPT and f[1] or f[2]) or L["Outros"]
end

local function ProfIcon(id)
	if not id or id == 0 then return nil end
	if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture then
		local ok, t = pcall(C_TradeSkillUI.GetTradeSkillTexture, id)
		if ok and t then return t end
	end
	return nil
end

-- itens que as suas receitas fabricam → profissão (da varredura das profissões)
local craftMap, craftAt
local function CraftMap()
	if craftMap and craftAt and time() - craftAt < 60 then return craftMap end
	craftMap = {}
	for _, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do
			local pid = e.parentID
			if pid then
				for _, list in ipairs({ e.rows or {}, e.unknown or {} }) do
					for _, r in ipairs(list) do
						if r.itemID then craftMap[r.itemID] = pid end
						if r.concItemID then craftMap[r.concItemID] = pid end
					end
				end
			end
		end
	end
	craftAt = time()
	return craftMap
end

function Sell.SourceProf(m)
	local cm = CraftMap()
	if cm[m.id] then return cm[m.id] end
	local c, sc = m.classID, m.subclassID
	if c == 7 then return TRADE_SUB[sc] or 0 end
	if c == 0 then return CONS_SUB[sc] or 0 end
	if c == 3 then return 755 end          -- gemas
	if c == 8 then return 333 end          -- melhorias de item (encantamentos)
	if c == 16 then return 773 end         -- glifos
	if c == 19 then return TOOL_SUB[sc] or 0 end
	if c == 9 then return RECIPE_SUB[sc] or 0 end
	return 0
end

function Sell.ExpansionName(x)
	if not x or x < 0 then return L["Outros"] end
	local n = (ns.isPT == ns.clientPT) and _G["EXPANSION_NAME" .. x]
	if type(n) == "string" and n ~= "" then return n end
	local EN = { [0] = "Classic", "The Burning Crusade", "Wrath of the Lich King", "Cataclysm", "Mists of Pandaria", "Warlords of Draenor",
		"Legion", "Battle for Azeroth", "Shadowlands", "Dragonflight", "The War Within", "Midnight" }
	return EN[x] or ((ns.isPT and "Expansão " or "Expansion ") .. x)
end

local function BagItems()
	local out, byKey = {}, {}
	if not (C_Container and C_Container.GetContainerNumSlots) then return out end
	local last = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
	for bag = 0, last do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not info.isBound and (info.quality == nil or info.quality >= 1) then
				local _, _, _, _, _, _, _, maxStack, _, _, _, classID, subclassID, _, xpac = C_Item.GetItemInfo(info.itemID)
				if classID ~= 12 then   -- 12 = itens de missão
					local stackable = (maxStack or 1) > 1
					local key = stackable and info.itemID or (info.hyperlink or info.itemID)
					local m = byKey[key]
					if not m then
						m = { id = info.itemID, link = info.hyperlink, count = 0, gear = not stackable,
							classID = classID, subclassID = subclassID, xpac = xpac }
						byKey[key] = m
						table.insert(out, m)
					end
					m.count = m.count + (info.stackCount or 1)
					if not m.bag or (info.stackCount or 1) > (m.slotCount or 0) then
						m.bag, m.slot, m.slotCount = bag, slot, info.stackCount or 1
					end
				end
			end
		end
	end
	return out
end

-- itens da bolsa entram no registro de preços (buscas/scans/Auctionator)
function Buy.ExtraTracked()
	local set = {}
	for _, m in ipairs(BagItems()) do if not m.gear then set[m.id] = true end end
	return set
end

local function Signal(a)
	if not a.now then return "none" end
	if a.conf == "none" and not a.diff then return "normal" end
	local diff = a.diff or 0
	local todayWd = Buy.WeekdayOf(Buy.DayNum(time()))
	if diff >= SELL_NOW or (a.bestSell == todayWd and diff >= -0.02) then return "sell" end
	if diff <= HOLD then return "hold" end
	return "normal"
end

-- análise de um item (com o link para equipamento)
local function AnalyzeItem(m)
	local a = Buy.Analyze(m.id)
	if m.gear then
		-- equipamento: o histórico é por itemID (não pelo nível de item) → só o preço da fonte, sem padrão
		local v, spd = P.SaleByLink and m.link and P.SaleByLink(m.link)
		local now = v or a.now
		a = { id = m.id, days = 0, wd = {}, band = {}, timed = 0, conf = "none", now = now, typical = now, diff = nil, gearOnly = true, spd = spd }
		for w = 1, 7 do a.wd[w] = { s = 0, n = 0 } end
	end
	return a
end

function Sell.Build()
	if Buy._ClearCache then Buy._ClearCache() end
	local cut = 1 - (tonumber(ns.Cfg("ahCut")) or 0.05)
	local plan = PlanItems()
	local posting = Sell.FindPosting()
	Sell.posting = posting
	local res = { char = ns.CharKey(), items = {}, revNow = 0, revTyp = 0, n = 0, nGreen = 0, hidden = 0 }
	for _, m in ipairs(BagItems()) do
		m.a = AnalyzeItem(m)
		if m.a.now and m.a.now > 0 then
			m.signal = Signal(m.a)
			m.inPlan = plan[m.id]
			m.rev = m.count * m.a.now * cut
			m.revTyp = m.count * (m.a.typical or m.a.now) * cut
			m.spd = m.a.spd or P.SoldPerDay(m.id)
			res.n = res.n + 1
			if m.signal == "sell" then res.nGreen = res.nGreen + 1 end
			res.revNow = res.revNow + m.rev
			res.revTyp = res.revTyp + m.revTyp
			table.insert(res.items, m)
		else
			res.hidden = res.hidden + 1
		end
	end
	table.sort(res.items, function(a, b) return a.rev > b.rev end)
	-- grupos: expansão > profissão de origem
	local xs, byX = {}, {}
	for _, m in ipairs(res.items) do
		local xk = m.xpac or -1
		local xg = byX[xk]
		if not xg then
			xg = { key = xk, name = Sell.ExpansionName(m.xpac), profs = {}, byP = {}, rev = 0, n = 0 }
			byX[xk] = xg
			table.insert(xs, xg)
		end
		local pk = Sell.SourceProf(m)
		m.prof = pk
		local pg = xg.byP[pk]
		if not pg then
			pg = { key = pk, name = Sell.ProfName(pk), icon = ProfIcon(pk), items = {}, rev = 0 }
			xg.byP[pk] = pg
			table.insert(xg.profs, pg)
		end
		table.insert(pg.items, m)
		pg.rev, xg.rev, xg.n = pg.rev + m.rev, xg.rev + m.rev, xg.n + 1
	end
	-- expansão atual no topo; as demais da mais recente para a mais antiga (Classic no fim); "Outros" (-1) por último.
	-- Só aparecem expansões e profissões que têm itens na bolsa.
	local cur = (GetExpansionLevel and GetExpansionLevel()) or (LE_EXPANSION_LEVEL_CURRENT) or -1
	local maxX = -1
	for _, xg in ipairs(xs) do if xg.key > maxX then maxX = xg.key end end
	if cur < maxX then cur = maxX end
	table.sort(xs, function(a, b)
		if (a.key == cur) ~= (b.key == cur) then return a.key == cur end
		if (a.key < 0) ~= (b.key < 0) then return b.key < 0 end
		return a.key > b.key   -- da mais recente para a mais antiga (Classic por último)
	end)
	-- profissões em ordem alfabética; "Outros" por último
	for _, xg in ipairs(xs) do
		table.sort(xg.profs, function(a, b)
			if (a.key == 0) ~= (b.key == 0) then return b.key == 0 end
			return (a.name or ""):lower() < (b.name or ""):lower()
		end)
	end
	res.xgroups = xs
	-- item anunciado: análise própria (pode não estar mais na bolsa: já está no slot de venda)
	if posting then
		local pm = { id = posting.id, link = posting.link, count = posting.count or 1 }
		local _, _, _, _, _, _, _, maxStack = C_Item.GetItemInfo(posting.id)
		pm.gear = (maxStack or 1) <= 1
		pm.a = AnalyzeItem(pm)
		pm.signal = Signal(pm.a)
		pm.spd = pm.a.spd or P.SoldPerDay(pm.id)
		-- soma o que ainda está na bolsa do mesmo item
		-- o item continua na bolsa enquanto está no slot de venda: "tem" = total da bolsa
		for _, m in ipairs(res.items) do if m.id == pm.id and not pm.gear then pm.bag = m.count end end
		pm.count = math.max(pm.bag or 0, pm.count)
		pm.rev = (pm.a.now or 0) * pm.count * cut
		res.posting = pm
	end
	-- padrão da bolsa toda (receita típica × índice do dia); melhor = MAIOR receita
	res.wd = {}
	local any = false
	for w = 1, 7 do
		local s = 0
		for _, m in ipairs(res.items) do
			local x = m.a.conf ~= "none" and m.a.wd[w].idx or 0
			if x ~= 0 then any = true end
			s = s + m.revTyp * (1 + x)
		end
		res.wd[w] = s
	end
	if any and res.revTyp > 0 then
		for w = 1, 7 do
			if not res.best or res.wd[w] > res.wd[res.best] then res.best = w end
		end
	end
	-- horário
	res.band = {}
	for b = 1, U.BANDS do
		local s, wsum, n, ds = 0, 0, 0, {}
		for _, m in ipairs(res.items) do
			local x = m.a.band and m.a.band[b]
			if x and x.n > 0 then
				local wgt = math.max(m.revTyp, 1)
				s, wsum, n = s + wgt * (x.s / x.n - 1), wsum + wgt, n + x.n
				for d in pairs(x.days) do ds[d] = true end
			end
		end
		local nd = 0
		for _ in pairs(ds) do nd = nd + 1 end
		res.band[b] = { idx = wsum > 0 and s / wsum or nil, n = n, days = nd }
	end
	local bs, bc = 0, 0
	for b = 1, U.BANDS do local x = res.band[b]; if x.idx and x.days >= 3 then bs, bc = bs + x.idx, bc + 1 end end
	for b = 1, U.BANDS do
		local x = res.band[b]
		if bc >= 2 and x.idx and x.days >= 3 then
			x.idx = x.idx - bs / bc
			if not res.bestBand or x.idx > res.band[res.bestBand].idx then res.bestBand = b end
		else
			x.idx = nil
		end
	end
	res.histDays = 0
	for _, m in ipairs(res.items) do if (m.a.days or 0) > res.histDays then res.histDays = m.a.days end end
	-- item selecionado (histórico embaixo): clicado > anunciado > o de maior receita
	local sel = Sell.selected
	if sel then
		for _, m in ipairs(res.items) do if (m.gear and m.link or m.id) == sel then res.sel = m end end
		if not res.sel and res.posting and (res.posting.gear and res.posting.link or res.posting.id) == sel then res.sel = res.posting end
	end
	res.sel = res.sel or res.posting or res.items[1]
	return res
end

-- ===== desenho =====
local SIGNAL = {
	sell = { txt = "VENDA", r = 0.15, g = 0.75, b = 0.25 },
	normal = { txt = "NORMAL", r = 0.85, g = 0.7, b = 0.1 },
	hold = { txt = "SEGURE", r = 0.85, g = 0.2, b = 0.2 },
	none = { txt = "SEM PREÇO", r = 0.35, g = 0.35, b = 0.35 },
}

-- verde = acima (bom para vender)
local function SellColored(x)
	if not x then return "|cff9d9d9d—|r" end
	local s = U.Pct(x)
	if x >= 0.005 then return "|cff55ff55" .. s .. "|r" end
	if x <= -0.005 then return "|cffff5555" .. s .. "|r" end
	return "|cffffffff" .. s .. "|r"
end

local function DayTip(a, title)
	return function(tt)
		tt:SetText(title)
		for w = 1, 7 do
			local x = a.wd[w]
			tt:AddDoubleLine(WD_LONG[w], x.idx and (SellColored(x.idx) .. string.format(" |cff9d9d9d(%d)|r", x.n)) or "|cff9d9d9d—|r", 1, 0.82, 0, 1, 1, 1)
		end
		tt:AddLine(" ")
		tt:AddLine(L["Barras: verde = dia em que o preço fica acima da média da semana (bom para vender), vermelho = abaixo."], 0.7, 0.7, 0.7, true)
		tt:AddLine(L["Cada dia é comparado com a média dos 7 dias em volta, para não confundir tendência com dia da semana."], 0.7, 0.7, 0.7, true)
		if a.conf ~= "ok" then tt:AddLine(L["Com menos de 2 semanas de dados o padrão ainda é fraco."], 1, 0.6, 0.1, true) end
	end
end

local function ItemTip(m)
	local a = m.a
	return function(tt)
		if m.link then tt:SetHyperlink(m.link) else tt:SetItemByID(m.id) end
		tt:AddLine(" ")
		tt:AddDoubleLine(L["Na bolsa"], root.Num(m.bag or m.count, 0), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L["Receita (− corte da AH)"], P.FormatMoney(m.rev or 0), 1, 0.82, 0, 0.3, 1, 0.3)
		if m.spd then tt:AddDoubleLine(L["Vendas/dia"], root.Num(m.spd, 1), 1, 0.82, 0, 1, 1, 1) end
		tt:AddLine(" ")
		tt:AddDoubleLine(L["Preço agora"], a.now and P.FormatMoney(a.now) or "—", 1, 0.82, 0, 1, 1, 1)
		if a.gearOnly then
			tt:AddLine(L["equipamento: preço pela fonte de preços (sem padrão por dia)"], 0.7, 0.7, 0.7, true)
		else
			tt:AddDoubleLine(L["Preço típico (7 dias)"], a.typical and P.FormatMoney(a.typical) or "—", 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Diferença"], SellColored(a.diff), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Melhor dia"], a.bestSell and (WD_LONG[a.bestSell] .. " " .. SellColored(a.wd[a.bestSell].idx)) or L["sem dados"], 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Dias com preço"], root.Num(a.days, 0), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Amostras com hora"], root.Num(a.timed, 0), 1, 0.82, 0, 1, 1, 1)
		end
		if m.inPlan then tt:AddLine(L["Item do Plano de concentração (o que você fabrica)."], 0.4, 0.8, 1, true) end
	end
end

local function Advice(m)
	local a = m.a
	if a.gearOnly or a.conf == "none" then
		return a.gearOnly and L["Sem histórico deste item (equipamento ou ainda não visto)."] or L["Preço normal."]
	end
	if m.signal == "sell" then return string.format(L["Venda agora: o preço está %s acima do típico."], SellColored(a.diff)) end
	if m.signal == "hold" and a.bestSell then
		return string.format(L["Segure até %s: hoje está %s do típico; no melhor dia costuma ficar %s."], WD_LONG[a.bestSell], SellColored(a.diff), SellColored(a.wd[a.bestSell].idx))
	end
	if a.bestSell then return string.format(L["Preço normal. Melhor dia: %s (%s)."], WD_LONG[a.bestSell], SellColored(a.wd[a.bestSell].idx)) end
	return L["Preço normal."]
end

-- cartão grande do item que está sendo anunciado
local function DrawPosting(cv, y, W, pm)
	local H = 92
	cv:Box(0, y, W, H, 0.83, 0.69, 0.22, 0.14)
	cv:Box(0, y, 4, H, 0.83, 0.69, 0.22, 0.95)
	cv:Text(12, y + 6, "|cffd4af37" .. L["Anunciando agora"] .. "|r", GameFontNormal, 200)
	cv:Hit(70, y + 4, 330, 80, function() Sell.Select(pm) end, function(tt) tt:SetText(L["Clique para ver o histórico de preço embaixo."], 1, 1, 1) end)
	local a = pm.a
	local rarity = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(pm.id) or nil
	cv:Icon(12, y + 26, 48, ns.Visual.ItemIcon(pm.id), { count = tostring(pm.count), rarity = rarity, link = pm.link, tip = ItemTip(pm) })
	local name = (pm.link and pm.link:match("%[(.-)%]")) or ns.Visual.ItemName(pm.id)
	cv:Text(70, y + 26, "|cffffffff" .. name .. "|r", GameFontNormalLarge, 330)
	local sub = string.format(L["tem %s"], root.Num(pm.count, 0))
	if pm.spd then sub = sub .. " · " .. string.format(L["vende ~%s/dia"], pm.spd >= 10 and root.Num(pm.spd, 0) or root.Num(pm.spd, 1)) end
	cv:Text(70, y + 46, "|cff9d9d9d" .. sub .. "|r", GameFontHighlightSmall, 330)
	cv:Text(70, y + 64, Advice(pm), GameFontHighlightSmall, 420)
	-- preço e selo
	cv:Text(410, y + 24, a.now and G(a.now, true) or "|cff9d9d9d—|r", GameFontNormalLarge, 130, "RIGHT")
	if not a.gearOnly then
		cv:Text(410, y + 44, SellColored(a.diff) .. " |cff9d9d9dvs. " .. (a.typical and G(a.typical) or "—") .. "|r", GameFontHighlightSmall, 130, "RIGHT")
	end
	local s = SIGNAL[pm.signal] or SIGNAL.none
	cv:Box(556, y + 24, 96, 28, s.r, s.g, s.b, 0.9)
	cv:Text(556, y + 31, "|cffffffff" .. L[s.txt] .. "|r", GameFontNormal, 96, "CENTER")
	-- 7 dias grandes
	if not a.gearOnly then
		local todayWd = Buy.WeekdayOf(Buy.DayNum(time()))
		for w = 1, 7 do
			local cx = 668 + (w - 1) * 32
			if a.bestSell == w then cv:Box(cx - 2, y + 20, 32, 46, 0.83, 0.69, 0.22, 0.95) end
			cv:Box(cx, y + 22, 28, 42, 0.08, 0.13, 0.24, 1)
			local v = a.conf ~= "none" and a.wd[w].idx or nil
			local r, g, b, al = CellColor(v and -v or nil)
			cv:Box(cx, y + 22, 28, 42, r, g, b, al)
			cv:Text(cx, y + 26, (w == todayWd and "|cffffffff" or "|cffb0b0b0") .. WD_SHORT[w] .. "|r", GameFontHighlightSmall, 28, "CENTER")
			cv:Text(cx - 4, y + 44, v and SellColored(v) or "|cff9d9d9d—|r", GameFontHighlightSmall, 36, "CENTER")
		end
		cv:Hit(668, y + 22, 7 * 32, 42, nil, DayTip(a, name))
	end
	cv:Text(W - 130, y + 72, "|cff9d9d9d" .. L["Receita agora"] .. "|r " .. G(pm.rev, true), GameFontHighlightSmall, 124, "RIGHT")
	return y + H + 8
end

-- linhas da lista da bolsa (desenhadas dentro da área com rolagem)
local function DrawRow(cv, y, W, res, m, idx)
	local X_ICON, X_NAME, X_PRICE, X_SIG, X_DAYS, X_REV = 8, 48, 300, 430, 520, W - 130
	local postId = res.posting and res.posting.id
	local a = m.a
	if idx then root.Zebra(cv, idx, 0, y, W, 40) end
	if postId and m.id == postId then cv:Box(0, y, W, 40, 0.83, 0.69, 0.22, 0.16) end
	if res.sel == m then cv:Box(0, y, 3, 40, 0.4, 0.8, 1, 1); cv:Box(0, y, W, 40, 0.4, 0.8, 1, 0.08) end
	local ahOpen = Sell.AHOpen()
	cv:Hit(X_NAME, y + 2, X_SIG - X_NAME - 6, 36, function()
		if ahOpen then Sell.PutOnAH(m) end
		Sell.Select(m)
	end, function(tt)
		if ahOpen then
			tt:SetText(L["Clique: coloca na aba Vender da casa de leilões"], 1, 1, 1)
			tt:AddDoubleLine(L["Preço sugerido"], P.FormatMoney(Sell.SuggestPrice(m) or 0), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Quantidade"], root.Num(Sell.PostQty(m), 0), 1, 0.82, 0, 1, 1, 1)
			tt:AddLine(L["O histórico de preço aparece embaixo."], 0.7, 0.7, 0.7)
		else
			tt:SetText(L["Clique para ver o histórico de preço embaixo."], 1, 1, 1)
		end
	end)
	if ahOpen and m.signal ~= "none" and m.bag then
		cv:Button(X_REV - 70, y + 10, 62, 20, L["Postar"], function() Sell.Post(m) end, function(tt)
			tt:SetText(L["Postar agora"])
			tt:AddDoubleLine(L["Quantidade"], root.Num(Sell.PostQty(m), 0), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(m.gear and L["Preço"] or L["Preço por unidade"], P.FormatMoney(Sell.SuggestPrice(m) or 0), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Duração"], L["24 horas"], 1, 0.82, 0, 1, 1, 1)
			if m.signal == "hold" then tt:AddLine(L["Selo SEGURE: o preço sugerido é o típico, não o menor anúncio."], 1, 0.5, 0.3, true) end
			tt:AddLine(L["Um clique = um anúncio. O jogo cobra o depósito normal."], 0.7, 0.7, 0.7, true)
		end)
	end
	local name = (m.link and m.link:match("%[(.-)%]")) or ns.Visual.ItemName(m.id)
	local rarity = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(m.id) or nil
	local q = ns.Scanner and ns.Scanner.ReagentQuality and ns.Scanner.ReagentQuality(m.id)
	cv:Icon(X_ICON, y + 4, 32, ns.Visual.ItemIcon(m.id), {
		count = tostring(m.count), rarity = rarity, quality = q and ns.QIcon(q, 2, 10) or nil,
		link = m.link, tip = ItemTip(m) })
	cv:Text(X_NAME, y + 6, "|cffffffff" .. name .. "|r", GameFontHighlight, X_PRICE - X_NAME - 8)
	local sub = string.format(L["tem %s"], root.Num(m.count, 0))
	if m.spd then sub = sub .. " · " .. string.format(L["vende ~%s/dia"], m.spd >= 10 and root.Num(m.spd, 0) or root.Num(m.spd, 1)) end
	if m.inPlan then sub = sub .. " · |cff66ccff" .. L["no plano"] .. "|r" end
	cv:Text(X_NAME, y + 22, "|cff9d9d9d" .. sub .. "|r", GameFontDisableSmall, X_PRICE - X_NAME + 52)
	cv:Text(X_PRICE, y + 6, a.now and G(a.now) or "|cff9d9d9d—|r", GameFontHighlightSmall, 120, "RIGHT")
	if not a.gearOnly then
		cv:Text(X_PRICE, y + 22, SellColored(a.diff) .. " |cff9d9d9dvs. " .. (a.typical and G(a.typical) or "—") .. "|r", GameFontDisableSmall, 120, "RIGHT")
	end
	local s = SIGNAL[m.signal] or SIGNAL.none
	cv:Box(X_SIG, y + 8, 80, 22, s.r, s.g, s.b, 0.85)
	cv:Text(X_SIG, y + 13, "|cffffffff" .. L[s.txt] .. "|r", GameFontNormalSmall, 80, "CENTER")
	cv:Hit(X_SIG, y + 8, 80, 22, nil, function(tt)
		tt:SetText(L[s.txt])
		tt:AddLine(Advice(m), 1, 1, 1, true)
	end)
	if a.gearOnly then
		cv:Text(X_DAYS, y + 13, "|cff9d9d9d" .. L["equipamento: preço pela fonte de preços (sem padrão por dia)"] .. "|r", GameFontDisableSmall, X_REV - X_DAYS - (ahOpen and 74 or 4))
	else
		MiniDays(cv, X_DAYS, y + 9, a, DayTip(a, name), true)
		local bestTxt = a.bestSell and (WD_LONG[a.bestSell] .. " " .. SellColored(a.wd[a.bestSell].idx))
			or ("|cff9d9d9d" .. (a.conf == "none" and L["poucos dados"] or "") .. "|r")
		cv:Text(X_DAYS + 7 * 17 + 6, y + 13, bestTxt, GameFontHighlightSmall, X_REV - (X_DAYS + 7 * 17 + 6) - (ahOpen and 74 or 4))
	end
	cv:Text(X_REV, y + 6, G(m.rev, true), GameFontNormal, 122, "RIGHT")
	cv:Text(X_REV, y + 22, "|cff9d9d9d" .. L["Receita líquida"] .. "|r", GameFontDisableSmall, 122, "RIGHT")
	return y + 40
end

-- cabeçalho de profissão (dentro da expansão), minimizável
local function ProfHeader(cv, y, W, key, icon, title, summary, onToggle)
	local c = LucroCraftDB.config.sellCollapsed
	local col = c and c[key] or false
	cv:Box(14, y, W - 14, 20, 1, 0.82, 0, 0.08)
	local pm = col and "|TInterface\\Buttons\\UI-PlusButton-Up:12:12|t " or "|TInterface\\Buttons\\UI-MinusButton-Up:12:12|t "
	local ic = icon and ("|T" .. icon .. ":14:14|t ") or ""
	cv:Text(20, y + 4, pm .. ic .. "|cffffd100" .. title .. "|r", GameFontNormalSmall, W - 240)
	if summary then cv:Text(20, y + 4, summary, GameFontHighlightSmall, W - 30, "RIGHT") end
	cv:Hit(14, y, W - 14, 20, function()
		LucroCraftDB.config.sellCollapsed = LucroCraftDB.config.sellCollapsed or {}
		LucroCraftDB.config.sellCollapsed[key] = not col or nil
		;(onToggle or Sell.Refresh)()
	end, function(tt)
		tt:SetText(title)
		tt:AddLine(col and L["Clique para expandir"] or L["Clique para minimizar"], 1, 1, 1)
	end)
	return y + 24, col
end

Sell.ProfHeader, Sell.ProfIcon = ProfHeader, ProfIcon

-- lista agrupada: expansão (atual no topo, depois da mais recente à mais antiga) > profissão de origem (alfabética) > itens
local function DrawRows(cv, y, W, res)
	for _, xg in ipairs(res.xgroups) do
		local col
		y, col = Sell.Group(cv, y, W, "x:" .. xg.key, xg.name, string.format(L["%d itens · %s"], xg.n, G(xg.rev, true)))
		if not col then
			for _, pg in ipairs(xg.profs) do
				local pcol
				y, pcol = ProfHeader(cv, y, W, "x:" .. xg.key .. ":p:" .. pg.key, pg.icon, pg.name, string.format(L["%d itens · %s"], #pg.items, G(pg.rev, true)))
				if not pcol then
					for k, m in ipairs(pg.items) do y = DrawRow(cv, y, W, res, m, k) end
				end
			end
		end
		y = y + 4
	end
	if res.hidden > 0 then
		cv:Text(48, y + 2, "|cff9d9d9d" .. string.format(L["%d itens sem preço na AH ocultos"], res.hidden) .. "|r", GameFontDisableSmall)
		y = y + 18
	end
	return y
end

function Sell.Render(cv)
	local res = Sell.Build()
	local W = cv:Width()
	cv:Begin()
	cv:Text(8, 4, L["Itens da bolsa que podem ir para a AH · melhor dia para vender"], GameFontNormal, W - 460)
	Buy.DrawScan(cv, "sell", W - 446)
	cv:Button(W - 146, 0, 140, 20, L["Lista de venda no Auctionator"], function() Sell.ExportAuctionator(res) end, function(tt)
		tt:SetText(L["Lista de venda no Auctionator"])
		tt:AddLine(L["Cria a lista \"Royal Revenue - Vender\" no Auctionator (para conferir os preços)."], 1, 1, 1, true)
	end)
	local y = 28

	-- item sendo anunciado
	if res.posting then
		y = DrawPosting(cv, y, W, res.posting)
	else
		cv:Text(8, y, "|cff9d9d9d" .. L["Coloque um item na aba Vender da casa de leilões (ou Selling do Auctionator) para ver aqui o melhor dia para ele."] .. "|r", GameFontDisableSmall, W - 16)
		y = y + 18
	end

	if #res.items == 0 then
		cv:Text(8, y, L["Nada para vender: nenhum item na bolsa pode ir para a casa de leilões."], GameFontHighlight)
		cv:End(y + 30)
		return
	end

	-- cartões
	local cw = math.floor((W - 8 - 3 * 8) / 4)
	local bestRev = res.best and res.wd[res.best]
	Card(cv, 4, y, cw, L["Vender hoje"], G(res.revNow, true), res.n .. " " .. L["itens"])
	Card(cv, 4 + (cw + 8), y, cw, L["No melhor dia"] .. (res.best and (" · " .. WD_LONG[res.best]) or ""),
		bestRev and G(bestRev, true) or "|cff9d9d9d—|r",
		bestRev and (bestRev > res.revNow and string.format(L["+%s no melhor dia"], G(bestRev - res.revNow)) or L["hoje já rende mais: venda agora"]) or L["poucos dados"])
	Card(cv, 4 + 2 * (cw + 8), y, cw, L["Venda agora"], string.format("|cff55ff55%d|r / %d", res.nGreen, res.n),
		L["itens com preço acima do típico agora"])
	Card(cv, 4 + 3 * (cw + 8), y, cw, L["Histórico"], string.format(L["%d dias"], res.histDays),
		L["dias com preço (Auctionator + suas buscas e scans)"])
	y = y + 56

	-- dias da semana (bolsa toda): melhor = maior receita
	cv:Text(8, y, L["Melhor dia para vender a bolsa toda"], GameFontNormal)
	y = y + 18
	local todayWd = Buy.WeekdayOf(Buy.DayNum(time()))
	local dw = math.floor((W - 8 - 6 * 6) / 7)
	local maxDev = 0.005
	if res.best then for w = 1, 7 do maxDev = math.max(maxDev, math.abs(res.wd[w] / res.revTyp - 1)) end end
	for w = 1, 7 do
		local x = 4 + (w - 1) * (dw + 6)
		local dev = res.best and (res.wd[w] / res.revTyp - 1) or nil
		if res.best == w then cv:Box(x - 2, y - 2, dw + 4, 48, 0.83, 0.69, 0.22, 0.9) end
		cv:Box(x, y, dw, 44, 0.08, 0.13, 0.24, 1)
		local r, g, b, al = CellColor(dev and -dev or nil)
		local bh = dev and math.max(3, math.floor(22 * math.abs(dev) / maxDev)) or 0
		if bh > 0 then cv:Box(x + 6, y + 40 - bh, dw - 12, bh, r, g, b, math.max(al, 0.5)) end
		local nm = (w == todayWd) and ("|cffffffff" .. WD_SHORT[w] .. "|r |cff9d9d9d(" .. L["hoje"] .. ")|r") or ("|cffd9dde3" .. WD_SHORT[w] .. "|r")
		cv:Text(x, y + 3, nm, GameFontHighlightSmall, dw, "CENTER")
		cv:Text(x, y + 16, dev and SellColored(dev) or "|cff9d9d9d—|r", GameFontNormal, dw, "CENTER")
		cv:Hit(x, y, dw, 44, nil, function(tt)
			tt:SetText(WD_LONG[w])
			tt:AddLine(L["Receita da bolsa em cada dia (preço típico × padrão do dia)"], 0.7, 0.7, 0.7, true)
			tt:AddDoubleLine(L["Receita líquida"], res.best and G(res.wd[w]) or "—", 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Diferença"], SellColored(dev), 1, 0.82, 0, 1, 1, 1)
			tt:AddLine(L["Ponderado pela receita de cada item."], 0.7, 0.7, 0.7, true)
			if res.histDays < 14 then tt:AddLine(L["Com menos de 2 semanas de dados o padrão ainda é fraco."], 1, 0.6, 0.1, true) end
		end)
	end
	y = y + 52

	-- horário
	cv:Text(8, y, L["Melhor horário para vender"], GameFontNormal, 150)
	if res.bestBand then
		local bw = math.floor((W - 160 - 5 * 4) / U.BANDS)
		for b = 1, U.BANDS do
			local x = 156 + (b - 1) * (bw + 4)
			local band = res.band[b]
			if res.bestBand == b then cv:Box(x - 2, y - 2, bw + 4, 22, 0.83, 0.69, 0.22, 0.9) end
			cv:Box(x, y, bw, 18, 0.08, 0.13, 0.24, 1)
			local r, g, bb, al = CellColor(band.idx and -band.idx or nil)
			cv:Box(x, y, bw, 18, r, g, bb, al)
			cv:Text(x, y + 3, U.BAND_TXT[b] .. "  " .. SellColored(band.idx), GameFontHighlightSmall, bw, "CENTER")
		end
	else
		cv:Text(156, y + 2, "|cff9d9d9d" .. L["Precisa de amostras com hora: faça buscas ou scans na casa de leilões em horários diferentes."] .. "|r", GameFontDisableSmall, W - 164)
	end
	y = y + 26
	cv:Text(8, y, "|cff9d9d9d" .. L["Verde = acima do típico (venda). Amarelo = normal. Vermelho = abaixo (segure até o melhor dia)."] .. "|r", GameFontDisableSmall, W - 16)
	y = y + 18

	-- lista da bolsa (grupo minimizável, com barra de rolagem própria)
	local col
	y, col = Sell.Group(cv, y, W, "bag", string.format(L["Bolsa de %s"], ns.Visual.ClassName(res.char, nil)),
		string.format(L["%d itens · %s"], res.n, G(res.revNow, true)))
	local sub = cv._sellList
	if col then
		if sub then sub:Hide() end
	else
		if not sub then sub = ns.Visual.CreateSub(cv); cv._sellList = sub end
		sub:Place(0, y, W, LIST_H)
		sub:Show()
		sub:Begin()
		local h = DrawRows(sub, 0, sub:Width(), res)
		sub:End(h)
		local vis = math.min(h, LIST_H)
		sub:Place(0, y, W, vis)
		y = y + vis + 6
	end
	-- histórico de preço do item selecionado
	if res.sel then y = Sell.DrawHistory(cv, y + 10, W, res.sel) end
	cv:End(y + 8)
end

-- ===== histórico de preço do item selecionado =====
function Sell.Select(m)
	Sell.selected = m and (m.gear and m.link or m.id) or nil
	Sell.Refresh()
end

local function SelKey(m) return m.gear and m.link or m.id end

local function DateOf(dn) return date(ns.isPT and "%d/%m" or "%m/%d", dn * 86400 + 43200) end

local RANGES = { { 7, "7d" }, { 14, "14d" }, { 30, "30d" }, { 0, "Tudo" } }
local SERIES = {
	{ key = "min", label = "Menor", col = { 0.83, 0.69, 0.22 } },
	{ key = "max", label = "Maior", col = { 0.4, 0.6, 1 } },
	{ key = "ma", label = "Média 7 dias", col = { 0.3, 0.85, 0.45 } },
	{ key = "typ", label = "Típico", col = { 1, 1, 1 } },
	{ key = "vol", label = "Volume", col = { 0.55, 0.55, 0.65 } },
}
local function HistCfg()
	LucroCraftDB.config = LucroCraftDB.config or {}
	local c = LucroCraftDB.config
	c.sellHist = c.sellHist or { range = 30, show = { min = true, max = true, ma = true, typ = true, vol = true }, table = false }
	return c.sellHist
end

local function Tile(cv, x, y, w, label, value, sub)
	cv:Box(x, y, w, 40, 0.17, 0.36, 0.66, 0.16)
	cv:Text(x + 6, y + 4, "|cff9d9d9d" .. label .. "|r", GameFontDisableSmall, w - 10)
	cv:Text(x + 6, y + 17, value, GameFontNormal, w - 10)
	if sub then cv:Text(x + 6, y + 29, sub, GameFontDisableSmall, w - 10) end
end

-- Inspirado nos sites de preço do WoW (TSM, The Undermine Journal, BootyBayBroker):
-- período (7/14/30 dias/tudo), resumo com tendência, gráfico de linhas com séries liga/desliga e volume embaixo.
function Sell.DrawHistory(cv, y, W, m, refresh, key)
	refresh = refresh or Sell.Refresh
	local a = m.a
	local cfg = HistCfg()
	local name = (m.link and m.link:match("%[(.-)%]")) or ns.Visual.ItemName(m.id)
	local top = y
	local yy, col = Sell.Group(cv, y, W, key or "hist", L["Histórico de preço"] .. " · |cffffffff" .. name .. "|r", nil, #RANGES * 50 + 8, refresh)
	-- período (fica no cabeçalho, à direita)
	local bx = W - 4 - #RANGES * 50
	for _, r in ipairs(RANGES) do
		local on = cfg.range == r[1]
		if on then cv:Box(bx - 2, top + 1, 48, 22, 0.83, 0.69, 0.22, 0.95) end
		cv:Button(bx, top + 2, 44, 20, r[1] == 0 and L["Tudo"] or r[2], function() cfg.range = r[1]; refresh() end)
		bx = bx + 50
	end
	if col then return yy end
	y = yy
	local h = (not m.gear) and Buy.History(m.id) or { days = {} }
	if not h.first then
		cv:Text(8, y, "|cff9d9d9d" .. L["Sem histórico deste item (equipamento ou ainda não visto)."] .. "|r", GameFontHighlightSmall, W - 16)
		return y + 20
	end
	local today = Buy.DayNum(time())
	local last = math.max(h.last, today)
	local first = cfg.range > 0 and math.max(h.first, last - cfg.range + 1) or h.first
	local nDays = last - first + 1

	-- média móvel de 7 dias (dos menores preços)
	local function MA(dn)
		local s, n = 0, 0
		for k = dn - 6, dn do local d = h.days[k]; if d and d.min then s, n = s + d.min, n + 1 end end
		return n >= 3 and s / n or nil
	end

	-- resumo (como o TSM): agora, típico, variação, menor/maior do período, vendas/dia, disponível
	local lo, loD, hi, hiD, vmax, lastAvail, lastAvailD = nil, nil, nil, nil, 0, nil, nil
	for dn = first, last do
		local d = h.days[dn]
		if d and d.min then
			if not lo or d.min < lo then lo, loD = d.min, dn end
			if not hi or d.max > hi then hi, hiD = d.max, dn end
		end
		if d and d.avail then
			vmax = math.max(vmax, d.avail)
			lastAvail, lastAvailD = d.avail, dn
		end
	end
	if not lo then
		cv:Text(8, y, "|cff9d9d9d" .. L["Sem preço neste período."] .. "|r", GameFontHighlightSmall, W - 16)
		return y + 20
	end
	local ma7 = MA(last) or a.typical
	local maPrev = MA(last - 7)
	local trend = (ma7 and maPrev and maPrev > 0) and (ma7 / maPrev - 1) or nil
	local tw = math.floor((W - 8 - 5 * 6) / 6)
	local function arrow(x) if not x then return "" end return x >= 0 and "|TInterface\\Buttons\\Arrow-Up-Up:12:12:0:-2|t" or "|TInterface\\Buttons\\Arrow-Down-Up:12:12:0:2|t" end
	Tile(cv, 4, y, tw, L["Preço agora"], a.now and G(a.now, true) or "—", a.diff and (SellColored(a.diff) .. " |cff9d9d9dvs. " .. L["típico"] .. "|r") or nil)
	Tile(cv, 4 + (tw + 6), y, tw, L["Média 7 dias"], ma7 and G(ma7, true) or "—", trend and (arrow(trend) .. SellColored(trend) .. " |cff9d9d9d" .. L["vs. semana anterior"] .. "|r") or nil)
	Tile(cv, 4 + 2 * (tw + 6), y, tw, L["Menor do período"], G(lo, true), "|cff9d9d9d" .. DateOf(loD) .. " · " .. WD_LONG[Buy.WeekdayOf(loD)] .. "|r")
	Tile(cv, 4 + 3 * (tw + 6), y, tw, L["Maior do período"], G(hi, true), "|cff9d9d9d" .. DateOf(hiD) .. " · " .. WD_LONG[Buy.WeekdayOf(hiD)] .. "|r")
	Tile(cv, 4 + 4 * (tw + 6), y, tw, L["Vendas/dia"], m.spd and root.Num(m.spd, 1) or "—", "|cff9d9d9d" .. ns.Pricing.SourceName() .. "|r")
	Tile(cv, 4 + 5 * (tw + 6), y, tw, L["Disponível"], lastAvail and root.Num(lastAvail, 0) or "—", lastAvailD and ("|cff9d9d9d" .. DateOf(lastAvailD) .. "|r") or nil)
	y = y + 48

	-- séries liga/desliga
	local sx = 8
	for _, sr in ipairs(SERIES) do
		local on = cfg.show[sr.key] ~= false
		cv:Box(sx, y + 4, 12, 12, sr.col[1], sr.col[2], sr.col[3], on and 1 or 0.2)
		cv:Text(sx + 16, y + 3, (on and "|cffffffff" or "|cff6f6f6f") .. L[sr.label] .. "|r", GameFontHighlightSmall, 110)
		cv:Hit(sx, y, 120, 20, function() cfg.show[sr.key] = not on; refresh() end, function(tt)
			tt:SetText(L[sr.label]); tt:AddLine(L["Clique para mostrar/esconder."], 1, 1, 1)
		end)
		sx = sx + 126
	end
	y = y + 24

	-- gráfico de preço
	local CH, LEFT = 150, 74
	local cw = W - LEFT - 8
	local step = cw / math.max(1, nDays - 1)
	local yLo, yHi = lo, hi
	if cfg.show.typ ~= false and a.typical then yLo, yHi = math.min(yLo, a.typical), math.max(yHi, a.typical) end
	local pad = (yHi - yLo) * 0.1 + 1
	yLo, yHi = math.max(0, yLo - pad), yHi + pad
	local function X(dn) return LEFT + (nDays == 1 and cw / 2 or (dn - first) * step) end
	local function Y(v) return y + CH - (v - yLo) / (yHi - yLo) * CH end
	cv:Box(LEFT, y, cw, CH, 0.08, 0.13, 0.24, 1)
	for k = 0, 3 do
		local v = yLo + (yHi - yLo) * (k / 3)
		cv:Box(LEFT, Y(v), cw, 1, 1, 1, 1, 0.07)
		cv:Text(4, Y(v) - 6, "|cff9d9d9d" .. G(v) .. "|r", GameFontDisableSmall, LEFT - 8, "RIGHT")
	end
	-- colunas: melhor dia para vender (fundo), hoje, e tooltip
	local colW = math.max(2, step)
	for dn = first, last do
		local cx = X(dn) - colW / 2
		local wd = Buy.WeekdayOf(dn)
		if a.bestSell == wd then cv:Box(math.max(LEFT, cx), y, math.min(colW, LEFT + cw - math.max(LEFT, cx)), CH, 0.15, 0.85, 0.25, 0.07) end
		if dn == today then cv:Box(X(dn), y, 1, CH, 1, 1, 1, 0.35) end
		local d = h.days[dn]
		cv:Hit(math.max(LEFT, cx), y, math.max(2, math.min(colW, LEFT + cw - math.max(LEFT, cx))), CH, nil, function(tt)
			tt:SetText(DateOf(dn) .. " · " .. WD_LONG[wd])
			if not d then tt:AddLine(L["sem dados"], 0.6, 0.6, 0.6) return end
			tt:AddDoubleLine(L["Menor"], d.min and P.FormatMoney(d.min) or "—", 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Maior"], d.max and P.FormatMoney(d.max) or "—", 1, 0.82, 0, 1, 1, 1)
			local mv = MA(dn)
			if mv then tt:AddDoubleLine(L["Média 7 dias"], P.FormatMoney(mv), 1, 0.82, 0, 1, 1, 1) end
			if mv and d.min then tt:AddDoubleLine(L["vs. média"], SellColored(d.min / mv - 1), 1, 0.82, 0, 1, 1, 1) end
			if d.avail then tt:AddDoubleLine(L["Disponível"], root.Num(d.avail, 0), 1, 0.82, 0, 1, 1, 1) end
			if #d.samples > 0 then
				tt:AddLine(" ")
				tt:AddLine(L["Amostras com hora"], 1, 0.82, 0)
				for i = #d.samples, math.max(1, #d.samples - 11), -1 do
					local smp = d.samples[i]
					tt:AddDoubleLine(date("%H:%M", smp.t), P.FormatMoney(smp.p), 0.8, 0.8, 0.8, 1, 1, 1)
				end
			end
		end)
	end
	-- típico (linha horizontal tracejada)
	if cfg.show.typ ~= false and a.typical then
		local ty = Y(a.typical)
		for xx = LEFT, LEFT + cw - 6, 10 do cv:Box(xx, ty, 5, 1, 1, 1, 1, 0.55) end
	end
	-- linhas: liga pontos de dias com dado
	local function Series(get, col, thick, dots)
		local px, py
		for dn = first, last do
			local v = get(dn)
			if v then
				local x, yy = X(dn), Y(v)
				if px then cv:Line(px, py, x, yy, thick, col[1], col[2], col[3], 0.95) end
				if dots then cv:Box(x - 2, yy - 2, 4, 4, col[1], col[2], col[3], 1) end
				px, py = x, yy
			end
		end
	end
	if cfg.show.max ~= false then Series(function(dn) local d = h.days[dn]; return d and d.max end, SERIES[2].col, 1, false) end
	if cfg.show.ma ~= false then Series(MA, SERIES[3].col, 2, false) end
	if cfg.show.min ~= false then Series(function(dn) local d = h.days[dn]; return d and d.min end, SERIES[1].col, 2, nDays <= 31) end
	y = y + CH + 4

	-- volume (quantidade anunciada no dia)
	if cfg.show.vol ~= false and vmax > 0 then
		local VH = 40
		cv:Box(LEFT, y, cw, VH, 0.08, 0.13, 0.24, 1)
		cv:Text(4, y + VH / 2 - 6, "|cff9d9d9d" .. L["Volume"] .. "|r", GameFontDisableSmall, LEFT - 8, "RIGHT")
		local bw = math.max(2, math.min(18, step * 0.7))
		for dn = first, last do
			local d = h.days[dn]
			if d and d.avail and d.avail > 0 then
				local bh = math.max(1, d.avail / vmax * (VH - 4))
				cv:Box(X(dn) - bw / 2, y + VH - bh, bw, bh, SERIES[5].col[1], SERIES[5].col[2], SERIES[5].col[3], 0.8)
			end
		end
		cv:Text(LEFT + cw - 120, y + 2, "|cff9d9d9d" .. string.format(L["máx. %s"], root.Num(vmax, 0)) .. "|r", GameFontDisableSmall, 116, "RIGHT")
		y = y + VH + 2
	end
	-- datas no eixo
	local every = nDays <= 8 and 1 or nDays <= 16 and 2 or nDays <= 35 and 7 or 14
	for dn = last, first, -every do
		cv:Text(X(dn) - 22, y, "|cff9d9d9d" .. DateOf(dn) .. "|r", GameFontDisableSmall, 44, "CENTER")
	end
	y = y + 16
	cv:Text(LEFT, y, "|cff9d9d9d" .. L["Fundo verde = melhor dia para vender · linha branca vertical = hoje · passe o mouse num dia para ver os detalhes e as amostras com hora"] .. "|r", GameFontDisableSmall, cw)
	y = y + 18

	-- tabela dia a dia (recolhível)
	cv:Button(8, y, 200, 20, cfg.table and L["Esconder tabela dia a dia"] or L["Mostrar tabela dia a dia"], function() cfg.table = not cfg.table; refresh() end)
	y = y + 26
	if cfg.table then
		local cols = { { L["Data"], 8, 70 }, { L["Dia"], 80, 80 }, { L["Menor"], 160, 110, "RIGHT" }, { L["Maior"], 280, 110, "RIGHT" },
			{ L["vs. média"], 400, 80, "RIGHT" }, { L["Disponível"], 490, 90, "RIGHT" }, { L["Amostras"], 590, 80, "RIGHT" }, { L["Fontes"], 690, W - 700 } }
		cv:Box(0, y, W, 18, 1, 1, 1, 0.06)
		for _, c in ipairs(cols) do cv:Text(c[2], y + 3, "|cff9d9d9d" .. c[1] .. "|r", GameFontDisableSmall, c[3], c[4]) end
		y = y + 20
		local k = 0
		for dn = last, first, -1 do
			local d = h.days[dn]
			if d then
				k = k + 1
				root.Zebra(cv, k, 0, y - 1, W, 17)
				local wd = Buy.WeekdayOf(dn)
				local src = {}
				if d.src.atr then table.insert(src, "Auctionator") end
				if d.src.own then table.insert(src, L["scan próprio"]) end
				if d.src.samp then table.insert(src, L["buscas/scans"]) end
				local mv = MA(dn)
				local vals = { DateOf(dn) .. (dn == today and (" |cff9d9d9d(" .. L["hoje"] .. ")|r") or ""),
					(a.bestSell == wd and "|cff55ff55" or "") .. WD_LONG[wd] .. (a.bestSell == wd and "|r" or ""),
					d.min and G(d.min) or "—", d.max and G(d.max) or "—",
					(mv and d.min) and SellColored(d.min / mv - 1) or "—",
					d.avail and root.Num(d.avail, 0) or "—", #d.samples > 0 and tostring(#d.samples) or "—", table.concat(src, ", ") }
				for i, c in ipairs(cols) do cv:Text(c[2], y, vals[i], GameFontHighlightSmall, c[3], c[4]) end
				y = y + 16
			end
		end
	end
	return y + 4
end

-- lista no Auctionator com os itens a vender (para buscar o preço do momento)
function Sell.ExportAuctionator(res)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
		ns.Print(L["Auctionator não encontrado."])
		return
	end
	res = res or Sell.Build()
	local terms, seen = {}, {}
	for _, m in ipairs(res.items) do
		if not seen[m.id] then
			seen[m.id] = true
			local name = C_Item.GetItemNameByID(m.id)
			if name then
				local term = { searchString = name, isExact = true }
				local q = ns.Scanner.ReagentQuality and ns.Scanner.ReagentQuality(m.id)
				if q then term.tier = q end
				local ok, str = pcall(api.ConvertToSearchString, ADDON, term)
				if ok and str then table.insert(terms, str) end
			end
		end
	end
	if #terms == 0 then ns.Print(L["nada a comprar."]) return end
	local listName = L["Royal Revenue - Vender"]
	local ok, err = pcall(api.CreateShoppingList, ADDON, listName, terms)
	if ok then
		ns.Print(string.format(L["lista \"%s\" criada no Auctionator com %d itens."], listName, #terms))
	else
		ns.Print(L["erro no Auctionator: "] .. tostring(err))
	end
end

-- ===== vender pela casa de leilões =====
function Sell.AHOpen()
	return AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown() and not InCombatLockdown() or false
end

local function Location(m)
	if not (m.bag and m.slot and ItemLocation and ItemLocation.CreateFromBagAndSlot) then return nil end
	local loc = ItemLocation:CreateFromBagAndSlot(m.bag, m.slot)
	if loc and loc.IsValid and loc:IsValid() then return loc end
	return nil
end

-- menor anúncio AO VIVO da busca que a AH acabou de fazer (quando o item vai para o slot de venda)
-- devolve preço por unidade e se o menor anúncio é seu
function Sell.LivePrice(m)
	if not (C_AuctionHouse and m) then return nil end
	if not m.gear and C_AuctionHouse.GetCommoditySearchResultInfo then
		local ok, r = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, m.id, 1)
		if ok and r and r.unitPrice and r.unitPrice > 0 then return r.unitPrice, r.containsOwnerItem end
	elseif m.gear and C_AuctionHouse.GetItemKeyFromItem and C_AuctionHouse.GetItemSearchResultInfo then
		local loc = m.bag and ItemLocation and ItemLocation:CreateFromBagAndSlot(m.bag, m.slot)
		local okK, key = pcall(C_AuctionHouse.GetItemKeyFromItem, loc)
		if okK and key then
			local ok, r = pcall(C_AuctionHouse.GetItemSearchResultInfo, key, 1)
			if ok and r and (r.buyoutAmount or 0) > 0 then return r.buyoutAmount, r.containsOwnerItem end
		end
	end
	return nil
end

-- preço sugerido (sem dar undercut desnecessário):
--   1. menor anúncio ao vivo da AH (se tiver) — senão o "agora" guardado — senão o típico;
--   2. commodity: IGUALA o menor anúncio (quem compra pega o mais barato primeiro; preço igual divide a fila),
--      arredondado PARA CIMA na prata; equipamento: iguala também;
--   3. selo SEGURE: nunca abaixo do típico;
--   4. piso: nunca abaixo de 85% do típico (quando o mercado está despencando, segura no piso e avisa).
-- devolve: preço, motivo ("live" | "stored" | "typical" | "floor" | "hold")
local FLOOR = 0.85
function Sell.SuggestPrice(m)
	local a = m.a or {}
	local live = Sell.LivePrice(m)
	local p, why = live, "live"
	if not p then p, why = a.now, "stored" end
	if not p then p, why = a.typical, "typical" end
	if not p or p <= 0 then return nil end
	local typ = a.typical
	if typ and typ > 0 then
		if m.signal == "hold" and p < typ then p, why = typ, "hold" end
		if p < typ * FLOOR then p, why = typ * FLOOR, "floor" end
	end
	if not m.gear then p = math.max(100, math.ceil(p / 100) * 100) end
	return math.floor(p), why, live
end

function Sell.PostQty(m)
	if m.gear then return 1 end
	local loc = Location(m)
	if loc and C_AuctionHouse and C_AuctionHouse.GetAvailablePostCount then
		local ok, n = pcall(C_AuctionHouse.GetAvailablePostCount, loc)
		if ok and type(n) == "number" and n > 0 then return math.min(n, m.count) end
	end
	return m.count
end

local function SellFrame(m)
	local ah = AuctionHouseFrame
	if not ah then return nil end
	if m.gear then return ah.ItemSellFrame end
	return ah.CommoditiesSellFrame
end

-- coloca o item na aba Vender da Blizzard com quantidade e preço
function Sell.PutOnAH(m)
	local loc = Location(m)
	if not loc then ns.Print(L["item não encontrado na bolsa (atualize a aba)."]) return end
	local ah = AuctionHouseFrame
	local ok = pcall(function()
		if ah.SetPostItem then ah:SetPostItem(loc)
		else
			local sf = SellFrame(m)
			if ah.SetDisplayMode and AuctionHouseFrameDisplayMode then
				ah:SetDisplayMode(m.gear and AuctionHouseFrameDisplayMode.ItemSell or AuctionHouseFrameDisplayMode.CommoditiesSell)
			end
			if sf and sf.SetItem then sf:SetItem(loc) end
		end
	end)
	if not ok then ns.Print(L["não deu para colocar o item na casa de leilões."]) return end
	-- a Blizzard ajusta o preço quando a busca volta: aplica o nosso depois (recalculado com o menor anúncio ao vivo)
	local qty = Sell.PostQty(m)
	local warned = false
	local function apply()
		local sf = SellFrame(m)
		if not sf then return end
		local price, why, live = Sell.SuggestPrice(m)
		if (why == "floor" or why == "hold") and live and not warned then
			warned = true
			ns.Print(string.format(L["menor anúncio agora %s está abaixo do típico: preço segurado em %s."], ns.Pricing.FormatMoney(live), ns.Pricing.FormatMoney(price or 0)))
		end
		if price and sf.PriceInput and sf.PriceInput.SetAmount then pcall(sf.PriceInput.SetAmount, sf.PriceInput, price) end
		if qty and sf.QuantityInput and sf.QuantityInput.SetQuantity then pcall(sf.QuantityInput.SetQuantity, sf.QuantityInput, qty) end
		if sf.UpdatePostState then pcall(sf.UpdatePostState, sf) end
	end
	C_Timer.After(0.6, apply)
	C_Timer.After(1.8, apply)
end

-- posta direto (precisa do clique do jogador: chamado só pelo botão)
local DURATION = 2   -- 1 = 12 h, 2 = 24 h, 3 = 48 h
function Sell.Post(m)
	if not Sell.AHOpen() then ns.Print(L["abra a casa de leilões para postar."]) return end
	local loc = Location(m)
	local price = (Sell.SuggestPrice(m))
	if not loc or not price then ns.Print(L["item não encontrado na bolsa (atualize a aba)."]) return end
	local qty = Sell.PostQty(m)
	local ok, err
	if m.gear then
		ok, err = pcall(C_AuctionHouse.PostItem, loc, DURATION, 1, nil, price)
	else
		ok, err = pcall(C_AuctionHouse.PostCommodity, loc, DURATION, qty, price)
	end
	if not ok then
		ns.Print(L["o jogo recusou o anúncio: "] .. tostring(err))
		return
	end
	Sell.lastPost = { name = (m.link and m.link:match("%[(.-)%]")) or C_Item.GetItemNameByID(m.id) or "?", qty = qty, price = price }
end

function Sell.Refresh()
	if ns.UI and ns.UI.RefreshTab and ns.UI.TAB and ns.UI.TAB.SELL then ns.UI.RefreshTab(ns.UI.TAB.SELL) end
end

-- ===== acompanha o item colocado para vender e a bolsa =====
-- Com a casa de leilões aberta: confere a cada 0,5 s qual item está no slot de venda.
-- Mudou → se a janela do Royal Revenue está aberta, mostra a aba Vender com o item em destaque.
local lastKey, ticker, bagPending = nil, nil, false
local function KeyOf(p) return p and ((p.link or p.id) .. "#" .. (p.count or 1)) or "" end

local function CheckPosting()
	local p = Sell.FindPosting()
	local key = KeyOf(p)
	if key == lastKey then return end
	local hadItem = lastKey ~= nil and lastKey ~= ""
	lastKey = key
	if p then Sell.selected = nil end
	local frame = _G.LucroCraftFrame
	if not (frame and frame:IsShown()) then return end
	if p and ns.UI and ns.UI.CurrentTab and ns.UI.CurrentTab() ~= ns.UI.TAB.SELL and ns.Cfg("sellFocus") ~= false then
		ns.UI.ShowTab(ns.UI.TAB.SELL)
	elseif p or hadItem then
		Sell.Refresh()
	end
end
Sell._CheckPosting = CheckPosting

-- abas da casa de leilões levam o addon junto (Vender ↔ Compras)
local hooked = false
local function FollowMode(mode)
	if InCombatLockdown() or not ns.UI or not ns.UI.TAB then return end
	local frame = _G.LucroCraftFrame
	if not (frame and frame:IsShown()) then return end
	local M = AuctionHouseFrameDisplayMode
	if not M then return end
	if mode == M.CommoditiesSell or mode == M.ItemSell then
		if ns.UI.CurrentTab() ~= ns.UI.TAB.SELL then ns.root.Open("mercado", ns.UI.TAB.SELL) end
	elseif mode == M.Buy or mode == M.ItemBuy or mode == M.CommoditiesBuy then
		if ns.UI.CurrentTab() ~= ns.UI.TAB.BUY then ns.root.Open("mercado", ns.UI.TAB.BUY) end
	end
end
local function HookAH()
	if hooked or not AuctionHouseFrame then return end
	hooked = true
	if AuctionHouseFrame.SetDisplayMode then
		hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode) pcall(FollowMode, mode) end)
	end
	-- aba Selling do Auctionator
	local af = AuctionHouseFrame.AuctionatorSellingFrame
	if af and af.HookScript then
		af:HookScript("OnShow", function()
			local frame = _G.LucroCraftFrame
			if frame and frame:IsShown() and not InCombatLockdown() then ns.root.Open("mercado", ns.UI.TAB.SELL) end
		end)
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
pcall(f.RegisterEvent, f, "AUCTION_HOUSE_AUCTION_CREATED")
pcall(f.RegisterEvent, f, "AUCTION_HOUSE_POST_WARNING")
pcall(f.RegisterEvent, f, "AUCTION_HOUSE_POST_ERROR")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:SetScript("OnEvent", function(_, event)
	if not LucroCraftDB then return end
	if event == "AUCTION_HOUSE_AUCTION_CREATED" then
		if Sell.lastPost then
			ns.Print(string.format(L["anunciado: %sx %s a %s."], root.Num(Sell.lastPost.qty, 0), Sell.lastPost.name, P.FormatMoney(Sell.lastPost.price)))
			Sell.lastPost = nil
		end
		C_Timer.After(1, Sell.Refresh)
		return
	elseif event == "AUCTION_HOUSE_POST_WARNING" then
		ns.Print(L["o jogo pediu confirmação do preço: confirme na janela da casa de leilões."])
		return
	elseif event == "AUCTION_HOUSE_POST_ERROR" then
		ns.Print(L["o jogo recusou o anúncio."])
		Sell.lastPost = nil
		return
	end
	if event == "AUCTION_HOUSE_SHOW" then
		C_Timer.After(0.2, function()
			pcall(HookAH)
			-- abre o addon no Mercado > Compras
			if ns.Cfg("ahAutoOpen") ~= false and not InCombatLockdown() and ns.root and ns.root.Open then
				ns.root.Open("mercado", ns.UI.TAB.BUY)
			end
		end)
		lastKey = nil
		if ticker then ticker:Cancel() end
		if C_Timer.NewTicker then ticker = C_Timer.NewTicker(0.5, function() pcall(CheckPosting) end) end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if ticker then ticker:Cancel(); ticker = nil end
		lastKey = nil
		Sell.posting = nil
		Sell.Refresh()
	elseif event == "BAG_UPDATE_DELAYED" then
		-- bolsa mudou (vendeu, recebeu do correio): redesenha se a aba estiver aberta
		if bagPending then return end
		bagPending = true
		C_Timer.After(1, function() bagPending = false; Sell.Refresh() end)
	end
end)
