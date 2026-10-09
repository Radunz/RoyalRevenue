local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- ===== Mercado > Receitas =====
-- Receitas que NENHUM personagem da conta tem (as "não aprendidas" que o scan das profissões guarda), que dá para
-- comprar: drop/tesouro (podem estar na casa de leilões) e vendedor (onde comprar). Treinador, especialização,
-- descoberta e missão ficam de fora.
-- Receita na AH não é commodity: cada servidor tem a sua. O addon lembra o que viu em cada servidor
-- (scan completo, buscas) com a hora, e mostra o preço daqui + o que já viu nos outros.
local RS = {}
ns.RecipeShop = RS

local P = ns.Pricing
local V = ns.Visual
local G = function(c, col) return P.FormatGold(c, col) end

local WEEKS_GOOD, WEEKS_BAD = 4, 12      -- paga em até 4 semanas = COMPRE; mais de 12 = CARO
local CRAFTS_GOOD, CRAFTS_BAD = 10, 50   -- sem ganho semanal (sem concentração): em crafts

if not ns.isPT then
	local T = {
		["Receitas que nenhum personagem tem · onde comprar"] = "Recipes no character has · where to buy",
		["Faltando"] = "Missing",
		["receitas que dá para comprar"] = "recipes you can buy",
		["À venda aqui"] = "For sale here",
		["no último scan de %s"] = "in the last scan of %s",
		["sem scan neste servidor"] = "no scan on this realm",
		["Melhor ganho"] = "Best gain",
		["por semana (com concentração)"] = "per week (with concentration)",
		["Servidores vistos"] = "Realms seen",
		["aprende: %s"] = "learns: %s",
		["Lucro/craft"] = "Profit/craft",
		["Ganho/semana"] = "Gain/week",
		["Preço aqui"] = "Price here",
		["Paga em"] = "Pays back in",
		["%s sem"] = "%s wk",
		["%s crafts"] = "%s crafts",
		["COMPRE"] = "BUY",
		["CARO"] = "PRICEY",
		["VENDEDOR"] = "VENDOR",
		["não está à venda aqui"] = "not for sale here",
		["sem scan"] = "no scan",
		["Visto em outros servidores"] = "Seen on other realms",
		["%s · %s · há %s"] = "%s · %s · %s ago",
		["nenhum anúncio"] = "no listing",
		["Origem"] = "Source",
		["Quem aprende"] = "Who learns it",
		["Mande pelo banco do bando se a receita não for vinculada: o alt pega lá e aprende."] = "Send it through the warband bank if the recipe isn't bound: the alt picks it up and learns it.",
		["Ganho/semana = lucro da semana com a concentração do alt com a receita nova menos sem ela."] = "Gain/week = the alt's weekly concentration profit with the new recipe minus without it.",
		["Mostrar de vendedor"] = "Show vendor recipes",
		["Só com anúncio aqui"] = "Only listed here",
		["Lista no Auctionator"] = "Auctionator list",
		["Royal Revenue - Receitas"] = "Royal Revenue - Recipes",
		["Cria a lista \"Royal Revenue - Receitas\" no Auctionator com as receitas que faltam (de drop)."] = "Creates the \"Royal Revenue - Recipes\" list in Auctionator with the missing (drop) recipes.",
		["Nenhuma receita faltando que dê para comprar. Abra as profissões dos personagens para o addon ler as receitas não aprendidas."] = "No missing recipe you can buy. Open your characters' professions so the addon reads the unlearned recipes.",
		["%d de treinador, especialização, descoberta ou missão ocultas"] = "%d from trainer, specialization, discovery or quest hidden",
		["Clique no nome: busca na casa de leilões"] = "Click the name: search the auction house",
		["há %s"] = "%s ago",
		["Comprar receitas"] = "Buy recipes",
		["receitas"] = "recipes",
		["SEM PREÇO"] = "NO PRICE",
		["VENDE POUCO"] = "SLOW SELLER",
		["NPC"] = "NPC",
		["aqui"] = "here",
		["Mais barato"] = "Cheapest",
		["AH"] = "AH",
		["Preço NPC / AH"] = "NPC / AH price",
		["No vendedor (NPC)"] = "At vendor (NPC)",
		["nunca vista na AH"] = "never seen on AH",
		["vinculada ao bando: sem AH"] = "warbound: no AH",
		["vinculada: não vai para a AH"] = "bound: can't go to AH",
		["visto há %s por %s"] = "seen %s ago at %s",
		["(não estava no último scan)"] = "(not in the last scan)",
		["Vinculada ao bando: não pode ser anunciada na AH. Compre no vendedor/drop com qualquer personagem e mande pelo banco do bando."] = "Warbound: can't be listed on the AH. Buy it at the vendor/drop with any character and send it through the warband bank.",
		["Vinculada ao pegar: não pode ser anunciada na AH. Quem aprende precisa comprar ou pegar ela."] = "Bind on pickup: can't be listed on the AH. The character who learns it must buy or loot it.",
		["Vende/dia"] = "Sold/day",
		["Vende/dia (região)"] = "Sold/day (region)",
		["Chance de vender (TSM)"] = "Sale rate (TSM)",
		["Preço no scan da profissão"] = "Price in profession scan",
		["Preço realista"] = "Realistic price",
		["preço recente (caindo)"] = "recent price (falling)",
		["valor de mercado / venda média"] = "market value / avg sale",
		["igual ao scan"] = "same as scan",
		["Lucro/craft no preço do scan"] = "Profit/craft at scan price",
		["scan"] = "scan",
		["Vende pouco: pode ficar dias na AH até sair, ou não sair nesse preço."] = "Slow seller: may sit on the AH for days, or not sell at this price.",
	}
	for k, v in pairs(T) do L[k] = v end
