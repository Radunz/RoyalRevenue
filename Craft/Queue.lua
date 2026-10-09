local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- Fila de fabricação (plano de concentração + itens que você adiciona) e lista de compras
-- descontando o estoque. Exporta para o Auctionator e para o TSM, e fabrica o próximo da fila.
local Queue = {}
ns.Queue = Queue

local P = ns.Pricing
local Cfg = ns.Cfg

local VARIANT_LABEL = { base = L["sem concentração"], conc = L["concentração"], mix = L["reagentes superiores"] }

local function DB()
	LucroCraftDB.queue = LucroCraftDB.queue or {}
	LucroCraftDB.queue.list = LucroCraftDB.queue.list or {}
	return LucroCraftDB.queue
end

local function Short(char) return (char:match("^([^-]+)")) or char end

local function FindRow(char, prof, recipeID)
	local e = LucroCraftDB.chars and LucroCraftDB.chars[char] and LucroCraftDB.chars[char][prof]
	if not e then return nil end
	for _, r in ipairs(e.rows or {}) do
		if r.recipeID == recipeID then return r, e end
	end
end

-- quantos crafts dessa receita já estão na fila manual
function Queue.Count(char, prof, recipeID, variant)
	for _, it in ipairs(DB().list) do
		if it.char == char and it.prof == prof and it.recipeID == recipeID and it.variant == (variant or "base") then return it.n end
	end
	return 0
end

-- adiciona n crafts (n negativo remove)
function Queue.Add(char, prof, recipeID, variant, n)
	local q = DB()
	variant = variant or "base"
	for i, it in ipairs(q.list) do
		if it.char == char and it.prof == prof and it.recipeID == recipeID and it.variant == variant then
			it.n = it.n + n
			if it.n <= 0 then table.remove(q.list, i) end
			Queue.Refresh()
			return
		end
	end
	if n > 0 then
		table.insert(q.list, { char = char, prof = prof, recipeID = recipeID, variant = variant, n = n })
	end
	Queue.Refresh()
end

function Queue.ClearManual()
	DB().list = {}
	Queue.Refresh()
end

local function VariantProfit(r, v)
	if v == "conc" then return r.concProfit end
	if v == "mix" then return r.mixProfit end
	return r.profit
end

local function VariantQuality(r, v)
	if v == "conc" then return r.concQuality end
	if v == "mix" then return r.mix and r.mix.quality end
	return r.quality
end

-- lista: { char, e, row, variant, n, source = "plano"|"manual", gold }
-- só o personagem logado
function Queue.Build()
	local items = {}
	local me = ns.CharKey()
	-- pedidos de fabricação pegos (de todos os personagens) vêm primeiro
	for _, c in pairs(DB().claimed or {}) do
		local r, e = FindRow(c.char, c.prof, c.recipeID)
		if not r then
			for _, e2 in pairs((LucroCraftDB.chars or {})[c.char] or {}) do
				for _, r2 in ipairs(e2.rows or {}) do if r2.recipeID == c.recipeID then r, e = r2, e2 end end
			end
		end
		if r then
			-- só os materiais que VOCÊ põe (o cliente manda o resto)
			local mine = {}
			for _, p in ipairs(r.parts or {}) do
				local given = false
				for _, id in ipairs(p.qualityItems or { p.itemID }) do if c.given and c.given[id] then given = true end end
				if not given then table.insert(mine, p) end
			end
			table.insert(items, { char = c.char, e = e, row = r, variant = "base", n = 1, source = "pedido", gold = c.profit, order = c, parts = mine })
		end
	end
	-- receitas que já estão na fila manual (adicionadas pelo botão do plano): o plano não repete
	local manual = {}
	for _, q in ipairs(DB().list) do manual[q.char .. "#" .. tostring(q.prof) .. "#" .. q.recipeID .. "#" .. q.variant] = true end
	if Cfg("queueIncludePlan") and ns.Plan then
		local list = ns.Plan.Build()
		for _, it in ipairs(list) do
			for _, u in ipairs(it.char == me and it.used or {}) do
				if not manual[it.char .. "#" .. tostring(it.prof) .. "#" .. u.row.recipeID .. "#conc"] then
					table.insert(items, { char = it.char, e = it.e, row = u.row, variant = "conc", n = u.crafts,
						source = "plano", gold = u.gold })
				end
			end
		end
	end
	-- fila manual de todos os personagens (a lista de compras junta tudo; fabricar continua só do logado)
	for _, q in ipairs(DB().list) do
		local r, e = FindRow(q.char, q.prof, q.recipeID)
		if r then
			local p = VariantProfit(r, q.variant)
			table.insert(items, { char = q.char, e = e, row = r, variant = q.variant, n = q.n, source = "manual",
				gold = p and p * q.n or nil, manual = q })
		end
	end
	return items
end

-- reagentes que a fila consome: itemID -> { need, crafted = "quem fabrica" }
local function Needs(items)
	local need = {}
	local function add(id, n, p)
		if not id or n <= 0 then return end
		local x = need[id] or { need = 0, qual = {} }
		x.need = x.need + n
		if p.crafted and p.itemID == id then x.crafted = p.crafted end
		-- outras qualidades do mesmo reagente servem no lugar (ex.: tem 6 mil da qualidade máxima)
		for _, q in ipairs(p.qualityItems or {}) do x.qual[q] = true end
		need[id] = x
	end
	for _, it in ipairs(items) do
		local r = it.row
		local alloc = it.variant == "mix" and r.mix and r.mix.alloc or nil
		for i, p in ipairs(it.parts or r.parts or {}) do
			if not p.bound then
				local base = p.buyItem or p.itemID
				local n = alloc and alloc[i] or 0
				local top = n > 0 and r.mix.top and r.mix.top[i] or nil
				add(base, ((p.qty or 0) - n) * it.n, p)
				if top then add(top, n * it.n, p) end
			end
		end
	end
	return need
end

-- lista de compras: { id, name, need, have, stock, buy, unit, total, crafted }
-- fila + pedidos lidos (ainda não pegos): estes entram com os materiais que VOCÊ põe (não os do cliente)
function Queue.ShopItems(items)
	local out = {}
	for _, it in ipairs(items or Queue.Build()) do table.insert(out, it) end
	local me = ns.CharKey()
	if Queue.ordersChar == me then
		for _, x in ipairs(Queue.orders or {}) do
			if x.row then
				local mine = {}
				for _, pp in ipairs(x.parts or {}) do if not pp.given then table.insert(mine, pp.part) end end
				table.insert(out, { char = me, row = x.row, variant = "base", n = 1, parts = mine, source = "lido" })
			end
		end
	end
	return out
end

function Queue.Shopping(items)
	local list, total = {}, 0
	for id, x in pairs(Needs(items or Queue.ShopItems())) do
		local s = ns.Stock and ns.Stock.Get(id)
		-- só o que dá para usar: bolsas + banco do bando (alts e banco do personagem não contam)
		local have, bags, wb = 0, 0, 0
		local byQ = {}
		if ns.Stock and ns.Stock.Usable then
			local ids = { id }
			for q in pairs(x.qual or {}) do if q ~= id then table.insert(ids, q) end end
			for _, q in ipairs(ids) do
				local h, b, w = ns.Stock.Usable(q)
				have, bags, wb = have + h, bags + b, wb + w
				if h > 0 then table.insert(byQ, { id = q, n = h }) end
			end
		end
		local buy = math.max(0, x.need - have)
		local unit = P.Cost(id)
		local line = { id = id, name = ns.Visual.ItemName(id), need = x.need, have = have, stock = s, bags = bags, wb = wb, byQ = byQ,
			buy = buy, unit = unit, total = unit and unit * buy or nil, crafted = x.crafted }
		if line.total then total = total + line.total end
		table.insert(list, line)
	end
	table.sort(list, function(a, b)
		if (a.buy > 0) ~= (b.buy > 0) then return a.buy > 0 end
		return (a.total or 0) > (b.total or 0)
	end)
	return list, total
end

local function RQ(id)
	local q = ns.Scanner.ReagentQuality and ns.Scanner.ReagentQuality(id)
	return q and (" " .. ns.QIcon(q, 2)) or ""
end

function Queue.GetText()
	local out = {}
	local function add(s) table.insert(out, s) end
	local G = P.FormatGold
	local items = Queue.Build()
	add(string.format(L["|cffffd100Fila de fabricação — %s|r |cff9d9d9d(botão direito numa receita da lista = +1 · Shift = +5 · Ctrl = -1)|r"], Short(ns.CharKey())))
	if #items == 0 then
		add(L["|cff9d9d9dFila vazia. Ative \"incluir plano\" ou adicione receitas pela lista.|r"])
		-- por que o plano não trouxe nada para este personagem
		if Cfg("queueIncludePlan") and ns.Plan then
			local me = ns.CharKey()
			for _, it in ipairs(ns.Plan.Build()) do
				if it.char == me and not it.cook and #(it.used or {}) == 0 then
					local why = #it.cands == 0 and L["nenhuma receita dá lucro com concentração"]
						or string.format(L["concentração insuficiente (~%d/%d), próximo craft em %s"], math.floor(it.est),
							it.e.conc.max or 0, ns.Alerts and ns.Alerts.Hours(it.nextIn or 0) or "?")
					add(string.format("|cffff8800%s:|r %s", it.e.name or "?", why))
				end
			end
		end
	end
	local byBlock, order = {}, {}
	local expected = 0
	for _, it in ipairs(items) do
		local key = it.char .. "#" .. (it.e.professionID or 0)
		if not byBlock[key] then byBlock[key] = {}; table.insert(order, key) end
		table.insert(byBlock[key], it)
		expected = expected + (it.gold or 0)
	end
	for _, key in ipairs(order) do
		local list = byBlock[key]
		local e = list[1].e
		add(string.format("|cffffd100%s|r |cff9d9d9d· %s|r", e.name or e.skillLine or "?", Short(list[1].char)))
		for _, it in ipairs(list) do
			local r = it.row
			local q = VariantQuality(r, it.variant)
			local qTag = (q and r.maxQuality and r.maxQuality > 1) and (" " .. ns.QIcon(q, r.maxQuality)) or ""
			local flag = P.TrendFlag(it.variant == "conc" and r.concTrend or it.variant == "mix" and r.mixTrend or r.trend)
			local warn = flag == "down" and L[" |cffff5555(preço caindo)|r"] or ""
			add(string.format(L["   %dx %s%s |cff9d9d9d(%s · %s)|r · lucro ~%s%s"], it.n, r.name or "?", qTag,
				VARIANT_LABEL[it.variant] or it.variant, L[it.source], it.gold and G(it.gold, true) or "—", warn))
		end
	end
	if #items > 0 then
		add(string.format(L["|cffffd100Lucro previsto da fila: %s|r"], G(expected, true)))
	end
	add(" ")
	local shop, total = Queue.Shopping(Queue.ShopItems(items))
	add(L["|cffffd100Lista de compras|r |cff9d9d9d(descontando bolsa, banco e banco do bando)|r"])
	if #shop == 0 then add(L["|cff9d9d9dNada a comprar.|r"]) end
	for _, s in ipairs(shop) do
		local status
		if s.buy > 0 then
			status = string.format(L["|cffffffffcomprar %d|r × %s = %s"], s.buy, G(s.unit), G(s.total))
		else
			status = L["|cff55ff55ok|r"]
		end
		local fab = s.crafted and string.format(L[" |cff66ccff(ou fabricar: %s)|r"], s.crafted) or ""
		add(string.format(L["   %s%s: precisa %d · tem %s · %s%s"], s.name, RQ(s.id), s.need,
			tostring(s.have), status, fab))
	end
	if total > 0 then add(string.format(L["|cffffd100Total a comprar: %s|r"], G(total))) end
	add(L["|cff9d9d9dQuantidades sem contar resourcefulness (o que sobrar fica no estoque).|r"])
	return table.concat(out, "\n")
