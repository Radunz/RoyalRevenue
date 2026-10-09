local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

local UI = {}
ns.UI = UI

-- IDs das abas = ordem visual (o PanelTemplates reancora as abas pela ordem do ID)
-- a aba Histórico (vendas) foi para o addon LucroLivro (/livro vendas)
-- (a aba Apostas saiu na v1.0.15: TAB.BETS = nil)
-- Dois grupos de abas na mesma janela (menu de cima): Craft (1-6) e Mercado (7-8). IDs na ordem visual de cada grupo.
local TAB = { LIST = 1, PLAN = 2, INVEST = 3, SALVAGE = 4, QUEUE = 5, SETTINGS = 6, BUY = 7, SELL = 8, RECIPES = 9 }
local MARKET = { [7] = true, [8] = true, [9] = true }
-- Configurações (6) não tem aba: abre pela engrenagem e mantém o grupo atual
function UI.ModeOf(id)
	if id == TAB.SETTINGS then return UI.Mode and UI.Mode() or "craft" end
	return MARKET[id or 1] and "market" or "craft"
end
UI.TAB = TAB

local P = ns.Pricing
local Cfg = ns.Cfg

local ROW_H = 18
local NUM_ROWS = 22
-- lista dividida em 3 grupos empilhados (cada um pode ser minimizado clicando no título):
-- com lucro | sem lucro | receitas desconhecidas (ainda não aprendidas, com lucro)
-- weight = parte do espaço livre; grupo com poucas linhas cede o que sobra aos outros
-- A divisão por volume (Volume x Baixo volume, alto lucro) saiu na v1.28.0: o que separa a lista
-- agora são as ABAS Concentração / Sem concentração (UI.RecipeList).
local SECTIONS = {
	{ title = L["Com lucro"], desc = L["dá lucro agora"], rows = 13, weight = 15 },
	{ title = L["Sem lucro"], desc = L["prejuízo ou sem preço de venda"], rows = 5, weight = 5 },
	{ title = L["Receitas desconhecidas"], desc = L["ainda não aprendidas, com lucro"], rows = 5, weight = 6 },
}
local TRANSMUTE, UNKNOWN = nil, 3   -- transmutações têm a parte delas na aba Destruir
local NOPROFIT = 2

-- grupos minimizados: LucroCraftDB.config.collapsed[índice] = true
local function IsCollapsed(si)
	local cfg = LucroCraftDB.config
	-- v1.11: grupo novo (Transmutações) entrou na posição 4; "desconhecidas" foi para a 5
	if not cfg.secMig5 then cfg.secMig5 = true end
	-- v1.15.2: o grupo Transmutações saiu; "desconhecidas" volta para a posição 4
	if not cfg.secMig6 then
		cfg.secMig6 = true
		if cfg.collapsed then cfg.collapsed[4], cfg.collapsed[5] = cfg.collapsed[5], nil end
	end
	-- v1.28.0: Volume + Baixo volume viraram um grupo só; sem lucro 3->2, desconhecidas 4->3
	if not cfg.secMig7 then
		cfg.secMig7 = true
		local c = cfg.collapsed
		if c then
			local comLucro = (c[1] and c[2]) and true or nil   -- só fica minimizado se os dois estavam
			c[1], c[2], c[3], c[4] = comLucro, c[3], c[4], nil
		end
	end
	local c = cfg.collapsed
	return c and c[si] and true or false
end

-- ===== Abas da lista: Concentração x Sem concentração =====
-- "conc" lista só os resultados que GASTAM concentração (a qualidade de cima);
-- "noconc" lista o resto (craft normal, reagentes superiores, revenda de NPC).
local RECIPE_LISTS = { { key = "conc", label = "Concentração" }, { key = "noconc", label = "Sem concentração" } }
function UI.RecipeList()
	local v = LucroCraftDB and LucroCraftDB.config and LucroCraftDB.config.recipeList
	return (v == "noconc") and "noconc" or "conc"
end
-- UI.SetRecipeList fica depois do "state" (local usado por função definida antes dele vira nil)
local TOTAL_ROWS = 0
for _, sec in ipairs(SECTIONS) do TOTAL_ROWS = TOTAL_ROWS + sec.rows + 1 end   -- +1 = linha do título
local WIDTH = 760

local COLUMNS = {
	{ key = "name",   label = L["Receita"],   width = 250, align = "LEFT" },
	{ key = "cost",   label = L["Custo"],     width = 80,  align = "RIGHT" },
	{ key = "sale",   label = L["Venda (un)"], width = 80, align = "RIGHT" },
	{ key = "trend",  label = L["Tend."],     width = 44,  align = "RIGHT" },
	{ key = "qty",    label = L["Qtd"],       width = 36,  align = "RIGHT" },
	{ key = "profit", label = L["Lucro"],     width = 86,  align = "RIGHT" },
	{ key = "margin", label = L["Margem"],    width = 60,  align = "RIGHT" },
	{ key = "spd",    label = L["Vendas/dia (%)"], width = 104, align = "RIGHT" },
	{ key = "mySpd",  label = L["Minhas/dia"], width = 64, align = "RIGHT", defaultHidden = true },
	{ key = "craftable", label = L["Estoque"], width = 52, align = "RIGHT", defaultHidden = true },
	{ key = "abc",    label = "ABC",       width = 40,  align = "CENTER" },
	{ key = "concCost",   label = "Conc",          width = 44, align = "RIGHT" },
	{ key = "perConc",    label = L["Lucro/conc"],    width = 72, align = "RIGHT" },
}

local COL_BY_KEY = {}
for _, c in ipairs(COLUMNS) do COL_BY_KEY[c.key] = c end
local COL_GAP = 6
local LEFT_PAD = 12 + ROW_H + 4   -- margem + ícone
local MIN_WIDTH = 520

-- Ordem e visibilidade salvas em LucroCraftDB.config.columns = { order = {...}, hidden = {key=true} }
local function ColCfg()
	local cfg = LucroCraftDB.config
	cfg.columns = cfg.columns or {}
	local cc = cfg.columns
	cc.hidden = cc.hidden or {}
	-- valida a ordem salva (colunas novas entram no fim, chaves antigas somem)
	local order, seen = {}, {}
	for _, k in ipairs(cc.order or {}) do
		if COL_BY_KEY[k] and not seen[k] then table.insert(order, k); seen[k] = true end
	end
	for i, c in ipairs(COLUMNS) do
		if not seen[c.key] then
			-- coluna nova entra logo depois da coluna que vem antes dela no padrão
			local prev = COLUMNS[i - 1] and COLUMNS[i - 1].key
			local pos = #order + 1
			for j, k in ipairs(order) do if k == prev then pos = j + 1 end end
			table.insert(order, pos, c.key)
			seen[c.key] = true
			if c.defaultHidden then cc.hidden[c.key] = true end
		end
	end
	cc.order = order
	cc.hidden.name = nil   -- Receita nunca some
	return cc
end

local function VisibleColumns()
	local cc = ColCfg()
	local list = {}
	for _, k in ipairs(cc.order) do
		if not cc.hidden[k] then table.insert(list, COL_BY_KEY[k]) end
	end
	return list
end

local state = {
	offset = 0,
	offsets = { 0, 0, 0, 0, 0 },
	views = { {}, {}, {} },
	view = nil,       -- linhas filtradas/ordenadas
	profID = nil,     -- profissão exibida
}

function UI.SetRecipeList(key)
	LucroCraftDB.config.recipeList = (key == "noconc") and "noconc" or "conc"
	state.offset = 0; state.offsets = { 0, 0, 0, 0, 0 }
	UI.Refresh()
end

local frame

local function Entries()
	local chars = LucroCraftDB.chars or {}
	return chars[ns.CharKey()] or {}
end

local function SortedProfIDs()
	local ids = {}
	for id in pairs(Entries()) do table.insert(ids, id) end
	table.sort(ids)
	return ids
end

local function CurrentEntry()
	local entries = Entries()
	if state.profID and entries[state.profID] then return entries[state.profID] end
	local last = LucroCraftDB.last
	if last and last.char == ns.CharKey() and entries[last.professionID] then
		state.profID = last.professionID
		return entries[last.professionID]
	end
	local ids = SortedProfIDs()
	state.profID = ids[1]
	return state.profID and entries[state.profID]
end

local function SortValue(r, key)
	if key == "abc" then
		return r.abc and ({ A = 3, B = 2, C = 1 })[r.abc] or 0
	end
	local v = r[key]
	if v == false then return nil end
	return v
end

