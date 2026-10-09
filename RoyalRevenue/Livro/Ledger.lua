local ADDON, root = ...
local print = function(...) return root.Out(...) end   -- mensagens vão para a aba de log
root.Livro = root.Livro or {}
local ns = root.Livro
ns.root = root
local L = ns.L

-- ===== Livro-caixa =====
-- Tudo que entra e sai do personagem, por dia:
--   atividades (raide, masmorra, imersão, mundo aberto, missões...): ouro + itens recebidos
--   gastos (reparo, vendedor, casa de leilões, voos...) e entradas fora das atividades (vender ao vendedor...)
-- LucroLivroDB.chars[personagem] = { class, days = { ["AAAA-MM-DD"] = { act = {...}, out = {...}, inc = {...} } } }
local Ledger = {}
ns.Ledger = Ledger

local KEEP_DAYS = 90

-- ordem e nomes das atividades / categorias
Ledger.ACTS = {
	{ key = "raid",    name = L["Raide"],               icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
	{ key = "dungeon", name = L["Masmorra"],            icon = "Interface\\Icons\\INV_Misc_Key_03" },
	{ key = "delve",   name = L["Imersão"],             icon = "Interface\\Icons\\INV_Misc_Lantern_01" },
	{ key = "pvp",     name = L["JxJ"],                 icon = "Interface\\Icons\\Achievement_BG_winWSG" },
	{ key = "scenario",name = L["Cenário"],             icon = "Interface\\Icons\\INV_Misc_Map_01" },
	{ key = "wq",      name = L["Missões de mundo"],    icon = "Interface\\Icons\\INV_Misc_Map02" },
	{ key = "daily",   name = L["Diárias"],             icon = "Interface\\Icons\\INV_Misc_Note_01" },
	{ key = "weekly",  name = L["Semanais"],            icon = "Interface\\Icons\\INV_Misc_Note_02" },
	{ key = "event",   name = L["Eventos e objetivos"], icon = "Interface\\Icons\\INV_Misc_Horn_01" },
	{ key = "quest",   name = L["Missões"],             icon = "Interface\\Icons\\INV_Misc_Book_09" },
	{ key = "gather",  name = L["Coleta"],              icon = "Interface\\Icons\\INV_Misc_Herb_01" },
	{ key = "world",   name = L["Mundo aberto"],        icon = "Interface\\Icons\\INV_Misc_Bag_10" },
	{ key = "orders",  name = L["Pedidos de fabricação"], icon = "Interface\\Icons\\INV_Misc_Note_05" },
}
Ledger.OUT = {
	{ key = "repair",   name = L["Reparo"],                                 icon = "Interface\\Icons\\Ability_Repair" },
	{ key = "vendor",   name = L["Compras no vendedor"],                    icon = "Interface\\Icons\\INV_Misc_Bag_07" },
	{ key = "ah",       name = L["Casa de leilões (compras e depósitos)"],  icon = "Interface\\Icons\\INV_Hammer_15" },   -- antigo (antes da v1.19)
	{ key = "ahdep",    name = L["Taxa de depósito da casa de leilões"],    icon = "Interface\\Icons\\INV_Hammer_15" },
	{ key = "ahitem",   name = L["Compras de itens para uso na casa de leilões"], icon = "Interface\\Icons\\INV_Hammer_15" },
	{ key = "ahbuy",    name = L["Material comprado na casa de leilões (estoque)"], icon = "Interface\\Icons\\INV_Hammer_15" },
	{ key = "vendmat",  name = L["Material comprado no vendedor (estoque)"], icon = "Interface\\Icons\\INV_Misc_Bag_07" },
	{ key = "mail",     name = L["Correio (postagem)"],                     icon = "Interface\\Icons\\INV_Letter_15" },
	{ key = "taxi",     name = L["Voos"],                                   icon = "Interface\\Icons\\Ability_Mount_Wyvern_01" },
	{ key = "trainer",  name = L["Treinador"],                              icon = "Interface\\Icons\\INV_Misc_Book_11" },
	{ key = "transmog", name = L["Transmogrificação"],                      icon = "Interface\\Icons\\INV_Chest_Cloth_17" },
	{ key = "barber",   name = L["Barbearia"],                              icon = "Interface\\Icons\\INV_Misc_Comb_01" },
	{ key = "order",    name = L["Pedidos de fabricação"],                  icon = "Interface\\Icons\\INV_Misc_Note_05" },
	{ key = "trade",    name = L["Troca"],                                  icon = "Interface\\Icons\\INV_Misc_Coin_02" },
	{ key = "upgrade",  name = L["Gear Upgrade"],                           icon = "Interface\\Icons\\INV_Misc_EngGizmos_20" },
	{ key = "other",    name = L["Outros gastos"],                          icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}
Ledger.INC = {
	{ key = "vendor",  name = L["Vendas ao vendedor"],                       icon = "Interface\\Icons\\INV_Misc_Coin_01" },
	{ key = "ahsale",  name = L["Vendas na casa de leilões"],                icon = "Interface\\Icons\\INV_Hammer_15" },
	{ key = "order",   name = L["Pedidos de fabricação"],                    icon = "Interface\\Icons\\INV_Misc_Note_05" },
	{ key = "trade",   name = L["Troca"],                                    icon = "Interface\\Icons\\INV_Misc_Coin_02" },
	{ key = "other",   name = L["Outras entradas"],                          icon = "Interface\\Icons\\INV_Misc_Coin_04" },
}
Ledger.XFER = { key = "xfer", name = L["Transferências (bancos, correio entre personagens)"], icon = "Interface\\Icons\\INV_Misc_Bag_EnchantedMageweave" }

-- ===== Plano de contas =====
-- 3 Receitas: 3.1 atividades (ouro) · 3.2 atividades (itens a valor de mercado) · 3.3 comerciais
-- 4 Despesas: 4.1 manutenção · 4.2 logística · 4.3 compras · 4.4 taxas e serviços · 4.9 outras
-- 5 Movimentações não operacionais (transferências entre bancos/personagens): não entram no resultado
local OUT_CODE = { repair = "4.1.01", taxi = "4.2.01", vendor = "4.3.01", ah = "4.3.02", ahitem = "4.3.03", mail = "4.4.01", trainer = "4.4.02",
	transmog = "4.4.03", barber = "4.4.04", order = "4.4.05", trade = "4.4.06", ahdep = "4.4.07", upgrade = "4.6.01", other = "4.9.01",
	ahbuy = "5.4.01", vendmat = "5.4.02" }
local INC_CODE = { ahsale = "3.3.01", vendor = "3.3.02", order = "3.3.03", trade = "3.3.04", other = "3.3.09" }
-- DRE (v1.19):
--   Receita bruta (3.1/3.2 atividades, 3.3 comerciais) − Deduções (comissão da AH 5%) = Receita líquida
--   − CPV (4.0: material gasto ao fabricar, comprado ou coletado, a valor de mercado) = Lucro bruto
--   − Despesas operacionais (grupos abaixo) = Resultado operacional (EBIT) = Lucro líquido
-- Material comprado (AH commodity, reagente no vendedor) vai para o estoque (5.4): sai do caixa, mas só vira
-- custo quando é gasto num craft. O "ah" antigo (compras + depósitos misturados, antes da v1.19) fica no CPV.
Ledger.GROUPS = {
	{ code = "4.1", name = L["Manutenção"], keys = { "repair" } },
	{ code = "4.2", name = L["Logística"], keys = { "taxi" } },
	{ code = "4.3", name = L["Compras para uso"], keys = { "vendor", "ahitem" } },
	{ code = "4.4", name = L["Taxas e serviços"], keys = { "ahdep", "mail", "trainer", "transmog", "barber", "order", "trade" } },
	{ code = "4.5", name = L["Consumíveis usados"], consum = true, keys = {} },
	{ code = "4.6", name = L["Gear Upgrade"], keys = { "upgrade" } },
	{ code = "4.9", name = L["Outras despesas"], keys = { "other" } },
}
Ledger.STOCK_KEYS = { "ahbuy", "vendmat" }
Ledger.CPV_ORDERS, Ledger.CPV_CRAFT = "4.0.01", "4.0.02"
local ACT_INDEX = {}
for i, a in ipairs(Ledger.ACTS) do ACT_INDEX[a.key] = i end
local function Code2(n) return (n < 10 and "0" or "") .. n end
function Ledger.ActCode(key, items) return (items and "3.2." or "3.1.") .. Code2(ACT_INDEX[key] or 99) end
function Ledger.OutCode(key) return OUT_CODE[key] or "4.9.01" end
function Ledger.IncCode(key) return INC_CODE[key] or "3.3.09" end
Ledger.XIN_CODE, Ledger.XOUT_CODE = "5.1.01", "5.2.01"
-- 9 Ajustes: diferença de caixa identificada no login (sessão anterior não salva, ex.: o jogo travou)
Ledger.ADJ_CODE = "9.1.01"

-- nome de uma conta pelo código (para o Diário)
local NAMES
function Ledger.AccountName(code)
	if not NAMES then
		NAMES = { [Ledger.XIN_CODE] = L["Transferências recebidas"], [Ledger.XOUT_CODE] = L["Transferências enviadas"],
			[Ledger.ADJ_CODE] = L["Ajuste de conciliação"], ["4.9.02"] = L["Uso (melhorias, chaves, custos)"],
			[Ledger.CONV_CODE] = L["Conversão de moeda"], ["5.3.02"] = L["Conversão de itens (desencantar)"],
			["4.5.01"] = L["Consumíveis usados (custo de reposição)"],
			["4.5.02"] = L["Materiais próprios em pedidos de fabricação"],
			["4.0.01"] = L["Material gasto em pedidos de fabricação"], ["4.0.02"] = L["Material gasto na fabricação própria"] }
		for _, a in ipairs(Ledger.ACTS) do
			NAMES[Ledger.ActCode(a.key)] = a.name .. " · " .. L["ouro"]
			NAMES[Ledger.ActCode(a.key, true)] = a.name .. " · " .. L["itens"]
		end
		for _, o in ipairs(Ledger.OUT) do NAMES[Ledger.OutCode(o.key)] = o.name end
		for _, o in ipairs(Ledger.INC) do NAMES[Ledger.IncCode(o.key)] = o.name end
	end
	return NAMES[code] or code
end

-- "Nome-Reino" do personagem logado (não muda na sessão: guardado assim que o jogo informa nome e reino)
local charKey
function ns.CharKey()
	if charKey then return charKey end
	local name, realm = UnitFullName("player")
	local r = realm or GetNormalizedRealmName() or GetRealmName()
	local k = (name or "?") .. "-" .. (r or "?")
	if name and r and r ~= "" then charKey = k end
	return k
end
function ns._ResetCharKey() charKey = nil end   -- testes fora do jogo

local function Today() return date("%Y-%m-%d") end

local function CharDB()
	LucroLivroDB.chars = LucroLivroDB.chars or {}
	local k = ns.CharKey()
	local c = LucroLivroDB.chars[k]
	if not c then
		c = { days = {} }
		LucroLivroDB.chars[k] = c
	end
	c.class = select(2, UnitClass("player"))
	return c
end

local function Day()
	local c = CharDB()
	local d = Today()
	local day = c.days[d]
	if not day then
		day = { act = {}, out = {}, inc = {}, xin = 0, xout = 0, adj = 0, time = {} }
		c.days[d] = day
	end
	-- v2: dia registrado com o controle de consumo (compra de material = estoque; consumíveis na DRE).
	-- Começa no dia seguinte à instalação da v1.19 (o dia da troca tem crafts sem registro de consumo).
	if day.v2 == nil and LucroLivroDB.v2From and d >= LucroLivroDB.v2From then day.v2 = true end
	day.time = day.time or {}
	if not day.cashOpen then day.cashOpen = GetMoney() end
	return day
end

local JOURNAL_DAYS, JOURNAL_MAX = 45, 5000
local function Prune()
	local cutoff = date("%Y-%m-%d", time() - KEEP_DAYS * 86400)
	local jcut = time() - JOURNAL_DAYS * 86400
	for _, c in pairs(LucroLivroDB.chars or {}) do
		for d in pairs(c.days or {}) do if d < cutoff then c.days[d] = nil end end
		local j = c.journal
		if j then
			local keep = {}
			for _, e in ipairs(j) do if e.t >= jcut then table.insert(keep, e) end end
			while #keep > JOURNAL_MAX do table.remove(keep, 1) end
			c.journal = keep
		end
	end
end

-- ===== Livro Diário: um lançamento por movimento (data, conta, histórico, valor) =====
-- v > 0 = entrada (receita), v < 0 = saída (despesa); cash = movimentou ouro (regime de caixa)
local function Post(code, hist, v, cash, itemID, qty)
	local c = CharDB()
	c.journal = c.journal or {}
	table.insert(c.journal, { t = time(), a = code, h = hist, v = v, c = cash and 1 or nil, i = itemID, q = qty })
	if #c.journal > JOURNAL_MAX + 200 then Prune() end
end
Ledger.Post = Post

-- Na Midnight alguns valores chegam "secretos" para addons (ex.: nome do NPC, textos em combate):
-- comparar ou concatenar dá erro. Safe() devolve nil nesses casos.
local function Safe(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end
Ledger.Safe = Safe

local function Npc()
	local n = Safe(UnitName and UnitName("npc"))
	return (type(n) == "string" and n ~= "") and n or nil
end

-- ===== contexto: onde o personagem está =====
local function MapName()
	local id = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local info = id and C_Map.GetMapInfo(id)
	return Safe(info and info.name) or Safe(GetZoneText()) or "?"
end

function Ledger.Context()
	local inInst, itype = IsInInstance()
	if inInst then
		local name, _, diffID, diffName = GetInstanceInfo()
		name, diffID, diffName = Safe(name), Safe(diffID), Safe(diffName)
		local sub = (name or "?") .. ((diffName and diffName ~= "") and (" · " .. diffName) or "")
		if itype == "raid" then
			-- lair / chefe de mundo: instância de raide com dificuldade "Mundo" (faz parte de missão de mundo/evento)
			local dn = type(diffName) == "string" and diffName or ""
			if dn:find("World") or dn:find("Mundo") or dn:find("Mundial") then return "event", sub end
			return "raid", sub
		end
		if itype == "party" then return "dungeon", sub end
		if itype == "scenario" then
			local delve = diffID == 208 or (C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress())
			return delve and "delve" or "scenario", sub
		end
		if itype == "pvp" or itype == "arena" then return "pvp", sub end
	end
	return "world", MapName()
end

-- ===== registro =====
local function Act(day, key, sub)
	local a = day.act[key]
	if not a then a = { gold = 0, items = {}, n = 0, sub = {} }; day.act[key] = a end
	a.cur = a.cur or {}
	if sub then
		local s = a.sub[sub]
		if not s then s = { gold = 0, items = {}, n = 0 }; a.sub[sub] = s end
		s.cur = s.cur or {}
		return a, s
	end
	return a
end

function Ledger.AddGold(key, sub, copper, hist)
	if not copper or copper == 0 then return end
	local a, s = Act(Day(), key, sub)
	a.gold = a.gold + copper
	if s then s.gold = s.gold + copper end
	Post(Ledger.ActCode(key), hist or sub or "", copper, true)
end

function Ledger.AddItem(key, sub, itemID, qty, vendorOnly)
	local d = Day()
	local a, s = Act(d, key, sub)
	local unit = ns.P.Value(itemID, vendorOnly)
	-- recompensa avaliada pelo vendedor: o painel e a DRE também usam o vendedor para este item
	if vendorOnly then
		LucroLivroDB.vendorItems = LucroLivroDB.vendorItems or {}
		LucroLivroDB.vendorItems[itemID] = true
	end
	a.items[itemID] = (a.items[itemID] or 0) + qty
	if s then s.items[itemID] = (s.items[itemID] or 0) + qty end
	Post(Ledger.ActCode(key, true), sub or "", unit and unit * qty or 0, false, itemID, qty)
	-- de onde veio (fila por item): se for vendido ao vendedor, o valor real substitui o estimado
	local cr = CharDB()
	cr.recv = cr.recv or {}
	local rl = cr.recv[itemID] or {}
	table.insert(rl, { d = Today(), k = key, s = sub, q = qty })
	while #rl > 50 do table.remove(rl, 1) end
	cr.recv[itemID] = rl
	-- baú, cofre, caixa de recompensa (ou item sem valor): guarda de onde veio para o conteúdo, ao abrir,
	-- ir para a mesma atividade (o baú sai e o conteúdo entra no lugar dele)
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	if not unit or (classID == 15 and subClassID ~= 2 and subClassID ~= 5) then
		for _ = 1, math.min(qty, 20) do Ledger.RememberOrigin(itemID, key, sub, unit) end
	end
	-- consumível ganho (caldeirão da raide, recompensa, saque): quando for usado, não é custo
	if classID == 0 then
		local c = CharDB()
		c.free = c.free or {}
		c.free[itemID] = (c.free[itemID] or 0) + qty
	end
end

-- moedas (Remnant, cristas, chaves...): não têm preço em ouro, entram como quantidade na atividade
function Ledger.AddCurrency(key, sub, currencyID, qty)
	local a, s = Act(Day(), key, sub)
	a.cur[currencyID] = (a.cur[currencyID] or 0) + qty
	if s then s.cur[currencyID] = (s.cur[currencyID] or 0) + qty end
	local c = CharDB()
	c.journal = c.journal or {}
	table.insert(c.journal, { t = time(), a = Ledger.ActCode(key, true), h = sub or "", v = 0, m = currencyID, q = qty })
end

-- ===== mover um lançamento de itens/moeda de atividade =====
-- key = nova atividade (sub = detalhe); key = nil: vira conversão de itens (fora do resultado)
Ledger.ITEMCONV_CODE = "5.3.02"
local function KeyFromCode(code)
	local n = tonumber(tostring(code or ""):match("^3%.2%.(%d+)$"))
	return n and Ledger.ACTS[n] and Ledger.ACTS[n].key or nil
end
function Ledger.MoveEntry(c, e, key, sub, hist)
	local oldKey = KeyFromCode(e.a)
	if not oldKey or e.c then return false end
	local field, id = e.i and "items" or "cur", e.i or e.m
	if not id or not e.q then return false end
	local day = c.days and c.days[root.DayKey(e.t)]
	if day and day.act then
		local function dec(t)
			if t and t[field] and t[field][id] then
				t[field][id] = t[field][id] - e.q
				if t[field][id] <= 0 then t[field][id] = nil end
			end
		end
		local a = day.act[oldKey]
		if a then dec(a); dec(a.sub and a.sub[e.h or ""]) end
		if key then
			local na, nsub = Act(day, key, sub)
			na[field][id] = (na[field][id] or 0) + e.q
			if nsub then nsub[field][id] = (nsub[field][id] or 0) + e.q end
		elseif e.i then
			day.itemConv = day.itemConv or {}
			day.itemConv[e.i] = (day.itemConv[e.i] or 0) + e.q
		end
	end
	if key then
		e.a, e.h = Ledger.ActCode(key, true), sub or ""
	else
		e.a, e.h, e.x, e.v = Ledger.ITEMCONV_CODE, hist or L["Desencantar"], e.v, 0
	end
	return true
end

-- materiais de uma transformação (Desencantar): o item de origem já foi contado quando você o ganhou,
-- então os materiais não são receita; ficam registrados como conversão (valor só informativo em e.x)
function Ledger.ItemConv(itemID, qty, hist)
	local d = Day()
	d.itemConv = d.itemConv or {}
	d.itemConv[itemID] = (d.itemConv[itemID] or 0) + qty
	local unit = ns.P.Value(itemID)
	local c = CharDB()
	c.journal = c.journal or {}
	table.insert(c.journal, { t = time(), a = Ledger.ITEMCONV_CODE, h = hist or L["Desencantar"], v = 0,
		x = unit and math.floor(unit * qty + 0.5) or nil, i = itemID, q = qty })
end

-- ===== baús de recompensa: o conteúdo vai para a atividade que deu o baú =====
-- c.origins[itemID] = lista (fila) de { k = atividade, s = detalhe, t = quando recebeu }; 14 dias
function Ledger.RememberOrigin(itemID, key, sub, unit)
	local c = CharDB()
	c.origins = c.origins or {}
	local list = c.origins[itemID] or {}
	table.insert(list, { k = key, s = sub, t = time(), d = Today(), v = unit })
	while #list > 20 do table.remove(list, 1) end
	c.origins[itemID] = list
end

function Ledger.TakeOrigin(itemID)
	local c = CharDB()
	local list = c.origins and c.origins[itemID]
	if not list then return nil end
	local cut = time() - 14 * 86400
	while list[1] and list[1].t < cut do table.remove(list, 1) end
	local o = table.remove(list, 1)
	if #list == 0 then c.origins[itemID] = nil end
	return o
end

-- uma ocorrência (missão entregue, chefe saqueado...) para contar quantas vezes
function Ledger.Count(key, sub)
	local a, s = Act(Day(), key, sub)
	a.n = a.n + 1
	if s then s.n = s.n + 1 end
end

local open = {}   -- janelas abertas (vendedor, AH, correio...)

-- Confere com o jogo se a interação ainda está aberta (C_PlayerInteractionManager). Se o evento de
-- fechamento não chegar (outro addon substituindo a janela, por exemplo), a marca não fica presa
-- e o ouro de saque/missão não vira "venda na casa de leilões".
local INTERACT = {
	merchant = { "Merchant" }, mail = { "MailInfo" }, ah = { "Auctioneer" }, taxi = { "TaxiNode" },
	trainer = { "Trainer", "ProfessionsTrainer" }, bank = { "Banker", "AccountBanker", "CharacterBanker" },
	gbank = { "GuildBanker" }, transmog = { "Transmogrifier" }, barber = { "Barber" }, trade = { "TradePartner" },
	order = { "ProfessionsCustomerOrder", "CraftingOrder" },
}
local FRAMES = { merchant = "MerchantFrame", mail = "MailFrame", ah = "AuctionHouseFrame", taxi = "FlightMapFrame",
	trainer = "ClassTrainerFrame", bank = "BankFrame", gbank = "GuildBankFrame", transmog = "TransmogFrame",
	barber = "BarberShopFrame", trade = "TradeFrame", order = "ProfessionsCustomerOrdersFrame" }
local function RefreshOpen()
	local api = C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType
	if not api then return end
	local PIT = Enum and Enum.PlayerInteractionType
	if not PIT then return end
	for kind, names in pairs(INTERACT) do
		if open[kind] then
			local any, known = false, false
			for _, n in ipairs(names) do
				local t = PIT[n]
				if t then known = true end
				local ok, r = false, nil
				if t then ok, r = pcall(api, t) end
				if ok and r then any = true end
			end
			-- só desmarca se o jogo diz que não há interação E a janela padrão também não está aberta
			local fr = _G[FRAMES[kind] or ""]
			local shown = fr and fr.IsShown and fr:IsShown()
			if known and not any and not shown then open[kind] = nil end
		end
	end
end
Ledger.RefreshOpen = RefreshOpen

-- ===== Rateio do reparo (centro de custo) =====
-- O desgaste do equipamento é medido pelo custo de reparo que o jogo informa em cada peça (tooltip.repairCost).
-- Cada aumento do custo (morte, combate) é anotado na atividade onde aconteceu (c.wear["atividade|detalhe"]).
-- Quando o reparo é pago, o valor é rateado entre essas atividades na proporção do desgaste de cada uma;
-- o que não tem origem conhecida (desgaste de antes do addon) fica como reparo geral.
local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17 }
local wearLast            -- custo de reparo total na última leitura
local wearCtx             -- atividade no momento da última perda de durabilidade
local wearPending = false

-- Desgaste = durabilidade perdida (fração de cada peça, x1000). O custo de reparo do tooltip vem
-- escondido dentro de instância na Midnight; a durabilidade continua legível.
local function RepairEstimate()
	if not GetInventoryItemDurability then return nil end
	local total, any = 0, false
	for _, slot in ipairs(SLOTS) do
		local cur, max = GetInventoryItemDurability(slot)
		cur, max = Safe(cur), Safe(max)
		if type(cur) == "number" and type(max) == "number" and max > 0 then
			total = total + (max - cur) / max
			any = true
		end
	end
	return any and total * 1000 or nil
end
local repairLoss   -- desgaste no momento do clique em "reparar tudo"

local function WearKey(k, s) return k .. "|" .. (s or "") end

-- saídas "outros gastos" recentes (reparo por diálogo, ex.: NPC de reparo sem janela de vendedor)
local otherOut = {}
local repairDialogUntil = 0

local function ReadWear()
	wearPending = false
	local now = RepairEstimate()
	if not now then return end
	local c = CharDB()
	if c.wearV ~= 2 then c.wear = {}; c.wearV = 2 end   -- v0.5.1: unidade mudou (durabilidade)
	c.wear = c.wear or {}
	if wearLast and now > wearLast and wearCtx then
		local key = WearKey(wearCtx.k, wearCtx.s)
		c.wear[key] = (c.wear[key] or 0) + (now - wearLast)
	elseif wearLast and now < wearLast and not open.merchant then
		-- durabilidade voltou sem janela de vendedor: se houve pagamento junto, foi reparo por diálogo
		-- (NPC de reparo); senão, banco da guilda ou troca de peça (reduz o desgaste na mesma proporção)
		local before, after = wearLast, now
		C_Timer.After(1.5, function() pcall(Ledger.RepairByDialog, before, after) end)
	end
	wearLast = now
end

-- perdeu durabilidade: guarda onde estava e lê o custo fora de combate (tooltips podem vir protegidos)
local function OnDurability()
	local k, s = Ledger.Context()
	wearCtx = { k = k, s = s }
	if InCombatLockdown and InCombatLockdown() then wearPending = true return end
	ReadWear()
end
Ledger.ReadWear = ReadWear

-- reparo pago: rateia entre as atividades que causaram o desgaste
local function AllocateRepair(copper)
	local c = CharDB()
	c.wear = c.wear or {}
	local total = 0
	for _, v in pairs(c.wear) do total = total + v end
	local alloc = {}
	local cur = repairLoss or wearLast
	repairLoss = nil
	if total > 0 then
		-- parte do desgaste com origem conhecida (o resto é de antes do registro)
		local known = (cur and cur > 0) and math.min(1, total / cur) or 1
		local base = copper * known
		for key, v in pairs(c.wear) do
			local part = base * v / total
			local k, sname = key:match("^([^|]*)|(.*)$")
			table.insert(alloc, { k = k, s = (sname ~= "" and sname or nil), v = part })
			c.wear[key] = v - part
			if c.wear[key] < 1 then c.wear[key] = nil end
		end
	elseif IsInInstance and IsInInstance() then
		-- sem medição: reparo feito dentro da instância vai para ela
		local k, sname = Ledger.Context()
		table.insert(alloc, { k = k, s = sname, v = copper })
	end
	wearLast = nil   -- próxima leitura recomeça do valor reparado
	C_Timer.After(1, function() pcall(ReadWear) end)
	return alloc
end

function Ledger.RepairByDialog(before, after)
	local list = {}
	for i = #otherOut, 1, -1 do
		if GetTime() - otherOut[i].t < 4 then table.insert(list, table.remove(otherOut, i)) end
	end
	local c = CharDB()
	if #list > 0 then
		local total = 0
		for _, o in ipairs(list) do
			o.d.out.other = math.max(0, (o.d.out.other or 0) - o.v)
			for j = #(c.journal or {}), 1, -1 do
				if c.journal[j] == o.e then table.remove(c.journal, j) break end
			end
			total = total + o.v
		end
		repairDialogUntil = GetTime() + 3
		Ledger.RepairNow(total, before)
		return
	end
	if GetTime() < repairDialogUntil then return end
	c.wear = c.wear or {}
	local f = before > 0 and (after / before) or 0
	for key, v in pairs(c.wear) do
		c.wear[key] = v * f
		if c.wear[key] < 1 then c.wear[key] = nil end
	end
end

local function Out(cat, copper)
	local d = Day()
	d.out[cat] = (d.out[cat] or 0) + copper
	if cat == "repair" then
		local alloc = AllocateRepair(copper)
		local used = 0
		for _, a in ipairs(alloc) do
			local act, s = Act(d, a.k, a.s)
			act.cost = act.cost or {}
			act.cost.repair = (act.cost.repair or 0) + a.v
			if s then s.cost = s.cost or {}; s.cost.repair = (s.cost.repair or 0) + a.v end
			used = used + a.v
			local def
			for _, x in ipairs(Ledger.ACTS) do if x.key == a.k then def = x end end
			Post(Ledger.OutCode(cat), L["Rateio"] .. " · " .. (def and def.name or a.k) .. (a.s and (" · " .. a.s) or ""), -math.floor(a.v + 0.5), true)
		end
		local rest = copper - math.floor(used + 0.5)
		if rest > 0 then Post(Ledger.OutCode(cat), (Npc() or "") .. (used > 0 and (" · " .. L["sem origem"]) or ""), -rest, true) end
		return
	end
	Post(Ledger.OutCode(cat), Npc() or "", -copper, true)
end
function Ledger.RepairNow(copper, lossBefore)
	repairLoss = lossBefore
	Out("repair", copper)
end

local function Inc(cat, copper)
	local d = Day()
	d.inc[cat] = (d.inc[cat] or 0) + copper
	Post(Ledger.IncCode(cat), Npc() or "", copper, true)
end
local function Xfer(copper)   -- + recebido, - enviado
	local d = Day()
	if copper > 0 then d.xin = d.xin + copper else d.xout = d.xout - copper end
	Post(copper > 0 and Ledger.XIN_CODE or Ledger.XOUT_CODE, "", copper, true)
end

-- ===== onde está o personagem (janelas abertas) =====
local OPEN_EVENTS = {
	MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
	AUCTION_HOUSE_SHOW = { "ah", true }, AUCTION_HOUSE_CLOSED = { "ah", false },
	MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
	TAXIMAP_OPENED = { "taxi", true }, TAXIMAP_CLOSED = { "taxi", false },
	TRAINER_SHOW = { "trainer", true }, TRAINER_CLOSED = { "trainer", false },
	TRANSMOGRIFY_OPEN = { "transmog", true }, TRANSMOGRIFY_CLOSE = { "transmog", false },
	BARBER_SHOP_OPEN = { "barber", true }, BARBER_SHOP_CLOSE = { "barber", false },
	TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
	GUILDBANKFRAME_OPENED = { "gbank", true }, GUILDBANKFRAME_CLOSED = { "gbank", false },
	BANKFRAME_OPENED = { "bank", true }, BANKFRAME_CLOSED = { "bank", false },
	CRAFTINGORDERS_SHOW_CUSTOMER = { "order", true }, CRAFTINGORDERS_HIDE_CUSTOMER = { "order", false },
	CRAFTINGORDERS_SHOW_CRAFTER = { "order", true }, CRAFTINGORDERS_HIDE_CRAFTER = { "order", false },
}

-- ===== casa de leilões: o que foi esse gasto? (marcado pelos ganchos de postar/comprar) =====
local ahMark, ahMarkAt, vendMatAt = nil, 0, 0
-- gasto com um NPC específico vai sempre para a mesma conta (LucroLivroDB.config.npcCat pode acrescentar)
Ledger.NPC_CAT = { ["Cuzolth"] = "upgrade" }
local function NpcCat()
	local n = Npc()
	if not n then return nil end
	local cfg = LucroLivroDB.config and LucroLivroDB.config.npcCat
	return (cfg and cfg[n]) or Ledger.NPC_CAT[n]
end

local function AhKind()
	if ahMark and GetTime() - ahMarkAt < 15 then return ahMark end
	return "ahbuy"
end

-- ===== ouro =====
local lastMoney
local checked = false                    -- conferência de ajuste do login já feita
local pending = { gain = 0, ctx = nil, sub = nil }
local questMoney, questUntil = 0, 0      -- ouro de missão já lançado (não contar de novo)
local mailKind                           -- "ahsale" ou "xfer" para o próximo ouro tirado do correio
local repairCost                         -- custo informado pelo jogo ao clicar em reparar tudo
local lastQuest, lastQuestAt = nil, 0
local lootOrigin, lootOriginUntil = nil, 0   -- baú aberto agora: atividade de onde ele veio
local lootOriginItem
local orderUntil = 0                     -- entregou um pedido de fabricação agora (artesão)
local deUntil = 0                        -- acabou de desencantar: o saque são os materiais (conversão)
local moxieUntil = 0                     -- chegou Moxie agora: recompensa de pedido (itens junto vão para os pedidos)
local moxieBuy, merchLoot                -- comprou algo com Moxie no vendedor (baú de reagentes)
local recentLoose = {}                   -- itens lançados agora em Mundo aberto/Coleta (podem ser de um pedido)
local MOXIE_IDS = { [3256] = true, [3258] = true, [3261] = true, [3262] = true, [3266] = true }
local moxieCache = {}
local function IsMoxie(id)
	if not id then return false end
	if moxieCache[id] ~= nil then return moxieCache[id] end
	local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
	local name = info and Safe(info.name)
	local v = MOXIE_IDS[id] or (type(name) == "string" and name:find("Moxie") ~= nil) or false
	moxieCache[id] = v
	return v
end
Ledger.IsMoxie = IsMoxie
-- Correio: só conta como venda/transferência o ouro que chega logo depois de tirar dinheiro/itens da
-- caixa (ou enviar). Um "correio aberto" preso (fechado pelo TSM sem aviso) não vira mais venda na AH.
local mailAt = -100
local function MailBusy() return GetTime() - mailAt < 5 end
-- Correio aberto: o flag do MAIL_SHOW (conferido por RefreshOpen e limpo em tela de carregamento/combate)
-- ou um clique recente na caixa. O TSM abre as cartas sem passar pelos ganchos, por isso o flag também vale.
local function MailOpen() return open.mail or MailBusy() end

-- Recompensas de pedidos de fabricação (pedidos de NPC) chegam pelo correio. Ao abrir a caixa, anota
-- quais itens vêm dessas cartas: quando eles entram na bolsa, são receita de "Pedidos de fabricação".
local mailOrder = { items = {}, any = false, seller = false }
local ORDER_WORDS = { "Crafting Order", "Pedido de fabrica", "Artisan", "Artesã", "Patron", "Patrono", "Consortium", "Consórcio" }
local function IsOrderMail(i, sender, subject)
	if C_Mail and C_Mail.GetCraftingOrderMailInfo then
		local ok, info = pcall(C_Mail.GetCraftingOrderMailInfo, i)
		if ok and info then return true end
	end
	local text = (Safe(sender) or "") .. " " .. (Safe(subject) or "")
	for _, w in ipairs(ORDER_WORDS) do if text:find(w, 1, true) then return true end end
	return false
end
local function ScanInbox()
	mailOrder = { items = {}, any = false, seller = false }
	if not (GetInboxNumItems and GetInboxHeaderInfo) then return end
	for i = 1, GetInboxNumItems() do
		local _, _, sender, subject, money, _, _, itemCount = GetInboxHeaderInfo(i)
		if GetInboxInvoiceInfo and (money or 0) > 0 then
			local inv = GetInboxInvoiceInfo(i)
			if inv == "seller" then mailOrder.seller = true end
		end
		if IsOrderMail(i, sender, subject) then
			mailOrder.any = true
			for j = 1, (itemCount or 0) do
				local _, itemID, _, count = GetInboxItem(i, j)
				if itemID then mailOrder.items[itemID] = (mailOrder.items[itemID] or 0) + (count or 1) end
			end
		end
	end
end
Ledger.ScanInbox = ScanInbox
local GOLD_WINDOW = 10                   -- ouro que chega até 10 s depois de entregar missão é da missão

-- atribuição de um ganho (item, moeda, ouro) que chegou agora
local function Attribution(window)
	if lootOrigin and GetTime() < lootOriginUntil then return lootOrigin.k, lootOrigin.s, true, "chest" end
	if GetTime() < orderUntil then return "orders", nil, true, "order" end
	if GetTime() < moxieUntil then return "orders", L["Recompensas de pedidos"], true, "order" end
	if lastQuest and GetTime() - lastQuestAt < (window or 3) then return lastQuest.kind, lastQuest.sub, true, "quest" end
	local ctx, sub = Ledger.Context()
	if ctx == "world" then
		local k, t = Ledger.WeeklyHere()
		if k then return k, t, true end
	end
	return ctx, sub, false
end

local function FlushGain()
	local g = pending.gain
	pending.gain = 0
	if GetTime() < questUntil then
		local use = math.min(g, questMoney)
		g, questMoney = g - use, questMoney - use
	end
	if g > 0 then
		-- ouro de um baú de recompensa vai para a atividade que deu o baú
		if pending.origin then
			Ledger.AddGold(pending.origin.k, pending.origin.s, g, L["Baú"] .. " · " .. (pending.origin.s or ""))
		elseif pending.src == "quest" then
			Ledger.AddGold(pending.ctx, pending.sub, g, L["Recompensa"] .. " · " .. (pending.title or pending.sub or ""))
		else
			-- ouro sem janela aberta = saque da atividade atual (mob, chefe)
			Ledger.AddGold(pending.ctx or "world", pending.sub, g, L["Saque"] .. " · " .. (pending.sub or ""))
		end
	end
	pending.origin, pending.src, pending.title = nil, nil, nil
end

local function OnMoney()
	RefreshOpen()
	local now = GetMoney()
	-- antes da conferência do login o ouro ainda pode estar "carregando": só acompanha o valor
	if not checked then lastMoney = now return end
	Day().cashClose = now
	if checked then CharDB().lastMoney = now end
	if not lastMoney then lastMoney = now return end
	local delta = now - lastMoney
	lastMoney = now
	if delta == 0 then return end
	if delta < 0 then
		local v = -delta
		local npcCat = NpcCat()
		if repairCost and repairCost > 0 then
			Out("repair", v); repairCost = nil
		elseif npcCat then Out(npcCat, v)
		elseif open.merchant and InRepairMode and InRepairMode() then Out("repair", v)
		elseif open.merchant then Out((GetTime() - vendMatAt < 3) and "vendmat" or "vendor", v)
		elseif open.ah then Out(AhKind(), v)
		elseif MailBusy() or open.mail then Out("mail", v)
		elseif open.taxi then Out("taxi", v)
		elseif open.trainer then Out("trainer", v)
		elseif open.transmog then Out("transmog", v)
		elseif open.barber then Out("barber", v)
		elseif open.order then Out("order", v)
		elseif open.trade then Out("trade", v)
		elseif open.gbank or open.bank then Xfer(-v)
		else
			Out("other", v)
			local j = CharDB().journal
			table.insert(otherOut, { t = GetTime(), v = v, d = Day(), e = j and j[#j] })
		end
		return
	end
	-- entrada
	if open.merchant then Inc("vendor", delta); Ledger.SoldCash(delta)
	elseif MailOpen() then
		-- sem o gancho (TSM): venda da AH se houver nota de venda com ouro na caixa; senão transferência
		local kind = MailBusy() and mailKind or (mailOrder.seller and "ahsale" or mailKind)
		if kind == "ahsale" then Inc("ahsale", delta) else Xfer(delta) end
	elseif GetTime() < orderUntil then Inc("order", delta)
	elseif open.ah then Inc("other", delta)
	elseif open.trade then Inc("trade", delta)
	elseif open.order then Inc("order", delta)
	elseif open.gbank or open.bank then Xfer(delta)
	else
		-- saque / recompensa: espera um instante para descontar o ouro de missão (eventos chegam em qualquer ordem)
		pending.gain = pending.gain + delta
		local k, sb, _, src = Attribution(GOLD_WINDOW)
		pending.ctx, pending.sub, pending.src = k, sb, src
		pending.title = src == "quest" and lastQuest and lastQuest.title or nil
		if src == "chest" then pending.origin = lootOrigin end
		C_Timer.After(0.6, FlushGain)
	end
end

-- ===== missões =====
local questFreq = {}
local weeklyActive = {}   -- semanais no diário: { id, title, onMap }
local function IsWeeklyFreq(f)
	local QF = Enum.QuestFrequency or {}
	return f and (f == (QF.Weekly or 2) or (QF.ResetByScheduler and f == QF.ResetByScheduler))
end
local function ScanQuestLog()
	if not C_QuestLog.GetNumQuestLogEntries then return end
	weeklyActive = {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and info.questID and not info.isHeader then
			questFreq[info.questID] = info.frequency
			local calling = C_QuestLog.IsQuestCalling and C_QuestLog.IsQuestCalling(info.questID)
			if (IsWeeklyFreq(info.frequency) or calling) and not info.isHidden then
				table.insert(weeklyActive, { id = info.questID, title = Safe(info.title), onMap = info.isOnMap })
			end
		end
	end
end

-- Caçada semanal (Prey, Special Assignment...) em andamento no mapa atual: o que cair no mundo aberto
-- (saques, baús, moedas, ouro) é da semanal, não do "Mundo aberto".
local function WeeklyHere()
	for _, q in ipairs(weeklyActive) do
		local onMap = q.onMap
		if C_QuestLog.IsOnMap then
			local ok, r = pcall(C_QuestLog.IsOnMap, q.id)
			if ok then onMap = r end
		end
		if onMap and q.title then return "weekly", q.title end
	end
end
Ledger.WeeklyHere = WeeklyHere

local function QuestKind(questID)
	if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then return "wq" end
	local f = questFreq[questID]
	local QF = Enum.QuestFrequency or {}
	if f and f == (QF.Daily or 1) then return "daily" end
	if f and (f == (QF.Weekly or 2) or (QF.ResetByScheduler and f == QF.ResetByScheduler)) then return "weekly" end
	if C_QuestLog.IsQuestCalling and C_QuestLog.IsQuestCalling(questID) then return "weekly" end
	if C_QuestLog.IsQuestTask and C_QuestLog.IsQuestTask(questID) then return "event" end
	return "quest"
end

local function OnQuestTurnedIn(questID, xp, money)
	local kind = QuestKind(questID)
	local title = Safe(C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID))
	local sub = (kind == "quest") and MapName() or (title or MapName())
	if kind == "wq" or kind == "event" then sub = MapName() end
	Ledger.Count(kind, sub)
	if money and money > 0 then
		Ledger.AddGold(kind, sub, money, title or sub)
		questMoney = questMoney + money
		questUntil = GetTime() + 3
	end
	lastQuest, lastQuestAt = { kind = kind, sub = sub, title = title }, GetTime()
	-- registro das missões entregues (conferência: ouro/itens que chegam depois da entrega)
	LucroLivroDB.questLog = LucroLivroDB.questLog or {}
	table.insert(LucroLivroDB.questLog, { t = time(), id = questID, k = kind, n = title, g = money or 0, c = ns.CharKey() })
	while #LucroLivroDB.questLog > 300 do table.remove(LucroLivroDB.questLog, 1) end
end

-- ===== itens =====
local function Pattern(fmt)
	if type(fmt) ~= "string" then return nil end
	local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
	return "^" .. p .. "$"
end
local PATTERNS = {}
local function BuildPatterns()
	-- múltiplos primeiro (mais específicos)
	for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
		"LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_BONUS_ROLL_SELF" }) do
		local p = Pattern(_G[g])
		if p then table.insert(PATTERNS, { p = p, pushed = g:find("PUSHED") ~= nil }) end
	end
end

local GATHER_SUB = { [9] = true, [7] = true, [6] = true }   -- erva, metal e pedra, couro

local function OnLootMsg(msg)
	RefreshOpen()
	msg = Safe(msg)
	if type(msg) ~= "string" then return end
	local link, qty, pushed
	for _, pt in ipairs(PATTERNS) do
		local a, b = msg:match(pt.p)
		if a then link, qty, pushed = a, tonumber(b) or 1, pt.pushed break end
	end
	if not link then return end
	local id = C_Item.GetItemInfoInstant(link)
	if not id then return end
	-- recompensa de pedido de fabricação tirada do correio: receita dos pedidos
	if MailOpen() and (mailOrder.items[id] or 0) > 0 then
		mailOrder.items[id] = math.max(0, mailOrder.items[id] - qty)
		Ledger.AddItem("orders", L["Recompensas pelo correio"], id, qty)
		return
	end
	-- materiais do Desencantar: conversão, não receita (o equipamento já foi contado ao ser ganho)
	if GetTime() < deUntil and not open.merchant and not MailOpen() then
		Ledger.ItemConv(id, qty, L["Desencantar"])
		return
	end
	-- compra no vendedor paga com Moxie: o baú de reagentes guarda a origem (pedidos de fabricação)
	if open.merchant then
		local _, _, _, _, _, cls = C_Item.GetItemInfoInstant(id)
		if cls == 15 then
			if moxieBuy and GetTime() - moxieBuy < 3 then
				for _ = 1, math.min(qty, 20) do Ledger.RememberOrigin(id, "orders", L["Baús de Moxie"]) end
				moxieBuy = nil
			else
				merchLoot = { id = id, q = qty, t = GetTime() }
			end
		end
		return
	end
	-- compras, correio, trocas e bancos não são ganho de atividade
	if open.ah or MailOpen() or open.trade or open.bank or open.gbank or open.order then return end
	local ctx, sub, fixed, src = Attribution()
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
	if not fixed and ctx == "world" then
		if classID == 7 and GATHER_SUB[subClassID] then ctx = "gather" end
	end
	-- equipamento de recompensa de missão: uso temporário, acaba vendido ao vendedor ou desencantado
	local vendorOnly = src == "quest" and (classID == 2 or classID == 4)
	Ledger.AddItem(ctx, sub, id, qty, vendorOnly)
	-- sem origem fixa: pode ser recompensa de pedido chegando antes do Moxie (correio sem gancho)
	if not fixed and (ctx == "world" or ctx == "gather") then
		local j = CharDB().journal
		table.insert(recentLoose, { t = GetTime(), e = j[#j] })
		while #recentLoose > 30 do table.remove(recentLoose, 1) end
	end
end

-- abriu um baú/cofre que veio de uma atividade: o conteúdo (itens, ouro, moedas) vai para ela e o
-- próprio baú sai da atividade (se tinha valor), para não contar duas vezes
local function OpenedContainer(itemID)
	local o = Ledger.TakeOrigin(itemID)
	if not o then return nil end
	local day = CharDB().days[o.d or Today()]
	local a = day and day.act and day.act[o.k]
	if a and (a.items[itemID] or 0) > 0 and o.v and o.v > 0 then
		a.items[itemID] = a.items[itemID] - 1
		if a.items[itemID] <= 0 then a.items[itemID] = nil end
		local s = o.s and a.sub and a.sub[o.s]
		if s and s.items and (s.items[itemID] or 0) > 0 then
			s.items[itemID] = s.items[itemID] - 1
			if s.items[itemID] <= 0 then s.items[itemID] = nil end
		end
		Post(Ledger.ActCode(o.k, true), (o.s or "") .. " · " .. L["baú aberto"], -math.floor(o.v + 0.5), false, itemID, -1)
	end
	lootOrigin, lootOriginUntil, lootOriginItem = o, GetTime() + 5, itemID
	return o
end
Ledger.OpenedContainer = OpenedContainer

local function OnLootReady()
	if not (GetLootSourceInfo and GetNumLootItems) or GetNumLootItems() == 0 then return end
	local guid = Safe(GetLootSourceInfo(1))
	if type(guid) ~= "string" or not guid:find("^Item%-") then return end
	local itemID = C_Item.GetItemIDByGUID and C_Item.GetItemIDByGUID(guid)
	if not itemID then return end
	-- já marcado pelo clique na bolsa
	if lootOriginItem == itemID and GetTime() < lootOriginUntil then return end
	OpenedContainer(itemID)
end

-- categorias de saída de moeda (para o livro da moeda escolhida no seletor)
Ledger.CUR_OUT = {
	{ key = "vendor",  name = L["Compras no vendedor"] },
	{ key = "order",   name = L["Pedidos de fabricação"] },
	{ key = "use",     name = L["Uso (melhorias, chaves, custos)"] },
	{ key = "convert", name = L["Conversão (fragmentos → chave)"] },
}
Ledger.CONV_CODE = "5.3.01"

-- Tipo da moeda pelo nome (inglês/português):
--  "ignore": Concentração (regenera com o tempo, não é ganho de atividade) e Conhecimento de profissão
--            (progresso da especialização, sem valor de troca; o LucroCraft cuida disso) -> não registra
--  "shard" / "key": Fragmentos de Chave do Cofre viram Chave do Cofre Restaurada ao entrar na imersão
local curKind = {}
function Ledger.CurKind(id)
	if curKind[id] ~= nil then return curKind[id] or nil end
	local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
	local name = info and Safe(info.name)
	if type(name) ~= "string" then return nil end
	local k = false
	if name:find("Concentration") or name:find("Concentração") or name:find("Knowledge") or name:find("Conhecimento") then k = "ignore"
	elseif (name:find("Coffer Key") and name:find("Shard")) or (name:find("Fragmento") and name:find("Cofre")) then k = "shard"
	elseif name:find("Coffer Key") or (name:find("Chave") and name:find("Cofre")) then k = "key" end
	curKind[id] = k
	return k or nil
end
function Ledger.CurIgnored(id) return Ledger.CurKind(id) == "ignore" end

local lastShardOut, pendingKey
local function RecordConv(d, keyID, q, hist)
	d.curConv = d.curConv or {}
	d.curConv[keyID] = (d.curConv[keyID] or 0) + q
	local c = CharDB()
	c.journal = c.journal or {}
	table.insert(c.journal, { t = time(), a = Ledger.CONV_CODE, h = hist or L["Fragmentos → chave"], v = 0, m = keyID, q = q })
end

local function OnCurrency(currencyID, quantity, change)
	RefreshOpen()
	currencyID, quantity, change = Safe(currencyID), Safe(quantity), Safe(change)
	if not currencyID or not change or change == 0 then return end
	local kind = Ledger.CurKind(currencyID)
	if kind == "ignore" then return end
	local d = Day()
	-- saldo da moeda no dia (para a conciliação da moeda)
	d.curOpen = d.curOpen or {}
	d.curClose = d.curClose or {}
	if quantity then
		if d.curOpen[currencyID] == nil then d.curOpen[currencyID] = quantity - change end
		d.curClose[currencyID] = quantity
	end
	LucroLivroDB.currencies = LucroLivroDB.currencies or {}
	LucroLivroDB.currencies[currencyID] = true
	if change < 0 then
		if open.merchant and IsMoxie(currencyID) then
			if merchLoot and GetTime() - merchLoot.t < 3 then
				for _ = 1, math.min(merchLoot.q, 20) do Ledger.RememberOrigin(merchLoot.id, "orders", L["Baús de Moxie"]) end
				merchLoot = nil
			else
				moxieBuy = GetTime()
			end
		end
		local cat = open.merchant and "vendor" or open.order and "order" or "use"
		-- fragmentos que viraram chave (a chave chegou agora ou chega logo em seguida)
		local conv = kind == "shard" and pendingKey and GetTime() - pendingKey.t < 3
		if conv then
			cat = "convert"
			RecordConv(d, pendingKey.id, pendingKey.q)
			pendingKey.done = true
			pendingKey = nil
		end
		d.curOut = d.curOut or {}
		d.curOut[currencyID] = d.curOut[currencyID] or {}
		d.curOut[currencyID][cat] = (d.curOut[currencyID][cat] or 0) - change
		local c = CharDB()
		c.journal = c.journal or {}
		local code = cat == "vendor" and Ledger.OutCode("vendor") or cat == "order" and Ledger.OutCode("order")
			or cat == "convert" and Ledger.CONV_CODE or "4.9.02"
		local e = { t = time(), a = code, h = cat == "convert" and L["Fragmentos → chave"] or (Npc() or ""), v = 0, m = currencyID, q = change }
		table.insert(c.journal, e)
		if kind == "shard" and not conv then lastShardOut = { t = GetTime(), id = currencyID, q = -change, d = d, e = e } end
		return
	end
	-- moeda recebida no vendedor (ex.: trocar 30 brasões inferiores por 10 do nível acima): troca, não ganho
	-- de atividade, mas entra no saldo para a conciliação da moeda fechar
	if open.merchant then RecordConv(d, currencyID, change, L["Troca no vendedor"] .. (Npc() and (" · " .. Npc()) or "")) return end
	-- moeda que chega com o correio aberto e cartas de pedidos na caixa (Moxie, pagamento do consórcio)
	if MailOpen() and mailOrder.any then
		Ledger.AddCurrency("orders", L["Recompensas pelo correio"], currencyID, change)
		return
	end
	if open.ah or MailOpen() or open.trade or open.bank or open.order then return end
	-- Moxie só vem de pedidos de fabricação: recompensa de pedido (correio aberto por outro addon, por exemplo).
	-- Os itens que chegaram junto (até 3 s antes) também vão para os pedidos.
	if IsMoxie(currencyID) and not (lootOrigin and GetTime() < lootOriginUntil) then
		local sub = L["Recompensas de pedidos"]
		local c = CharDB()
		for _, r in ipairs(recentLoose) do
			if GetTime() - r.t <= 3 and r.e and not r.moved then
				r.moved = Ledger.MoveEntry(c, r.e, "orders", sub)
			end
		end
		recentLoose = {}
		moxieUntil = GetTime() + 3
		if GetTime() >= orderUntil then
			Ledger.AddCurrency("orders", sub, currencyID, change)
			return
		end
	end
	if kind == "key" then
		-- fragmentos acabaram de sair: é conversão, não ganho
		local so = lastShardOut
		if so and GetTime() - so.t < 3 then
			local o = so.d.curOut and so.d.curOut[so.id]
			if o and (o.use or 0) >= so.q then
				o.use = o.use - so.q
				o.convert = (o.convert or 0) + so.q
			end
			so.e.a, so.e.h = Ledger.CONV_CODE, L["Fragmentos → chave"]
			RecordConv(d, currencyID, change)
			lastShardOut = nil
			return
		end
		-- espera um instante: se os fragmentos saírem em seguida, também é conversão
		local ctx, sub = Attribution()
		local pk = { id = currencyID, q = change, t = GetTime() }
		pendingKey = pk
		C_Timer.After(2, function()
			if not pk.done then Ledger.AddCurrency(ctx, sub, currencyID, change) end
			if pendingKey == pk then pendingKey = nil end
		end)
		return
	end
	local ctx, sub = Attribution()
	Ledger.AddCurrency(ctx, sub, currencyID, change)
end

-- chefes derrotados: conta uma ocorrência na raide/masmorra
local function OnEncounterEnd(_, name, _, _, success)
	if success ~= 1 then return end
	local ctx, sub = Ledger.Context()
	if ctx == "raid" or ctx == "dungeon" or ctx == "delve" then Ledger.Count(ctx, sub) end
end

-- ===== Consumo de consumíveis (custo da atividade) =====
-- Conta os consumíveis (classe 0: poções, frascos, comida, runas...) nas bolsas. Quando a quantidade cai
-- sem vendedor/AH/correio/troca/banco/pedidos abertos, foi consumido: o custo (preço de mercado = custo de
-- reposição) vai para a atividade atual (raide, masmorra, caçada...). O que foi ganho de graça (caldeirão
-- da raide, recompensa, saque — c.free) sai primeiro e não custa nada; itens sem preço também não custam.
local bagCounts
local isConsum = {}   -- itemID -> classe 0? (não muda)
local function ConsumableCounts()
	local counts = {}
	for id, q in pairs((root.BagCounts())) do
		local c = isConsum[id]
		if c == nil then
			local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
			c = classID == 0
			isConsum[id] = c
		end
		if c then counts[id] = q end
	end
	return counts
end

-- ===== Venda ao vendedor de item recebido em atividade =====
-- O item entrou na atividade a valor estimado (AH, vendedor, desencantar). Vendido ao NPC, vale o que o NPC
-- pagou: o item sai da atividade e o valor pago entra no lugar (items.sold, em cobre). O ouro da venda fica
-- no caixa como "venda de itens das atividades" (inc.itemsale), fora das receitas comerciais (não conta duas vezes).
local function BagAll() return (root.BagCounts()) end   -- tabela compartilhada: só leitura
local merchBag
local sellCash, sellAt = 0, 0
local soldQueue = {}
Ledger.MerchantOpen = function() merchBag = BagAll(); sellCash = 0; soldQueue = {} end

local function Realize(id, qty, unit)
	local c = CharDB()
	local list = c.recv and c.recv[id]
	if not list then return 0 end
	local cut = date("%Y-%m-%d", time() - 30 * 86400)
	local left, done = qty, 0
	while left > 0 and list[1] do
		local e = list[1]
		local day = e.d >= cut and c.days[e.d]
		local a = day and day.act and day.act[e.k]
		local have = a and (a.items[id] or 0) or 0
		local take = math.min(left, e.q, have)
		if take > 0 then
			local book = (ns.P.Value(id) or 0) * take
			a.items[id] = have - take
			if a.items[id] <= 0 then a.items[id] = nil end
			a.items.sold = (a.items.sold or 0) + unit * take
			local s = e.s and a.sub and a.sub[e.s]
			if s and s.items then
				local hs = s.items[id] or 0
				local ts = math.min(take, hs)
				if ts > 0 then
					s.items[id] = hs - ts
					if s.items[id] <= 0 then s.items[id] = nil end
				end
				s.items.sold = (s.items.sold or 0) + unit * take
			end
			Post(Ledger.ActCode(e.k, true), (e.s or "") .. " · " .. L["vendido ao vendedor"], math.floor(unit * take - book + 0.5), false, id, 0)
			done = done + take
			left = left - take
		end
		e.q = e.q - math.max(take, 0)
		if e.q <= 0 or take <= 0 then table.remove(list, 1) end
	end
	if #list == 0 then c.recv[id] = nil end
	return done
end

local function MatchSales()
	local d = Day()
	while soldQueue[1] do
		local it = soldQueue[1]
		if GetTime() - it.t > 5 then table.remove(soldQueue, 1)
		elseif sellCash + 1 >= it.v then
			table.remove(soldQueue, 1)
			sellCash = sellCash - it.v
			local n = Realize(it.id, it.q, it.unit)
			if n > 0 then
				local cash = it.unit * n
				d.inc.vendor = math.max(0, (d.inc.vendor or 0) - cash)
				d.inc.itemsale = (d.inc.itemsale or 0) + cash
			end
		else break end
	end
end
Ledger.SoldCash = function(v) sellCash = sellCash + v; sellAt = GetTime(); MatchSales() end

local function OnMerchantBags()
	local now = BagAll()
	if merchBag then
		for id, q in pairs(merchBag) do
			local gone = q - (now[id] or 0)
			if gone > 0 then
				local sell = select(11, C_Item.GetItemInfo(id))
				if sell and sell > 0 then table.insert(soldQueue, { id = id, q = gone, unit = sell, v = sell * gone, t = GetTime() }) end
			end
		end
	end
	merchBag = now
	MatchSales()
end

local function OnBags()
	RefreshOpen()
	if open.merchant then pcall(OnMerchantBags) end
	local now = ConsumableCounts()
	local old = bagCounts
	bagCounts = now
	if not old then return end
	if open.merchant or open.ah or open.mail or MailBusy() or open.trade or open.bank or open.gbank or open.order then return end
	if GetTime() < orderUntil then return end
	if Ledger.OrderCraftActive and Ledger.OrderCraftActive() then return end
	local c = CharDB()
	c.free = c.free or {}
	c.made = c.made or {}
	for id, q in pairs(old) do
		local used = q - (now[id] or 0)
		if used > 0 then
			local freeQ = math.min(used, c.free[id] or 0)
			if freeQ > 0 then
				c.free[id] = c.free[id] - freeQ
				if c.free[id] <= 0 then c.free[id] = nil end
			end
			-- feito por você (o material já foi custo quando fabricou)
			local madeQ = math.min(used - freeQ, c.made[id] or 0)
			if madeQ > 0 then
				c.made[id] = c.made[id] - madeQ
				if c.made[id] <= 0 then c.made[id] = nil end
				freeQ = freeQ + madeQ
			end
			local paid = used - freeQ
			local unit = ns.P.Value(id)
			if paid > 0 and unit then
				local ctx, sname = Ledger.Context()
				if ctx == "world" then
					local k, t = Ledger.WeeklyHere()
					if k then ctx, sname = k, t end
				end
				local cost = unit * paid
				local d = Day()
				local act, sb = Act(d, ctx, sname)
				act.cost = act.cost or {}
				act.cost.consum = (act.cost.consum or 0) + cost
				if sb then sb.cost = sb.cost or {}; sb.cost.consum = (sb.cost.consum or 0) + cost end
				local cj = CharDB()
				cj.journal = cj.journal or {}
				table.insert(cj.journal, { t = time(), a = "4.5.01", h = sname or "", v = -math.floor(cost + 0.5), i = id, q = -paid, k = ctx })
			end
		end
	end
end
Ledger.OnBags = OnBags

-- ===== Material gasto ao fabricar (CPV) =====
-- Começou a fabricar (TRADE_SKILL_CRAFT_BEGIN): guarda as bolsas. Fabricou (UNIT_SPELLCAST_SUCCEEDED) → na próxima
-- atualização das bolsas: o que diminuiu foi gasto, o que aumentou foi produzido.
--   gasto: vale o preço de mercado (custo de reposição), seja comprado (estava no estoque) ou coletado (entrou como
--          receita de atividade 3.2). O que você mesmo fabricou antes (c.made) sai sem custo — o material dele já foi
--          custo quando ele foi feito (ex.: pigmento → tinta → pergaminho não conta três vezes).
--   produzido: entra em c.made (o produto ou o reagente feito por você).
-- Pedido reivindicado da mesma receita → 4.0.01 (centro: o pedido); senão 4.0.02 (centro: a profissão).
-- O que o cliente mandou nunca passa pelas bolsas. A receita fica "armada" por 15 s para os crafts em sequência.
local craft
function Ledger.OrderCraftActive() return craft ~= nil and GetTime() - craft.t < 30 end
Ledger.CraftActive = Ledger.OrderCraftActive

local function ProfName()
	local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
	return ok and info and Safe(info.professionName) or L["Fabricação"]
end

function Ledger.OnCraftBegin(recipeSpellID)
	local rid = Safe(recipeSpellID)
	local order
	if C_CraftingOrders and C_CraftingOrders.GetClaimedOrder then
		local ok, o = pcall(C_CraftingOrders.GetClaimedOrder)
		if ok and o then
			local sid = Safe(o.spellID)
			if not (sid and rid and sid ~= rid) then
				local name = Safe(o.outputItemHyperlink) and o.outputItemHyperlink:match("%[(.-)%]")
				if not name and o.itemID then name = C_Item.GetItemNameByID(o.itemID) end
				order = { name = name or L["Pedido de fabricação"], id = Safe(o.orderID) }
			end
		end
	end
	local rname
	if rid and C_TradeSkillUI.GetRecipeInfo then
		local ok, ri = pcall(C_TradeSkillUI.GetRecipeInfo, rid)
		rname = ok and ri and Safe(ri.name) or nil
	end
	craft = { snap = BagAll(), t = GetTime(), spell = rid, order = order, name = rname or L["Fabricação"], prof = ProfName() }
end

function Ledger.OnCraftDone(spellID)
	if craft and (not craft.spell or not spellID or Safe(spellID) == craft.spell) then craft.done = true end
end

function Ledger.OnCraftStop()
	if craft and not craft.done and not craft.armed then craft = nil end
end

local function SettleOrderCraft()
	local cr = craft
	if not (cr and cr.done) then
		if cr and cr.armed and GetTime() - cr.t > 15 then craft = nil end
		return
	end
	if GetTime() - cr.t > 30 then craft = nil return end
	local now = BagAll()
	local c = CharDB()
	c.made = c.made or {}
	local d = Day()
	local total = 0
	for id, q in pairs(cr.snap) do
		local used = q - (now[id] or 0)
		if used > 0 then
			local madeQ = math.min(used, c.made[id] or 0)
			if madeQ > 0 then
				c.made[id] = c.made[id] - madeQ
				if c.made[id] <= 0 then c.made[id] = nil end
			end
			local paid = used - madeQ
			local unit = paid > 0 and ns.P.Value(id) or nil
			if unit and unit > 0 then
				local cost = unit * paid
				total = total + cost
				Post(cr.order and Ledger.CPV_ORDERS or Ledger.CPV_CRAFT, cr.order and cr.order.name or cr.name, -math.floor(cost + 0.5), false, id, -paid)
			end
		end
	end
	for id, q in pairs(now) do
		local got = q - (cr.snap[id] or 0)
		if got > 0 then c.made[id] = (c.made[id] or 0) + got end
	end
	if total > 0 then
		d.cpv = d.cpv or {}
		if cr.order then
			d.cpv.orders = (d.cpv.orders or 0) + total
			local a, s = Act(d, "orders", cr.order.name)
			a.cost = a.cost or {}
			a.cost.mat = (a.cost.mat or 0) + total
			if s then s.cost = s.cost or {}; s.cost.mat = (s.cost.mat or 0) + total end
		else
			d.cpv.craft = (d.cpv.craft or 0) + total
			d.cpvProf = d.cpvProf or {}
			d.cpvProf[cr.prof] = (d.cpvProf[cr.prof] or 0) + total
		end
	end
	-- crafts em sequência da mesma receita: continua armado com as bolsas de agora
	craft = { snap = now, t = GetTime(), spell = cr.spell, order = cr.order, name = cr.name, prof = cr.prof, armed = true }
end
Ledger.SettleOrderCraft = SettleOrderCraft

-- ===== correção única (v0.4.0) =====
-- Antes da v0.4.0 o "correio aberto" podia ficar preso: o ouro de missão entrou duas vezes (na missão e em
-- 3.3.01 vendas na AH). Remove o lançamento 3.3.01 que tem o mesmo valor e o mesmo segundo de um 3.1.xx.
-- ===== correção única (v1.19.2): conciliar os totais do dia com o Diário =====
-- O Diário (lançamentos com ouro, e.c) bate centavo a centavo com o ouro real. Correções antigas (v0.5.x) mexeram
-- no Diário sem acertar o total do dia: ex.: 01/10 do Radunz ficou com 2.856g de "vendas na AH" que viraram saque
-- no Diário (contados duas vezes), e 200g de transferência no Nazdru sem lançamento. Para cada dia coberto pelo
-- Diário, as contas comerciais (3.3), despesas (4.x/5.4) e transferências passam a valer o que o Diário diz.
-- Dia sem saldo de abertura (criado por correção antiga): abre = abertura do dia seguinte − movimento do dia.
local function DayMv(day)
	local mv = (day.xin or 0) - (day.xout or 0) + (day.adj or 0)
	for _, a in pairs(day.act or {}) do mv = mv + (a.gold or 0) end
	for _, v in pairs(day.inc or {}) do mv = mv + v end
	for _, v in pairs(day.out or {}) do mv = mv - v end
	return mv
end
Ledger.DayMv = DayMv
local function FixCashDays()
	if LucroLivroDB.fixCash1 then return end
	LucroLivroDB.fixCash1 = true
	local INC_KEY, OUT_KEY = {}, {}
	for k, code in pairs(INC_CODE) do INC_KEY[code] = k end
	for k, code in pairs(OUT_CODE) do OUT_KEY[code] = k end
	local fixed, moved = 0, 0
	for _, c in pairs(LucroLivroDB.chars or {}) do
		local firstJ
		local J = {}
		for _, e in ipairs(c.journal or {}) do
			local d = root.DayKey(e.t)
			if not firstJ or d < firstJ then firstJ = d end
			if e.c then
				J[d] = J[d] or { inc = {}, out = {}, xin = 0, xout = 0, net = 0 }
				local jd = J[d]
				jd.net = jd.net + (e.v or 0)
				if INC_KEY[e.a] then jd.inc[INC_KEY[e.a]] = (jd.inc[INC_KEY[e.a]] or 0) + e.v
				elseif OUT_KEY[e.a] then jd.out[OUT_KEY[e.a]] = (jd.out[OUT_KEY[e.a]] or 0) - e.v
				elseif e.a == Ledger.XIN_CODE then jd.xin = jd.xin + e.v
				elseif e.a == Ledger.XOUT_CODE then jd.xout = jd.xout - e.v end
			end
		end
		for d, day in pairs(c.days or {}) do
			-- só quando o total do dia NÃO fecha com o saldo e o Diário fecha (o Diário está completo e certo)
			local jd = J[d]
			local okAgg = day.cashOpen and day.cashClose and math.abs(day.cashClose - day.cashOpen - DayMv(day)) < 100
			local okJ = jd and day.cashOpen and day.cashClose and math.abs(day.cashClose - day.cashOpen - jd.net) < 100
			if firstJ and d >= firstJ and not okAgg and okJ then
				local function fix(tbl, key, want)
					local have = tbl[key] or 0
					if math.abs(have - want) >= 100 then
						if LucroLivroDB.debugFix then print("FIX", d, key, have, want) end
						moved = moved + math.abs(have - want); fixed = fixed + 1
						tbl[key] = want ~= 0 and want or nil
					end
				end
				day.inc, day.out = day.inc or {}, day.out or {}
				-- venda ao vendedor de item de atividade: o ouro está em 3.3.02 no Diário, mas no dia fica em inc.itemsale
				for k in pairs(INC_CODE) do
					local want = jd.inc[k] or 0
					if k == "vendor" then want = want - (day.inc.itemsale or 0) end
					fix(day.inc, k, want)
				end
				for k in pairs(OUT_CODE) do fix(day.out, k, jd.out[k] or 0) end
				if math.abs((day.xin or 0) - jd.xin) >= 100 then moved = moved + math.abs((day.xin or 0) - jd.xin); fixed = fixed + 1; day.xin = jd.xin end
				if math.abs((day.xout or 0) - jd.xout) >= 100 then moved = moved + math.abs((day.xout or 0) - jd.xout); fixed = fixed + 1; day.xout = jd.xout end
			end
		end
		-- saldo de abertura que faltou: do dia seguinte para trás
		local ds = {}
		for d in pairs(c.days or {}) do table.insert(ds, d) end
		table.sort(ds)
		for i = #ds - 1, 1, -1 do
			local day, nxt = c.days[ds[i]], c.days[ds[i + 1]]
			if not day.cashOpen and nxt.cashOpen then
				day.cashClose = day.cashClose or nxt.cashOpen
				day.cashOpen = day.cashClose - DayMv(day)
				fixed = fixed + 1
			end
		end
	end
	if fixed > 0 then print("|cffd4af37Royal Revenue|r: " .. string.format(L["conciliação: %d totais de dia acertados pelo Diário (%s)."], fixed, ns.P.FormatMoney(moved))) end
end
Ledger.FixCashDays = FixCashDays

-- ===== correção única (v1.19.1): reclassificar compras/depósitos antigos (Reclass.lua, casado com o TSM) =====
local function FixReclass()
	-- corte do controle de consumo: amanhã; dias até hoje são "antigos" (compra de material = CPV)
	if not LucroLivroDB.v2From then
		LucroLivroDB.v2From = date("%Y-%m-%d", time() + 86400)
		for _, c in pairs(LucroLivroDB.chars or {}) do
			for d, day in pairs(c.days or {}) do if d < LucroLivroDB.v2From then day.v2 = nil end end
		end
	end
	if LucroLivroDB.fixReclass1 or not ns.RECLASS1 then return end
	LucroLivroDB.fixReclass1 = true
	local idx = {}
	for _, x in ipairs(ns.RECLASS1) do idx[x[1] .. ":" .. x[2] .. ":" .. x[3] .. ":" .. x[4]] = x[5] end
	local OLD = { ["4.3.02"] = "ah", ["4.3.01"] = "vendor" }
	local n, moved = 0, 0
	for char, c in pairs(LucroLivroDB.chars or {}) do
		for _, e in ipairs(c.journal or {}) do
			local to = e.a and OLD[e.a] and idx[char .. ":" .. e.t .. ":" .. e.v .. ":" .. e.a]
			if to then
				local d = c.days and c.days[root.DayKey(e.t)]
				if d and d.out then
					local old = OLD[e.a]
					d.out[old] = math.max(0, (d.out[old] or 0) + e.v)
					d.out[to] = (d.out[to] or 0) - e.v
				end
				e.a = Ledger.OutCode(to)
				n, moved = n + 1, moved - e.v
			end
		end
	end
	print("|cffd4af37Royal Revenue|r: " .. string.format(L["%d lançamentos antigos da casa de leilões reclassificados (%s)."], n, ns.P.FormatMoney(moved)))
end
Ledger.FixReclass = FixReclass

-- ===== correção única (v1.19): gastos antigos com NPCs de conta fixa (Cuzolth → Gear Upgrade) =====
local function FixNpcCat()
	if LucroLivroDB.fixNpc1 then return end
	LucroLivroDB.fixNpc1 = true
	for _, c in pairs(LucroLivroDB.chars or {}) do
		for _, e in ipairs(c.journal or {}) do
			local cat = e.h and Ledger.NPC_CAT[e.h]
			if cat and e.c and (e.v or 0) < 0 and e.a and e.a:find("^4%.") and e.a ~= Ledger.OutCode(cat) then
				local old
				for k, code in pairs(OUT_CODE) do if code == e.a then old = k end end
				local d = c.days and c.days[root.DayKey(e.t)]
				if old and d and d.out then
					d.out[old] = math.max(0, (d.out[old] or 0) + e.v)
					d.out[cat] = (d.out[cat] or 0) - e.v
				end
				e.a = Ledger.OutCode(cat)
			end
		end
	end
end
Ledger.FixNpcCat = FixNpcCat

local function FixDoubleAH()
	if LucroLivroDB.fixAH1 then return end
	LucroLivroDB.fixAH1 = true
	for _, c in pairs(LucroLivroDB.chars or {}) do
		local j = c.journal or {}
		local act = {}
		for _, e in ipairs(j) do
			if e.c and e.a and e.a:find("^3%.1%.") then act[e.t .. ":" .. e.v] = true end
		end
		local keep = {}
		for _, e in ipairs(j) do
			if e.a == "3.3.01" and act[e.t .. ":" .. e.v] then
				local d = c.days and c.days[root.DayKey(e.t)]
				if d and d.inc and d.inc.ahsale then d.inc.ahsale = math.max(0, d.inc.ahsale - e.v) end
			else
				table.insert(keep, e)
			end
		end
		c.journal = keep
	end
end

-- ===== correção única (v0.5.1) dos dados da sessão de 01-02/10 =====
-- Radunz: correio preso das 20:50 às 00:05 -> ouro de saque/recompensa saiu de "vendas na AH" (3.3.01) para
-- Mundo aberto; os da mesa de alquimia eram pedidos de fabricação. Dunraz: comissões de pedidos (00:59).
-- Lairs (raide "Mundo") passam de Raide para Eventos.
function Ledger.FixSession0502()
	if LucroLivroDB.fix0502 then return end
	LucroLivroDB.fix0502 = true
	local chars = LucroLivroDB.chars or {}
	local function DayOf(c, t) return c.days and c.days[date("%Y-%m-%d", t)] end
	local function SubAct(d, key, sub)
		local a = d.act[key]
		if not a then a = { gold = 0, items = {}, n = 0, sub = {}, cur = {} }; d.act[key] = a end
		local s = a.sub[sub]
		if not s then s = { gold = 0, items = {}, n = 0, cur = {} }; a.sub[sub] = s end
		return a, s
	end
	local RECL = L["Reclassificado (correio preso)"]
	local c = chars["Radunz-Goldrinn"]
	for _, e in ipairs(c and c.journal or {}) do
		if e.a == "3.3.01" and e.t >= 1790898640 and e.t <= 1790910300 and (e.h == "" or e.h == "Alchemist's Lab Bench") then
			local d = DayOf(c, e.t)
			if d then
				d.inc.ahsale = math.max(0, (d.inc.ahsale or 0) - e.v)
				if e.h == "" then
					local a, s = SubAct(d, "world", RECL)
					a.gold = a.gold + e.v; s.gold = s.gold + e.v
					e.a, e.h = Ledger.ActCode("world"), L["Saque"] .. " · " .. RECL
				else
					d.inc.order = (d.inc.order or 0) + e.v
					e.a = Ledger.IncCode("order")
				end
			end
		end
	end
	c = chars["Dunraz-Goldrinn"]
	for _, e in ipairs(c and c.journal or {}) do
		if e.a == Ledger.ActCode("world") and e.t >= 1790913530 and e.t <= 1790913605 then
			local d = DayOf(c, e.t)
			local w = d and d.act.world
			if w then
				w.gold = w.gold - e.v
				local s = w.sub["Silvermoon City"]
				if s then s.gold = s.gold - e.v end
				d.inc.order = (d.inc.order or 0) + e.v
				e.a, e.h = Ledger.IncCode("order"), "Blacksmith's Table"
			end
		end
	end
	-- lairs: sub de raide com dificuldade "Mundo" -> Eventos e objetivos
	for _, ch in pairs(chars) do
		local moved = {}
		for _, d in pairs(ch.days or {}) do
			local r = d.act and d.act.raid
			for name, s in pairs(r and r.sub or {}) do
				if name:find("· World$") or name:find("· Mundo") then
					local ev, es = SubAct(d, "event", name)
					ev.gold, es.gold = ev.gold + s.gold, es.gold + s.gold
					ev.n, es.n = ev.n + (s.n or 0), es.n + (s.n or 0)
					for id, q in pairs(s.items or {}) do
						ev.items[id] = (ev.items[id] or 0) + q; es.items[id] = (es.items[id] or 0) + q
					end
					for id, q in pairs(s.cur or {}) do
						ev.cur[id] = (ev.cur[id] or 0) + q; es.cur[id] = (es.cur[id] or 0) + q
					end
					r.gold, r.n = r.gold - s.gold, r.n - (s.n or 0)
					for id, q in pairs(s.items or {}) do
						r.items[id] = (r.items[id] or 0) - q
						if r.items[id] <= 0 then r.items[id] = nil end
					end
					for id, q in pairs(s.cur or {}) do
						if r.cur then r.cur[id] = (r.cur[id] or 0) - q; if r.cur[id] <= 0 then r.cur[id] = nil end end
					end
					if s.cost then
						ev.cost = ev.cost or {}; es.cost = es.cost or {}
						for k2, v2 in pairs(s.cost) do
							ev.cost[k2] = (ev.cost[k2] or 0) + v2; es.cost[k2] = (es.cost[k2] or 0) + v2
							if r.cost and r.cost[k2] then r.cost[k2] = r.cost[k2] - v2 end
						end
					end
					r.sub[name] = nil
					moved[name] = true
					if next(r.sub) == nil and math.abs(r.gold) < 1 and next(r.items) == nil then d.act.raid = nil end
				end
			end
		end
		for _, e in ipairs(ch.journal or {}) do
			if e.a == Ledger.ActCode("raid") or e.a == Ledger.ActCode("raid", true) then
				for name in pairs(moved) do
					if e.h and (e.h == name or e.h:find(name, 1, true)) then
						e.a = Ledger.ActCode("event", e.a == Ledger.ActCode("raid", true))
						break
					end
				end
			end
		end
	end
end

-- ===== correção (v0.5.2): equipamento lançado com o preço inflado da AH =====
-- Recalcula o valor dos lançamentos de armas/armaduras recebidas (vendedor ou desencantar). Repete no
-- próximo login enquanto houver item sem dados carregados.
function Ledger.FixGear0503()
	if LucroLivroDB.fix0503 then return end
	local pending = false
	for _, c in pairs(LucroLivroDB.chars or {}) do
		for _, e in ipairs(c.journal or {}) do
			if e.i and e.q and not e.c and e.a and e.a:find("^3%.2%.") then
				local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(e.i)
				if classID == 2 or classID == 4 then
					local sell = select(11, C_Item.GetItemInfo(e.i))
					if sell == nil then
						pending = true
					else
						local unit = ns.P.Value(e.i) or 0
						e.v = math.floor(unit * e.q + 0.5)
					end
				end
			end
		end
	end
	if not pending then LucroLivroDB.fix0503 = true end
end

-- ===== correção (v0.5.6): pagamentos ao NPC de reparo por diálogo estavam em "Outros gastos" =====
function Ledger.FixDialogRepair()
	if LucroLivroDB.fix0506 then return end
	LucroLivroDB.fix0506 = true
	for _, c in pairs(LucroLivroDB.chars or {}) do
		for _, e in ipairs(c.journal or {}) do
			if e.a == "4.9.01" and e.c and e.h == "Cuzolth" and e.v < 0 then
				local d = c.days and c.days[root.DayKey(e.t)]
				if d and d.out then
					d.out.other = math.max(0, (d.out.other or 0) + e.v)
					d.out.repair = (d.out.repair or 0) - e.v
				end
				e.a, e.h = Ledger.OutCode("repair"), e.h .. " · " .. L["sem origem"]
			end
		end
	end
end

function Ledger.FixOrders0507()
	if LucroLivroDB.fix0507 then return end
	LucroLivroDB.fix0507 = true
	local c = LucroLivroDB.chars and LucroLivroDB.chars["Radunz-Goldrinn"]
	if not c then return end
	local SUB = L["Recompensas pelo correio"]
	for _, e in ipairs(c.journal or {}) do
		if e.t >= 1791048360 and e.t <= 1791048720 and not e.c and (e.a == Ledger.ActCode("world", true) or e.a == Ledger.ActCode("gather", true)) then
			local d = c.days[root.DayKey(e.t)]
			local fromKey = e.a == Ledger.ActCode("gather", true) and "gather" or "world"
			local fa = d and d.act and d.act[fromKey]
			if fa then
				local field, key = e.i and "items" or "cur", e.i or e.m
				if key and e.q then
					fa[field] = fa[field] or {}
					fa[field][key] = (fa[field][key] or 0) - e.q
					if fa[field][key] <= 0 then fa[field][key] = nil end
					local fs = e.h and fa.sub and fa.sub[e.h]
					if fs and fs[field] and fs[field][key] then
						fs[field][key] = fs[field][key] - e.q
						if fs[field][key] <= 0 then fs[field][key] = nil end
					end
					local oa = d.act.orders or { gold = 0, items = {}, n = 0, sub = {}, cur = {} }
					d.act.orders = oa
					oa[field] = oa[field] or {}
					oa[field][key] = (oa[field][key] or 0) + e.q
					oa.sub = oa.sub or {}
					local os_ = oa.sub[SUB] or { gold = 0, items = {}, n = 0, cur = {} }
					oa.sub[SUB] = os_
					os_[field] = os_[field] or {}
					os_[field][key] = (os_[field][key] or 0) + e.q
					e.a, e.h = Ledger.ActCode("orders", true), SUB
				end
			end
		end
	end
end

-- ===== correção única (v1.0.8) =====
-- 1) Moxie e itens de recompensa de pedido que entraram como Mundo aberto/Coleta (correio aberto sem os
--    ganchos): Moxie + itens até 3 s antes/depois -> Pedidos de fabricação · Recompensas de pedidos.
-- 2) Radünz-Medivh 03/10: 3 Surplus Reagent Chests compradas com Moxie (16:55:19–23 BRT) -> Baús de Moxie;
--    Eversinging Dust do Desencantar (16:47:55–16:48:30 BRT) -> conversão de itens.
function Ledger.FixMoxie0508()
	if LucroLivroDB.fix0508 then return end
	LucroLivroDB.fix0508 = true
	local W, G = Ledger.ActCode("world", true), Ledger.ActCode("gather", true)
	local SUB = L["Recompensas de pedidos"]
	for ck, c in pairs(LucroLivroDB.chars or {}) do
		local J = c.journal or {}
		local mark = {}
		for i, e in ipairs(J) do
			if (e.a == W or e.a == G) and e.m and IsMoxie(e.m) then
				for k = math.max(1, i - 12), math.min(#J, i + 12) do
					local o = J[k]
					if (o.a == W or o.a == G) and not o.c and math.abs(o.t - e.t) <= 3 then mark[k] = true end
				end
			end
		end
		if ck == "Radünz-Medivh" then
			for k, e in ipairs(J) do
				if (e.a == W or e.a == G) and not e.c then
					if e.t >= 1791057319 and e.t <= 1791057323 then mark[k] = "chest"
					elseif e.t >= 1791056875 and e.t <= 1791056910 and e.i == 243599 then mark[k] = "de" end
				end
			end
		end
		for k, how in pairs(mark) do
			local e = J[k]
			if how == "de" then Ledger.MoveEntry(c, e, nil, nil, L["Desencantar"])
			elseif how == "chest" then Ledger.MoveEntry(c, e, "orders", L["Baús de Moxie"])
			else Ledger.MoveEntry(c, e, "orders", SUB) end
		end
	end
end

-- ===== ajuste automático no login =====
-- O WoW só grava os dados no logout/reload. Se o jogo fechou de forma bruta, os movimentos da sessão se perdem
-- e o ouro real não bate com o último saldo gravado. A diferença vira um lançamento de ajuste (fora do resultado)
-- para a conciliação de caixa voltar a fechar.
local function CheckAdjustment(last)
	local c = CharDB()
	local now = GetMoney()
	if last and now ~= last then
		local diff = now - last
		local existed = c.days[Today()] ~= nil
		local d = Day()
		-- dia novo: o saldo de abertura é o último saldo conhecido (antes da sessão perdida), não o atual
		if not existed then d.cashOpen = last end
		d.adj = (d.adj or 0) + diff
		local when = c.lastSeen and date("%d/%m %H:%M", c.lastSeen) or "?"
		Post(Ledger.ADJ_CODE, string.format(L["Movimentos não registrados (sessão de %s não salva)"], when), diff, true)
		print("|cffd4af37Royal Revenue|r: " .. string.format(L["ajuste de conciliação de %s lançado (dados da sessão anterior não foram salvos)."], ns.P.FormatMoney(diff)))
	end
	c.lastMoney = now
	checked = true
end

-- ===== tempo em cada atividade (a cada 15 s, fora de AFK) =====
local TICK = 15
local function Tick()
	if not LucroLivroDB or (UnitIsAFK and UnitIsAFK("player")) then return end
	local ctx = Ledger.Context()
	local d = Day()
	d.time[ctx] = (d.time[ctx] or 0) + TICK
	d.cashClose = GetMoney()
	if checked then CharDB().lastMoney = d.cashClose end
	CharDB().lastSeen = time()
	Ledger.rev = (Ledger.rev or 0) + 1
end

-- ===== ganchos =====
local function Hooks()
	if RepairAllItems then
		hooksecurefunc("RepairAllItems", function(guild)
			if not guild then
				repairCost = GetRepairAllCost and GetRepairAllCost() or nil
				repairLoss = RepairEstimate()
			else
				local c = CharDB(); c.wear = {}; wearLast = nil
				C_Timer.After(1, function() pcall(ReadWear) end)
			end
		end)
	end
	local function MailKind(index)
		local invoiceType = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index)
		mailKind = (invoiceType == "seller") and "ahsale" or "xfer"
		mailAt = GetTime()
	end
	local function MailTouch() mailAt = GetTime() end
	if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", MailKind) end
	if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", MailKind) end
	if TakeInboxItem then hooksecurefunc("TakeInboxItem", MailTouch) end
	if SendMail then hooksecurefunc("SendMail", MailTouch) end
	-- casa de leilões: postar = depósito; comprar commodity = material (estoque); comprar item = uso
	if C_AuctionHouse then
		local function mark(k) return function() ahMark, ahMarkAt = k, GetTime() end end
		for _, fn in ipairs({ "PostItem", "PostCommodity" }) do
			if C_AuctionHouse[fn] then hooksecurefunc(C_AuctionHouse, fn, mark("ahdep")) end
		end
		if C_AuctionHouse.ConfirmCommoditiesPurchase then hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", mark("ahbuy")) end
		if C_AuctionHouse.StartCommoditiesPurchase then hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", mark("ahbuy")) end
		if C_AuctionHouse.PlaceBid then hooksecurefunc(C_AuctionHouse, "PlaceBid", mark("ahitem")) end
	end
	-- vendedor: reagente de profissão = material (estoque); o resto = compra para uso
	if BuyMerchantItem then
		hooksecurefunc("BuyMerchantItem", function(index)
			pcall(function()
				local id = GetMerchantItemID and GetMerchantItemID(index)
				local isReagent = id and select(17, C_Item.GetItemInfo(id))
				if isReagent then vendMatAt = GetTime() end
			end)
		end)
	end
	-- pedido de fabricação entregue (artesão): comissão e recompensas do pedido
	if C_CraftingOrders and C_CraftingOrders.FulfillOrder then
		hooksecurefunc(C_CraftingOrders, "FulfillOrder", function() orderUntil = GetTime() + 6 end)
	end
	-- clique num baú/cofre na bolsa (abre sem janela de saque, conteúdo direto na bolsa)
	if C_Container and C_Container.UseContainerItem then
		hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
			pcall(function()
				if open.merchant or open.mail or open.bank or open.gbank or open.trade or open.ah then return end
				local info = C_Container.GetContainerItemInfo(bag, slot)
				local id = info and Safe(info.itemID)
				local c = CharDB()
				if id and c.origins and c.origins[id] then OpenedContainer(id) end
			end)
		end)
	end
end

-- ===== eventos =====
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_MONEY")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("CHAT_MSG_LOOT")
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("LOOT_READY")
f:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("MAIL_INBOX_UPDATE")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
pcall(f.RegisterEvent, f, "CRAFTINGORDERS_FULFILL_ORDER_RESPONSE")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
pcall(f.RegisterEvent, f, "TRADE_SKILL_CRAFT_BEGIN")
pcall(f.RegisterEvent, f, "UNIT_SPELLCAST_INTERRUPTED")
pcall(f.RegisterEvent, f, "UNIT_SPELLCAST_FAILED")
for ev in pairs(OPEN_EVENTS) do pcall(f.RegisterEvent, f, ev) end

local questScanPending = false
f:SetScript("OnEvent", function(_, event, ...)
	if (event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED"
		or event == "CHAT_MSG_LOOT") and root.AnySecret(...) then return end
	if not LucroLivroDB then return end
	local ok, err = pcall(function(...)
		local o = OPEN_EVENTS[event]
		if o then
			open[o[1]] = o[2]
			if o[1] == "merchant" and o[2] then pcall(Ledger.MerchantOpen) end
			if not o[2] and o[1] == "mail" then mailKind = nil end
			if o[1] == "mail" and o[2] then pcall(ScanInbox) end
			return
		end
		if event == "PLAYER_LOGIN" then
			lastMoney = GetMoney()
			BuildPatterns()
			Hooks()
			CharDB()
			Prune()
			pcall(FixDoubleAH)
			pcall(FixNpcCat)
			pcall(FixReclass)
			pcall(FixCashDays)
			pcall(Ledger.FixSession0502)
			pcall(Ledger.FixDialogRepair)
			pcall(Ledger.FixOrders0507)
			pcall(Ledger.FixMoxie0508)
			C_Timer.After(10, function() pcall(Ledger.FixGear0503) end)
			ScanQuestLog()
			-- o ouro às vezes ainda vem 0 no login: confere depois de alguns segundos
			local saved = CharDB().lastMoney
			local function check()
				if GetMoney() == 0 and (saved or 0) > 0 then return false end
				lastMoney = GetMoney()
				CheckAdjustment(saved)
				Day().cashClose = GetMoney()
				return true
			end
			if not check() then C_Timer.After(5, check) end
			CharDB().lastSeen = time()
			C_Timer.NewTicker(TICK, function() pcall(Tick) end)
			C_Timer.After(3, function() pcall(ReadWear) end)
			C_Timer.After(4, function() pcall(function() bagCounts = ConsumableCounts() end) end)
		elseif event == "MAIL_INBOX_UPDATE" then
			if open.mail then pcall(ScanInbox) end
		elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_DISABLED" then
			if event == "PLAYER_ENTERING_WORLD" then
				local isLogin = ...
				-- login novo = sessão nova; /reload continua a mesma (se ainda não houver, começa agora)
				if isLogin or not CharDB().session then Ledger.StartSession() end
			end
			-- tela de carregamento ou combate: nenhuma janela (correio, AH, banco...) pode estar aberta
			for k in pairs(open) do open[k] = nil end
			mailKind = nil
		elseif event == "CRAFTINGORDERS_FULFILL_ORDER_RESPONSE" then
			orderUntil = GetTime() + 6
			pcall(SettleOrderCraft)
		elseif event == "TRADE_SKILL_CRAFT_BEGIN" then
			Ledger.OnCraftBegin(...)
			return
		elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
			if (...) == "player" then Ledger.OnCraftStop() end
			return
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			local unit, _, spellID = ...
			if unit == "player" and Safe(spellID) == 13262 then deUntil = GetTime() + 5 end
			if unit == "player" then Ledger.OnCraftDone(spellID) end
			return
		elseif event == "PLAYER_MONEY" then
			OnMoney()
		elseif event == "QUEST_TURNED_IN" then
			OnQuestTurnedIn(...)
		elseif event == "QUEST_ACCEPTED" or event == "QUEST_LOG_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" then
			if questScanPending then return end
			questScanPending = true
			C_Timer.After(2, function() questScanPending = false; pcall(ScanQuestLog) end)
		elseif event == "CHAT_MSG_LOOT" then
			OnLootMsg(...)
		elseif event == "UPDATE_INVENTORY_DURABILITY" then
			OnDurability()
		elseif event == "BAG_UPDATE_DELAYED" then
			pcall(SettleOrderCraft)
			OnBags()
		elseif event == "PLAYER_REGEN_ENABLED" then
			if wearPending then ReadWear() end
		elseif event == "LOOT_READY" then
			OnLootReady()
		elseif event == "CURRENCY_DISPLAY_UPDATE" then
			OnCurrency(...)
		elseif event == "ENCOUNTER_END" then
			OnEncounterEnd(...)
		end
		Ledger.rev = (Ledger.rev or 0) + 1   -- algo pode ter mudado: telas recalculam
		if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
	end, ...)
	if not ok then
		LucroLivroDB.log = LucroLivroDB.log or {}
		table.insert(LucroLivroDB.log, date("%d/%m %H:%M:%S ") .. event .. ": " .. tostring(err))
		while #LucroLivroDB.log > 50 do table.remove(LucroLivroDB.log, 1) end
	end
end)

-- ===== leitura (para o painel) =====
-- days = tamanho do período (nil = tudo); shift = quantos dias para trás (período anterior = days)
-- ===== sessão de jogo (desde o login do personagem; /reload não reinicia) =====
-- c.session = { t = início, d = dia do início, cash = ouro no início, base = cópia do dia no início }
local function DeepCopy(v)
	if type(v) ~= "table" then return v end
	local r = {}
	for k, x in pairs(v) do r[k] = DeepCopy(x) end
	return r
end
-- dia menos a foto do início da sessão (só os acumulados; saldos ficam de fora)
local KEEP = { cashOpen = true, cashClose = true, curOpen = true, curClose = true }
local function Minus(a, b)
	local r = {}
	for k, v in pairs(a) do
		if type(v) == "number" then r[k] = v - ((type(b) == "table" and type(b[k]) == "number") and b[k] or 0)
		elseif type(v) == "table" then r[k] = Minus(v, type(b) == "table" and b[k] or nil)
		else r[k] = v end
	end
	return r
end
function Ledger.StartSession()
	local c = CharDB()
	local today = c.days[Today()]
	local money = GetMoney()
	if (not money or money == 0) and c.lastMoney then money = c.lastMoney end
	c.session = { t = time(), d = Today(), cash = money, base = DeepCopy(today) or {} }
end
function Ledger.SessionChar(onlyChar)
	return onlyChar or ns.CharKey()
end
-- o dia como ele ficou desde o início da sessão
local function SessionDay(c, d, day)
	local s = c.session
	if not s or d < s.d then return nil end
	if d ~= s.d then return day end
	local r = Minus(day, s.base)
	-- tira o que ficou zerado (itens, moedas e atividades sem movimento na sessão)
	local function clean(a)
		for _, f in ipairs({ "items", "cur" }) do
			for id, q in pairs(a[f] or {}) do if q == 0 then a[f][id] = nil end end
		end
	end
	for k, a in pairs(r.act or {}) do
		clean(a)
		for sn, sb in pairs(a.sub or {}) do
			clean(sb)
			if sb.gold == 0 and (sb.n or 0) == 0 and not next(sb.items or {}) and not next(sb.cur or {}) then a.sub[sn] = nil end
		end
		local cost = a.cost and ((a.cost.repair or 0) + (a.cost.consum or 0) + (a.cost.mat or 0)) or 0
		if a.gold == 0 and (a.n or 0) == 0 and not next(a.items or {}) and not next(a.cur or {}) and cost == 0 then r.act[k] = nil end
	end
	for k in pairs(KEEP) do r[k] = day[k] end
	r.cashOpen = s.cash
	r.curOpen = {}
	for id, v in pairs(day.curOpen or {}) do r.curOpen[id] = v end
	for id, v in pairs(s.base.curClose or {}) do r.curOpen[id] = v end
	return r
end

function Ledger.Range(days, shift)
	if days == "session" then
		local c = LucroLivroDB.chars and LucroLivroDB.chars[ns.CharKey()]
		local s = c and c.session
		local d = s and s.d or date("%Y-%m-%d")
		return d, "9999"
	end
	if not days then return "0000", "9999" end
	shift = shift or 0
	local last = time() - shift * 86400
	return date("%Y-%m-%d", last - (days - 1) * 86400), date("%Y-%m-%d", last)
end

function Ledger.Collect(days, onlyChar, shift)
	local from, to = Ledger.Range(days, shift)
	local out = { chars = {}, from = from, to = to }
	local isSession = days == "session"
	if isSession then onlyChar = Ledger.SessionChar(onlyChar) end
	for char, c in pairs(LucroLivroDB.chars or {}) do
		if (not onlyChar or onlyChar == char) and (not isSession or c.session) then
			local t = { char = char, class = c.class, act = {}, out = {}, inc = {}, xin = 0, xout = 0, adj = 0, time = {}, any = false,
				curOut = {}, curOpen = {}, curClose = {}, curConv = {} }
			local curFirst, curLast = {}, {}
			local firstD, lastD
			for d, day0 in pairs(c.days or {}) do
				local day = day0
				if isSession then day = SessionDay(c, d, day0) end
				if day and (isSession or (d >= from and d <= to)) then
					t.any = true
					if not firstD or d < firstD then firstD = d end
					if not lastD or d > lastD then lastD = d end
					for k, a in pairs(day.act or {}) do
						local ta = t.act[k] or { gold = 0, items = {}, n = 0, sub = {}, cur = {} }
						ta.gold, ta.n = ta.gold + a.gold, ta.n + (a.n or 0)
						for id, q in pairs(a.items) do ta.items[id] = (ta.items[id] or 0) + q end
						for id, q in pairs(a.cur or {}) do ta.cur[id] = (ta.cur[id] or 0) + q end
						ta.repair = (ta.repair or 0) + (a.cost and a.cost.repair or 0)
						ta.consum = (ta.consum or 0) + (a.cost and a.cost.consum or 0)
						ta.mat = (ta.mat or 0) + (a.cost and a.cost.mat or 0)
						for sname, s in pairs(a.sub or {}) do
							local ts = ta.sub[sname] or { gold = 0, items = {}, n = 0, cur = {} }
							ts.gold, ts.n = ts.gold + s.gold, ts.n + (s.n or 0)
							for id, q in pairs(s.items) do ts.items[id] = (ts.items[id] or 0) + q end
							for id, q in pairs(s.cur or {}) do ts.cur[id] = (ts.cur[id] or 0) + q end
							ts.repair = (ts.repair or 0) + (s.cost and s.cost.repair or 0)
							ts.consum = (ts.consum or 0) + (s.cost and s.cost.consum or 0)
							ts.mat = (ts.mat or 0) + (s.cost and s.cost.mat or 0)
							ta.sub[sname] = ts
						end
						t.act[k] = ta
					end
					for k, v in pairs(day.out or {}) do t.out[k] = (t.out[k] or 0) + v end
					-- dia antigo: material comprado (estoque) conta como CPV do dia da compra
					if not day.v2 then
						local sl = 0
						for _, k in ipairs(Ledger.STOCK_KEYS) do sl = sl + ((day.out or {})[k] or 0) end
						t.stockLegacy = (t.stockLegacy or 0) + sl
					end
					-- CPV e consumíveis na DRE: só dias com o controle novo (v2)
					if day.v2 then
						t.cpv = t.cpv or { orders = 0, craft = 0 }
						for k, v in pairs(day.cpv or {}) do t.cpv[k] = (t.cpv[k] or 0) + v end
						t.cpvProf = t.cpvProf or {}
						for k, v in pairs(day.cpvProf or {}) do t.cpvProf[k] = (t.cpvProf[k] or 0) + v end
						for k, a in pairs(day.act or {}) do
							local cc = a.cost and a.cost.consum or 0
							if cc > 0 then
								t.consumD = t.consumD or {}
								local e = t.consumD[k] or { v = 0, sub = {} }
								e.v = e.v + cc
								for sname, sx in pairs(a.sub or {}) do
									local sc = sx.cost and sx.cost.consum or 0
									if sc > 0 then e.sub[sname] = (e.sub[sname] or 0) + sc end
								end
								t.consumD[k] = e
							end
							local mc = a.cost and a.cost.mat or 0
							if k == "orders" and mc > 0 then
								t.cpvOrd = t.cpvOrd or {}
								for sname, sx in pairs(a.sub or {}) do
									local sc = sx.cost and sx.cost.mat or 0
									if sc > 0 then t.cpvOrd[sname] = (t.cpvOrd[sname] or 0) + sc end
								end
							end
						end
					end
					for k, v in pairs(day.inc or {}) do t.inc[k] = (t.inc[k] or 0) + v end
					for k, v in pairs(day.time or {}) do t.time[k] = (t.time[k] or 0) + v end
					t.xin, t.xout, t.adj = t.xin + (day.xin or 0), t.xout + (day.xout or 0), t.adj + (day.adj or 0)
					for id, q in pairs(day.curConv or {}) do t.curConv[id] = (t.curConv[id] or 0) + q end
					for id, cats in pairs(day.curOut or {}) do
						t.curOut[id] = t.curOut[id] or {}
						for k, v in pairs(cats) do t.curOut[id][k] = (t.curOut[id][k] or 0) + v end
					end
					for id, v in pairs(day.curOpen or {}) do
						if not curFirst[id] or d < curFirst[id] then curFirst[id] = d; t.curOpen[id] = v end
					end
					for id, v in pairs(day.curClose or {}) do
						if not curLast[id] or d > curLast[id] then curLast[id] = d; t.curClose[id] = v end
					end
				end
			end
			-- caixa: saldo de abertura do primeiro dia e de fechamento do último
			if firstD then t.cashOpen = c.days[firstD].cashOpen end
			if isSession and firstD == c.session.d then t.cashOpen = c.session.cash end
			if lastD then t.cashClose = c.days[lastD].cashClose end
			t.firstD, t.lastD = firstD, lastD
			table.insert(out.chars, t)
		end
	end
	return out
end

-- lançamentos do Diário no período (mais recentes primeiro)
local jCache = {}
function Ledger.Journal(days, onlyChar)
	-- mesma consulta sem nada novo no livro (Ledger.rev): devolve a lista anterior (só leitura)
	local key = tostring(days) .. "|" .. tostring(onlyChar)
	local c = jCache[key]
	if c and c.rev == Ledger.rev and GetTime() - c.t < 10 then return c.list end
	local list = Ledger._Journal(days, onlyChar)
	if next(jCache) and not jCache[key] then wipe(jCache) end
	jCache[key] = { rev = Ledger.rev, t = GetTime(), list = list }
	return list
end
function Ledger._Journal(days, onlyChar)
	local from = Ledger.Range(days)
	local isSession = days == "session"
	if isSession then onlyChar = Ledger.SessionChar(onlyChar) end
	local DK = root.DayKey
	-- o Diário de cada personagem é gravado em ordem de tempo: lido de trás para frente, cada lista já sai do
	-- mais recente para o mais antigo e as listas são intercaladas sem ordenar tudo (fora de ordem → ordena)
	local lists, sorted = {}, true
	for char, c in pairs(LucroLivroDB.chars or {}) do
		if (not onlyChar or onlyChar == char) and (not isSession or c.session) then
			local since = isSession and c.session.t or nil
			local j, out, prev = c.journal or {}, {}, math.huge
			for i = #j, 1, -1 do
				local e = j[i]
				local t = e.t
				local inside
				if since then inside = t >= since else inside = DK(t) >= from end
				if inside then out[#out + 1] = { e = e, char = char, class = c.class, t = t } end
				if t > prev then sorted = false end
				prev = t
			end
			if #out > 0 then lists[#lists + 1] = out end
		end
	end
	local function merge(a, b)
		local r, i, k = {}, 1, 1
		local na, nb = #a, #b
		while i <= na and k <= nb do
			if a[i].t >= b[k].t then r[#r + 1] = a[i]; i = i + 1 else r[#r + 1] = b[k]; k = k + 1 end
		end
		for x = i, na do r[#r + 1] = a[x] end
		for x = k, nb do r[#r + 1] = b[x] end
		return r
	end
	if not sorted then
		local list = {}
		for _, l in ipairs(lists) do for _, it in ipairs(l) do list[#list + 1] = it end end
		table.sort(list, function(a, b) return a.t > b.t end)
		return list
	end
	while #lists > 1 do
		local nx = {}
		for i = 1, #lists, 2 do nx[#nx + 1] = lists[i + 1] and merge(lists[i], lists[i + 1]) or lists[i] end
		lists = nx
	end
	return lists[1] or {}
end

-- ===== Demonstrações =====
-- soma de vários personagens coletados em um só "centro"
function Ledger.Merge(data)
	local m = { act = {}, out = {}, inc = {}, xin = 0, xout = 0, adj = 0, time = {}, cashOpen = 0, cashClose = 0, hasCash = false,
		cpv = {}, cpvProf = {}, cpvOrd = {}, consumD = {},
		curOut = {}, curOpen = {}, curClose = {}, curConv = {} }
	for _, t in ipairs(data.chars) do
		for k, a in pairs(t.act) do
			local ma = m.act[k] or { gold = 0, items = {}, n = 0, sub = {}, cur = {} }
			ma.gold, ma.n = ma.gold + a.gold, ma.n + a.n
			for id, q in pairs(a.items) do ma.items[id] = (ma.items[id] or 0) + q end
			for id, q in pairs(a.cur or {}) do ma.cur[id] = (ma.cur[id] or 0) + q end
			ma.repair = (ma.repair or 0) + (a.repair or 0)
			ma.consum = (ma.consum or 0) + (a.consum or 0)
			ma.mat = (ma.mat or 0) + (a.mat or 0)
			for sname, s in pairs(a.sub) do
				local ms = ma.sub[sname] or { gold = 0, items = {}, n = 0, cur = {} }
				ms.gold, ms.n = ms.gold + s.gold, ms.n + s.n
				for id, q in pairs(s.items) do ms.items[id] = (ms.items[id] or 0) + q end
				for id, q in pairs(s.cur or {}) do ms.cur[id] = (ms.cur[id] or 0) + q end
				ms.repair = (ms.repair or 0) + (s.repair or 0)
				ms.consum = (ms.consum or 0) + (s.consum or 0)
				ms.mat = (ms.mat or 0) + (s.mat or 0)
				ma.sub[sname] = ms
			end
			m.act[k] = ma
		end
		for k, v in pairs(t.out) do m.out[k] = (m.out[k] or 0) + v end
		for k, v in pairs(t.cpv or {}) do m.cpv[k] = (m.cpv[k] or 0) + v end
		m.stockLegacy = (m.stockLegacy or 0) + (t.stockLegacy or 0)
		for k, v in pairs(t.cpvProf or {}) do m.cpvProf[k] = (m.cpvProf[k] or 0) + v end
		for k, v in pairs(t.cpvOrd or {}) do m.cpvOrd[k] = (m.cpvOrd[k] or 0) + v end
		for k, e in pairs(t.consumD or {}) do
			local me = m.consumD[k] or { v = 0, sub = {} }
			me.v = me.v + e.v
			for sname, v in pairs(e.sub) do me.sub[sname] = (me.sub[sname] or 0) + v end
			m.consumD[k] = me
		end
		for k, v in pairs(t.inc) do m.inc[k] = (m.inc[k] or 0) + v end
		for k, v in pairs(t.time) do m.time[k] = (m.time[k] or 0) + v end
		m.xin, m.xout, m.adj = m.xin + t.xin, m.xout + t.xout, m.adj + (t.adj or 0)
		if t.cashOpen and t.cashClose then
			m.cashOpen, m.cashClose, m.hasCash = m.cashOpen + t.cashOpen, m.cashClose + t.cashClose, true
		end
		for id, q in pairs(t.curConv or {}) do m.curConv[id] = (m.curConv[id] or 0) + q end
		for id, cats in pairs(t.curOut or {}) do
			m.curOut[id] = m.curOut[id] or {}
			for k, v in pairs(cats) do m.curOut[id][k] = (m.curOut[id][k] or 0) + v end
		end
		for id, v in pairs(t.curOpen or {}) do m.curOpen[id] = (m.curOpen[id] or 0) + v end
		for id, v in pairs(t.curClose or {}) do m.curClose[id] = (m.curClose[id] or 0) + v end
	end
	return m
end

-- DRE (regime de competência: ouro + itens a valor de mercado)
function Ledger.DRE(m)
	local r = { actGold = 0, actItems = 0, comm = 0, ahFee = 0, out = 0, groups = {} }
	for _, a in pairs(m.act) do
		r.actGold = r.actGold + a.gold
		r.actItems = r.actItems + Ledger.ItemsValue(a.items)
	end
	for k, v in pairs(m.inc) do if k ~= "itemsale" then r.comm = r.comm + v end end
	r.itemsale = m.inc.itemsale or 0   -- caixa da venda de itens das atividades (receita já está nos itens)
	-- 1. Receita bruta · 2. Deduções (comissão da AH 5%: o ouro chega líquido; a DRE mostra o bruto e a dedução)
	r.ahFee = (m.inc.ahsale or 0) / 0.95 * 0.05
	r.gross = r.actGold + r.actItems + r.comm + r.ahFee
	-- 3. Receita líquida
	r.net = r.gross - r.ahFee
	-- 4. CPV
	local cpv = m.cpv or {}
	-- dias antigos (antes do controle de consumo): material comprado no dia = CPV; "ah" não reclassificado também
	r.cpvLegacyMat, r.cpvLegacyAH = m.stockLegacy or 0, m.out.ah or 0
	r.cpvOrders, r.cpvCraft, r.cpvLegacy = cpv.orders or 0, cpv.craft or 0, r.cpvLegacyMat + r.cpvLegacyAH
	r.cpv = r.cpvOrders + r.cpvCraft + r.cpvLegacy
	-- 5. Lucro bruto
	r.grossProfit = r.net - r.cpv
	-- 6. Despesas operacionais
	local consum = 0
	for _, e in pairs(m.consumD or {}) do consum = consum + e.v end
	r.consum = consum
	for _, g in ipairs(Ledger.GROUPS) do
		local gv = g.consum and consum or 0
		for _, k in ipairs(g.keys) do gv = gv + (m.out[k] or 0) end
		r.groups[g.code] = gv
		r.out = r.out + gv
	end
	-- 7. Resultado operacional (EBIT) · 8. Lucro líquido (sem resultado financeiro nem impostos no jogo)
	r.result = r.grossProfit - r.out
	r.netIncome = r.result
	r.grossMargin = r.gross > 0 and r.grossProfit / r.gross or nil
	r.margin = r.gross > 0 and r.result / r.gross or nil
	r.netMargin = r.margin
	-- fora do resultado: material comprado para o estoque
	r.stock = -(m.stockLegacy or 0)
	for _, k in ipairs(Ledger.STOCK_KEYS) do r.stock = r.stock + (m.out[k] or 0) end
	-- caixa: todo ouro pago (despesas em ouro + estoque + "ah" antigo); consumíveis e CPV não são caixa
	r.cashOut = 0
	for _, v in pairs(m.out) do r.cashOut = r.cashOut + v end
	return r
end

-- valor dos itens de uma tabela {itemID = qtd}
function Ledger.ItemsValue(items)
	local v, missing = 0, 0
	for id, q in pairs(items or {}) do
		local p = (id == "sold") and 1 or ns.P.Value(id)
		if p then v = v + p * q else missing = missing + q end
	end
	return v, missing
end