end

-- ===== Exportar =====
function Queue.TSMString()
	local ids = {}
	for _, s in ipairs(Queue.Shopping()) do
		if s.buy > 0 then table.insert(ids, "i:" .. s.id) end
	end
	return table.concat(ids, ",")
end

-- o que falta comprar da fila (para a lista do Auctionator)
local function QueueRows()
	local rows = {}
	for _, x in ipairs(Queue.Shopping()) do if x.buy > 0 then table.insert(rows, { id = x.id, qty = x.buy }) end end
	return rows
end
ns.Stock.RegisterListBuilder("queue", QueueRows)

function Queue.ExportAuctionator()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
		ns.Print(L["Auctionator não encontrado."])
		return
	end
	local terms, missing = ns.Stock.Terms(QueueRows())
	if #terms == 0 then ns.Print(L["nada a comprar."]) return end
	local ok, err = pcall(api.CreateShoppingList, ADDON, "Royal Revenue", terms)
	if ok then
		ns.Stock.LiveList("Royal Revenue", "queue", terms)
		ns.Print(string.format(L["lista \"Royal Revenue\" criada no Auctionator com %d itens."], #terms)
			.. (missing > 0 and string.format(L[" (%d sem nome carregado — tente de novo)"], missing) or "")
			.. L[" Ela se atualiza sozinha: o que você compra sai da lista."])
	else
		ns.Print(L["erro no Auctionator: "] .. tostring(err))
	end
end

local copyFrame
function Queue.ShowCopy(text, title)
	if not copyFrame then
		copyFrame = CreateFrame("Frame", "LucroCraftCopyFrame", UIParent, "BasicFrameTemplateWithInset")
		copyFrame:SetSize(460, 160)
		copyFrame:SetPoint("CENTER")
		copyFrame:SetFrameStrata("DIALOG")
		copyFrame:SetMovable(true)
		copyFrame:EnableMouse(true)
		copyFrame:RegisterForDrag("LeftButton")
		copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
		copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
		table.insert(UISpecialFrames, "LucroCraftCopyFrame")
		copyFrame.title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		copyFrame.title:SetPoint("TOP", 0, -5)
		local sf = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
		sf:SetPoint("TOPLEFT", 12, -30)
		sf:SetPoint("BOTTOMRIGHT", -30, 28)
		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true)
		eb:SetFontObject(ChatFontNormal)
		eb:SetWidth(400)
		eb:SetAutoFocus(false)
		eb:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
		sf:SetScrollChild(eb)
		copyFrame.eb = eb
		local hint = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("BOTTOMLEFT", 14, 10)
		hint:SetText(L["Ctrl+C para copiar · TSM: Grupos > Importar"])
	end
	copyFrame.title:SetText(title or "Royal Revenue")
	copyFrame.eb:SetText(text or "")
	copyFrame:Show()
	copyFrame.eb:SetFocus()
	copyFrame.eb:HighlightText()
end

function Queue.ExportTSM()
	local s = Queue.TSMString()
	if s == "" then ns.Print(L["nada a comprar."]) return end
	Queue.ShowCopy(s, L["Itens para comprar (formato de importação do TSM)"])
end

-- ===== Fabricar o próximo da fila =====
local lastCraft

local function OpenProfessionIDs()
	local set = {}
	if not (C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady()) then return set end
	if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return set end
	for _, info in ipairs(C_TradeSkillUI.GetChildProfessionInfos and C_TradeSkillUI.GetChildProfessionInfos() or {}) do
		if info.professionID then set[info.professionID] = true end
	end
	local shown = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	if shown and shown.professionID then set[shown.professionID] = true end
	return set
end

function Queue.NextForMe()
	local me = ns.CharKey()
	local open = OpenProfessionIDs()
	if not next(open) then return nil, L["abra a profissão para fabricar."] end
	for _, it in ipairs(Queue.Build()) do
		if it.char == me and open[it.e.professionID] then return it end
	end
	return nil, L["nada na fila para este personagem nesta profissão."]
end

function Queue.NextLabel()
	local it = Queue.NextForMe()
	if not it then return L["Fabricar próximo"] end
	local q = VariantQuality(it.row, it.variant)
	local qTag = (q and it.row.maxQuality and it.row.maxQuality > 1) and (" " .. ns.QIcon(q, it.row.maxQuality, 12)) or ""
	return L["Fabricar: "] .. (it.row.name or "?") .. qTag
end

function Queue.CraftNext()
	local it, why = Queue.NextForMe()
	if not it then ns.Print(why) return end
	local r = it.row
	local info = C_TradeSkillUI.GetRecipeInfo(r.recipeID)
	if info and info.isEnchantingRecipe then
		ns.Print(L["encantamento: fabrique pela janela da profissão (precisa do pergaminho)."])
		return
	end
	Queue.CraftItem(it)
end

-- craft concluído: tira 1 da fila manual
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:SetScript("OnEvent", function(_, _, unit, _, spellID)
	if root.AnySecret(unit, spellID) then return end
	if unit ~= "player" or not LucroCraftDB or not LucroCraftDB.queue then return end
	if lastCraft and lastCraft.order and lastCraft.recipeID == spellID then
		local c = DB().claimed and DB().claimed[lastCraft.order]
		if c then c.crafted = true end
		Queue.Refresh()
		return
	end
	local me = ns.CharKey()
	local list = DB().list
	local pick
	for i, it in ipairs(list) do
		if it.char == me and it.recipeID == spellID then
			if lastCraft and lastCraft.recipeID == spellID and lastCraft.variant == it.variant then pick = i break end
			pick = pick or i
		end
	end
	if pick then
		list[pick].n = list[pick].n - 1
		if list[pick].n <= 0 then table.remove(list, pick) end
		Queue.Refresh()
	end
end)

function Queue.Refresh()
	if ns.UI and ns.UI.RefreshTab then ns.UI.RefreshTab(ns.UI.TAB.QUEUE) end
end

-- ===== Pedidos de fabricação =====
-- Lê os pedidos que a janela de pedidos da profissão carregou (aba Público / Patrono / Pessoal / Guilda),
-- calcula o lucro de cada um (comissão − corte do consórcio + recompensas − materiais que VOCÊ põe)
-- e permite pegar (reivindicar) o pedido pelo botão.
Queue.orders = {}
local ORDER_TYPE = { [0] = L["Público"], [1] = L["Guilda"], [2] = L["Pessoal"], [3] = L["Patrono"] }

local function MyRow(recipeID)
	local me = ns.CharKey()
	for _, e in pairs((LucroCraftDB.chars or {})[me] or {}) do
		for _, r in ipairs(e.rows or {}) do if r.recipeID == recipeID then return r, e end end
	end
end

-- recompensa que dá ponto de conhecimento da profissão: o texto do item fala em conhecimento
-- ("Study to increase your Leatherworking knowledge by 1." / "...conhecimento de Couraria em 1.")
-- devolve quantos pontos (1 se não achar o número) ou nil
local kpCache = {}
function Queue.KnowledgeOf(link, id)
	if not (link or id) then return nil end
	local key = id or link
	if kpCache[key] ~= nil then return kpCache[key] or nil end
	local lines = {}
	if C_TooltipInfo then
		local ok, data = pcall(link and C_TooltipInfo.GetHyperlink or C_TooltipInfo.GetItemByID, link or id)
		if ok and data and data.lines then
			for _, ln in ipairs(data.lines) do if ln.leftText then table.insert(lines, ln.leftText) end end
		end
	end
	local name = link and link:match("%[(.-)%]")
	if not name or name == "" then name = (id and C_Item.GetItemNameByID(id)) or "" end
	table.insert(lines, name)
	local kp
	for _, t in ipairs(lines) do
		local l = t:lower()
		if l:find("knowledge") or l:find("conhecimento") then
			kp = tonumber(l:match("by (%d+)") or l:match("em (%d+)") or l:match("(%d+)%s+knowledge") or l:match("(%d+)%s+ponto")) or kp or 1
		end
	end
	-- itens de conhecimento conhecidos pelo nome (tratados, anotações, padrões)
	local n = name:lower()
	if not kp and (n:find("treatise") or n:find("tratado") or n:find("notes") or n:find("anotaç") or n:find("knowledge")) then kp = 1 end
	-- item ainda não carregado (sem nome nem texto): não guarda o "não dá", tenta de novo depois
	if kp or name ~= "" then kpCache[key] = kp or false end
	if not kp and name == "" and id and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	return kp
end