end

local realmKey
local function RealmKey()
	if realmKey then return realmKey end
	local k = ((GetRealmName and GetRealmName() or "?"):gsub("[%s%-']", ""))
	if GetRealmName and (GetRealmName() or "") ~= "" then realmKey = k end
	return k
end
local function DB()
	LucroCraftDB.recipeAH = LucroCraftDB.recipeAH or {}
	return LucroCraftDB.recipeAH
end
local function RealmDB(realm)
	local d = DB()
	realm = realm or RealmKey()
	d[realm] = d[realm] or { items = {}, scanT = 0, name = GetRealmName and GetRealmName() or realm }
	return d[realm]
end

local function Ago(secs)
	secs = math.max(0, secs)
	if secs < 3600 then return string.format("%d min", math.floor(secs / 60)) end
	if secs < 86400 then return string.format("%d h", math.floor(secs / 3600)) end
	return string.format(ns.isPT and "%d dias" or "%d days", math.floor(secs / 86400))
end

-- ===== origem da receita =====
local function Clean(s) return (s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "") end
-- categoria: "ah" (drop/tesouro/sem origem: pode estar na AH), "vendor", nil (não dá para comprar)
local function Category(src)
	local s = Clean(src)
	local head = (s:match("^([^:|]+)") or ""):lower()
	if s == "" then return "ah" end
	if head:find("drop") or head:find("saque") or head:find("treasure") or head:find("tesouro") or head:find("world creatures") or head:find("criaturas") then return "ah" end
	if head:find("vendor") or head:find("vendedor") or head:find("mercador") then return "vendor" end
	return nil
end
-- só o primeiro vendedor/origem (o texto pode ter vários blocos separados por linha em branco), sem o custo
local function FirstBlock(src) return ((src or ""):gsub("|n|n.*$", "")) end
local function SourceShort(src)
	local s = Clean(FirstBlock(src))
	local parts = {}
	for seg in (s .. "|n"):gmatch("(.-)|n") do
		seg = strtrim(seg)
		if seg ~= "" and not seg:match("^[Cc]ost:") and not seg:match("^[Cc]usto:") then table.insert(parts, seg) end
	end
	s = table.concat(parts, " · ")
	if s == "" then return ns.isPT and "origem desconhecida (pode ser drop)" or "unknown source (may be a drop)" end
	return s
end

-- custo no vendedor, do texto da origem: devolve (texto com ícones pronto para mostrar, cobre se for só ouro)
local function VendorCost(src)
	local c = FirstBlock(src):match("[CcU][ou][sr][tr]?o?:%s*|r(.-)$")
	if not c then return nil end
	c = c:gsub("|n.*$", "")
	local copper
	local g = c:match("^%s*([%d,%.]+)%s*|T[^|]*[Gg][Oo][Ll][Dd][Ii][Cc][Oo][Nn]")
	if g and not c:find("|H") then copper = (tonumber((g:gsub("[,%.]", ""))) or 0) * 10000 end
	-- tira os links (|Hcurrency:..|h ... |h) e aumenta os ícones
	local txt = c:gsub("|H.-|h(.-)|h", "%1"):gsub("(|T[^:|]+):0|t", "%1:12:12|t"):gsub("(|T[^:|]+):0:0|t", "%1:12:12|t")
	txt = strtrim(txt)
	return txt ~= "" and txt or nil, copper
end

-- ===== receitas que faltam na conta =====
-- WeeklyValue é caro (todas as receitas da profissão): uma vez por entrada a cada montagem da lista
local wvCache = {}
local function WV(e)
	local c = wvCache[e]
	if not c then
		local ok, x, info = pcall(ns.Invest.WeeklyValue, e)
		c = { v = ok and x or 0, info = ok and info or nil }
		wvCache[e] = c
	end
	return c.v, c.info
end
local function BaseValue(e) return (WV(e)) end

function RS.Missing()
	wipe(wvCache)
	local learned = {}
	for _, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do
			for _, r in ipairs(e.rows or {}) do if r.recipeID then learned[r.recipeID] = true end end
		end
	end
	local out, byID, hidden = {}, {}, 0
	for char, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do
			for _, u in ipairs(e.unknown or {}) do
				local rid = u.recipeID
				if rid and not learned[rid] then
					local cat = Category(u.source)
					local m = byID[rid]
					if not m then
						m = { rid = rid, row = u, name = u.name, cat = cat, src = u.source, prof = e.parentID or 0, profName = e.name, xname = e.expansion }
						byID[rid] = m
						if cat then table.insert(out, m) else hidden = hidden + 1 end
					end
					-- quem aprende: o personagem com a profissão que rende mais por semana
					local base = BaseValue(e)
					if not m.e or base > (m.base or -1) then m.e, m.char, m.base = e, char, base end
				end
			end
		end
	end
	return out, hidden
end