-- Cada receita vira uma linha por qualidade que você consegue fazer:
--   sem concentração (qualidade que a skill atinge) e com concentração (qualidade acima).
-- A linha é uma "visão" da receita salva: campos sobrescritos, o resto vem da receita.
local VIEW_MT = { __index = function(t, k) return rawget(t, "_r")[k] end }
local function Variants(r)
	local out = {}
	local function my(id) return ns.Sales and ns.Sales.PerDay(id) or false end
	local base = setmetatable({ _r = r, variant = "base", concCost = false, perConc = false, concEff = false,
		concProfit = false, trend = r.trend or false, mySpd = my(r.itemID) }, VIEW_MT)
	table.insert(out, base)
	if r.concCost and r.concItemID then
		table.insert(out, setmetatable({
			_r = r, variant = "conc",
			quality = r.concQuality, itemID = r.concItemID,
			sale = r.concSale or false, spd = r.concSpd or false,
			profit = r.concProfit or false, profitBase = false,
			margin = (r.concProfit and r.expCost and r.expCost > 0) and (r.concProfit / r.expCost) or false,
			lowVolume = (r.concSpd or 0) < (tonumber(Cfg("minSoldPerDay")) or 1),
			trend = r.concTrend or false,
			mySpd = (r.concItemID ~= r.itemID) and my(r.concItemID) or false,
			-- classe do item de cima (curva do ouro/ponto), não a do item base
			abc = r.concAbc or false, abcShare = r.concAbcShare or false, abcFree = false,
			notAuctionable = r.concNotAuctionable or false,
		}, VIEW_MT))
	end
	-- mesma qualidade de cima trocando reagentes pela qualidade superior (sem gastar concentração)
	if r.mix and r.mixSale and r.mixCost then
		table.insert(out, setmetatable({
			_r = r, variant = "mix",
			quality = r.mix.quality, itemID = r.mix.itemID,
			sale = r.mixSale, spd = r.mixSpd or false,
			cost = r.mixCost, buyCost = r.mixCost, expCost = r.mixExpCost or r.mixCost,
			profit = r.mixProfit or false, profitBase = false,
			margin = (r.mixProfit and r.mixExpCost and r.mixExpCost > 0) and (r.mixProfit / r.mixExpCost) or false,
			concCost = false, perConc = false, concEff = false, concProfit = false,
			lowVolume = (r.mixSpd or 0) < (tonumber(Cfg("minSoldPerDay")) or 1),
			trend = r.mixTrend or false,
			mySpd = (r.mix.itemID ~= r.itemID) and my(r.mix.itemID) or false,
			-- não gasta concentração: A quando o craft dá lucro
			abc = r.mixAbc or false, abcShare = false, abcFree = r.mixAbc and true or false,
		}, VIEW_MT))
	end
	-- revenda: item que o vendedor (NPC) vende e dá para anunciar na AH
	local cut = Cfg("ahCut")
	local function npc(itemID, quality, sale, spd)
		local vb = itemID and P.VendorBuy(itemID)
		if not vb or not sale then return end
		local profit = sale * (1 - cut) - vb
		if profit <= 0 then return end   -- revenda só aparece quando dá lucro
		table.insert(out, setmetatable({
			_r = r, variant = "npc", itemID = itemID, quality = quality,
			cost = vb, buyCost = vb, expCost = false, qty = 1, expQty = 1, sale = sale, spd = spd or false,
			profit = profit, profitBase = false, margin = profit / vb,
			concCost = false, perConc = false, concEff = false, concProfit = false,
			missing = false, usesCrafted = false, usesStock = false, excluded = false, parts = false, stats = false,
			mix = false, craftable = false, trend = P.Trend(itemID) or false, mySpd = my(itemID),
			lowVolume = (spd or 0) < (tonumber(Cfg("minSoldPerDay")) or 1),
			-- revenda do NPC só existe dando lucro, e não gasta concentração
			abc = "A", abcShare = false, abcFree = true, notAuctionable = false,
		}, VIEW_MT))
	end
	npc(r.itemID, r.quality, r.sale, r.spd)
	if r.concItemID and r.concItemID ~= r.itemID then npc(r.concItemID, r.concQuality, r.concSale, r.concSpd) end
	return out
end

-- Ordenação em vários níveis, salva em LucroCraftDB.config.sort = { {key=, desc=}, ... }
local DEFAULT_SORT = { { key = "abc", desc = true }, { key = "profit", desc = true } }

local function SortKeys()
	local cfg = LucroCraftDB.config
	if type(cfg.sort) ~= "table" or #cfg.sort == 0 then
		cfg.sort = {}
		for _, s in ipairs(DEFAULT_SORT) do table.insert(cfg.sort, { key = s.key, desc = s.desc }) end
	end
	return cfg.sort
end

local function SortIndexOf(key)
	for i, s in ipairs(SortKeys()) do if s.key == key then return i end end
end

-- clique normal: ordena só por essa coluna; Shift+clique: adiciona como próximo nível
function UI.SortByColumn(key, additive)
	local keys = SortKeys()
	local i = SortIndexOf(key)
	if additive then
		if i then keys[i].desc = not keys[i].desc
		else table.insert(keys, { key = key, desc = key ~= "name" }) end
	else
		if i == 1 and #keys == 1 then
			keys[1].desc = not keys[1].desc
		else
			local desc = key ~= "name"
			if i == 1 then desc = not keys[1].desc end
			LucroCraftDB.config.sort = { { key = key, desc = desc } }
		end
	end
	UI.Refresh()
end

function UI.ResetSort()
	LucroCraftDB.config.sort = nil
	UI.Refresh()
end

UI._Variants = Variants

-- 1 = com lucro, 2 = sem lucro (a divisão por volume saiu na v1.28.0)
function UI.Category(r)
	local best = r.profit
	if r.excluded or not best or best <= 0 then return NOPROFIT end
	return 1
end
-- a linha pertence à aba aberta? ("conc" = gasta concentração; "noconc" = o resto)
local function InRecipeList(v)
	local isConc = v.variant == "conc"
	return isConc == (UI.RecipeList() == "conc")
end