local function Eval(o)
	local r, e = MyRow(o.spellID)
	local x = { order = o, row = r, e = e, id = o.orderID, type = ORDER_TYPE[o.orderType] or "?", customer = o.customerName,
		tip = o.tipAmount or 0, cut = o.consortiumCut or 0, exp = o.expirationTime, minQ = o.minQuality }
	-- reagentes que o cliente/patrono já mandou
	local given, custR = {}, {}
	for _, rg in ipairs(o.reagents or {}) do
		local ri = rg.reagentInfo or rg
		local id = (rg.reagent and rg.reagent.itemID) or (ri.reagent and ri.reagent.itemID) or ri.itemID or rg.itemID
		if id then
			given[id] = true
			table.insert(custR, { itemID = id, quantity = ri.quantity or rg.quantity, slot = ri.dataSlotIndex or rg.dataSlotIndex })
		end
	end
	x.given, x.custR = given, custR
	-- materiais que você precisa pôr (os espaços que o cliente não preencheu), na qualidade mais barata
	local mat, miss, parts = 0, false, {}
	for _, p in ipairs(r and r.parts or {}) do
		local provided = false
		for _, id in ipairs(p.qualityItems or { p.itemID }) do if given[id] then provided = true end end
		table.insert(parts, { part = p, given = provided })
		if not provided then
			if p.unit then mat = mat + p.unit * (p.qty or 1) elseif not p.bound then miss = true end
		end
	end
	x.parts = parts
	-- recompensas do patrono (itens e MOEDAS: o Moxie de cada profissão vem como currency, não item)
	local rew, rewList, kp = 0, {}, 0
	for _, rw in ipairs(o.npcOrderRewards or {}) do
		-- link novo da Midnight ("|cnIQ1:|Hitem:...|h[]|h|r", às vezes sem nome): o id sai do próprio link
		local id = rw.itemLink and (tonumber(rw.itemLink:match("item:(%d+)")) or C_Item.GetItemInfoInstant(rw.itemLink))
		-- Moxie vem SEM itemLink: o jogo manda { count = 30, currencyType = 3257 }.
		-- (o link com "currency:" fica como reserva, caso alguma recompensa venha assim)
		local curID = rw.currencyType
			or ((not id) and rw.itemLink and tonumber(rw.itemLink:match("currency:(%d+)")) or nil)
		local icon = curID and ns.Visual.CurrencyIcon(curID) or nil
		local v = id and ns.Pricing.Sale(id)
		rew = rew + (v or 0) * (rw.count or 1)
		local k = Queue.KnowledgeOf(rw.itemLink, id)
		if k then kp = kp + k * (rw.count or 1) end
		table.insert(rewList, { link = rw.itemLink, id = id, currency = curID, n = rw.count or 1, v = v, kp = k,
			icon = icon })
	end
	x.mat, x.miss, x.rew, x.rewList, x.kp = mat, miss, rew, rewList, kp
	x.profit = x.tip - x.cut + rew - mat
	-- concentração do pedido: mostra os pontos sempre que a receita puder usar.
	-- Só desconta do lucro quando ela é OBRIGATÓRIA para a qualidade mínima (x.concOpt = opcional).
	if r and Queue.OrderConc then
		Queue.OrderConc(x, { recipeID = o.spellID, char = ns.CharKey(), prof = e and e.professionID, given = given, custR = custR, minQ = o.minQuality, id = o.orderID })
		if x.concValue and not x.concOpt then x.profit = x.profit - x.concValue end
	end
	return x
end

function Queue.ReadOrders()
	Queue.orders = {}
	if not (C_CraftingOrders and C_CraftingOrders.GetCrafterOrders) then return 0, L["pedidos de fabricação não disponíveis."] end
	local ok, list = pcall(C_CraftingOrders.GetCrafterOrders)
	if not ok or type(list) ~= "table" or #list == 0 then
		return 0, L["abra a profissão > Pedidos de fabricação e escolha a aba (Público, Patrono, Pessoal) para o jogo carregar a lista."]
	end
	-- cópia dos pedidos lidos (para conferir os campos do jogo depois). Copia até 5 níveis:
	-- o itemID do reagente do cliente fica fundo (reagents[i].reagentInfo.reagents[j].itemID) e
	-- a versão antiga parava em "{...}", o que já atrapalhou um diagnóstico.
	local function Copy(v, depth)
		if type(v) ~= "table" then return v end
		if depth <= 0 then return "{...}" end
		local out = {}
		for k, v2 in pairs(v) do
			if type(k) == "string" or type(k) == "number" then out[k] = Copy(v2, depth - 1) end
		end
		return out
	end
	local snap = {}
	for i, o in ipairs(list) do
		if i > 8 then break end
		snap[i] = Copy(o, 5)
	end
	LucroCraftDB.ordersDebug = snap
	local claimed = DB().claimed or {}
	local known = 0
	for _, o in ipairs(list) do
		local okE, x = pcall(Eval, o)
		if okE and x and not claimed[o.orderID] then
			if x.row then known = known + 1 end
			table.insert(Queue.orders, x)
		end
	end
	-- sabe fazer primeiro; depois quem dá ponto de conhecimento; depois lucro
	table.sort(Queue.orders, function(a, b)
		if (a.row ~= nil) ~= (b.row ~= nil) then return a.row ~= nil end
		if (a.kp or 0) ~= (b.kp or 0) then return (a.kp or 0) > (b.kp or 0) end
		return a.profit > b.profit
	end)
	Queue.ordersT = time()
	local okP, info = pcall(C_TradeSkillUI.GetChildProfessionInfo)
	Queue.ordersProf = okP and info and info.professionID or nil
	Queue.ordersChar = ns.CharKey()
	return #list, nil, known
end

function Queue.ClearOrders()
	Queue.orders, Queue.ordersT, Queue.ordersProf = {}, nil, nil
	Queue.Refresh()
end

function Queue.ClaimOrder(x)
	if not (x and C_CraftingOrders and C_CraftingOrders.ClaimOrder) then return end
	local prof
	local okP, info = pcall(C_TradeSkillUI.GetChildProfessionInfo)
	if okP and info then prof = info.profession end
	if not prof then ns.Print(L["abra a profissão para pegar o pedido."]) return end
	local ok, err = pcall(C_CraftingOrders.ClaimOrder, x.id, prof)
	ns.Log(string.format("fila: pegando pedido #%s %s (%s): %s", tostring(x.id), x.row and x.row.name or "?", tostring(x.customer or x.type), ok and "ok" or tostring(err)))
	if ok then
		ns.Print(string.format(L["pedido pego: %s (%s)."], x.row and x.row.name or "?", x.customer or x.type))
		local q = DB()
		q.claimed = q.claimed or {}
		local given = {}
		for id in pairs(x.given or {}) do given[id] = true end
		q.claimed[x.id] = { id = x.id, recipeID = x.row and x.row.recipeID or x.order.spellID, char = ns.CharKey(),
			prof = x.e and x.e.professionID, profEnum = prof, type = x.type, customer = x.customer, tip = x.tip, cut = x.cut,
			rew = x.rew, profit = x.profit, given = given, t = time(), exp = x.exp, minQ = x.minQ,
			concPts = x.concPts, concValue = x.concValue, concFrom = x.concFrom, custR = x.custR }
		for i, y in ipairs(Queue.orders) do if y.id == x.id then table.remove(Queue.orders, i) break end end
	else
		ns.Print(L["não foi possível pegar o pedido: "] .. tostring(err))
	end
	Queue.Refresh()
end

-- ===== pedidos pegos: fabricar, entregar, soltar =====
local function ClaimedFor(char)
	local out = {}
	for _, c in pairs(DB().claimed or {}) do
		if c.char == char then table.insert(out, c) end
	end
	table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
	return out
end
Queue.ClaimedFor = ClaimedFor

local function ProfEnum(c)
	if c.profEnum then return c.profEnum end
	local ok, info = pcall(C_TradeSkillUI.GetChildProfessionInfo)
	return ok and info and info.profession or nil
end

-- reagentes que VOCÊ põe no pedido (o resto vem do cliente)
local function OrderReagents(c)
	local r = FindRow(c.char, c.prof, c.recipeID)
	if not r then
		for _, e2 in pairs((LucroCraftDB.chars or {})[c.char] or {}) do
			for _, r2 in ipairs(e2.rows or {}) do if r2.recipeID == c.recipeID then r = r2 end end
		end
	end
	if not r then return nil end
	local mine = {}
	for _, p in ipairs(r.parts or {}) do
		local given = false
		for _, id in ipairs(p.qualityItems or { p.itemID }) do if c.given and c.given[id] then given = true end end
		if not given then table.insert(mine, p) end
	end
	return ns.Scanner.BuildReagentTbl(mine), r, mine
end

-- tabela completa (seus reagentes + os do cliente) para a API calcular a qualidade do pedido
local function OrderReagentsFull(c)
	local tbl, r, mine = OrderReagents(c)
	if not tbl then return nil end
	local full = {}
	for _, e in ipairs(tbl) do table.insert(full, e) end
	for _, cr in ipairs(c.custR or {}) do
		if cr.itemID and cr.quantity and cr.slot then
			table.insert(full, { reagent = { itemID = cr.itemID }, quantity = cr.quantity, dataSlotIndex = cr.slot })
		end
	end
	return full, r, mine
end

-- confere a bolsa antes de fabricar: troca de qualidade se precisar; se faltar, avisa e não tenta
local function CheckBags(tbl, parts, what)
	local _, missing, swaps = ns.Scanner.FitToBags(tbl, parts)
	if #missing > 0 then
		local t = {}
		for _, m in ipairs(missing) do
			table.insert(t, string.format("%s %d/%d", ns.Visual.ItemName(m.id), m.have, m.need))
		end
		local msg = string.format(L["faltam materiais para %s: %s."], what, table.concat(t, ", "))
		ns.Print(msg); ns.Log("fila: " .. msg)
		return false
	end
	if #swaps > 0 then
		local msg = string.format(L["%s: completando com a outra qualidade que está na bolsa (%s)."], what, table.concat(swaps, ", "))
		ns.Print(msg); ns.Log("fila: " .. msg)
	end
	return true
end