-- preço REALISTA de venda: o lido no scan da profissão pode ser um anúncio caro que não vende.
-- Fica com o menor entre: preço do scan, preço recente (tendência do TSM: DBRecent vs DBHistorical) e o valor de
-- mercado do reino / da região / venda média da região (Pricing.FlipReference). Vendas/dia e chance de vender
-- (TSM DBRegionSaleRate) marcam o que "vende pouco".
local SLOW_RATE = 0.05
local function Realistic(m)
	local u = m.row
	local id = u.concItemID or u.itemID
	local listed = u.concSale or u.sale
	m.listed, m.real, m.realWhy = listed, listed, nil
	if not listed then return end
	local real, why = listed, nil
	local tr = u.concTrend or u.trend
	if tr and tr < -0.05 then real, why = listed * (1 + tr), "trend" end
	local ok, ref = pcall(P.FlipReference, id)
	if ok and ref and ref > 0 and ref < real then real, why = ref, "ref" end
	m.real, m.realWhy = real, why
	local ok2, rate = pcall(P.SaleRate, id)
	m.rate = ok2 and rate or nil
	m.spd = u.spd
	local minSpd = tonumber(LucroCraftDB.config.minSoldPerDay) or 1
	m.slow = ((u.spd or 0) < minSpd) or (m.rate ~= nil and m.rate < SLOW_RATE)
end

-- ganho por semana com a receita nova: a concentração do alt passa da melhor receita de hoje (ouro/ponto da
-- semana) para a nova, limitada ao que o mercado absorve (vendas/dia × 7). Tudo com o preço realista.
local function Value(m)
	local u, e = m.row, m.e
	Realistic(m)
	local cut = tonumber(LucroCraftDB.config.ahCut) or 0.05
	local qty = u.expQty or u.qty or 1
	local cost = u.expCost or u.cost
	if m.real and cost then m.perCraft = m.real * qty * (1 - cut) - cost else m.perCraft = u.profit end
	m.perCraftListed = u.profit
	m.gain = nil
	if not (e and u.concCost and u.concCost > 0 and m.perCraft) then return end
	if m.perCraft <= 0 then m.gain = 0 return end
	local budget = ns.Invest.ConcPerWeek and ns.Invest.ConcPerWeek() or 0
	local _, info = WV(e)
	local basePer = (info and info.perConc) or 0
	local newPer = m.perCraft / u.concCost
	if newPer <= basePer then m.gain = 0 return end
	local n = budget / u.concCost
	if u.spd and u.spd > 0 then n = math.min(n, u.spd * 7) else n = 0 end
	m.gain = math.max(0, n * (m.perCraft - u.concCost * basePer))
	m.crafts7 = n
end

-- expansão da receita (nome guardado no scan da profissão) → número (para ordenar e para o nome no idioma)
local XP_EN = { "Classic", "The Burning Crusade", "Wrath of the Lich King", "Cataclysm", "Mists of Pandaria", "Warlords of Draenor",
	"Legion", "Battle for Azeroth", "Shadowlands", "Dragonflight", "The War Within", "Midnight", "The Last Titan" }
local function XpacIndex(name, itemID)
	if name and name ~= "" then
		local n = name:lower()
		for i, en in ipairs(XP_EN) do
			if n == en:lower() or n:find(en:lower(), 1, true) then return i - 1 end
			local loc = _G["EXPANSION_NAME" .. (i - 1)]
			if type(loc) == "string" and loc ~= "" and n:find(loc:lower(), 1, true) then return i - 1 end
		end
		-- várias expansões usam o nome do continente na linha de perícia
		local CONT = { { "khaz algar", 10 }, { "dragon isles", 9 }, { "ilhas do dragão", 9 }, { "kul tiran", 7 }, { "zandalari", 7 },
			{ "draenor", 5 }, { "pandaria", 4 }, { "northrend", 2 }, { "nortúndria", 2 }, { "outland", 1 }, { "terralém", 1 } }
		for _, c in ipairs(CONT) do if n:find(c[1], 1, true) then return c[2] end end
	end
	if itemID then
		local x = select(15, C_Item.GetItemInfo(itemID))
		if x then return x end
	end
	return -1
end

-- ===== anúncios vistos por servidor =====
local nameIndex   -- nome em minúsculas → recipeID (das que faltam)
local function BuildIndex()
	nameIndex = {}
	for _, m in ipairs((RS.Missing())) do
		if m.name then nameIndex[m.name:lower()] = m.rid end
	end
	return nameIndex
end

-- "Receita: Nome" / "Pattern: Name" → recipeID
local function MatchName(itemName)
	if not itemName or not nameIndex then return nil end
	local rest = itemName:match("^[^:]+:%s*(.+)$")
	if not rest then return nil end
	return nameIndex[rest:lower()]
end

-- ===== dados do item da receita (vinculação e preço no vendedor) =====
local function Info()
	LucroCraftDB.recipeInfo = LucroCraftDB.recipeInfo or {}
	return LucroCraftDB.recipeInfo
end
local BIND_BOP = { [1] = true, [4] = true }            -- vinculado ao pegar / missão
local BIND_WARBAND = { [7] = true, [8] = true, [9] = true } -- vinculado à conta / ao bando
function RS.NoteItem(rid, itemID, link)
	if not rid or not (itemID or link) then return end
	local inf = Info()[rid] or {}
	Info()[rid] = inf
	inf.item = itemID or inf.item
	local bind = select(14, C_Item.GetItemInfo(link or itemID))
	if bind then inf.bind = bind end
	return inf