local function BuildView()
	local entry = CurrentEntry()
	local view = {}
	if entry then
		for _, r in ipairs(entry.rows) do
			for _, v in ipairs(Variants(r)) do table.insert(view, v) end
		end
		-- % das vendas/dia: participação de cada item (cada qualidade conta separado) no total da profissão
		local total, seen = 0, {}
		for _, v in ipairs(view) do
			local id = v.itemID or v.recipeID
			if type(v.spd) == "number" and not seen[id] and not v.gathered then seen[id] = true; total = total + v.spd end
		end
		for _, v in ipairs(view) do
			v.spdPct = (total > 0 and type(v.spd) == "number" and not v.gathered) and (v.spd / total) or false
			-- quantos crafts o estoque atual cobre (ao vivo)
			if v.variant ~= "npc" and ns.Stock then
				rawset(v, "craftable", ns.Stock.CraftsFor(v.parts) or false)
			end
		end
		local keys = SortKeys()
		state.cmp = function(a, b)
			-- receitas com reagente sem preço sempre no fim (custo não confiável)
			if (a.excluded or false) ~= (b.excluded or false) then return not a.excluded end
			for _, sk in ipairs(keys) do
				local va, vb = SortValue(a, sk.key), SortValue(b, sk.key)
				if va ~= vb then
					if va == nil then return false end   -- vazios sempre no fim
					if vb == nil then return true end
					if sk.desc then return va > vb end
					return va < vb
				end
			end
			return (a.name or "") < (b.name or "")
		end
		table.sort(view, state.cmp)
	end
	state.view = view
	-- separa nas seções, só o que pertence à aba aberta (Concentração x Sem concentração)
	state.views = { {}, {}, {} }
	for _, r in ipairs(view) do
		if InRecipeList(r) then table.insert(state.views[UI.Category(r)], r) end
	end
	-- receitas desconhecidas: só as variações que dão lucro (sem revenda de NPC)
	if entry and entry.unknown then
		local uv = state.views[UNKNOWN]
		for _, r in ipairs(entry.unknown) do
			for _, v in ipairs(Variants(r)) do
				local p = v.profit
				if InRecipeList(v) and v.variant ~= "npc" and not v.excluded and type(p) == "number" and p > 0 then
					if v.variant ~= "npc" and ns.Stock then
						rawset(v, "craftable", ns.Stock.CraftsFor(v.parts) or false)
					end
					rawset(v, "spdPct", false)
					table.insert(uv, v)
				end
			end
		end
		if state.cmp then table.sort(uv, state.cmp) end
	end
	for i, sec in ipairs(SECTIONS) do
		local maxOffset = math.max(0, #state.views[i] - sec.rows)
		if state.offsets[i] > maxOffset then state.offsets[i] = maxOffset end
	end
end

local function SecsText(s)
	s = math.max(0, s or 0)
	if s >= 3600 then return string.format("%dh%02d", math.floor(s / 3600), math.floor((s % 3600) / 60)) end
	return string.format("%d min", math.ceil(s / 60))
end

local ABC_COLOR = { A = "|cff55ff55A|r", B = "|cffffd100B|r", C = "|cff9d9d9dC|r" }

-- cor do número de vendas/dia pela chance de vender (escala log, ancorada nas configs):
-- < minSoldPerDay vermelho · até volumeMinSpd laranja · até 10× amarelo · até 100× lima · acima verde forte
local function SpdColor(n)
	local minS = tonumber(Cfg("minSoldPerDay")) or 1
	local vol = tonumber(Cfg("volumeMinSpd")) or 10
	if n < minS then return "|cffff5555" end
	if n < vol then return "|cffff8800" end
	if n < vol * 10 then return "|cffffd100" end
	if n < vol * 100 then return "|cffa8ff60" end
	return "|cff20ff60"
end

-- "Instrutor", "Vendedor", "Drop"... = primeiro trecho do texto de origem do próprio jogo
function UI.SourceTag(txt)
	if type(txt) ~= "string" then return nil end
	local plain = txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
	local first = plain:match("^%s*([^:|\n]+)")
	if not first then return nil end
	first = first:gsub("%s+$", "")
	if #first > 22 then first = first:sub(1, 20) .. "…" end
	return first ~= "" and first or nil
end

local function FillRow(row, r)
	row.data = r
	row.icon:SetTexture(r.icon)
	local qTag = ""
	if r.quality and r.maxQuality and r.maxQuality > 1 then
		qTag = " " .. ns.QIcon(r.quality, r.maxQuality)
	end
	local tag = (r.variant == "npc" and L[" |cff66ccff(revenda NPC)|r"])
		or (r.variant == "mix" and L[" |cff66ccff(reagentes sup.)|r"]) or ""
	if r.unknown then
		local how = UI.SourceTag(r.source)
		tag = tag .. " |cffff8800(" .. (how or L["desconhecida"]) .. ")|r"
	end
	row.cols.name:SetText((r.name or "?") .. qTag .. tag)
	local cost = P.FormatGold(r.cost)
	if r.missing then cost = cost .. "|cffff8800*|r" end
	if r.usesCrafted then cost = cost .. "|cff66ccfff|r" end
	if r.usesStock then cost = cost .. "|cffa8ff60e|r" end
	row.cols.cost:SetText(cost)
	row.cols.sale:SetText(P.FormatGold(r.sale))
	row.cols.trend:SetText(P.TrendText(type(r.trend) == "number" and r.trend or nil))
	if type(r.mySpd) == "number" then
		row.cols.mySpd:SetText(r.mySpd >= 10 and root.Num(r.mySpd, 0) or root.Num(r.mySpd, 1))
	else
		row.cols.mySpd:SetText("|cff808080—|r")
	end
	if type(r.craftable) == "number" then
		row.cols.craftable:SetText((r.craftable > 0 and "|cff55ff55" or "|cff808080") .. r.craftable .. "|r")
	else
		row.cols.craftable:SetText("|cff808080—|r")
	end
	row.cols.qty:SetText(r.qty == math.floor(r.qty) and tostring(r.qty) or root.Num(r.qty, 1))
	if r.excluded then
		row.cols.profit:SetText("|cff808080" .. P.FormatGold(r.profit) .. "|r")
	else
		row.cols.profit:SetText(P.FormatGold(r.profit, true))
	end
	if r.margin then
		local c = r.margin >= 0 and "|cff55ff55" or "|cffff5555"
		row.cols.margin:SetText(string.format("%s%d%%|r", c, math.floor(r.margin * 100 + 0.5)))
	else
		row.cols.margin:SetText("|cff808080—|r")
	end
	if type(r.spd) == "number" then
		local n = r.spd
		local txt = n >= 1000 and string.format("%.1fk", n / 1000) or n >= 10 and root.Num(n, 0) or root.Num(n, 2)
		txt = SpdColor(n) .. txt .. "|r"
		if r.gathered then
			txt = txt .. " |cff9d9d9d(" .. L["coleta"] .. ")|r"
		elseif r.spdPct then
			local pct = r.spdPct * 100
			txt = txt .. string.format(" |cff9d9d9d(%s)|r", pct >= 10 and string.format("%.0f%%", pct)
				or pct >= 0.1 and (root.Num(pct, 1) .. "%") or (root.Num(pct, 2) .. "%"))
		end
		if r.lowVolume then txt = "|cffff8800!|r" .. txt end
		row.cols.spd:SetText(txt)
	else
		row.cols.spd:SetText("|cffff8800—!|r")
	end
	row.cols.abc:SetText(r.abc and ABC_COLOR[r.abc] or "|cff808080—|r")
	if r.concCost then
		-- verde: dá para fazer agora · amarelo: precisa esperar regenerar · vermelho: maior que a barra cheia
		local entry = CurrentEntry()
		local col = "|cffffffff"
		if entry and entry.conc and entry.conc.cur then
			local now = entry.conc.cur
			if ns.Plan and ns.Plan.EstimatedConc then now = ns.Plan.EstimatedConc(entry) end
			if r.concCost <= now then col = "|cff55ff55"
			elseif r.concCost <= (entry.conc.max or 1000) then col = "|cffffd100"
			else col = "|cffff5555" end
		end
		row.cols.concCost:SetText(col .. tostring(r.concCost) .. "|r")
	else
		row.cols.concCost:SetText("|cff808080—|r")
	end
	if r.perConc and not ns.Recommendable(r, true) then
		-- vende pouco: não entra nas recomendações, mostra em cinza
		row.cols.perConc:SetText("|cff808080" .. P.FormatGold(r.perConc) .. "|r")
	else
		row.cols.perConc:SetText(r.perConc and P.FormatGold(r.perConc, true) or "|cff808080—|r")
	end
	row:Show()
end

function UI.Refresh()
	if not frame or not frame:IsShown() then return end
	if frame.currentTab and frame.currentTab ~= 1 then
		UI.RefreshTab(frame.currentTab)
		return
	end
	BuildView()
	local entry = CurrentEntry()
	local view = state.view

	if entry then
		local when = date("%d/%m %H:%M", entry.time)
		local concTxt = ""
		if entry.conc and entry.conc.cur then
			concTxt = string.format(L["  |cff66ccffConcentração %d/%d|r"], entry.conc.cur, entry.conc.max or 0)
		end
		local age = ns.Alerts and ns.Alerts.AgeText(entry.time) or when
		local priced = ns.Alerts and ns.Alerts.AgeText(entry.pricedAt or entry.time) or ""
		frame.profLabel:SetText(string.format(L["|cffffd100%s|r  %s%s  |cff9d9d9d(scan há %s|cff9d9d9d · preços há %s|cff9d9d9d · %s)|r"],
			entry.name or "?", entry.expansion or entry.skillLine or "", concTxt, age, priced, entry.source or "?"))
	else
		frame.profLabel:SetText(L["|cff9d9d9dNenhum dado. Abra sua profissão para escanear.|r"])
	end

	-- abas da lista: a ativa em dourado
	local curList = UI.RecipeList()
	for i, b in ipairs(frame.listTabs or {}) do
		local on = b.key == curList
		b.bg:SetColorTexture(0.06, 0.1, 0.2, 1)
		b.edge:SetColorTexture(on and 0.83 or 0.3, on and 0.69 or 0.3, on and 0.22 or 0.35, on and 0.95 or 0.6)
		local n = #(state.views and state.views[1] or {})
		b.text:SetText((on and "|cffffd100" or "|cffd9dde3") .. L[RECIPE_LISTS[i].label]
			.. (on and string.format("  |cff9d9d9d(%d)|r", n) or "") .. "|r")
	end

	UI.LayoutRows()
	for si, sec in ipairs(frame.sections) do
		local v = state.views[si] or {}
		local hidden = (si == NOPROFIT and Cfg("onlyProfit"))
		local collapsed = IsCollapsed(si)
		local off = state.offsets[si] or 0
		for j, row in ipairs(sec.rows) do
			local r = (not hidden) and j <= sec.cfg.rows and v[off + j] or nil
			if r then FillRow(row, r) else row.data = nil; row:Hide() end
		end
		local range = ""
		if #v > sec.cfg.rows and not hidden then
			range = string.format(L["  |cff9d9d9d%d–%d de %d (role com o mouse)|r"], off + 1, math.min(off + sec.cfg.rows, #v), #v)
		end
		local extra = ""
		if si == TRANSMUTE and #v > 0 then
			-- cargas: o limite do dia. Melhor uso da carga = a de maior lucro esperado
			local cur, max, nextIn
			for _, r in ipairs(v) do
				local c, m, n = ns.Charges(r)
				if c and (not max or m > max) then cur, max, nextIn = c, m, n end
			end
			local best
			for _, r in ipairs(v) do if not r.excluded and r.profit and (not best or r.profit > best.profit) then best = r end end
			if max then
				extra = extra .. string.format(L[" · cargas %d/%d"], cur, max)
				if nextIn then extra = extra .. string.format(L[" (+1 em %s)"], SecsText(nextIn)) end
			end
			if best then
				extra = extra .. " · " .. (best.profit > 0 and string.format(L["use em: %s"], best.name or "?")
					or L["|cffff5555nenhuma dá lucro hoje|r"])
			end
		end
		if collapsed then range = "" end
		if si == UNKNOWN and entry and not entry.unknown then extra = L[" · escaneie a profissão de novo"] end
		local icon = collapsed and "|TInterface\\Buttons\\UI-PlusButton-Up:14:14|t " or "|TInterface\\Buttons\\UI-MinusButton-Up:14:14|t "
		sec.title:SetText(string.format("%s|cffffd100%s|r |cff9d9d9d(%s%s)|r  |cffffffff%d|r%s%s", icon, sec.cfg.title, sec.cfg.desc, extra, #v,
			hidden and L[" |cff9d9d9d(oculto: Só lucrativos)|r"] or "", range))
	end

	for _, h in ipairs(frame.headers) do
		local arrow = ""
		local si = SortIndexOf(h.key)
		if si then
			local keys = SortKeys()
			arrow = (keys[si].desc and " v" or " ^")
			if #keys > 1 then arrow = arrow .. si end
		end
		h.text:SetText(h.label .. arrow)
	end

	local total = entry and #entry.rows or 0
	local extra = ""
	if entry and entry.skipped and entry.skipped > 0 then
		extra = string.format(L["  ·  %d ignoradas (salvage/sem item)"], entry.skipped)
	end
	frame.status:SetText(string.format(L["total %d receitas%s   |cffff8800!|r pouca venda  |cff66ccfff|r fabricado  |cffa8ff60e|r estoque   Conc: |cff55ff55agora|r/|cffffd100esperar|r/|cffff5555acima|r   Botão direito: fila"],
		total, extra))
	frame.onlyProfit:SetChecked(Cfg("onlyProfit") and true or false)
end

local function ShowTooltip(row)
	local r = row.data
	if not r then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if r.itemID then GameTooltip:SetItemByID(r.itemID) else GameTooltip:SetText(r.name or "?") end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cffd4af37Royal Revenue|r")
	for _, part in ipairs(r.parts or {}) do
		local name = ns.Visual.ItemName(part.itemID)
		local val = (part.bound and part.boundCost and P.FormatMoney(part.boundCost * part.qty))
			or part.bound and L["|cff9d9d9dvinculado (0g)|r"]
			or (part.fromStock and r.usesStock and L["|cffa8ff60estoque (0g)|r"])
			or (part.unit and P.FormatMoney(part.unit * part.qty)) or L["|cffff8800sem preço|r"]
		GameTooltip:AddDoubleLine(string.format("%dx %s", part.qty, name), val, 1, 1, 1, 1, 1, 1)
		if part.crafted then
			GameTooltip:AddLine(string.format(L["   |cff66ccfffabricado:|r %s (comprar: %s)"], part.crafted,
				part.buyUnit and P.FormatMoney(part.buyUnit * part.qty) or L["sem preço"]), 0.7, 0.7, 0.7)
		end
		if part.bound and part.boundCost then
			GameTooltip:AddLine(string.format(L["   |cff66ccffvinculado, feito em:|r %s (aba Destruir)"], part.boundSrc or "?"), 0.7, 0.7, 0.7)
		end
		if not part.bound and ns.Stock then
			local s = ns.Stock.Get(part.itemID)
			if s and s.total > 0 then
				GameTooltip:AddLine(L["   estoque: "] .. ns.Stock.Text(s), 0.6, 0.8, 0.6)
			end
		end
	end
	-- transmutação: o resultado depende do multicraft
	if ns.IsTransmute(r) and r.sale and r.qty and r.expCost then
		local cut = tonumber(Cfg("ahCut")) or 0.05
		local mc = r.stats and r.stats.mc or 0
		local net = r.sale * (1 - cut)
		local procQty = (mc > 0 and r.expQty and r.expQty > r.qty) and (r.qty + (r.expQty - r.qty) / mc) or nil
		local function Pf(q) local v = net * q - r.expCost; return (v >= 0 and "|cff55ff55" or "|cffff5555") .. P.FormatMoney(math.abs(v)) .. (v < 0 and " (-)" or "") .. "|r" end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(string.format(L["Transmutação · chance de multicraft %s"], root.Num(mc * 100, 1) .. "%"), 1, 0.82, 0)
		GameTooltip:AddDoubleLine(string.format(L["Sem proc (%s)"], root.Num(r.qty, 0)), Pf(r.qty), 1, 1, 1)
		if r.expQty then GameTooltip:AddDoubleLine(string.format(L["Esperado (%s)"], root.Num(r.expQty, 2)), Pf(r.expQty), 1, 1, 1) end
		if procQty then GameTooltip:AddDoubleLine(string.format(L["Com proc (~%s)"], root.Num(procQty, 1)), Pf(procQty), 1, 1, 1) end
		local be = net > 0 and r.expCost / net or nil
		if be then GameTooltip:AddDoubleLine(L["Empata com"], string.format(L["%s itens"], root.Num(be, 1)), 1, 1, 1, 1, 1, 1) end
		local cur, max, nextIn, perDay = ns.Charges(r)
		if cur then
			GameTooltip:AddDoubleLine(L["Cargas"], string.format("%d/%d", cur, max) .. (nextIn and (" · +1 " .. string.format(L["em %s"], SecsText(nextIn))) or ""), 1, 1, 1, 1, 1, 1)
			if r.profit then
				GameTooltip:AddDoubleLine(L["Por dia (esperado)"], P.FormatMoney(math.abs(r.profit * (perDay or 1))) .. (r.profit < 0 and " (-)" or ""), 1, 1, 1,
					r.profit >= 0 and 0.3 or 1, r.profit >= 0 and 1 or 0.3, 0.3)
			end
			GameTooltip:AddLine(L["As cargas são o limite: use cada uma na transmutação de maior lucro esperado."], 0.6, 0.6, 0.6, true)
		end
	end
	if r.variant == "mix" and r.mix and r.mix.alloc then
		GameTooltip:AddLine(L["Trocar pela qualidade superior:"], 0.4, 0.8, 1)
		for i, n in pairs(r.mix.alloc) do
			local top = r.mix.top and r.mix.top[i]
			local name = top and C_Item.GetItemNameByID(top) or ("item " .. tostring(top))
			local q = top and ns.Scanner.ReagentQuality and ns.Scanner.ReagentQuality(top)
			GameTooltip:AddLine(string.format("   %dx %s%s", n, name, q and (" " .. ns.QIcon(q, 2)) or ""), 1, 1, 1)
		end
		GameTooltip:AddDoubleLine(L["Custo extra dos reagentes"], P.FormatMoney(r.mix.extra or 0), 1, 0.82, 0, 1, 1, 1)
	end
	local cut = Cfg("ahCut")
	if r.variant == "npc" then
		GameTooltip:AddLine(L["Revenda: comprar no vendedor (NPC) e anunciar na AH"], 0.4, 0.8, 1)
	end
	GameTooltip:AddDoubleLine(r.variant == "npc" and L["Preço no vendedor"] or L["Custo dos reagentes"], P.FormatMoney(r.cost), 1, 0.82, 0, 1, 1, 1)
	local st = r.stats
	if st and (st.mc > 0 or st.res > 0 or st.ing > 0) and Cfg("useStats") then
		GameTooltip:AddDoubleLine(L["Atributos"], string.format("%s %.0f%% · %s %.0f%% · %s %.0f%%",
			ns.STAT.multicraft, st.mc * 100, ns.STAT.resourcefulness, st.res * 100, ns.STAT.ingenuity, st.ing * 100), 1, 0.82, 0, 0.8, 0.8, 0.8)
		if r.expCost and r.expCost < r.cost then
			GameTooltip:AddDoubleLine(L["Custo esperado (resourcefulness)"], P.FormatMoney(r.expCost), 1, 0.82, 0, 1, 1, 1)
		end
	end
	local q = r.expQty or r.qty
	local ent = CurrentEntry()
	local sig = ent and ent.sig
	local o, old = ns.Scanner.Observed(r.recipeID, nil, sig)
	if o and (o.n or 0) > 0 then
		GameTooltip:AddDoubleLine(string.format(old and L["Rendimento real (%d fabricações, perfil anterior)"] or L["Rendimento real (%d fabricações)"], o.n),
			string.format(L["%.2f por fabricação · base %s"], o.items / o.n, tostring(r.qty)), 1, 0.82, 0, 0.4, 0.8, 1)
		if (o.mcN or 0) > 0 then
			GameTooltip:AddDoubleLine(string.format(L["Multicraft observado (%d de %d)"], o.mcN, o.n),
				string.format(L["+%.1f itens por proc"], o.mcItems / o.mcN), 1, 0.82, 0, 0.4, 0.8, 1)
		end
	end
	if r.schemQty and r.schemQty ~= r.qty then
		GameTooltip:AddLine(string.format(L["O jogo informa %s por fabricação; o cálculo usa a base observada (%s)."], tostring(r.schemQty), tostring(r.qty)), 0.6, 0.6, 0.6, true)
	end
	if st and st.mc > 0 and Cfg("useStats") then
		local ex, src = ns.Scanner.ExtraPerProc(r.qty or 1, r.recipeID, nil, sig)
		local srcTxt = src == "receita" and L["suas fabricações desta receita"] or src == "geral" and L["suas fabricações com a mesma base"]
			or src == "anterior" and L["antes da última mudança de pontos/equipamento"] or L["fórmula de referência"]
		GameTooltip:AddDoubleLine(L["Extra por multicraft"], string.format("+%.1f · %s", ex, srcTxt), 1, 0.82, 0, 0.7, 0.7, 0.7)
		GameTooltip:AddLine(L["Dados deste personagem com os pontos de conhecimento e o equipamento atuais."], 0.6, 0.6, 0.6, true)
	end
	GameTooltip:AddDoubleLine(string.format(L["Venda (%.2f un esperadas, -%d%% AH)"], q, cut * 100),
		r.sale and P.FormatMoney(r.sale * q * (1 - cut)) or "—", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Lucro esperado"], P.FormatMoney(r.profit), 1, 0.82, 0, 1, 1, 1)
	if r.profitBase and r.profit and math.abs(r.profit - r.profitBase) >= 1 then
		GameTooltip:AddDoubleLine(L["Lucro sem stats"], P.FormatMoney(r.profitBase), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
	end
	if r.variant ~= "conc" and r.quality and r.maxQuality and r.maxQuality > 1 then
		GameTooltip:AddDoubleLine(L["Qualidade sem concentração"], ns.QIcon(r.quality, r.maxQuality) .. string.format(L[" de %d"], r.maxQuality),
			1, 0.82, 0, 1, 1, 1)
	end
	if r.concCost then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["|cff66ccffCom concentração > "] .. ns.QIcon(r.concQuality or 0, r.maxQuality) .. "|r")
		local eff = r.concEff and r.concEff < r.concCost and string.format(L["%d (efetivo %.0f c/ ingenuity)"], r.concCost, r.concEff) or tostring(r.concCost)
		GameTooltip:AddDoubleLine(L["Custo em concentração"], eff, 1, 0.82, 0, 1, 1, 1)
		if r.perConc then
			GameTooltip:AddDoubleLine(L["Lucro por ponto de conc"], P.FormatMoney(r.perConc), 1, 0.82, 0, 1, 1, 1)
			local entry = CurrentEntry()
			if entry and entry.conc and entry.conc.cur and r.concCost > 0 then
				local per = r.concEff or r.concCost
				-- começar um craft exige o custo cheio; a devolução da engenhosidade vem depois
				local n = entry.conc.cur >= r.concCost and (math.floor((entry.conc.cur - r.concCost) / per) + 1) or 0
				GameTooltip:AddDoubleLine(string.format(L["Com sua conc atual (~%d crafts)"], n),
					P.FormatMoney(n * r.perConc * per), 1, 0.82, 0, 1, 1, 1)
			end
			GameTooltip:AddLine(L["Lucro/conc = lucro do craft com concentração ÷ pontos gastos"], 0.6, 0.6, 0.6)
		end
	elseif r.variant ~= "conc" and r.quality and r.maxQuality and r.quality >= r.maxQuality then
		GameTooltip:AddLine(L["Já sai na qualidade máxima — concentração não ajuda"], 0.6, 0.6, 0.6)
	end
	if r.concBeaten and r.variant ~= "mix" then
		GameTooltip:AddLine(L["Reagentes superiores dão a mesma qualidade com mais lucro: não gaste concentração aqui"], 0.4, 0.8, 1, true)
	end
	if type(r.spd) == "number" then
		GameTooltip:AddDoubleLine(P.SpdIsEstimate() and L["Vendas/dia (estimado)"] or L["Vendas/dia (região)"], string.format(L["%.2f  (%.1f%% do total)"], r.spd, (r.spdShare or 0) * 100),
			1, 0.82, 0, 1, 1, 1)
	end
	-- curva ABC = melhor uso da concentração (ordem e corte pelo ouro por ponto)
	if r.abcFree then
		GameTooltip:AddLine(L["Classe A: lucra sem gastar concentração"], 0.4, 0.8, 1, true)
	elseif r.abc and r.abcShare then
		GameTooltip:AddDoubleLine(string.format(L["Classe %s · curva do ouro/ponto"], r.abc),
			string.format(L["%.1f%% da profissão"], r.abcShare * 100), 1, 0.82, 0, 1, 1, 1)
		GameTooltip:AddLine(L["A curva ABC classifica pelo melhor uso da concentração (ouro por ponto)"], 0.6, 0.6, 0.6, true)
	elseif not r.unknown and not r.gathered and not r.notAuctionable then
		GameTooltip:AddLine(L["Sem lucro ou sem giro: fora da curva ABC"], 0.6, 0.6, 0.6, true)
	end
	if type(r.mySpd) == "number" then
		local it = ns.Sales and ns.Sales.Get(r.itemID)
		GameTooltip:AddDoubleLine(string.format(L["Suas vendas (%d dias)"], tonumber(Cfg("salesDays")) or 14),
			it and string.format(L["%d un · %.1f/dia · média %s"], it.qty, it.perDay, P.FormatMoney(it.avg)) or "—", 1, 0.82, 0, 1, 1, 1)
	end
	if type(r.trend) == "number" then
		local flag = P.TrendFlag(r.trend)
		GameTooltip:AddDoubleLine(L["Tendência (recente x histórico)"], P.TrendText(r.trend), 1, 0.82, 0, 1, 1, 1)
		if flag == "down" then
			GameTooltip:AddLine(L["Preço caindo: o lucro pode ser menor quando vender"], 1, 0.4, 0.4, true)
		elseif flag == "spike" then
			GameTooltip:AddLine(L["Preço em pico: pode não se sustentar até vender"], 1, 0.82, 0, true)
		end
	end
	GameTooltip:AddLine(" ")
	if r.excluded then
		GameTooltip:AddLine(L["Reagente sem preço: custo subestimado, fora do ranking de lucro"], 1, 0.5, 0, true)
	end
	if r.unknown then
		GameTooltip:AddLine(L["Receita desconhecida: você ainda não aprendeu"], 1, 0.53, 0, true)
		if r.source then
			GameTooltip:AddLine(L["Como aprender:"], 1, 0.82, 0)
			GameTooltip:AddLine(r.source, 1, 1, 1, true)
		end
		GameTooltip:AddLine(L["Valores estimados com a sua perícia e atributos atuais"], 0.6, 0.6, 0.6, true)
	end
	local okReco, why = ns.Recommendable(r, r.concCost and true or false)
	if r.unknown then okReco = true end
	if not okReco then
		GameTooltip:AddLine(L["Fora das recomendações ("] .. why .. L["): não entra no plano de concentração nem no investimento"], 1, 0.5, 0, true)
	end
	if r.gathered then
		GameTooltip:AddLine(L["Item obtido também por coleta: fora do % de vendas e da curva ABC"], 0.6, 0.6, 0.6, true)
	end
	if r.notAuctionable then
		GameTooltip:AddLine(L["Item vinculado (não vai para a casa de leilões): fora do % de vendas e da curva ABC"], 0.6, 0.6, 0.6, true)
	end
	if r.lowVolume then
		GameTooltip:AddLine(string.format(L["Pouca venda: menos de %s por dia na região — pode não vender"],
			tostring(Cfg("minSoldPerDay"))), 1, 0.5, 0, true)
	end
	if r.audit and r.audit.opError then
		GameTooltip:AddLine(L["Aviso: "] .. r.audit.opError, 1, 0.5, 0)
	end
	GameTooltip:AddLine(L["Clique: abrir receita · Shift+clique: linkar item · Alt+clique: auditoria · Ctrl+clique: marcar como item de coleta"], 0.6, 0.6, 0.6)
	GameTooltip:AddLine(L["Ctrl+Shift+clique: marcar/desmarcar como transmutação"], 0.6, 0.6, 0.6)
	if r.variant ~= "npc" and not r.unknown then
		GameTooltip:AddLine(L["Botão direito: +1 na fila · Shift: +5 · Ctrl: -1"], 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function OnRowClick(row, button)
	local r = row.data
	if not r then return end
	if button == "RightButton" then
		if r.variant == "npc" or not ns.Queue then return end
		if r.unknown then ns.Print(L["receita ainda não aprendida: não entra na fila."]) return end
		local n = IsControlKeyDown() and -1 or IsShiftKeyDown() and 5 or 1
		ns.Queue.Add(ns.CharKey(), state.profID, r.recipeID, r.variant, n)
		local q = r.quality and r.maxQuality and r.maxQuality > 1 and (" " .. ns.QIcon(r.quality, r.maxQuality)) or ""
		ns.Print(string.format(L["fila: %+d %s%s"], n, r.name or "?", q))
		return
	end
	if IsAltKeyDown() then
		ns.Audit(tostring(r.recipeID))
		return
	end
	if IsControlKeyDown() and IsShiftKeyDown() and r.recipeID then
		local cfg = LucroCraftDB.config
		cfg.transmute = cfg.transmute or {}
		cfg.transmute[r.recipeID] = not ns.IsTransmute(r)
		ns.Print(string.format(L["%s: %s"], r.name or "?", cfg.transmute[r.recipeID] and L["marcada como transmutação"] or L["não é mais transmutação"]))
		local entry = CurrentEntry()
		if entry then ns.Scanner.Reprice(entry, ns.CharKey()) end
		UI.Refresh()
		return
	end
	if IsControlKeyDown() and r.recipeID then
		if r.unknown then return end
		local cfg = LucroCraftDB.config
		cfg.gathered = cfg.gathered or {}
		cfg.gathered[r.recipeID] = not ns.IsGathered(r)
		local entry = CurrentEntry()
		if entry then ns.Scanner.ApplyABC(entry.rows) end
		UI.Refresh()
		return
	end
	if IsShiftKeyDown() and r.itemID then
		local link = select(2, C_Item.GetItemInfo(r.itemID))
		local insert = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
		if link and insert then insert(link) end
		return
	end
	if C_TradeSkillUI.OpenRecipe then C_TradeSkillUI.OpenRecipe(r.recipeID) end
end

local function CycleProfession(dir)
	local ids = SortedProfIDs()
	if #ids == 0 then return end
	local idx = 1
	for i, id in ipairs(ids) do if id == state.profID then idx = i end end
	idx = ((idx - 1 + dir) % #ids) + 1
	state.profID = ids[idx]
	state.offset = 0; state.offsets = { 0, 0, 0, 0, 0 }
	UI.Refresh()
end

local function Create()
	frame = CreateFrame("Frame", "LucroCraftFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(WIDTH, 128 + TOTAL_ROWS * ROW_H)
	-- camada normal das janelas (como as de outros addons): quem foi clicada por último fica por cima
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		LucroCraftDB.pos = { point, relPoint, x, y }
	end)
	frame:SetScript("OnShow", function()
		if ns.root.FitToScreen(frame) then
			local point, _, relPoint, x, y = frame:GetPoint()
			LucroCraftDB.pos = { point, relPoint, x, y }
		end
		UI.Refresh()
	end)

	-- janela redimensionável: alça no canto inferior direito; tamanho salvo em LucroCraftDB.size
	frame:SetResizable(true)
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetFrameLevel(frame:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:RegisterForClicks("LeftButtonUp")
	grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		ns.root.FitToScreen(frame)
		RoyalRevenueDB = RoyalRevenueDB or {}
		RoyalRevenueDB.winSize = { math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5) }
		local point, _, relPoint, x, y = frame:GetPoint()
		LucroCraftDB.pos = { point, relPoint, x, y }
		UI.OnResize()
		if ns.root.ApplyLivroSize then ns.root.ApplyLivroSize() end
	end)
	grip:SetScript("OnDoubleClick", function()
		RoyalRevenueDB.winSize = nil
		UI.ApplyTabSize(frame.currentTab or 1)
		UI.OnResize()
		if ns.root.ApplyLivroSize then ns.root.ApplyLivroSize() end
	end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(L["Arraste para mudar o tamanho da janela"])
		GameTooltip:AddLine(L["Duplo clique: tamanho padrão"], 1, 1, 1)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame:SetScript("OnSizeChanged", function()
		if frame.resizePending then return end
		frame.resizePending = true
		C_Timer.After(0.05, function()
			frame.resizePending = false
			UI.OnResize()
		end)
	end)
	frame:Hide()
	table.insert(UISpecialFrames, "LucroCraftFrame")

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText("|cffd4af37Royal|r |cff6f9be0Revenue|r |cffd9dde3— Craft|r")
	frame.titleFS = title

	-- engrenagem: Configurações (como no Livro-caixa); clique de novo volta para a aba de antes
	local gear = CreateFrame("Button", nil, frame)
	gear:SetSize(18, 18)
	gear:SetPoint("TOPRIGHT", -30, -4)
	gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
	gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	gear:SetScript("OnClick", function()
		if frame.currentTab == TAB.SETTINGS then
			UI.ShowTab(UI.LastTab(frame.mode or "craft"))
		else
			UI.ShowTab(TAB.SETTINGS)
		end
	end)
	gear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L["Configurações"])
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.gear = gear

	-- Linha de controles
	local prev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	prev:SetSize(24, 20); prev:SetPoint("TOPLEFT", 12, -56); prev:SetText("<")
	prev:SetScript("OnClick", function() CycleProfession(-1) end)
	local nextB = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	nextB:SetSize(24, 20); nextB:SetPoint("LEFT", prev, "RIGHT", 2, 0); nextB:SetText(">")
	nextB:SetScript("OnClick", function() CycleProfession(1) end)

	frame.profLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.profLabel:SetPoint("LEFT", nextB, "RIGHT", 8, 0)
	frame.profLabel:SetJustifyH("LEFT")

	local scan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	scan:SetSize(80, 20); scan:SetPoint("TOPRIGHT", -12, -56); scan:SetText(L["Escanear"])
	scan:SetScript("OnClick", function()
		local e = ns.Scanner.Scan(false)
		if e then state.profID = e.professionID end
		UI.Refresh()
	end)

	local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	cb:SetSize(22, 22); cb:SetPoint("RIGHT", scan, "LEFT", -90, 0)
	local cbText = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0); cbText:SetText(L["Só lucrativos"])
	cb:SetScript("OnClick", function(self)
		LucroCraftDB.config.onlyProfit = self:GetChecked() and true or false
		state.offset = 0; state.offsets = { 0, 0, 0, 0, 0 }
		UI.Refresh()
	end)
	frame.onlyProfit = cb

	-- Abas da lista (no estilo da barra de listas do Mercado > Comprar): Concentração x Sem concentração
	frame.listBar = CreateFrame("Frame", nil, frame)
	frame.listBar:SetPoint("TOPLEFT", 12, -80)
	frame.listBar:SetPoint("TOPRIGHT", -12, -80)
	frame.listBar:SetHeight(26)
	local barBg = frame.listBar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	barBg:SetColorTexture(0.08, 0.13, 0.24, 0.9)
	frame.listTabs = {}
	for i, li in ipairs(RECIPE_LISTS) do
		local b = CreateFrame("Button", nil, frame.listBar)
		b:SetHeight(22)
		b.key = li.key
		b.bg = b:CreateTexture(nil, "ARTWORK")
		b.bg:SetAllPoints()
		b.edge = b:CreateTexture(nil, "BORDER")
		b.edge:SetPoint("TOPLEFT", -2, 2); b.edge:SetPoint("BOTTOMRIGHT", 2, -2)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		b.text:SetAllPoints()
		b.text:SetJustifyH("CENTER")
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b:SetScript("OnClick", function(self) UI.SetRecipeList(self.key) end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L[li.label])
			GameTooltip:AddLine(self.key == "conc" and L["Só os resultados que gastam concentração (a qualidade de cima)."]
				or L["Só os resultados que não gastam concentração (craft normal, reagentes superiores, revenda de NPC)."], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		frame.listTabs[i] = b
	end

	-- Cabeçalhos (arrastáveis; botão direito = mostrar/ocultar)
	frame.headers = {}
	frame.headerByKey = {}
	for _, col in ipairs(COLUMNS) do
		local h = CreateFrame("Button", nil, frame)
		h:SetSize(col.width, 18)
		h.key, h.label = col.key, col.label
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.text:SetAllPoints()
		h.text:SetJustifyH(col.align)
		h:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
		h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		h:RegisterForDrag("LeftButton")
		h:SetScript("OnClick", function(self, button)
			if button == "RightButton" then UI.ShowColumnMenu(self) return end
			if frame.dragJustEnded then return end
			UI.SortByColumn(self.key, IsShiftKeyDown())
		end)
		h:SetScript("OnDragStart", function(self) UI.BeginColumnDrag(self) end)
		h:SetScript("OnDragStop", function(self) UI.EndColumnDrag(self) end)
		h:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.label)
			GameTooltip:AddLine(L["Clique: ordenar só por esta coluna"], 1, 1, 1)
			GameTooltip:AddLine(L["Shift+clique: adicionar como próximo critério"], 1, 1, 1)
			GameTooltip:AddLine(L["Arrastar: mudar posição"], 1, 1, 1)
			GameTooltip:AddLine(L["Botão direito: mostrar/ocultar colunas"], 1, 1, 1)
			GameTooltip:Show()
		end)
		h:SetScript("OnLeave", function() GameTooltip:Hide() end)
		table.insert(frame.headers, h)
		frame.headerByKey[col.key] = h
	end

	-- marcador de onde a coluna vai cair
	frame.dropMarker = frame:CreateTexture(nil, "OVERLAY")
	frame.dropMarker:SetColorTexture(1, 0.82, 0, 0.9)
	frame.dropMarker:SetSize(2, 22)
	frame.dropMarker:Hide()

	-- Linhas
	local list = CreateFrame("Frame", nil, frame)
	list:SetPoint("TOPLEFT", 12, -132)
	list:SetSize(WIDTH - 24, TOTAL_ROWS * ROW_H)
	frame.list = list

	frame.rows = {}
	frame.sections = {}
	local y = 0
	for si, cfg in ipairs(SECTIONS) do
		local sec = CreateFrame("Frame", nil, list)
		sec:SetPoint("TOPLEFT", 0, -y)
		sec:SetPoint("RIGHT", list, "RIGHT", 0, 0)
		sec:SetHeight((cfg.rows + 1) * ROW_H)
		sec.cfg, sec.rows = cfg, {}
		-- faixa do título da seção
		local band = sec:CreateTexture(nil, "BACKGROUND")
		band:SetPoint("TOPLEFT", 0, 0); band:SetPoint("RIGHT", sec, "RIGHT", 0, 0); band:SetHeight(ROW_H)
		band:SetColorTexture(1, 0.82, 0, 0.10)
		sec.title = sec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		sec.title:SetPoint("LEFT", sec, "TOPLEFT", 4, -ROW_H / 2)
		sec.title:SetJustifyH("LEFT")
		-- clique no título minimiza/expande o grupo
		local tb = CreateFrame("Button", nil, sec)
		tb:SetPoint("TOPLEFT", 0, 0); tb:SetPoint("RIGHT", sec, "RIGHT", 0, 0); tb:SetHeight(ROW_H)
		tb:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		tb:SetScript("OnClick", function()
			local cfgDB = LucroCraftDB.config
			cfgDB.collapsed = cfgDB.collapsed or {}
			cfgDB.collapsed[si] = not cfgDB.collapsed[si] or nil
			state.offsets[si] = 0
			UI.Refresh()
		end)
		tb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(cfg.title)
			GameTooltip:AddLine(IsCollapsed(si) and L["Clique para expandir"] or L["Clique para minimizar"], 1, 1, 1)
			if si == UNKNOWN then
				GameTooltip:AddLine(L["Receitas da expansão que este personagem ainda não aprendeu e que dariam lucro. Passe o mouse para ver como aprender."], 0.8, 0.8, 0.8, true)
			end
			GameTooltip:Show()
		end)
		tb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		tb:EnableMouseWheel(true)
		tb:SetScript("OnMouseWheel", function(_, delta) sec:GetScript("OnMouseWheel")(sec, delta) end)
		sec.toggle = tb
		sec:EnableMouseWheel(true)
		sec:SetScript("OnMouseWheel", function(_, delta)
			if IsCollapsed(si) then return end
			local maxOffset = math.max(0, #(state.views[si] or {}) - cfg.rows)
			local step = IsShiftKeyDown() and cfg.rows or 3
			state.offsets[si] = math.min(maxOffset, math.max(0, (state.offsets[si] or 0) - delta * step))
			UI.Refresh()
		end)
		-- linhas criadas sob demanda (a quantidade depende da altura da janela)
		function sec.MakeRow(j)
			local row = CreateFrame("Button", nil, sec)
			row:SetSize(WIDTH - 24, ROW_H)
			row:SetPoint("TOPLEFT", 0, -j * ROW_H)
			row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			if j % 2 == 0 then
				local bg = row:CreateTexture(nil, "BACKGROUND")
				bg:SetAllPoints(); bg:SetColorTexture(ns.root.ZEBRA[1], ns.root.ZEBRA[2], ns.root.ZEBRA[3], ns.root.ZEBRA[4])
			end
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(ROW_H - 2, ROW_H - 2)
			row.icon:SetPoint("LEFT", 0, 0)
			row.cols = {}
			for _, col in ipairs(COLUMNS) do
				local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				fs:SetWidth(col.width)
				fs:SetJustifyH(col.align)
				fs:SetWordWrap(false)
				row.cols[col.key] = fs
			end
			row:SetScript("OnEnter", ShowTooltip)
			row:SetScript("OnLeave", function() GameTooltip:Hide() end)
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row:SetScript("OnClick", OnRowClick)
			-- a rodinha na linha rola a seção
			row:EnableMouseWheel(true)
			row:SetScript("OnMouseWheel", function(_, delta) sec:GetScript("OnMouseWheel")(sec, delta) end)
			table.insert(sec.rows, row)
			table.insert(frame.rows, row)
		end
		for j = 1, cfg.rows do sec.MakeRow(j) end
		frame.sections[si] = sec
		y = y + (cfg.rows + 1) * ROW_H
	end

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.status:SetPoint("BOTTOMLEFT", 14, 10)
	frame.status:SetJustifyH("LEFT")

	-- elementos que só aparecem na aba Receitas
	frame.recipeWidgets = { prev, nextB, frame.profLabel, scan, cb, list, frame.status, frame.listBar }
	for _, h in ipairs(frame.headers) do table.insert(frame.recipeWidgets, h) end

	-- painel com rolagem para as abas de texto (Plano de concentração / Investimento)
	local pane = CreateFrame("ScrollFrame", nil, frame)
	pane:SetPoint("TOPLEFT", 12, -56)
	pane:SetPoint("BOTTOMRIGHT", -12, 10)
	local child = CreateFrame("Frame", nil, pane)
	child:SetSize(100, 100)
	pane:SetScrollChild(child)
	child.text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	child.text:SetPoint("TOPLEFT", 2, -2)
	child.text:SetJustifyH("LEFT")
	child.text:SetJustifyV("TOP")
	child.text:SetSpacing(2)
	pane:EnableMouseWheel(true)
	pane:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
		local v = math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 40))
		self:SetVerticalScroll(v)
	end)
	pane:Hide()
	frame.pane, frame.paneChild = pane, child

	-- abas visuais (Plano de concentração e Investimento)
	frame.canvases = { [TAB.PLAN] = ns.Visual.Create(frame), [TAB.INVEST] = ns.Visual.Create(frame), [TAB.QUEUE] = ns.Visual.Create(frame),
		[TAB.SALVAGE] = ns.Visual.Create(frame), [TAB.BUY] = ns.Visual.Create(frame), [TAB.SELL] = ns.Visual.Create(frame), [TAB.RECIPES] = ns.Visual.Create(frame) }
	-- a aba Fila tem a barra de botões em cima
	-- (a barra de botões da Fila agora fica dentro da aba, em cada parte)

	-- barra de botões da aba Fila (fica acima do texto)
	local bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT", 12, -54)
	bar:SetPoint("TOPRIGHT", -12, -54)
	bar:SetHeight(24)
	bar:Hide()
	local function BarButton(w, label, fn, anchor)
		local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
		b:SetSize(w, 22)
		if anchor then b:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else b:SetPoint("LEFT", 0, 0) end
		b:SetText(label)
		b:SetScript("OnClick", fn)
		return b
	end
	bar.craft = BarButton(230, L["Fabricar próximo"], function()
		ns.Queue.CraftNext()
		C_Timer.After(1.5, function() UI.RefreshTab(TAB.QUEUE) end)
	end)
	bar.craft:GetFontString():SetWordWrap(false)
	local bAuc = BarButton(130, L["Lista no Auctionator"], function() ns.Queue.ExportAuctionator() end, bar.craft)
	local bTsm = BarButton(110, L["Copiar p/ TSM"], function() ns.Queue.ExportTSM() end, bAuc)
	local bClr = BarButton(110, L["Limpar manuais"], function()
		if IsShiftKeyDown() then ns.Queue.ClearManual() else ns.Print(L["segure Shift e clique para limpar a fila manual."]) end
	end, bTsm)
	local bOrd = BarButton(120, L["Pegar pedidos"], function() ns.Queue.OrdersButton() end, bClr)
	bOrd:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Pegar pedidos"])
		GameTooltip:AddLine(L["Lê os pedidos de fabricação abertos na janela da profissão e mostra o lucro de cada um aqui na fila. Shift+clique: pega direto o de maior lucro."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	bOrd:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local cbPlan = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
	cbPlan:SetSize(22, 22)
	cbPlan:SetPoint("LEFT", bOrd, "RIGHT", 8, 0)
	local cbText = cbPlan:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cbText:SetPoint("LEFT", cbPlan, "RIGHT", 2, 0)
	cbText:SetText(L["incluir plano"])
	cbPlan:SetScript("OnClick", function(self)
		LucroCraftDB.config.queueIncludePlan = self:GetChecked() and true or false
		UI.RefreshTab(TAB.QUEUE)
	end)
	bar.cbPlan = cbPlan
	frame.queueBar = bar

	-- abas no rodapé, no estilo da janela de profissão. IDs fixos (1..6); a ordem visual é outra.
	local TAB_LABELS = { L["Receitas"], L["Plano de concentração"], L["Investimento"], L["Destruir"], L["Fila de craft"],
		L["Configurações"], L["Compras"], L["Vender"], L["Comprar receitas"] }
	local TAB_ORDER = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
	frame.Tabs = {}
	local strip = ns.root.MakeTabStrip(frame)
	for _, i in ipairs(TAB_ORDER) do
		frame.Tabs[i] = ns.root.MakeTab(strip, "LucroCraftFrameTab" .. i, TAB_LABELS[i], i, function(self) UI.ShowTab(self:GetID()) end)
	end
	frame.currentTab = 1
	ns.root.SelectTab(frame.Tabs, 1)
	frame.lastTab = { craft = 1, market = TAB.BUY }
	UI.LayoutTabs("craft")

	UI.Layout()
end

-- mostra só as abas do grupo (Craft ou Mercado), encadeadas da esquerda para a direita, e troca o título
function UI.LayoutTabs(mode)
	if not frame or not frame.Tabs then return end
	local prev
	for i = 1, #frame.Tabs do
		local tab = frame.Tabs[i]
		local show = (i ~= TAB.SETTINGS) and (UI.ModeOf(i) == mode)
		tab:SetShown(show)
		if show then
			tab:ClearAllPoints()
			if prev then tab:SetPoint("LEFT", prev, "RIGHT", 2, 0) else tab:SetPoint("LEFT", frame.rrStrip, "LEFT", 4, 0) end
			prev = tab
		end
	end
	frame.mode = mode
	if frame.titleFS then
		frame.titleFS:SetText("|cffd4af37Royal|r |cff6f9be0Revenue|r |cffd9dde3— " .. (mode == "market" and L["Mercado"] or "Craft") .. "|r")
	end
	if ns.root and ns.root.UpdateNav then pcall(ns.root.UpdateNav, frame, mode == "market" and "mercado" or "craft") end
end

function UI.Mode() return frame and frame.mode or "craft" end
function UI.LastTab(mode)
	if not frame then return mode == "market" and TAB.BUY or TAB.LIST end
	return frame.lastTab and frame.lastTab[mode] or (mode == "market" and TAB.BUY or TAB.LIST)
end

local TEXT_WIDTH = 760
local SETTINGS_WIDTH = 1010
local VISUAL_WIDTH = 960

local function RenderVisual(id, resetScroll)
	local cv = frame.canvases and frame.canvases[id]
	if not cv then return end
	local mod = (id == TAB.PLAN and ns.Plan) or (id == TAB.INVEST and ns.Invest) or (id == TAB.QUEUE and ns.Queue)
		or (id == TAB.SALVAGE and ns.Salvage) or (id == TAB.BUY and ns.Buy) or (id == TAB.SELL and ns.Sell) or (id == TAB.RECIPES and ns.RecipeShop)
	if id == TAB.QUEUE and frame.queueBar then
		frame.queueBar.craft:SetText(ns.Queue.NextLabel())
		frame.queueBar.cbPlan:SetChecked(Cfg("queueIncludePlan") and true or false)
	end
	if resetScroll then cv:ResetScroll() end
	local ok, err = pcall(mod.Render, cv)
	if not ok then
		cv:Begin()
		cv:Text(8, 8, L["|cffff5555Erro ao montar a aba:|r "] .. tostring(err), GameFontHighlightSmall, cv:Width() - 16)
		cv:End(40)
	end
end
local function RenderPane(id)
	local mod = (id == TAB.PLAN and ns.Plan) or (id == TAB.INVEST and ns.Invest) or (id == TAB.QUEUE and ns.Queue)
	if id == TAB.QUEUE and frame.queueBar then
		frame.queueBar.craft:SetText(ns.Queue.NextLabel())
		frame.queueBar.cbPlan:SetChecked(Cfg("queueIncludePlan") and true or false)
	end
	local ok, txt = pcall(function() return mod and mod.GetText and mod.GetText() end)
	if not ok then txt = L["|cffff5555Erro ao montar a aba:|r "] .. tostring(txt) end
	local child, pane = frame.paneChild, frame.pane
	local w = frame:GetWidth() - 28
	child:SetWidth(w)
	child.text:SetWidth(w - 4)
	child.text:SetText(txt or "")
	child:SetHeight(math.max(child.text:GetStringHeight() + 8, pane:GetHeight()))
end

-- Troca de aba: 1 = lista de receitas, 2 = plano de concentração, 3 = investimento
function UI.ShowTab(id)
	if not frame then Create() end
	if not frame:IsShown() then UI.Show() end
	id = id or 1
	frame.currentTab = id
	ns.root.SelectTab(frame.Tabs, id)
	local mode = UI.ModeOf(id)
	frame.lastTab = frame.lastTab or {}
	if id ~= TAB.SETTINGS then frame.lastTab[mode] = id end
	UI.LayoutTabs(mode)
	if frame.gear then
		if id == TAB.SETTINGS then frame.gear:LockHighlight() else frame.gear:UnlockHighlight() end
	end
	local isList = id == 1
	local isSettings = id == TAB.SETTINGS
	local isHistory = id == TAB.SALES
	local isBets = id == TAB.BETS
	local isVisual = frame.canvases[id] ~= nil
	if ns.History and not isHistory then ns.History.Hide() end
	if ns.Bets and not isBets then ns.Bets.Hide() end
	for cid, cv in pairs(frame.canvases) do if cid ~= id then cv:Hide() end end
	for _, w in ipairs(frame.recipeWidgets) do w:SetShown(isList) end
	frame.pane:SetShown(not isList and not isSettings and not isHistory and not isVisual and not isBets)
	frame.queueBar:SetShown(false)
	frame.pane:ClearAllPoints()
	frame.pane:SetPoint("TOPLEFT", 12, id == TAB.QUEUE and -82 or -56)
	frame.pane:SetPoint("BOTTOMRIGHT", -12, 10)
	UI.ApplyTabSize(id)
	if isSettings then
		ns.Settings.Show(frame)
		return
	elseif ns.Settings then
		ns.Settings.Hide()
	end
	if isHistory then
		ns.History.Show(frame)
		return
	end
	if isBets then
		ns.Bets.Show(frame)
		return
	end
	if isVisual then
		frame.canvases[id]:Show()
		RenderVisual(id, true)
		return
	end
	if isList then
		UI.LayoutRows()
		UI.Layout()
		UI.Refresh()
	else
		frame.pane:SetVerticalScroll(0)
		RenderPane(id)
	end
end

function UI.RefreshTab(id)
	if id == TAB.SALES then
		if frame and frame:IsShown() and frame.currentTab == id and ns.History then ns.History.Refresh() end
		return
	end
	if id == TAB.BETS then
		if frame and frame:IsShown() and frame.currentTab == id and ns.Bets then ns.Bets.Refresh() end
		return
	end
	if frame and frame.canvases and frame.canvases[id] then
		if frame:IsShown() and frame.currentTab == id then RenderVisual(id) end
		return
	end
	if frame and frame:IsShown() and frame.currentTab == id and (id ~= TAB.LIST and id ~= TAB.SETTINGS) then RenderPane(id) end
end

-- ===== Tamanho da janela =====
local DEFAULT_HEIGHT = 128 + TOTAL_ROWS * ROW_H
local DEFAULT_WIDTH = { [TAB.PLAN] = VISUAL_WIDTH, [TAB.INVEST] = VISUAL_WIDTH, [TAB.QUEUE] = VISUAL_WIDTH, [TAB.SALVAGE] = VISUAL_WIDTH, [TAB.BUY] = VISUAL_WIDTH, [TAB.SELL] = VISUAL_WIDTH, [TAB.RECIPES] = VISUAL_WIDTH, [TAB.SETTINGS] = SETTINGS_WIDTH }

-- largura mínima de cada aba (o que precisa para não cortar nada)
local function TabMinWidth(id)
	if id == TAB.LIST then return UI.RequiredListWidth() end
	if id == TAB.SETTINGS then return SETTINGS_WIDTH end
	if id == TAB.SALES then return ns.History and ns.History.MinWidth() or 1010 end
	if id == TAB.BETS then return ns.Bets and ns.Bets.MinWidth() or 1010 end
	if id == TAB.QUEUE then return 700 end
	return 760
end

-- aplica o tamanho escolhido pelo usuário (ou o padrão, na 1ª vez); igual em todas as abas,
-- nunca força a janela a crescer até o mínimo de uma aba específica
function UI.ApplyTabSize(id)
	if not frame then return end
	local minW = TabMinWidth(id)
	local sz = RoyalRevenueDB and RoyalRevenueDB.winSize
	local maxW, maxH = ns.root.ScreenMax(frame)
	local w, h
	if sz then
		w = math.min(math.max(sz[1], 1), math.max(maxW, 1))
		h = math.min(math.max(sz[2], 420), math.max(maxH, 420))
	else
		w = math.min(math.max(DEFAULT_WIDTH[id] or minW, minW), math.max(maxW, minW))
		h = math.min(math.max(DEFAULT_HEIGHT, 420), math.max(maxH, 420))
	end
	-- limite pra redimensionar na mão: não deixa menor que o mínimo da aba atual, mas sem forçar a janela a crescer até lá
	local boundMinW = math.min(minW, w)
	if frame.SetResizeBounds then
		pcall(frame.SetResizeBounds, frame, boundMinW, 420, math.max(maxW, boundMinW), math.max(maxH, 420))
	elseif frame.SetMinResize then
		pcall(frame.SetMinResize, frame, boundMinW, 420)
	end
	if math.abs(frame:GetWidth() - w) > 0.5 or math.abs(frame:GetHeight() - h) > 0.5 then
		frame:SetSize(w, h)
	end
end
-- chamado pelo Livro-caixa quando ele muda o tamanho compartilhado (RoyalRevenueDB.winSize)
ns.root.ApplyCraftSize = function() if frame then UI.ApplyTabSize(frame.currentTab or 1) end end

-- quantas linhas cada grupo da lista de receitas mostra, conforme a altura da janela.
-- Grupo minimizado (ou oculto) = só o título; grupo com menos receitas que a sua parte cede o resto aos outros.
function UI.LayoutRows()
	if not frame then return end
	local slots = math.max(9, math.floor((frame:GetHeight() - 158) / ROW_H) - #SECTIONS)
	local counts, active = {}, {}
	for si = 1, #frame.sections do
		counts[si] = 0
		local hidden = (si == 3 and Cfg("onlyProfit"))
		if not IsCollapsed(si) and not hidden then
			local need = math.max(1, #((state.views or {})[si] or {}))
			table.insert(active, { si = si, need = need, w = SECTIONS[si].weight or 1 })
		end
	end
	local remaining = slots
	while #active > 0 do
		local W = 0
		for _, a in ipairs(active) do W = W + a.w end
		local capped = false
		for k, a in ipairs(active) do
			if a.need <= math.floor(remaining * a.w / W) then
				counts[a.si] = a.need
				remaining = remaining - a.need
				table.remove(active, k)
				capped = true
				break
			end
		end
		if not capped then
			local used = 0
			for _, a in ipairs(active) do
				local n = math.max(1, math.floor(remaining * a.w / W))
				counts[a.si] = n
				used = used + n
			end
			-- sobra do arredondamento vai para o primeiro grupo aberto
			local first = active[1]
			counts[first.si] = math.max(1, counts[first.si] + (remaining - used))
			break
		end
	end
	local y = 0
	for si, sec in ipairs(frame.sections) do
		local n = counts[si] or 0
		sec.cfg.rows = n
		for k = #sec.rows + 1, n do sec.MakeRow(k) end
		for k, row in ipairs(sec.rows) do if k > n then row.data = nil; row:Hide() end end
		sec:ClearAllPoints()
		sec:SetPoint("TOPLEFT", 0, -y)
		sec:SetPoint("RIGHT", frame.list, "RIGHT", 0, 0)
		sec:SetHeight((n + 1) * ROW_H)
		y = y + (n + 1) * ROW_H
	end
	frame.list:SetHeight(math.max(y, ROW_H))
end

-- a janela mudou de tamanho: refaz o conteúdo da aba atual
function UI.OnResize()
	if not frame or not frame:IsShown() then return end
	local id = frame.currentTab or 1
	if id == TAB.LIST then
		UI.LayoutRows()
		UI.Layout()
		UI.Refresh()
	elseif id == TAB.SALES then
		if ns.History then ns.History.Resize(); ns.History.Refresh() end
	elseif id == TAB.BETS then
		if ns.Bets then ns.Bets.Resize(); ns.Bets.Refresh() end
	else
		UI.RefreshTab(id)
	end
end

function UI.CurrentTab()
	return frame and frame.currentTab or 1
end

-- Reposiciona cabeçalhos/células conforme ordem e visibilidade, e ajusta a largura da janela
function UI.RequiredListWidth()
	local x = LEFT_PAD
	for _, col in ipairs(VisibleColumns()) do x = x + col.width + COL_GAP end
	return math.max(MIN_WIDTH, x - COL_GAP + 12)
end

function UI.Layout()
	if not frame then return end
	local visible = VisibleColumns()
	local required = UI.RequiredListWidth()
	if (frame.currentTab or 1) == TAB.LIST and frame:GetWidth() < required - 0.5 then
		UI.ApplyTabSize(TAB.LIST)
	end
	-- abas da lista: dividem a largura da barra em partes iguais
	if frame.listTabs then
		local n = #frame.listTabs
		local bw = math.max(80, math.floor((frame.listBar:GetWidth() - 8 * (n + 1)) / n))
		for i, b in ipairs(frame.listTabs) do
			b:ClearAllPoints()
			b:SetPoint("LEFT", frame.listBar, "LEFT", 8 + (i - 1) * (bw + 8), 0)
			b:SetWidth(bw)
		end
	end
	local width = math.max(frame:GetWidth(), required)
	local extra = math.max(0, width - required)
	local shown = {}
	local x = LEFT_PAD
	for _, col in ipairs(visible) do
		shown[col.key] = true
		local cw = col.width + (col.key == "name" and extra or 0)
		local h = frame.headerByKey[col.key]
		h:SetWidth(cw)
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -112)
		h:SetShown((frame.currentTab or 1) == 1)
		h.x = x
		for _, row in ipairs(frame.rows) do
			local fs = row.cols[col.key]
			fs:SetWidth(cw)
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", row, "LEFT", x - 12, 0)
			fs:Show()
		end
		x = x + cw + COL_GAP
	end
	for _, col in ipairs(COLUMNS) do
		if not shown[col.key] then
			frame.headerByKey[col.key]:Hide()
			for _, row in ipairs(frame.rows) do row.cols[col.key]:Hide() end
		end
	end
	frame.list:SetWidth(width - 24)
	for _, row in ipairs(frame.rows) do row:SetWidth(width - 24) end
	-- se ordenava por uma coluna que sumiu, volta para Lucro (ou Receita)
	local keys, kept = SortKeys(), {}
	for _, sk in ipairs(keys) do if shown[sk.key] then table.insert(kept, sk) end end
	if #kept ~= #keys then LucroCraftDB.config.sort = kept end
end

-- Índice de inserção (na ordem visível) a partir da posição do cursor
local function DropIndex(dragKey)
	local scale = frame:GetEffectiveScale()
	local cx = GetCursorPosition() / scale
	local idx = 1
	for _, col in ipairs(VisibleColumns()) do
		if col.key ~= dragKey then
			local h = frame.headerByKey[col.key]
			local center = h:GetLeft() + h:GetWidth() / 2
			if cx > center then idx = idx + 1 end
		end
	end
	return idx
end

local function MarkerX(dragKey, idx)
	local others = {}
	for _, col in ipairs(VisibleColumns()) do
		if col.key ~= dragKey then table.insert(others, col) end
	end
	local target = others[idx]
	if target then return frame.headerByKey[target.key].x - COL_GAP / 2 end
	local last = others[#others]
	if last then return frame.headerByKey[last.key].x + last.width + COL_GAP / 2 end
	return LEFT_PAD
end

function UI.BeginColumnDrag(h)
	frame.dragKey = h.key
	h:SetAlpha(0.4)
	GameTooltip:Hide()
	frame.dropMarker:Show()
	frame:SetScript("OnUpdate", function()
		local idx = DropIndex(h.key)
		frame.dropMarker:ClearAllPoints()
		frame.dropMarker:SetPoint("TOP", frame, "TOPLEFT", MarkerX(h.key, idx), -54)
	end)
end

function UI.EndColumnDrag(h)
	frame:SetScript("OnUpdate", nil)
	frame.dropMarker:Hide()
	h:SetAlpha(1)
	local key = frame.dragKey
	frame.dragKey = nil
	if not key then return end

	-- evita que o soltar do arraste conte como clique de ordenação
	frame.dragJustEnded = true
	C_Timer.After(0.05, function() frame.dragJustEnded = false end)

	local idx = DropIndex(key)
	local cc = ColCfg()
	-- ordem visível sem a coluna arrastada, insere na nova posição
	local vis = {}
	for _, col in ipairs(VisibleColumns()) do
		if col.key ~= key then table.insert(vis, col.key) end
	end
	table.insert(vis, math.min(idx, #vis + 1), key)
	-- recompõe a ordem completa mantendo as ocultas nas posições relativas
	local newOrder, vi = {}, 1
	for _, k in ipairs(cc.order) do
		if cc.hidden[k] then
			table.insert(newOrder, k)
		else
			table.insert(newOrder, vis[vi]); vi = vi + 1
		end
	end
	cc.order = newOrder
	UI.Layout()
	UI.Refresh()
end

function UI.SetColumnHidden(key, hidden)
	if key == "name" then return end
	local cc = ColCfg()
	cc.hidden[key] = hidden or nil
	UI.Layout()
	UI.Refresh()
end

function UI.ResetColumns()
	LucroCraftDB.config.columns = nil
	UI.Layout()
	UI.Refresh()
end

function UI.ShowColumnMenu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		ns.Print(L["menu indisponível — use /lucro colunas"])
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L["Colunas"])
		local cc = ColCfg()
		for _, k in ipairs(cc.order) do
			local col = COL_BY_KEY[k]
			if k == "name" then
				root:CreateCheckbox(col.label .. L[" (fixa)"], function() return true end, function() end)
			else
				root:CreateCheckbox(col.label,
					function() return not ColCfg().hidden[k] end,
					function() UI.SetColumnHidden(k, not ColCfg().hidden[k]) end)
			end
		end
		root:CreateDivider()
		root:CreateButton(L["Restaurar colunas"], function() UI.ResetColumns() end)
		root:CreateButton(L["Ordenação padrão (ABC > Lucro)"], function() UI.ResetSort() end)
		root:CreateButton(L["Ordenar por Lucro/conc"], function()
			LucroCraftDB.config.sort = { { key = "perConc", desc = true } }
			UI.Refresh()
		end)
	end)
end

function UI.ColumnsCommand(arg)
	local cc = ColCfg()
	local k = arg and arg:lower() or ""
	if k == "reset" or k == "restaurar" then
		UI.ResetColumns()
		ns.Print(L["colunas restauradas."])
		return
	end
	if COL_BY_KEY[k] then
		UI.SetColumnHidden(k, not cc.hidden[k])
		ns.Print(COL_BY_KEY[k].label .. (cc.hidden[k] and L[" oculta"] or L[" visível"]))
		return
	end
	local parts = {}
	for _, key in ipairs(cc.order) do
		table.insert(parts, (cc.hidden[key] and "|cff808080" or "|cff55ff55") .. key .. "|r")
	end
	ns.Print(L["colunas: "] .. table.concat(parts, ", "))
	ns.Print(L["/lucro colunas <chave> alterna, /lucro colunas reset restaura"])
end

local function Position()
	frame:ClearAllPoints()
	local pos = LucroCraftDB.pos
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	elseif ProfessionsFrame and ProfessionsFrame:IsShown() then
		frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 4, 0)
	else
		frame:SetPoint("CENTER")
	end
end

function UI.Show(profID)
	if not frame then Create() end
	if profID then state.profID = profID; state.offset = 0; state.offsets = { 0, 0, 0, 0, 0 } end
	Position()
	UI.ApplyTabSize(frame.currentTab or 1)
	if (frame.currentTab or 1) == TAB.LIST then
		UI.LayoutRows()
		UI.Layout()
	end
	frame:Show()
	UI.Refresh()
end

function UI.Select(profID)
	if profID and profID ~= state.profID then
		state.profID = profID
		state.offset = 0; state.offsets = { 0, 0, 0, 0, 0 }
	end
	UI.Refresh()
end

function UI.Hide()
	if frame then frame:Hide() end
end

function UI.Toggle()
	if frame and frame:IsShown() then UI.Hide() else UI.Show() end
end

function UI.IsShown()
	return frame and frame:IsShown()
end