-- erro do jogo logo depois de mandar fabricar/entregar vai para o registro (para conferir depois)
local watch = { t = 0 }
local wf = CreateFrame("Frame")
pcall(wf.RegisterEvent, wf, "UI_ERROR_MESSAGE")
pcall(wf.RegisterEvent, wf, "UNIT_SPELLCAST_FAILED")
pcall(wf.RegisterEvent, wf, "UNIT_SPELLCAST_INTERRUPTED")
wf:SetScript("OnEvent", function(_, ev, a1, a2, a3)
	if root.AnySecret(a1, a2, a3) then return end
	if GetTime() - watch.t > 5 then return end
	if ev == "UI_ERROR_MESSAGE" then
		ns.Log(string.format("fila: erro do jogo em %s: %s", watch.what or "?", tostring(a2)))
	elseif a1 == "player" and (not watch.spell or a3 == watch.spell) then
		ns.Log(string.format("fila: %s em %s", ev == "UNIT_SPELLCAST_FAILED" and "falhou" or "interrompido", watch.what or "?"))
	end
end)
local function Watch(what, spell) watch.t, watch.what, watch.spell = GetTime(), what, spell end

-- qualidade que sai no pedido com/sem concentração (o jogo calcula com os reagentes do cliente)
local function OrderOp(c, tbl, conc)
	local f = C_TradeSkillUI.GetCraftingOperationInfoForOrder
	local ok, op
	if f then ok, op = pcall(f, c.recipeID, tbl, c.id, conc) end
	if not (ok and op) then ok, op = pcall(C_TradeSkillUI.GetCraftingOperationInfo, c.recipeID, tbl, nil, conc) end
	return ok and op or nil
end

-- precisa de concentração para chegar na qualidade mínima do pedido?
-- devolve: usar concentração (bool), custo de concentração, qualidade sem, qualidade com, alcança (bool)
function Queue.OrderPlan(c)
	local tbl, r, mine = OrderReagentsFull(c)
	if not tbl then return false end
	r = c.row or r
	local minQ = c.minQ or 0
	-- pedido antigo sem a lista do cliente e com tudo fornecido: não dá para calcular direito → não pede concentração
	if not c.custR and mine and #mine == 0 then return false, nil, nil, nil, true end
	local op0 = OrderOp(c, tbl, false)
	local q0 = op0 and op0.craftingQuality
	if minQ <= 1 then return false, nil, q0, nil, true end
	-- A API não respondeu a qualidade (acontece com pedido que não está aberto/selecionado).
	-- Antes isso virava "não precisa de concentração" — resposta errada e silenciosa, que fazia
	-- dois pedidos iguais aparecerem um com e outro sem o custo. Agora usa o que o scan sabe.
	if not q0 then
		if r and r.concCost and r.concCost > 0 and (r.quality or 0) < minQ then
			local alcanca = (r.concQuality or 0) >= minQ
			return true, r.concCost, r.quality, r.concQuality, alcanca, true   -- true final = estimado
		end
		return false, nil, nil, nil, true
	end
	if q0 >= minQ then return false, nil, q0, nil, true end
	-- a API não devolve a qualidade "com concentração": concentrationCost é o custo para subir 1 nível
	-- (o mesmo que o Scanner usa). Com concentração sai q0 + 1.
	local cost = op0 and op0.concentrationCost
	local q1 = (cost and cost > 0) and (q0 + 1) or q0
	return true, cost, q0, q1, q1 >= minQ
end

-- quanto vale 1 ponto de concentração deste personagem/profissão: o lucro por ponto da melhor receita
-- (é o que você deixa de ganhar gastando os pontos no pedido)
function Queue.ConcPointValue(char, profID)
	local best, name
	for _, e in pairs((LucroCraftDB.chars or {})[char or ns.CharKey()] or {}) do
		if not profID or e.professionID == profID then
			for _, r in ipairs(e.rows or {}) do
				if r.perConc and r.perConc > 0 and not r.excluded and r.concSale and (not best or r.perConc > best) then best, name = r.perConc, r.name end
			end
		end
	end
	return best or 0, name
end

-- ===== Tabela dos pedidos de fabricação (colunas com título, ordenável) =====
-- Ordem: Item · Custo · Reagentes · Recompensa · Lucro · Tempo · Pegar pedido.
-- A coluna Item tem um mínimo garantido: se o painel for estreito, as OUTRAS encolhem
-- (proporcionalmente, até um mínimo próprio) em vez de passar por cima do nome.
local OCOL  = { cost = 76, reag = 132, reward = 118, profit = 84, time = 50, claim = 104 }
local OCMIN = { cost = 54, reag = 70,  reward = 54,  profit = 62, time = 34, claim = 72 }
local OORDER = { "cost", "reag", "reward", "profit", "time", "claim" }
local OGAP, ITEM_MIN = 8, 170
function Queue.OrderCols(QW)
	local w = {}
	for _, k in ipairs(OORDER) do w[k] = OCOL[k] end
	local fixed = 16 + OGAP * #OORDER
	local total, mins = 0, 0
	for _, k in ipairs(OORDER) do total = total + w[k]; mins = mins + OCMIN[k] end
	local avail = QW - fixed - ITEM_MIN
	if total > avail then
		local room, flex = math.max(0, avail - mins), total - mins
		for _, k in ipairs(OORDER) do
			w[k] = OCMIN[k] + ((flex > 0) and math.floor((w[k] - OCMIN[k]) * room / flex) or 0)
		end
	end
	local c = { w = w }
	c.claim = QW - 8 - w.claim
	c.time = c.claim - OGAP - w.time
	c.profit = c.time - OGAP - w.profit
	c.reward = c.profit - OGAP - w.reward
	c.reag = c.reward - OGAP - w.reag
	c.cost = c.reag - OGAP - w.cost
	c.item = 8
	c.itemW = math.max(60, c.cost - OGAP - c.item)   -- nunca invade a coluna Custo
	return c
end
-- comissão líquida + recompensas (o que o pedido paga)
local function OrderReward(x) return (x.tip or 0) - (x.cut or 0) + (x.rew or 0) end
local OSORT = {
	item = function(x) return (x.row and x.row.name) or "" end,
	cost = function(x) return x.mat or 0 end,
	reward = OrderReward,
	profit = function(x) return x.profit or 0 end,
	time = function(x) return x.exp or (x.order and x.order.expirationTime) or math.huge end,
}
function Queue.OrderSort()
	local s = LucroCraftDB.config and LucroCraftDB.config.orderSort
	if type(s) ~= "table" or not OSORT[s.key] then return { key = "profit", desc = true } end
	return s
end
function Queue.SetOrderSort(key)
	if not OSORT[key] then return end
	local cur = Queue.OrderSort()
	local desc
	if cur.key == key then
		desc = not cur.desc            -- mesma coluna de novo: inverte
	else
		desc = (key ~= "item" and key ~= "time")   -- nome e tempo começam crescentes
	end
	LucroCraftDB.config.orderSort = { key = key, desc = desc }
	Queue.Refresh()
end
function Queue.SortOrders(list)
	local s = Queue.OrderSort()
	local get = OSORT[s.key]
	table.sort(list, function(a, b)
		local va, vb = get(a), get(b)
		if va ~= vb then
			-- nada de "s.desc and va > vb or va < vb": com desc e va <= vb isso cai no segundo ramo
			if s.desc then return va > vb end
			return va < vb
		end
		return ((a.row and a.row.name) or "") < ((b.row and b.row.name) or "")
	end)
end
-- Bônus de PRIMEIRA fabricação: só ele usa o ícone do livro (Professions_Icon_FirstTimeCraft).
-- Prefere o dado ao vivo do jogo (a receita pode ter sido feita depois do último scan).
local fcCache, fcT = {}, 0
function Queue.IsFirstCraft(r)
	if not (r and r.recipeID) then return false end
	if time() - fcT > 30 then fcCache, fcT = {}, time() end
	local v = fcCache[r.recipeID]
	if v ~= nil then return v end
	local live
	if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
		local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, r.recipeID)
		if ok and type(info) == "table" and info.firstCraft ~= nil then live = info.firstCraft and true or false end
	end
	if live == nil then live = r.firstCraft and true or false end   -- reserva: o que o scan guardou
	fcCache[r.recipeID] = live
	return live
end

-- tempo restante até o pedido expirar
function Queue.OrderTimeLeft(x)
	local exp = x.exp or (x.order and x.order.expirationTime)
	if not exp or exp <= 0 then return nil end
	return exp - time()
end
function Queue.ShortTime(s)
	if not s then return "—" end
	if s <= 0 then return L["expirado"] end
	if s < 3600 then return string.format(L["%dmin"], math.floor(s / 60)) end
	if s < 86400 then return string.format(L["%dh"], math.floor(s / 3600)) end
	return string.format(L["%dd"], math.floor(s / 86400))
end

-- concentração do pedido (preenche x.concPts, x.concValue, x.concOpt, x.unreach)
-- Mostra o custo SEMPRE que a receita puder usar concentração, não só quando ela é obrigatória
-- para a qualidade mínima: com minQuality 1 o pedido aceita a qualidade de baixo, mas a receita
-- continua tendo custo de concentração (é o que o jogo e o CraftSim mostram). x.concOpt marca
-- que é opcional — nesse caso o lucro não desconta os pontos (você escolhe se gasta).
local function OrderConc(x, c)
	c.row = c.row or x.row   -- o OrderPlan usa o scan como reserva quando a API não responde
	local okP, conc, cost, q0, q1, reach, est = pcall(Queue.OrderPlan, c)
	if not okP then return end
	if conc and not reach then x.unreach = true; x.q0 = q0 return end
	x.q0, x.q1, x.concEst = q0, q1, est or nil
	if not conc then
		-- não é obrigatória: pega o custo da receita escaneada (subir 1 qualidade)
		local r = x.row
		if r and r.concCost and r.concCost > 0 and (r.quality or 0) < (r.maxQuality or 0) then
			cost, conc, x.concOpt = r.concCost, true, true
		end
	end
	if conc and cost then
		local per, from = Queue.ConcPointValue(c.char, c.prof)
		x.concPts, x.concPer, x.concFrom = cost, per, from
		x.concValue = cost * per
	end
end
Queue.OrderConc = OrderConc