end
local function OnMerchant()
	if not (GetMerchantNumItems and GetMerchantItemLink) then return end
	if not nameIndex then BuildIndex() end
	local any = false
	for i = 1, GetMerchantNumItems() do
		local link = GetMerchantItemLink(i)
		local name = link and link:match("%[(.-)%]")
		local rid = MatchName(name)
		if rid then
			local id = tonumber(link:match("item:(%d+)"))
			local inf = RS.NoteItem(rid, id, link)
			local price = 0
			if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
				local ok, d = pcall(C_MerchantFrame.GetItemInfo, i)
				if ok and d then price = d.price or 0 end
			elseif GetMerchantItemInfo then
				price = select(3, GetMerchantItemInfo(i)) or 0
			end
			if inf then inf.vendor, inf.vendorT = price > 0 and price or inf.vendor, time() end
			any = true
		end
	end
	if any then RS.Refresh() end
end

local function Note(rid, itemID, unit, qty, realm)
	local rd = RealmDB(realm)
	local it = rd.items[rid]
	local now = time()
	if not it or now - (it.t or 0) > 120 then it = { item = itemID, n = 0, t = now }; rd.items[rid] = it end
	it.item = itemID or it.item
	if unit and unit > 0 and (not it.min or unit < it.min) then it.min = math.floor(unit) end
	it.n = (it.n or 0) + (qty or 1)
	it.t = now
	it.seenMin, it.seenT = it.min, now
	RS.NoteItem(rid, itemID)
end

-- scan completo (Own.lua chama a cada anúncio): só olha nomes com ":"
function RS.BeginScan() BuildIndex(); RS.scanAcc = {} end
function RS.OnListing(name, itemID, unit, qty)
	local acc = RS.scanAcc
	if not acc or not name or not name:find(":", 1, true) then return end
	local rid = MatchName(name)
	if not rid then return end
	local a = acc[rid]
	if not a then a = { item = itemID, n = 0 }; acc[rid] = a end
	if unit and (not a.min or unit < a.min) then a.min = unit end
	a.n = a.n + (qty or 1)
end
function RS.EndScan()
	local acc = RS.scanAcc
	RS.scanAcc = nil
	if not acc then return end
	local rd = RealmDB()
	local now = time()
	-- o que não apareceu neste scan fica com n = 0 e guarda quando/quanto foi visto pela última vez
	for rid, it in pairs(rd.items) do
		if not acc[rid] and (it.n or 0) > 0 then it.seenMin, it.seenT, it.n, it.min = it.min, it.t, 0, nil end
	end
	for rid, a in pairs(acc) do
		local old = rd.items[rid] or {}
		rd.items[rid] = { item = a.item, min = a.min and math.floor(a.min), n = a.n, t = now, seenMin = a.min and math.floor(a.min), seenT = now }
		RS.NoteItem(rid, a.item)
	end
	rd.scanT = now
	RS.Refresh()
end

-- buscas (Blizzard ou Auctionator): resultados da navegação
local function OnBrowse()
	if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return end
	if not nameIndex then BuildIndex() end
	local ok, list = pcall(C_AuctionHouse.GetBrowseResults)
	if not ok or type(list) ~= "table" then return end
	local any = false
	for _, r in ipairs(list) do
		local id = r.itemKey and r.itemKey.itemID
		local name = id and C_Item.GetItemNameByID(id)
		local rid = MatchName(name)
		if rid then Note(rid, id, r.minPrice, r.totalQuantity); any = true end
	end
	if any then RS.Refresh() end
end

-- ===== montagem =====
function RS.Build()
	local list, hidden = RS.Missing()
	local cfg = LucroCraftDB.config
	local showVendor = cfg.rsVendor ~= false
	local onlyHere = cfg.rsOnlyHere and true or false
	local realm = RealmKey()
	local here = DB()[realm]
	local res = { groups = {}, n = 0, forSale = 0, best = nil, hidden = hidden, realm = realm, scanT = here and here.scanT or 0 }
	local byX = {}
	res.xgroups = {}
	for _, m in ipairs(list) do
		Value(m)
		local h = here and here.items[m.rid]
		m.here = (h and (h.n or 0) > 0) and h or nil
		m.hereSeen = (not m.here and h and h.seenT) and h or nil   -- já esteve à venda aqui
		m.others = {}
		for rk, rd in pairs(DB()) do
			local it = rd.items[m.rid]
			if rk ~= realm and it and ((it.n or 0) > 0 or it.seenT) then
				table.insert(m.others, { realm = rd.name or rk, it = it, now = (it.n or 0) > 0 })
			end
		end
		table.sort(m.others, function(a, b) return (a.it.seenT or a.it.t or 0) > (b.it.seenT or b.it.t or 0) end)
		-- vendedor: custo do texto da origem (ícones) e o preço lido no próprio vendedor
		local inf = Info()[m.rid]
		m.bind = inf and inf.bind
		m.vText, m.vCopper = VendorCost(m.src)
		if inf and inf.vendor and inf.vendor > 0 then m.vCopper = inf.vendor end
		-- não dá para comprar na AH: vinculada ao pegar ou ao bando
		m.noAH = (m.bind and (BIND_BOP[m.bind] or BIND_WARBAND[m.bind])) and true or false
		-- retorno do investimento: o mais barato entre a AH daqui e o vendedor (em ouro)
		-- mais barato entre os servidores com anúncio no último scan (receita não vinculada vai pelo correio/banco do bando)
		m.cheap = m.here and { realm = GetRealmName and GetRealmName() or realm, min = m.here.min, n = m.here.n, here = true } or nil
		m.ahRealms = m.here and 1 or 0
		for _, o in ipairs(m.others) do
			if o.now and o.it.min then
				m.ahRealms = m.ahRealms + 1
				if not m.cheap or o.it.min < m.cheap.min then m.cheap = { realm = o.realm, min = o.it.min, n = o.it.n, t = o.it.t } end
			end
		end
		local price = m.cheap and m.cheap.min
		m.buyAt = price and "ah" or nil
		if m.vCopper and (not price or m.vCopper < price) then price, m.buyAt = m.vCopper, "vendor" end
		m.price = price
		if price and m.gain and m.gain > 0 then m.weeks = price / m.gain
		elseif price and m.perCraft and m.perCraft > 0 then m.crafts = price / m.perCraft end
		if m.cat == "vendor" and m.buyAt ~= "ah" then m.signal = "vendor"
		elseif not price then m.signal = "none"
		elseif m.slow and ((m.weeks and m.weeks <= WEEKS_BAD) or (m.crafts and m.crafts <= CRAFTS_BAD)) then m.signal = "slow"
		elseif (m.weeks and m.weeks <= WEEKS_GOOD) or (m.crafts and m.crafts <= CRAFTS_GOOD) then m.signal = "buy"
		elseif (m.weeks and m.weeks > WEEKS_BAD) or (m.crafts and m.crafts > CRAFTS_BAD) or (not m.weeks and not m.crafts) then m.signal = "pricey"
		else m.signal = "normal" end
		local show = (m.cat ~= "vendor" or showVendor) and (not onlyHere or m.here)
		if show then
			res.n = res.n + 1
			if m.here then res.forSale = res.forSale + 1 end
			if m.gain and m.gain > 0 and (not res.best or m.gain > res.best.gain) then res.best = m end
			local xk = XpacIndex(m.xname, m.row.itemID)
			local xg = byX[xk]
			if not xg then
				xg = { key = xk, name = ns.Sell.ExpansionName(xk), profs = {}, byP = {}, n = 0 }
				byX[xk] = xg
				table.insert(res.xgroups, xg)
			end
			local g = xg.byP[m.prof]
			if not g then
				g = { prof = m.prof, name = (ns.Sell and ns.Sell.ProfName and ns.Sell.ProfName(m.prof)) or m.profName or "?",
					icon = ns.Sell.ProfIcon and ns.Sell.ProfIcon(m.prof), items = {} }
				xg.byP[m.prof] = g
				table.insert(xg.profs, g)
				table.insert(res.groups, g)
			end
			table.insert(g.items, m)
			xg.n = xg.n + 1
		end
	end
	-- expansão atual no topo, depois da mais recente para a mais antiga (Classic no fim), "Outros" por último
	local cur = (GetExpansionLevel and GetExpansionLevel()) or -1
	for _, xg in ipairs(res.xgroups) do if xg.key > cur then cur = xg.key end end
	table.sort(res.xgroups, function(a, b)
		if (a.key == cur) ~= (b.key == cur) then return a.key == cur end
		if (a.key < 0) ~= (b.key < 0) then return b.key < 0 end
		return a.key > b.key
	end)
	for _, xg in ipairs(res.xgroups) do
		table.sort(xg.profs, function(a, b) return a.name:lower() < b.name:lower() end)
	end
	local rank = { buy = 1, normal = 2, slow = 3, pricey = 4, none = 5, vendor = 6 }
	for _, g in ipairs(res.groups) do
		table.sort(g.items, function(a, b)
			if rank[a.signal] ~= rank[b.signal] then return rank[a.signal] < rank[b.signal] end
			local va, vb = a.gain or (a.perCraft or 0) / 100, b.gain or (b.perCraft or 0) / 100
			return va > vb
		end)
	end
	-- servidores vistos
	res.realms = {}
	for rk, rd in pairs(DB()) do if (rd.scanT or 0) > 0 or next(rd.items) then table.insert(res.realms, { name = rd.name or rk, t = rd.scanT }) end end
	table.sort(res.realms, function(a, b) return (a.t or 0) > (b.t or 0) end)
	return res
end

-- ===== desenho =====
local SIGNAL = {
	buy = { txt = "COMPRE", r = 0.15, g = 0.75, b = 0.25 },
	normal = { txt = "NORMAL", r = 0.85, g = 0.7, b = 0.1 },
	pricey = { txt = "CARO", r = 0.85, g = 0.2, b = 0.2 },
	slow = { txt = "VENDE POUCO", r = 0.85, g = 0.45, b = 0.1 },
	none = { txt = "SEM PREÇO", r = 0.35, g = 0.35, b = 0.35 },
	vendor = { txt = "VENDEDOR", r = 0.45, g = 0.45, b = 0.5 },
}

-- custo no vendedor: ouro (lido no vendedor ou no texto) + moedas/itens do texto da origem
function RS.VendorText(m, fmt)
	local cur = m.vText and not m.vText:upper():find("GOLDICON") and m.vText or nil
	if m.vCopper and cur then return fmt(m.vCopper) .. " + " .. cur end
	if m.vCopper then return fmt(m.vCopper) end
	return m.vText or "?"
end