function Queue.CraftOrder(c)
	local tbl, r, mine = OrderReagents(c)
	if not tbl then ns.Print(L["abra a profissão deste pedido para fabricar."]) return end
	local what = (r and r.name or "?") .. " (" .. tostring(c.customer or c.type) .. ")"
	if not CheckBags(tbl, mine, what) then return end
	local conc, cost, q0, q1, reach = Queue.OrderPlan(c)
	if conc and not reach then
		ns.Print(string.format(L["o pedido pede qualidade %s; nem com concentração chega (sai %s). Use reagentes melhores pela janela de pedidos."],
			tostring(c.minQ), tostring(q1 or q0 or "?")))
		return
	end
	if conc then
		ns.Print(string.format(L["pedido pede qualidade %s: fabricando com concentração (%s pontos)."], tostring(c.minQ), tostring(cost or "?")))
	end
	lastCraft = { recipeID = c.recipeID, variant = "order", order = c.id }
	local sent = {}
	for _, e in ipairs(tbl) do if e.quantity > 0 then table.insert(sent, e.quantity .. "x " .. e.reagent.itemID) end end
	ns.Log(string.format("fila: fabricando pedido %s #%s%s · %s", what, tostring(c.id), conc and " com concentração" or "", table.concat(sent, ", ")))
	Watch(what, c.recipeID)
	local ok, err = pcall(C_TradeSkillUI.CraftRecipe, c.recipeID, 1, tbl, nil, c.id, conc and true or false)
	if not ok then ns.Print(L["erro ao fabricar: "] .. tostring(err)); ns.Log("fila: erro ao fabricar " .. what .. ": " .. tostring(err)) end
end

function Queue.FulfillOrder(c)
	local prof = ProfEnum(c)
	if not (prof and C_CraftingOrders and C_CraftingOrders.FulfillOrder) then ns.Print(L["abra a profissão para entregar o pedido."]) return end
	ns.Log(string.format("fila: entregando pedido #%s (%s)", tostring(c.id), tostring(c.customer or c.type)))
	Watch("entrega #" .. tostring(c.id))
	local ok, err = pcall(C_CraftingOrders.FulfillOrder, c.id, "", prof)
	if not ok then ns.Print(L["não foi possível entregar: "] .. tostring(err)); ns.Log("fila: erro ao entregar: " .. tostring(err)) end
end

function Queue.ReleaseOrder(c)
	local prof = ProfEnum(c)
	if prof and C_CraftingOrders and C_CraftingOrders.ReleaseOrder then pcall(C_CraftingOrders.ReleaseOrder, c.id, prof) end
	if DB().claimed then DB().claimed[c.id] = nil end
	Queue.Refresh()
end

-- confere com o jogo: pedido que não está mais reivindicado (entregue, expirado, soltou na janela) sai da lista
function Queue.SyncClaimed()
	local cl = DB().claimed
	if not cl or not (C_CraftingOrders and C_CraftingOrders.GetClaimedOrder) then return end
	local ok, cur = pcall(C_CraftingOrders.GetClaimedOrder)
	if ok and cur and cur.orderID and not cl[cur.orderID] then
		-- pego pela janela do jogo: entra na fila também
		local r, e = MyRow(cur.spellID)
		local x = Eval(cur)
		cl[cur.orderID] = { id = cur.orderID, recipeID = cur.spellID, char = ns.CharKey(), prof = e and e.professionID,
			type = ORDER_TYPE[cur.orderType] or "?", customer = cur.customerName, tip = cur.tipAmount or 0, cut = cur.consortiumCut or 0,
			rew = x.rew, profit = x.profit, given = x.given, t = time(), exp = cur.expirationTime, minQ = cur.minQuality,
			concPts = x.concPts, concValue = x.concValue, concFrom = x.concFrom, custR = x.custR }
	end
	for id, c in pairs(cl) do
		if c.exp and c.exp > 0 and c.exp < time() then cl[id] = nil end
	end
end

local of = CreateFrame("Frame")
for _, ev in ipairs({ "CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", "CRAFTINGORDERS_RELEASE_ORDER_RESPONSE", "CRAFTINGORDERS_CLAIM_ORDER_RESPONSE",
	"CRAFTINGORDERS_CLAIMED_ORDER_UPDATED", "CRAFTINGORDERS_CLAIMED_ORDER_REMOVED", "TRADE_SKILL_SHOW" }) do
	pcall(of.RegisterEvent, of, ev)
end
of:SetScript("OnEvent", function(_, ev, a1, a2)
	if not LucroCraftDB then return end
	local cl = DB().claimed or {}
	if ev == "CRAFTINGORDERS_FULFILL_ORDER_RESPONSE" or ev == "CRAFTINGORDERS_RELEASE_ORDER_RESPONSE" then
		-- (resultado, orderID): 0 = ok
		local id = type(a2) == "number" and a2 or nil
		ns.Log(string.format("fila: %s resultado=%s pedido=%s", ev == "CRAFTINGORDERS_FULFILL_ORDER_RESPONSE" and "entrega" or "soltar", tostring(a1), tostring(a2)))
		if id and (a1 == 0 or a1 == nil) then cl[id] = nil
			if ev == "CRAFTINGORDERS_FULFILL_ORDER_RESPONSE" then ns.Print(L["pedido entregue."]) end
		end
	elseif ev == "CRAFTINGORDERS_CLAIMED_ORDER_REMOVED" then
		local ok, cur = pcall(C_CraftingOrders.GetClaimedOrder)
		for id in pairs(cl) do if not (ok and cur and cur.orderID == id) and cl[id].char == ns.CharKey() and cl[id].type ~= ORDER_TYPE[3] and cl[id].type ~= ORDER_TYPE[2] then cl[id] = nil end end
	else
		if ev == "TRADE_SKILL_SHOW" and #Queue.orders > 0 then
			local okP, info = pcall(C_TradeSkillUI.GetChildProfessionInfo)
			local line = okP and info and info.professionID or nil
			if Queue.ordersChar ~= ns.CharKey() or (line and Queue.ordersProf and line ~= Queue.ordersProf) then Queue.orders = {} end
		end
		pcall(Queue.SyncClaimed)
	end
	Queue.Refresh()
end)

-- fabricar uma linha específica da fila (não só a próxima)
function Queue.CraftItem(it)
	if it.order then return Queue.CraftOrder(it.order) end
	local r = it.row
	local alloc, tops
	if it.variant == "mix" and r.mix then alloc, tops = r.mix.alloc, r.mix.top end
	local tbl = ns.Scanner.BuildReagentTbl(r.parts, alloc, tops)
	if not CheckBags(tbl, r.parts, r.name or "?") then return end
	lastCraft = { recipeID = r.recipeID, variant = it.variant }
	Watch(r.name, r.recipeID)
	local ok, err = pcall(C_TradeSkillUI.CraftRecipe, r.recipeID, 1, tbl, nil, nil, it.variant == "conc")
	if not ok then ns.Print(L["erro ao fabricar: "] .. tostring(err)) end
end

-- muda a posição de um item da fila manual (dir = -1 sobe, +1 desce)
function Queue.Move(m, dir)
	local list = DB().list
	for i, q in ipairs(list) do
		if q == m then
			local j = i + dir
			if j >= 1 and j <= #list then list[i], list[j] = list[j], list[i] end
			break
		end
	end
	Queue.Refresh()
end

-- botão "Pegar pedidos": lê a lista; com Shift pega direto o de maior lucro
function Queue.OrdersButton()
	local n, why, known = Queue.ReadOrders()
	if why then ns.Print(why) end
	if n > 0 then ns.Print(string.format(L["%d pedidos lidos, %d de receitas que você sabe."], n, known or 0)) end
	if IsShiftKeyDown() then
		local best = Queue.orders[1]
		if best and best.row and best.profit > 0 then Queue.ClaimOrder(best) else ns.Print(L["nenhum pedido com lucro para pegar."]) end
	end
	Queue.Refresh()
end


-- ===== Versão visual da aba (Royal Revenue) =====
-- Esquerda: fila de fabricação por personagem (ícone, variante, lucro, materiais, +/-).
-- Direita: lista de compras (precisa / tem / comprar / custo), descontando o estoque de todos.
local function VariantItem(r, v)
	if v == "conc" then return r.concItemID or r.itemID end
	if v == "mix" then return (r.mix and r.mix.itemID) or r.concItemID or r.itemID end
	return r.itemID
end

local VARIANT_COLOR = { base = "|cffd9dde3", conc = "|cff66ccff", mix = "|cffd4af37" }

function Queue.Render(cv)
	local V = ns.Visual
	local G = P.FormatGold
	local W = cv:Width()
	local me = ns.CharKey()
	cv:Begin()
	local items = Queue.Build()
	local shopItems = Queue.ShopItems(items)
	local shop, total = Queue.Shopping(shopItems)
	local expected, crafts = 0, 0
	for _, it in ipairs(items) do expected = expected + (it.gold or 0); crafts = crafts + (it.n or 0) end
	local toBuy = 0
	for _, s in ipairs(shop) do if s.buy > 0 then toBuy = toBuy + 1 end end

	-- cartões de resumo
	local y = 4
	local cw = math.floor((W - 24) / 4)
	local function Card(i, title, value, sub)
		local x = (i - 1) * (cw + 8)
		cv:Box(x, y, cw, 50, 0.17, 0.36, 0.66, 0.18)
		cv:Box(x, y, 3, 50, 0.70, 0.13, 0.20, 0.9)
		cv:Text(x + 10, y + 5, "|cffd9dde3" .. title .. "|r", GameFontDisableSmall, cw - 14)
		cv:Text(x + 10, y + 19, value, GameFontNormalLarge, cw - 14)
		if sub then cv:Text(x + 10, y + 37, "|cff9d9d9d" .. sub .. "|r", GameFontDisableSmall, cw - 14) end
	end
	Card(1, L["Lucro previsto da fila"], G(expected, true), string.format(L["%d fabricações"], crafts))
	Card(2, L["Compras"], total > 0 and ("|cffd4af37" .. G(total) .. "|r") or L["|cff55ff55nada a comprar|r"],
		string.format(L["%d itens faltando"], toBuy))
	Card(3, L["Resultado"], G(expected - total, true), L["lucro − compras"])
	Card(4, L["Personagem"], V.ClassName(me, select(2, UnitClass("player"))), L["fabricar próximo usa este"])
	y = y + 60

	-- ===== 3 partes: painel (cartões, acima) · fila (esquerda) · lista de compras (direita) =====
	-- cada parte tem os seus botões e a sua barra de rolagem
	local twoCols = W >= 900
	local LW = twoCols and math.floor(W * 0.56) or W
	local RX = twoCols and (LW + 12) or 0
	local RW = twoCols and (W - RX) or W
	local function Band(c, x, yy, w, title, right)
		c:Box(x, yy, w, 20, 0.08, 0.13, 0.24, 0.95)
		c:Box(x, yy + 19, w, 1, 0.83, 0.69, 0.22, 0.6)
		c:Text(x + 8, yy + 4, "|cffd4af37" .. title .. "|r", GameFontNormalSmall)
		if right then c:Text(x + 8, yy + 4, "|cff9d9d9d" .. right .. "|r", GameFontDisableSmall, w - 16, "RIGHT") end
		return yy + 24
	end
	local viewH = cv.frame:GetHeight()
	local paneH = twoCols and math.max(160, viewH - y - 64) or math.max(140, math.floor((viewH - y - 120) / 2))

	-- ----- fila: título + botões -----
	local qTop = y
	Band(cv, 0, qTop, LW, L["Fila de fabricação"], nil)
	local bx = 130
	local nextLabel = Queue.NextLabel()
	cv:Button(bx, qTop + 24, 200, 22, nextLabel, function()
		Queue.CraftNext()
		C_Timer.After(1.5, Queue.Refresh)
	end, function(tt) tt:SetText(nextLabel); tt:AddLine(L["Fabrica o primeiro item da fila deste personagem (pedidos pegos primeiro)."], 1, 1, 1, true) end)
	cv:Button(bx + 204, qTop + 24, 110, 22, L["Pegar pedidos"], function() Queue.OrdersButton() end, function(tt)
		tt:SetText(L["Pegar pedidos"])
		tt:AddLine(L["Lê os pedidos de fabricação abertos na janela da profissão e mostra o lucro de cada um aqui na fila. Shift+clique: pega direto o de maior lucro."], 1, 1, 1, true)
	end)
	cv:Button(bx + 318, qTop + 24, 100, 22, L["Limpar manuais"], function()
		if IsShiftKeyDown() then Queue.ClearManual() else ns.Print(L["segure Shift e clique para limpar a fila manual."]) end
	end, function(tt) tt:SetText(L["Limpar manuais"]); tt:AddLine(L["Shift+clique: tira tudo o que você adicionou à fila."], 1, 1, 1, true) end)
	local incl = Cfg("queueIncludePlan") and true or false
	cv:Box(8, qTop + 29, 12, 12, 0.83, 0.69, 0.22, incl and 1 or 0.18)
	cv:Text(24, qTop + 28, (incl and "|cffffffff" or "|cff8f8f8f") .. L["incluir plano"] .. "|r", GameFontHighlightSmall, 100)
	cv:Hit(4, qTop + 24, 120, 22, function() LucroCraftDB.config.queueIncludePlan = not incl; Queue.Refresh() end, function(tt)
		tt:SetText(L["incluir plano"]); tt:AddLine(L["Põe na fila as fabricações do Plano de concentração deste personagem."], 1, 1, 1, true)
	end)
	local qc = cv._qList
	if not qc then qc = V.CreateSub(cv); cv._qList = qc end
	qc:Place(0, qTop + 50, LW, paneH)
	qc:Show(); qc:Begin()
	local QW = qc:Width()
	local ly = 0
	if #items == 0 then
		qc:Text(8, ly + 4, L["|cff9d9d9dFila vazia. Use \"+ Fila\" no plano de concentração, o botão direito numa receita ou ative \"incluir plano\".|r"], GameFontHighlightSmall, QW - 16)
		ly = ly + 24
	end
	-- agrupa por personagem
	local groups, order = {}, {}
	for _, it in ipairs(items) do
		if not groups[it.char] then groups[it.char] = {}; table.insert(order, it.char) end
		table.insert(groups[it.char], it)
	end
	table.sort(order, function(a, b) if (a == me) ~= (b == me) then return a == me end return a < b end)
	local ROW = 40
	for _, char in ipairs(order) do
		local list = groups[char]
		local e0 = list[1].e
		qc:Text(8, ly + 2, V.ClassName(char, e0 and e0.class) .. (char == me and L["  |cff55ff55(logado)|r"] or ""), GameFontNormal, QW - 16)
		ly = ly + 20
		for k, it in ipairs(list) do
			local r = it.row
			root.Zebra(qc, k, 0, ly - 2, QW, ROW)
			local id = VariantItem(r, it.variant)
			local q = VariantQuality(r, it.variant)
			qc:Icon(8, ly + 2, 32, V.ItemIcon(id, r.icon), {
				count = tostring(it.n), quality = (q and r.maxQuality and r.maxQuality > 1) and ns.QIcon(q, r.maxQuality, 12) or nil,
				rarity = id and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id) or nil,
				link = id and select(2, C_Item.GetItemInfo(id)) or nil,
				tip = function(tt)
					if id then tt:SetItemByID(id) else tt:SetText(r.name or "?") end
					tt:AddLine(" ")
					tt:AddDoubleLine(L["Fabricações"], tostring(it.n), 1, 0.82, 0, 1, 1, 1)
					tt:AddDoubleLine(L["Lucro previsto"], it.gold and P.FormatMoney(it.gold) or "—", 1, 0.82, 0, 0.3, 1, 0.3)
					tt:AddLine(it.source == "plano" and L["Vem do plano de concentração (desligue \"incluir plano\" para tirar)."]
						or L["Adicionada por você."], 0.6, 0.6, 0.6, true)
				end })
			local vtxt = (VARIANT_COLOR[it.variant] or "") .. (VARIANT_LABEL[it.variant] or it.variant) .. "|r"
			if it.source == "pedido" then
				vtxt = "|cffff9e40" .. L["pedido"] .. " · " .. (it.order.type or "") .. (it.order.customer and (" · " .. it.order.customer) or "") .. "|r"
				if it.char == me then
					local cx = { row = r }
					OrderConc(cx, it.order)
					if cx.unreach then
						vtxt = vtxt .. L[" |cffff5555qualidade mínima inalcançável|r"]
					elseif cx.concPts then
						vtxt = vtxt .. " |cff66ccff" .. ns.ConcStr(cx.concPts, it.e and it.e.professionID)
							.. (cx.concOpt and L[" (opcional)"] or string.format(" (≈%s)", G(cx.concValue or 0))) .. "|r"
						-- pedido pego antes desta versão: o lucro guardado ainda não descontava a concentração
						-- (só quando a concentração é obrigatória; opcional não desconta)
						if not cx.concOpt and not it.order.concValue and it.gold and cx.concValue then it.gold = it.gold - cx.concValue end
					end
				end
				vtxt = vtxt .. (it.order.crafted and (" |cff55ff55" .. L["fabricado, falta entregar"] .. "|r") or "")
			end
			qc:Text(48, ly + 4, r.name or "?", GameFontHighlight, QW - 300)
			qc:Text(48, ly + 21, vtxt .. (it.source == "pedido" and "" or ("  |cff9d9d9d· " .. L[it.source] .. " · " .. (it.e.name or "") .. "|r")), GameFontDisableSmall, QW - 300)
			qc:Text(QW - 244, ly + 6, it.gold and G(it.gold, true) or "|cff9d9d9d—|r", GameFontNormal, 80, "RIGHT")
			-- materiais deste item
			local st = ns.Plan and ns.Plan.Materials and ns.Plan.Materials({ char = it.char, used = { { row = it.parts and { parts = it.parts } or r, crafts = it.n } } })
			local stTxt = not st and "" or (st.state == "ok" or st.state == "warband") and L["|cff55ff55materiais ok|r"]
				or st.state == "alts" and L["|cffffd100nos alts|r"] or string.format(L["|cffff5555faltam %d|r"], st.missing)
			qc:Text(QW - 244, ly + 24, stTxt, GameFontHighlightSmall, 80, "RIGHT")
			local canCraft = it.char == me and it.e and OpenProfessionIDs()[it.e.professionID]
			if it.source == "pedido" then
				local c = it.order
				local lbl = c.crafted and L["Entregar"] or L["Fabricar"]
				qc:Button(QW - 160, ly + 8, 70, 20, lbl, function()
					if c.crafted then Queue.FulfillOrder(c) else Queue.CraftOrder(c) end
				end, function(tt)
					tt:SetText(lbl)
					tt:AddLine(c.crafted and L["Entrega o pedido ao cliente (como o botão da janela de pedidos)."]
						or L["Fabrica o pedido com os materiais do cliente + os seus. Depois aparece Entregar."], 1, 1, 1, true)
					if not canCraft then tt:AddLine(L["Abra a profissão deste personagem."], 1, 0.5, 0.2) end
				end)
				qc:Button(QW - 86, ly + 8, 56, 20, L["Soltar"], function()
					if IsShiftKeyDown() then Queue.ReleaseOrder(c) else ns.Print(L["segure Shift e clique para soltar o pedido."]) end
				end, function(tt) tt:SetText(L["Soltar pedido (Shift+clique)"]) end)
				qc:Button(QW - 26, ly + 8, 22, 20, "x", function() DB().claimed[c.id] = nil; Queue.Refresh() end,
					function(tt) tt:SetText(L["Tirar da fila (o pedido continua com você no jogo)"]) end)
			elseif it.source == "manual" and it.manual then
				local m = it.manual
				qc:Button(QW - 150, ly + 8, 20, 20, "^", function() Queue.Move(m, -1) end, function(tt) tt:SetText(L["Subir na fila"]) end)
				qc:Button(QW - 128, ly + 8, 20, 20, "v", function() Queue.Move(m, 1) end, function(tt) tt:SetText(L["Descer na fila"]) end)
				if canCraft then
					qc:Button(QW - 104, ly + 8, 24, 20, ">", function() Queue.CraftItem(it) end, function(tt) tt:SetText(L["Fabricar este agora (1)"]) end)
				end
				qc:Button(QW - 78, ly + 8, 22, 20, "-", function() Queue.Add(m.char, m.prof, m.recipeID, m.variant, IsShiftKeyDown() and -m.n or -1) end,
					function(tt) tt:SetText(L["-1 (Shift: tira tudo)"]) end)
				qc:Button(QW - 54, ly + 8, 22, 20, "+", function() Queue.Add(m.char, m.prof, m.recipeID, m.variant, IsShiftKeyDown() and 5 or 1) end,
					function(tt) tt:SetText(L["+1 (Shift: +5)"]) end)
				qc:Button(QW - 30, ly + 8, 26, 20, "x", function() Queue.Add(m.char, m.prof, m.recipeID, m.variant, -m.n) end,
					function(tt) tt:SetText(L["Tirar da fila"]) end)
			else
				qc:Text(QW - 80, ly + 10, L["|cff9d9d9dplano|r"], GameFontDisableSmall, 76, "CENTER")
			end
			ly = ly + ROW
		end
		ly = ly + 6
	end

	-- ===== pedidos de fabricação =====
	if Queue.ordersChar and Queue.ordersChar ~= me then Queue.orders = {} end   -- trocou de personagem
	if #Queue.orders > 0 then
		local top = ly + 4
		ly = Band(qc, 0, top, QW, L["Pedidos de fabricação"], string.format(L["lidos há %s · comissão − consórcio + recompensas − seus materiais"],
			Queue.ordersT and (math.floor((time() - Queue.ordersT) / 60) .. " min") or "?") .. "            ")
		qc:Button(QW - 64, top + 1, 60, 18, L["Limpar"], function() Queue.ClearOrders() end, function(tt) tt:SetText(L["Limpar a lista de pedidos lidos"]) end)
		local unknown, k = 0, 0
		for _, x in ipairs(Queue.orders) do if not x.row then unknown = unknown + 1 end end
		-- o jogo só deixa UM pedido reivindicado por vez: com um pego, os outros ficam desabilitados
		local claimedMine = 0
		for _, c in pairs(DB().claimed or {}) do if c.char == me then claimedMine = claimedMine + 1 end end
		local OC = Queue.OrderCols(QW)
		local srt = Queue.OrderSort()
		-- cabeçalho: clique ordena pela coluna
		local function OHead(x0, w, key, label, just)
			local arrow = (srt.key == key) and (srt.desc and " v" or " ^") or ""
			qc:Header(x0, ly, w, 16, "|cffd4af37" .. L[label] .. arrow .. "|r", just or "LEFT",
				{ onClick = function() Queue.SetOrderSort(key) end,
				  tip = function(tt) tt:SetText(L[label]); tt:AddLine(L["Clique: ordenar por esta coluna"], 1, 1, 1) end })
		end
		OHead(OC.item, OC.itemW, "item", "Item")
		OHead(OC.cost, OC.w.cost, "cost", "Custo", "RIGHT")
		qc:Text(OC.reag, ly + 2, "|cffd4af37" .. L["Reagentes"] .. "|r", GameFontNormalSmall, OC.w.reag)
		OHead(OC.reward, OC.w.reward, "reward", "Recompensa")
		OHead(OC.profit, OC.w.profit, "profit", "Lucro", "RIGHT")
		OHead(OC.time, OC.w.time, "time", "Tempo", "RIGHT")
		ly = ly + 18
		Queue.SortOrders(Queue.orders)
		for _, x in ipairs(Queue.orders) do
			if x.row then k = k + 1 end
			if k > 15 then break end
			if x.row then
			local r = x.row
			root.Zebra(qc, k, 0, ly - 2, QW, 34)
			local id = (r and r.itemID) or x.order.itemID
			qc:Icon(OC.item, ly + 2, 28, V.ItemIcon(id, r and r.icon), { link = x.order.outputItemHyperlink, tip = function(tt)
				if x.order.outputItemHyperlink then tt:SetHyperlink(x.order.outputItemHyperlink) elseif id then tt:SetItemByID(id) end
				tt:AddLine(" ")
				tt:AddDoubleLine(L["Tipo"], x.type .. (x.customer and (" · " .. x.customer) or ""), 1, 0.82, 0, 1, 1, 1)
				tt:AddDoubleLine(L["Comissão"], P.FormatMoney(x.tip), 1, 0.82, 0, 0.3, 1, 0.3)
				if x.cut > 0 then tt:AddDoubleLine(L["Corte do consórcio"], "-" .. P.FormatMoney(x.cut), 1, 0.82, 0, 0.9, 0.5, 0.5) end
				for _, rw in ipairs(x.rewList) do
					local nome = (rw.id and C_Item.GetItemNameByID(rw.id))
						or (rw.currency and V.CurrencyName(rw.currency))
						or rw.link or "?"
					tt:AddDoubleLine((rw.n > 1 and (rw.n .. "x ") or "") .. nome, rw.v and P.FormatMoney(rw.v * rw.n) or "?", 1, 1, 1, 0.3, 1, 0.3)
				end
				tt:AddDoubleLine(L["Seus materiais"], "-" .. P.FormatMoney(x.mat) .. (x.miss and " (?)" or ""), 1, 0.82, 0, 0.9, 0.5, 0.5)
				for _, pp in ipairs(x.parts or {}) do
					local p = pp.part
					local nm = C_Item.GetItemNameByID(p.buyItem or p.itemID) or "?"
					tt:AddDoubleLine("   " .. (p.qty or 1) .. "x " .. nm, pp.given and L["|cff55ff55cliente|r"] or (p.unit and P.FormatMoney(p.unit * (p.qty or 1)) or "?"), 0.8, 0.8, 0.8, 1, 1, 1)
				end
				if x.concPts then
					tt:AddDoubleLine(string.format(L["Concentração (%s)"], ns.ConcStr(x.concPts, x.e and x.e.professionID)),
						(x.concOpt and "" or "-") .. P.FormatMoney(x.concValue or 0), 0.4, 0.8, 1, 0.9, 0.5, 0.5)
					tt:AddLine(string.format(L["   %s por ponto: o que a melhor receita (%s) renderia com eles"], P.FormatMoney(x.concPer or 0), x.concFrom or "?"), 0.6, 0.6, 0.6, true)
					if x.concOpt then
						tt:AddLine(L["   Opcional: o pedido aceita a qualidade de baixo, então o lucro acima NÃO desconta esses pontos."], 0.6, 0.6, 0.6, true)
					end
				elseif x.unreach then
					tt:AddLine(L["Nem com concentração chega na qualidade mínima com os reagentes mais baratos."], 1, 0.4, 0.4, true)
				end
				tt:AddDoubleLine(L["Lucro"], P.FormatMoney(math.abs(x.profit)) .. (x.profit < 0 and " (-)" or ""), 1, 0.82, 0, 1, 1, 1)
				if x.minQ and x.minQ > 1 then
					tt:AddLine(string.format(L["Qualidade mínima: %s"], ns.QIcon(x.minQ, 5, 14)), 1, 0.82, 0)
					if x.q0 then tt:AddLine(string.format(L["Sai sem concentração: %s (com os reagentes do cliente + os seus)"], ns.QIcon(x.q0, 5, 14)), 0.7, 0.7, 0.7) end
				end
				if #(x.parts or {}) > 0 then
					local all = true
					for _, pp in ipairs(x.parts) do if not pp.given then all = false end end
					if all then tt:AddLine(L["O cliente mandou todos os materiais."], 0.3, 1, 0.3) end
				end
			end })
			-- Item: ícone + nome (cor da qualidade) e o patrono como subtexto; nada entre os dois
			local nameW = OC.itemW - 36
			local qual = id and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
			local nameCol = "|cffffffff"
			if not r then nameCol = "|cff808080"
			elseif qual and C_Item.GetItemQualityColor then
				local qr, qg, qb = C_Item.GetItemQualityColor(qual)
				nameCol = string.format("|cff%02x%02x%02x", qr * 255, qg * 255, qb * 255)
			end
			qc:Text(OC.item + 34, ly + 2, nameCol .. (r and r.name or (V.ItemName(id) or "?")) .. "|r", GameFontHighlight, nameW)
			qc:Text(OC.item + 34, ly + 18, "|cff9d9d9d" .. (x.customer or x.type)
				.. (r and "" or (" · " .. L["receita que você não sabe"])) .. "|r"
				.. (x.unreach and L["  |cffff5555qualidade inalcançável|r"] or ""), GameFontDisableSmall, nameW)

			-- Custo: o que SAI do seu bolso (os materiais que você fornece)
			qc:Text(OC.cost, ly + 9, (x.mat or 0) > 0 and ("|cffff9e40" .. G(x.mat, true) .. "|r") or "|cff9d9d9d—|r",
				GameFontHighlightSmall, OC.w.cost, "RIGHT")
			qc:Hit(OC.cost, ly, OC.w.cost, 32, nil, function(tt)
				tt:SetText(L["Custo"])
				tt:AddLine(L["Os materiais que VOCÊ fornece, a preço de mercado."], 1, 1, 1, true)
				for _, pp in ipairs(x.parts or {}) do
					local p = pp.part
					tt:AddDoubleLine("   " .. (p.qty or 1) .. "x " .. (V.ItemName(p.buyItem or p.itemID) or "?"),
						pp.given and L["|cff55ff55cliente|r"] or (p.unit and P.FormatMoney(p.unit * (p.qty or 1)) or "?"), 0.8, 0.8, 0.8, 1, 1, 1)
				end
				if x.miss then tt:AddLine(L["(?) algum reagente está sem preço"], 1, 0.6, 0.2, true) end
			end)

			-- Recompensa: comissão líquida + ícones (Moxie, conhecimento, itens), cada um com a quantidade
			local rewTotal = OrderReward(x)
			qc:Text(OC.reward, ly + 1, "|cff55ff55" .. G(rewTotal, true) .. "|r", GameFontHighlightSmall, OC.w.reward)
			qc:Hit(OC.reward, ly, OC.w.reward, 14, nil, function(tt)
				tt:SetText(L["Recompensa"])
				tt:AddDoubleLine(L["Comissão"], P.FormatMoney(x.tip), 1, 0.82, 0, 0.3, 1, 0.3)
				if (x.cut or 0) > 0 then tt:AddDoubleLine(L["Corte do consórcio"], "-" .. P.FormatMoney(x.cut), 1, 0.82, 0, 0.9, 0.5, 0.5) end
				if (x.rew or 0) > 0 then tt:AddDoubleLine(L["Itens de recompensa"], P.FormatMoney(x.rew), 1, 0.82, 0, 0.3, 1, 0.3) end
			end)
			-- recompensa que carregou depois de ler os pedidos: confere de novo se dá conhecimento
			for _, rw in ipairs(x.rewList or {}) do
				if rw.kp == nil and rw.id then
					rw.kp = Queue.KnowledgeOf(rw.link, rw.id)
					if rw.kp then x.kp = (x.kp or 0) + rw.kp * rw.n end
				end
			end
			local rx, rmax = OC.reward, OC.reward + OC.w.reward - 22
			-- o livro só aparece no bônus de PRIMEIRA fabricação desta receita
			if Queue.IsFirstCraft(r) then
				qc:Icon(rx, ly + 14, 20, nil, { atlas = "Professions_Icon_FirstTimeCraft",
					border = { 1, 0.82, 0 }, tip = function(tt)
						tt:SetText(L["Primeira fabricação"])
						tt:AddLine(L["Você ainda não fabricou esta receita: a primeira dá conhecimento extra."], 1, 1, 1, true)
					end })
				rx = rx + 25
			end
			for _, rw in ipairs(x.rewList or {}) do
				if rx > rmax then break end
				-- moeda (Moxie) tem o ícone dela; item fora do cache resolve pelo GetItemIconByID
				-- borda verde = essa recompensa dá conhecimento da profissão
				qc:Icon(rx, ly + 14, 20, rw.icon or V.ItemIcon(rw.id), { count = rw.n > 1 and tostring(rw.n) or nil,
					border = rw.kp and { 0.3, 1, 0.3 } or nil,
					link = rw.link, tip = function(tt)
						if rw.currency then
							if tt.SetCurrencyByID then tt:SetCurrencyByID(rw.currency)
							else tt:SetText(V.CurrencyName(rw.currency) or "?") end
						elseif rw.id then tt:SetItemByID(rw.id)
						elseif rw.link then tt:SetHyperlink(rw.link) end
						tt:AddLine(" ")
						if rw.n > 1 then tt:AddDoubleLine(L["Quantidade"], root.Num(rw.n, 0), 1, 0.82, 0, 1, 1, 1) end
						if rw.kp then tt:AddLine(string.format(L["Dá %d ponto(s) de conhecimento da profissão."], rw.kp * rw.n), 0.3, 1, 0.3) end
						-- moeda não tem preço de AH: a linha só vale para item
						if not rw.currency then
							tt:AddDoubleLine(L["Valor na AH"], rw.v and P.FormatMoney(rw.v * rw.n) or L["vinculado / sem preço"], 1, 0.82, 0, 1, 1, 1)
						end
					end })
				rx = rx + 25
			end

			-- Lucro: recompensa − custo
			qc:Text(OC.profit, ly + 9, G(x.profit, true), GameFontNormal, OC.w.profit, "RIGHT")

			-- Reagentes que VOCÊ fornece, com a quantidade; a concentração entra como mais um
			local gx, gmax = OC.reag, OC.reag + OC.w.reag - 22
			for _, pp in ipairs(x.parts or {}) do
				if gx > gmax then break end
				if not pp.given then
					local p = pp.part
					local pid = p.buyItem or p.itemID
					local need = p.qty or 1
					local have = (ns.Stock and ns.Stock.Usable and ns.Stock.Usable(pid)) or 0
					local falta = have < need
					qc:Icon(gx, ly + 5, 22, V.ItemIcon(pid), { count = tostring(need),
						countColor = falta and { 1, 0.3, 0.3 } or nil,
						link = pid and select(2, C_Item.GetItemInfo(pid)) or nil, tip = function(tt)
							if pid then tt:SetItemByID(pid) end
							tt:AddLine(" ")
							tt:AddDoubleLine(L["Precisa"], tostring(need), 1, 0.82, 0, 1, 1, 1)
							tt:AddDoubleLine(L["Tem"], root.Num(have, 0), 1, 0.82, 0, falta and 1 or 0.3, falta and 0.3 or 1, 0.3)
							if p.unit then tt:AddDoubleLine(L["Custo"], P.FormatMoney(p.unit * need), 1, 0.82, 0, 1, 1, 1) end
						end })
					gx = gx + 26
				end
			end
			-- concentração entra como reagente só quando é OBRIGATÓRIA para a qualidade mínima;
			-- a opcional (o pedido aceita a qualidade de baixo) fica só no tooltip do item
			if x.concPts and not x.concOpt and gx <= gmax then
				-- profissão escaneada sem dados de concentração não tem e.conc
				local est
				if x.e and x.e.conc and ns.Plan and ns.Plan.EstimatedConc then
					local okE, v = pcall(ns.Plan.EstimatedConc, x.e)
					if okE then est = v end
				end
				local faltaC = est and est < x.concPts
				qc:Icon(gx, ly + 5, 22, ns.ConcTexture(x.e and x.e.professionID) or 134400,
					{ count = root.Num(x.concPts, 0), countColor = faltaC and { 1, 0.3, 0.3 } or nil,
					  border = { 0.4, 0.8, 1 }, tip = function(tt)
						tt:SetText(L["Concentração"])
						tt:AddDoubleLine(L["Precisa"], root.Num(x.concPts, 0) .. (x.concEst and " (~)" or ""), 1, 0.82, 0, 1, 1, 1)
						if x.concEst then
							tt:AddLine(L["Estimado pelo scan da profissão: o jogo não calculou a qualidade deste pedido (abra o pedido para o número exato)."], 1, 0.8, 0.3, true)
						end
						if est then tt:AddDoubleLine(L["Tem"], root.Num(math.floor(est), 0), 1, 0.82, 0, faltaC and 1 or 0.3, faltaC and 0.3 or 1, 0.3) end
						if x.concOpt then
							tt:AddLine(L["   Opcional: o pedido aceita a qualidade de baixo, então o lucro acima NÃO desconta esses pontos."], 0.6, 0.6, 0.6, true)
						end
					end })
				gx = gx + 26
			end

			-- Tempo restante
			local left = Queue.OrderTimeLeft(x)
			local tcol = (left and left < 3600) and "|cffff5555" or (left and left < 86400) and "|cffffd100" or "|cff9d9d9d"
			qc:Text(OC.time, ly + 9, tcol .. Queue.ShortTime(left) .. "|r", GameFontDisableSmall, OC.w.time, "RIGHT")

			if r then
				local b = qc:Button(OC.claim, ly + 6, OC.w.claim, 20, L["Pegar pedido"],
					function() if claimedMine == 0 then Queue.ClaimOrder(x) end end, function(tt)
						tt:SetText(L["Pegar pedido"])
						if claimedMine > 0 then
							tt:AddLine(L["Você já tem um pedido pego. Entregue ou largue ele antes de pegar outro."], 1, 0.4, 0.4, true)
						else
							tt:AddLine(L["Reivindica o pedido (como o botão da janela de pedidos) e põe 1 na fila."], 1, 1, 1, true)
						end
					end)
				if claimedMine > 0 and b.Disable then b:Disable() end
			end
			ly = ly + 34
			end
		end
		if unknown > 0 then
			qc:Text(8, ly + 2, "|cff9d9d9d" .. string.format(L["+%d pedidos de receitas que este personagem não sabe (ocultos)"], unknown) .. "|r", GameFontDisableSmall, QW - 16)
			ly = ly + 18
		end
	end

	qc:End(ly + 6)
	local qVis = math.min(ly + 6, paneH)
	qc:Place(0, qTop + 50, LW, math.max(qVis, 40))
	local leftBottom = qTop + 50 + math.max(qVis, 40)

	-- ----- lista de compras: foi para Mercado > Comprar (lá dá para comprar direto e ver se vale fabricar) -----
	local sTop = twoCols and y or (leftBottom + 10)
	Band(cv, RX, sTop, RW, L["Lista de compras"], L["descontando bolsa, banco e banco do bando"])
	local nBuy = 0
	for _, s in ipairs(shop) do if s.buy > 0 then nBuy = nBuy + 1 end end
	local sy = sTop + 30
	if nBuy == 0 then
		cv:Text(RX + 8, sy, L["|cff55ff55Você tem tudo o que a fila e os pedidos precisam.|r"], GameFontHighlight, RW - 16)
		sy = sy + 24
	else
		cv:Text(RX + 8, sy, string.format(L["%d materiais para comprar"], nBuy), GameFontHighlight, RW - 16)
		cv:Text(RX + 8, sy, "|cffd4af37" .. G(total) .. "|r", GameFontNormalLarge, RW - 16, "RIGHT")
		sy = sy + 26
		-- os 5 mais caros, só para ter ideia
		table.sort(shop, function(a, b) return (a.total or 0) > (b.total or 0) end)
		local k = 0
		for _, s in ipairs(shop) do
			if s.buy > 0 then
				k = k + 1
				if k > 5 then break end
				cv:Icon(RX + 8, sy, 18, V.ItemIcon(s.id), { link = select(2, C_Item.GetItemInfo(s.id)) })
				cv:Text(RX + 30, sy + 2, string.format("%dx %s", s.buy, s.name), GameFontHighlightSmall, RW - 150)
				cv:Text(RX + 8, sy + 2, s.total and G(s.total) or L["|cff9d9d9dsem preço|r"], GameFontHighlightSmall, RW - 16, "RIGHT")
				sy = sy + 20
			end
		end
	end
	sy = sy + 6
	cv:Button(RX + 8, sy, 220, 24, L["Comprar em Mercado > Comprar"], function()
		LucroCraftDB.config.buyList = "queue"
		if ns.UI and ns.UI.ShowTab then ns.UI.ShowTab(ns.UI.TAB.BUY) end
	end, function(tt)
		tt:SetText(L["Lista de compras"])
		tt:AddLine(L["A lista da fila e dos pedidos está no topo de Mercado > Comprar: com a casa de leilões aberta, compre item por item e veja se sai mais barato fabricar."], 1, 1, 1, true)
	end)
	sy = sy + 30
	if cv._sList then cv._sList:Hide() end
	cv:End(math.max(leftBottom, sy) + 10)
end

-- comprou/pegou/usou material: a lista de compras da fila e a de Mercado > Comprar se atualizam sozinhas
do
	local f, pend = CreateFrame("Frame"), false
	f:RegisterEvent("BAG_UPDATE_DELAYED")
	f:SetScript("OnEvent", function()
		local fr = LucroCraftFrame
		if pend or not (fr and fr:IsShown() and ns.UI and fr.currentTab) then return end
		local t = fr.currentTab
		if t ~= ns.UI.TAB.QUEUE and t ~= ns.UI.TAB.BUY then return end
		pend = true
		C_Timer.After(1, function()
			pend = false
			if ns.Stock and ns.Stock.Invalidate then ns.Stock.Invalidate() end
			if ns.Buy and ns.Buy._ClearCache and t == ns.UI.TAB.BUY then ns.Buy._ClearCache() end
			if fr:IsShown() and fr.currentTab == t then pcall(ns.UI.RefreshTab, t) end
		end)
	end)
end