local function Tip(m)
	return function(tt)
		if m.row.itemID then tt:SetItemByID(m.row.itemID) else tt:SetText(m.name or "?") end
		tt:AddLine(" ")
		tt:AddDoubleLine(L["Quem aprende"], ((m.char or ""):match("^([^-]+)") or "?") .. " · " .. (m.profName or ""), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L["Origem"], SourceShort(m.src), 1, 0.82, 0, 1, 1, 1)
		if m.listed then
			tt:AddDoubleLine(L["Preço no scan da profissão"], P.FormatMoney(m.listed), 1, 0.82, 0, 1, 1, 1)
			local why = m.realWhy == "trend" and L["preço recente (caindo)"] or m.realWhy == "ref" and L["valor de mercado / venda média"] or L["igual ao scan"]
			tt:AddDoubleLine(L["Preço realista"], P.FormatMoney(m.real or 0) .. " |cff9d9d9d(" .. why .. ")|r", 1, 0.82, 0, 1, 1, 1)
		end
		if m.perCraft then tt:AddDoubleLine(L["Lucro/craft"], P.FormatMoney(m.perCraft), 1, 0.82, 0, 1, 1, 1) end
		if m.perCraftListed and m.perCraft and math.abs(m.perCraftListed - m.perCraft) > 100 then
			tt:AddDoubleLine(L["Lucro/craft no preço do scan"], P.FormatMoney(m.perCraftListed), 1, 0.82, 0, 0.6, 0.6, 0.6)
		end
		tt:AddDoubleLine(L["Vende/dia (região)"], m.spd and root.Num(m.spd, 2) or "—", 1, 0.82, 0, 1, 1, 1)
		if m.rate then tt:AddDoubleLine(L["Chance de vender (TSM)"], root.Num(m.rate * 100, 1) .. "%", 1, 0.82, 0, 1, 1, 1) end
		if m.slow then tt:AddLine(L["Vende pouco: pode ficar dias na AH até sair, ou não sair nesse preço."], 1, 0.5, 0.2, true) end
		if m.gain then tt:AddDoubleLine(L["Ganho/semana"], P.FormatMoney(m.gain), 1, 0.82, 0, 0.3, 1, 0.3) end
		if m.vText or m.vCopper then tt:AddDoubleLine(L["No vendedor (NPC)"], RS.VendorText(m, P.FormatMoney), 1, 0.82, 0, 1, 1, 1) end
		if m.cheap and m.ahRealms > 1 then
			tt:AddDoubleLine(L["Mais barato"], P.FormatMoney(m.cheap.min) .. " · " .. (m.cheap.here and L["aqui"] or m.cheap.realm), 1, 0.82, 0, 0.3, 1, 0.3)
		end
		if m.here then tt:AddDoubleLine(L["Preço aqui"], P.FormatMoney(m.here.min or 0) .. " (" .. root.Num(m.here.n or 0, 0) .. ")", 1, 0.82, 0, 1, 1, 1)
		elseif m.hereSeen then tt:AddDoubleLine(L["Preço aqui"], L["visto há %s por %s"]:format(Ago(time() - m.hereSeen.seenT), P.FormatMoney(m.hereSeen.seenMin or 0)), 1, 0.82, 0, 0.7, 0.7, 0.7) end
		if m.noAH then
			tt:AddLine(BIND_WARBAND[m.bind] and L["Vinculada ao bando: não pode ser anunciada na AH. Compre no vendedor/drop com qualquer personagem e mande pelo banco do bando."]
				or L["Vinculada ao pegar: não pode ser anunciada na AH. Quem aprende precisa comprar ou pegar ela."], 1, 0.5, 0.2, true)
		end
		if #m.others > 0 then
			tt:AddLine(" ")
			tt:AddLine(L["Visto em outros servidores"], 1, 0.82, 0)
			for _, o in ipairs(m.others) do
				local t = o.it.seenT or o.it.t or 0
				tt:AddLine(string.format(L["%s · %s · há %s"], o.realm, P.FormatMoney(o.it.min or o.it.seenMin or 0), Ago(time() - t))
					.. (o.now and "" or " " .. L["(não estava no último scan)"]), 1, 1, 1)
			end
		end
		tt:AddLine(" ")
		tt:AddLine(L["Ganho/semana = lucro da semana com a concentração do alt com a receita nova menos sem ela."], 0.6, 0.6, 0.6, true)
		if m.cat == "ah" then tt:AddLine(L["Mande pelo banco do bando se a receita não for vinculada: o alt pega lá e aprende."], 0.6, 0.6, 0.6, true) end
	end
end

local function SearchAH(m)
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
	local box = AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.SearchBox
	if box and box.SetText then
		pcall(box.SetText, box, m.name or "")
		local bar = AuctionHouseFrame.SearchBar
		if bar.StartSearch then pcall(bar.StartSearch, bar) end
	end
end

local function Row(cv, y, W, m, idx)
	root.Zebra(cv, idx, 0, y, W, 40)
	local X_NAME, X_PC, X_SPD, X_GAIN, X_PRICE, X_PAY, X_SIG = 48, W - 730, W - 620, W - 540, W - 420, W - 200, W - 96
	local tip = Tip(m)
	cv:Icon(8, y + 4, 32, V.ItemIcon(m.row.itemID, m.row.icon), { tip = tip, link = m.row.itemID and select(2, C_Item.GetItemInfo(m.row.itemID)) or nil })
	cv:Text(X_NAME, y + 5, "|cffffffff" .. (m.name or "?") .. "|r", GameFontHighlight, X_PC - X_NAME - 8)
	cv:Text(X_NAME, y + 22, "|cff9d9d9d" .. string.format(L["aprende: %s"], (m.char or ""):match("^([^-]+)") or "?") .. " · " .. SourceShort(m.src) .. "|r",
		GameFontDisableSmall, X_PC - X_NAME - 8)
	cv:Hit(X_NAME, y + 2, X_PC - X_NAME - 8, 36, function() SearchAH(m) end, function(tt)
		tip(tt)
		if AuctionHouseFrame and AuctionHouseFrame:IsShown() then tt:AddLine(L["Clique no nome: busca na casa de leilões"], 0.4, 0.8, 1) end
	end)
	if m.perCraft and m.perCraftListed and m.perCraftListed - m.perCraft > math.max(10000, math.abs(m.perCraft) * 0.1) then
		cv:Text(X_PC, y + 5, G(m.perCraft, true), GameFontHighlightSmall, 100, "RIGHT")
		cv:Text(X_PC, y + 22, "|cff6f6f6f" .. L["scan"] .. " " .. P.FormatGold(m.perCraftListed) .. "|r", GameFontDisableSmall, 100, "RIGHT")
	else
		cv:Text(X_PC, y + 12, m.perCraft and G(m.perCraft, true) or "|cff9d9d9d—|r", GameFontHighlightSmall, 100, "RIGHT")
	end
	local spdTxt = m.spd and root.Num(m.spd, m.spd < 10 and 1 or 0) or "—"
	cv:Text(X_SPD, y + 12, (m.slow and "|cffff8040" or "|cffffffff") .. spdTxt .. "|r", GameFontHighlightSmall, 70, "RIGHT")
	cv:Text(X_GAIN, y + 12, (m.gain and m.gain > 0) and G(m.gain, true) or "|cff9d9d9d—|r", GameFontHighlightSmall, 100, "RIGHT")
	-- preço: linha 1 = vendedor (se tiver), linha 2 = AH (aqui, outro servidor, ou por que não dá)
	local l1, l2
	if m.vText or m.vCopper then
		l1 = "|cffffd100" .. L["NPC"] .. "|r " .. RS.VendorText(m, G)
	end
	local ah
	if m.cheap then
		local c = m.cheap
		ah = "|cffffd100" .. L["AH"] .. "|r " .. G(c.min or 0) .. " |cff9d9d9d(" .. root.Num(c.n or 0, 0) .. ")|r"
		if m.ahRealms > 1 or not c.here then
			ah = ah .. " " .. (c.here and "|cff9d9d9d" .. L["aqui"] or "|cff55ff55" .. c.realm:sub(1, 12)) .. "|r"
		end
	elseif m.noAH then ah = "|cffff8040" .. (BIND_WARBAND[m.bind] and L["vinculada ao bando: sem AH"] or L["vinculada: não vai para a AH"]) .. "|r"
	elseif #m.others > 0 then
		local o = m.others[1]
		ah = "|cff9d9d9d" .. o.realm .. ":|r " .. G(o.it.min or o.it.seenMin or 0) .. (o.now and "" or " |cff6f6f6f" .. L["há %s"]:format(Ago(time() - (o.it.seenT or 0))) .. "|r")
	elseif m.hereSeen then ah = "|cff9d9d9d" .. L["AH"] .. " " .. P.FormatGold(m.hereSeen.seenMin or 0) .. " · " .. L["há %s"]:format(Ago(time() - m.hereSeen.seenT)) .. "|r"
	elseif (DB()[RealmKey()] and (DB()[RealmKey()].scanT or 0) > 0) or #m.others > 0 then ah = "|cff6f6f6f" .. L["não está à venda aqui"] .. "|r"
	else ah = "|cff6f6f6f" .. L["nunca vista na AH"] .. "|r" end
	if l1 then l2 = ah else l1 = ah end
	if l2 then
		cv:Text(X_PRICE, y + 5, l1, GameFontHighlightSmall, 180, "RIGHT")
		cv:Text(X_PRICE, y + 22, l2, GameFontDisableSmall, 180, "RIGHT")
	else
		cv:Text(X_PRICE, y + 12, l1, GameFontHighlightSmall, 180, "RIGHT")
	end
	local pay = m.weeks and string.format(L["%s sem"], root.Num(m.weeks, 1)) or m.crafts and string.format(L["%s crafts"], root.Num(m.crafts, 0)) or "|cff9d9d9d—|r"
	cv:Text(X_PAY, y + 12, pay, GameFontHighlightSmall, 96, "RIGHT")
	local s = SIGNAL[m.signal] or SIGNAL.none
	cv:Box(X_SIG, y + 9, 86, 22, s.r, s.g, s.b, 0.85)
	cv:Text(X_SIG, y + 14, "|cffffffff" .. L[s.txt] .. "|r", GameFontNormalSmall, 86, "CENTER")
	return y + 40
end

function RS.Render(cv)
	local res = RS.Build()
	local W = cv:Width()
	cv:Begin()
	cv:Text(8, 4, L["Receitas que nenhum personagem tem · onde comprar"], GameFontNormal, W - 460)
	ns.Buy.DrawScan(cv, "recipes", W - 446)
	cv:Button(W - 146, 0, 140, 20, L["Lista no Auctionator"], function() RS.ExportAuctionator(res) end, function(tt)
		tt:SetText(L["Lista no Auctionator"])
		tt:AddLine(L["Cria a lista \"Royal Revenue - Receitas\" no Auctionator com as receitas que faltam (de drop)."], 1, 1, 1, true)
	end)
	local y = 28
	-- filtros
	local cfg = LucroCraftDB.config
	local function Toggle(x, label, key, default)
		local on = cfg[key]
		if on == nil then on = default end
		cv:Box(x, y + 3, 12, 12, 0.83, 0.69, 0.22, on and 1 or 0.2)
		cv:Text(x + 16, y + 2, (on and "|cffffffff" or "|cff6f6f6f") .. label .. "|r", GameFontHighlightSmall, 160)
		cv:Hit(x, y, 170, 18, function() cfg[key] = not on; RS.Refresh() end)
	end
	Toggle(8, L["Mostrar de vendedor"], "rsVendor", true)
	Toggle(190, L["Só com anúncio aqui"], "rsOnlyHere", false)
	y = y + 24

	-- cartões
	local cw = math.floor((W - 8 - 3 * 8) / 4)
	local Card = ns.Buy.UI.Card
	Card(cv, 4, y, cw, L["Faltando"], tostring(res.n), L["receitas que dá para comprar"])
	Card(cv, 4 + (cw + 8), y, cw, L["À venda aqui"], tostring(res.forSale),
		res.scanT > 0 and string.format(L["no último scan de %s"], L["há %s"]:format(Ago(time() - res.scanT))) or L["sem scan neste servidor"])
	Card(cv, 4 + 2 * (cw + 8), y, cw, L["Melhor ganho"], res.best and G(res.best.gain, true) or "|cff9d9d9d—|r",
		res.best and res.best.name or L["por semana (com concentração)"])
	local rl = {}
	for k, r in ipairs(res.realms) do if k <= 3 then table.insert(rl, r.name) end end
	Card(cv, 4 + 3 * (cw + 8), y, cw, L["Servidores vistos"], tostring(#res.realms), table.concat(rl, ", "))
	y = y + 56

	if #res.groups == 0 then
		cv:Text(8, y, L["Nenhuma receita faltando que dê para comprar. Abra as profissões dos personagens para o addon ler as receitas não aprendidas."], GameFontHighlight, W - 16)
		cv:End(y + 30)
		return
	end
	-- cabeçalho das colunas
	local X_PC, X_SPD, X_GAIN, X_PRICE, X_PAY, X_SIG = W - 730, W - 620, W - 540, W - 420, W - 200, W - 96
	cv:Text(X_PC, y, "|cff9d9d9d" .. L["Lucro/craft"] .. "|r", GameFontDisableSmall, 100, "RIGHT")
	cv:Text(X_SPD, y, "|cff9d9d9d" .. L["Vende/dia"] .. "|r", GameFontDisableSmall, 70, "RIGHT")
	cv:Text(X_GAIN, y, "|cff9d9d9d" .. L["Ganho/semana"] .. "|r", GameFontDisableSmall, 100, "RIGHT")
	cv:Text(X_PRICE, y, "|cff9d9d9d" .. L["Preço NPC / AH"] .. "|r", GameFontDisableSmall, 180, "RIGHT")
	cv:Text(X_PAY, y, "|cff9d9d9d" .. L["Paga em"] .. "|r", GameFontDisableSmall, 96, "RIGHT")
	y = y + 16
	for _, xg in ipairs(res.xgroups) do
		local col
		y, col = ns.Sell.Group(cv, y, W, "rx:" .. xg.key, xg.name, root.Num(xg.n, 0) .. " " .. L["receitas"], nil, RS.Refresh)
		if not col then
			for _, g in ipairs(xg.profs) do
				local pcol
				y, pcol = ns.Sell.ProfHeader(cv, y, W, "rx:" .. xg.key .. ":p:" .. g.prof, g.icon, g.name, root.Num(#g.items, 0) .. " " .. L["receitas"], RS.Refresh)
				if not pcol then
					for k, m in ipairs(g.items) do y = Row(cv, y, W, m, k) end
				end
			end
		end
		y = y + 4
	end
	if res.hidden > 0 then
		cv:Text(8, y + 4, "|cff9d9d9d" .. string.format(L["%d de treinador, especialização, descoberta ou missão ocultas"], res.hidden) .. "|r", GameFontDisableSmall, W - 16)
		y = y + 20
	end
	cv:End(y + 8)
end

function RS.ExportAuctionator(res)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
		ns.Print(L["Auctionator não encontrado."])
		return
	end
	res = res or RS.Build()
	local terms = {}
	for _, g in ipairs(res.groups) do
		for _, m in ipairs(g.items) do
			if m.cat == "ah" and m.name then
				local ok, str = pcall(api.ConvertToSearchString, ADDON, { searchString = m.name, isExact = false })
				if ok and str then table.insert(terms, str) end
			end
		end
	end
	if #terms == 0 then ns.Print(L["nada a comprar."]) return end
	local listName = L["Royal Revenue - Receitas"]
	local ok, err = pcall(api.CreateShoppingList, ADDON, listName, terms)
	if ok then ns.Print(string.format(L["lista \"%s\" criada no Auctionator com %d itens."], listName, #terms))
	else ns.Print(L["erro no Auctionator: "] .. tostring(err)) end
end

function RS.Refresh()
	if ns.UI and ns.UI.RefreshTab and ns.UI.TAB and ns.UI.TAB.RECIPES then ns.UI.RefreshTab(ns.UI.TAB.RECIPES) end
end

local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
pcall(f.RegisterEvent, f, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("MERCHANT_SHOW")
pcall(f.RegisterEvent, f, "MERCHANT_UPDATE")
f:SetScript("OnEvent", function(_, event)
	if not LucroCraftDB then return end
	if event == "AUCTION_HOUSE_SHOW" then nameIndex = nil return end
	if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
		if event == "MERCHANT_SHOW" then nameIndex = nil end
		pcall(OnMerchant)
		return
	end
	pcall(OnBrowse)
end)

RS._Category, RS._MatchName, RS._BuildIndex = Category, MatchName, BuildIndex
