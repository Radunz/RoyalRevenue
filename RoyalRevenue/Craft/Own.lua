local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- Dados próprios do LucroCraft para quem não usa o TSM (ou o Auctionator):
--  o scan da casa de leilões (preço mínimo, quantidade anunciada, histórico diário e giro estimado)
--  o preço dos vendedores (anotado ao abrir o vendedor)
--  o registro das suas vendas (lido do correio da casa de leilões)
--  o estoque de cada personagem (para somar os alts)
-- Também lê o histórico diário do Auctionator para tendência e giro estimado.
local Own = {}
ns.Own = Own

local KEEP_DAYS = 30
local SCAN_COOLDOWN = 15 * 60

local realmKey
local function RealmKey()
	if realmKey then return realmKey end
	local k = ((GetRealmName() or "?"):gsub("[%s%-']", ""))
	if GetRealmName and (GetRealmName() or "") ~= "" then realmKey = k end
	return k
end
local function Day() return math.floor(time() / 86400) end

local function DB()
	LucroCraftDB.ah = LucroCraftDB.ah or {}
	local k = RealmKey()
	LucroCraftDB.ah[k] = LucroCraftDB.ah[k] or { items = {}, last = 0 }
	return LucroCraftDB.ah[k]
end

-- ===== itens que interessam: saídas e reagentes de todas as receitas salvas =====
local TOOL_SCROLLS = { 243966, 243967, 243994, 243995, 244024, 244025 }
local relevant, relevantAt
function Own.Relevant()
	if relevant and relevantAt and time() - relevantAt < 60 then return relevant end
	relevant = {}
	for _, id in ipairs(TOOL_SCROLLS) do relevant[id] = true end
	for _, b in ipairs(ns.Invest and ns.Invest.BUFFS or {}) do relevant[b.itemID] = true end   -- frascos de fabricação
	for _, b in ipairs(ns.Invest and ns.Invest.GATHER_BUFFS or {}) do relevant[b.itemID] = true end   -- chás, frascos e pedra de coleta
	for _, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do
			local list = {}
			for _, r in ipairs(e.rows or {}) do table.insert(list, r) end
			for _, r in ipairs(e.unknown or {}) do table.insert(list, r) end
			for _, r in ipairs(list) do
				if r.itemID then relevant[r.itemID] = true end
				if r.concItemID then relevant[r.concItemID] = true end
				if r.mix and r.mix.itemID then relevant[r.mix.itemID] = true end
				for _, p in ipairs(r.parts or {}) do
					if p.itemID then relevant[p.itemID] = true end
					for _, id in ipairs(p.qualityItems or {}) do relevant[id] = true end
				end
			end
		end
	end
	relevantAt = time()
	return relevant
end

-- ===== leitura do scan próprio =====
function Own.Min(itemID)
	local it = itemID and DB().items[itemID]
	return it and it.m or nil
end

function Own.LastScan() return DB().last end

-- giro estimado: soma das quedas de quantidade anunciada entre scans, por dia
function Own.SoldPerDay(itemID)
	local it = itemID and DB().items[itemID]
	if not it or not it.first then return nil end
	local days = math.min(14, (time() - it.first) / 86400)
	if days < 0.5 then return nil end
	local cutoff, s = Day() - 14, 0
	for d, v in pairs(it.d or {}) do
		if tonumber(d) > cutoff then s = s + (v.s or 0) end
	end
	return s / math.max(days, 1)
end

-- tendência: preço do último scan contra a média dos dias anteriores
function Own.Trend(itemID)
	local it = itemID and DB().items[itemID]
	if not it or not it.m then return nil end
	local sum, n, today = 0, 0, Day()
	for d, v in pairs(it.d or {}) do
		if tonumber(d) < today and v.l then sum = sum + v.l; n = n + 1 end
	end
	if n < 3 or sum <= 0 then return nil end
	return it.m / (sum / n) - 1
end

-- mercado agora pelo scan próprio: preço, quantidade, se o item já foi visto
function Own.Now(itemID)
	local it = itemID and DB().items[itemID]
	if not it then return nil, nil, false end
	if (it.q or 0) == 0 then return nil, 0, true end
	return it.m, it.q, true
end

-- média dos preços mínimos diários guardados (até 30 dias)
function Own.Mean(itemID)
	local it = itemID and DB().items[itemID]
	if not it then return nil end
	local sum, n = 0, 0
	for _, v in pairs(it.d or {}) do
		if v.l then sum = sum + v.l; n = n + 1 end
	end
	return n > 0 and sum / n or nil
end

-- ===== Auctionator: histórico diário (preço mínimo e quantidade anunciada) =====
local function AtrDB()
	return Auctionator and Auctionator.Database
end

function Own.AtrTrend(itemID)
	local db = AtrDB()
	if not db or not db.GetPrice or not db.GetMeanPrice then return nil end
	local ok1, now = pcall(db.GetPrice, db, tostring(itemID))
	local ok2, mean = pcall(db.GetMeanPrice, db, tostring(itemID), 30)
	if ok1 and ok2 and type(now) == "number" and type(mean) == "number" and mean > 0 then
		return now / mean - 1
	end
	return nil
end

-- mercado agora pelo Auctionator: visto hoje = anunciado; não visto há 2+ dias = nada anunciado
function Own.AtrNow(itemID)
	local db = AtrDB()
	if not db or not db.GetPriceAge then return nil, nil, false end
	local key = tostring(itemID)
	local ok, age = pcall(db.GetPriceAge, db, key)
	if not ok or age == nil then return nil, nil, false end
	if age >= 2 then return nil, 0, true end
	local okP, price = pcall(db.GetPrice, db, key)
	local qty
	local okH, hist = pcall(db.GetPriceHistory, db, key)
	if okH and type(hist) == "table" and hist[1] then qty = hist[1].available end
	return okP and price or nil, qty, true
end

function Own.AtrMean(itemID)
	local db = AtrDB()
	if not db or not db.GetMeanPrice then return nil end
	local ok, v = pcall(db.GetMeanPrice, db, tostring(itemID), 30)
	return ok and type(v) == "number" and v > 0 and v or nil
end

function Own.AtrSoldPerDay(itemID)
	local db = AtrDB()
	if not db or not db.GetPriceHistory then return nil end
	local ok, hist = pcall(db.GetPriceHistory, db, tostring(itemID))
	if not ok or type(hist) ~= "table" or #hist < 3 then return nil end
	-- mais recente primeiro; available = maior quantidade vista no dia
	local drops, n = 0, 0
	for i = #hist, 2, -1 do
		local a, b = hist[i].available, hist[i - 1].available
		if a and b then
			n = n + 1
			if b < a then drops = drops + (a - b) end
		end
	end
	if n < 2 then return nil end
	return drops / n
end

-- ===== scan da casa de leilões (C_AuctionHouse.ReplicateItems) =====
local ahOpen, scanning = false, false
-- andamento do scan (aba Compras mostra): phase = "wait" (esperando o servidor) | "read" (lendo os anúncios)
local scan = { phase = nil, i = 0, n = 0, t0 = 0 }
local WAIT_LIMIT = 120
local progTicker

local function Notify()
	if ns.Buy and ns.Buy.ScanProgress then pcall(ns.Buy.ScanProgress) end
end

local function StopTicker()
	if progTicker then progTicker:Cancel(); progTicker = nil end
end

local function Abort(msg)
	scanning, scan.phase = false, nil
	StopTicker()
	if msg then ns.Print(msg) end
	Notify()
end

-- estado para a interface
function Own.ScanStatus()
	local last = DB().last or 0
	local wait = math.max(0, SCAN_COOLDOWN - (time() - last))
	return {
		scanning = scanning, phase = scan.phase, i = scan.i, n = scan.n,
		waited = scanning and (time() - scan.t0) or 0,
		last = last, cooldown = wait, ahOpen = ahOpen,
	}
end

function Own.StartScan(manual)
	if scanning then return end
	if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then return end
	if not ahOpen then
		if manual then ns.Print(L["abra a casa de leilões para escanear."]) end
		return
	end
	local wait = SCAN_COOLDOWN - (time() - (DB().last or 0))
	if wait > 0 then
		if manual then ns.Print(string.format(L["a casa de leilões só permite um scan completo a cada 15 min; faltam %d min."], math.ceil(wait / 60))) end
		return
	end
	scanning = true
	scan.phase, scan.i, scan.n, scan.t0 = "wait", 0, 0, time()
	ns.Print(L["escaneando a casa de leilões..."])
	local ok = pcall(C_AuctionHouse.ReplicateItems)
	if not ok then Abort(L["o jogo recusou o scan da casa de leilões."]) return end
	StopTicker()
	if C_Timer.NewTicker then
		progTicker = C_Timer.NewTicker(1, function()
			if scan.phase == "wait" and time() - scan.t0 > WAIT_LIMIT then
				Abort(L["scan cancelado: o servidor não respondeu em 2 min. Tente de novo."])
				return
			end
			Notify()
		end)
	end
	Notify()
end

local function Store(acc)
	local db = DB()
	local now, day = time(), tostring(Day())
	local found = 0
	for id in pairs(Own.Relevant()) do
		local a, it = acc[id], db.items[id]
		if a then
			found = found + 1
			it = it or { d = {} }
			it.d = it.d or {}
			local dd = it.d[day] or {}
			-- vendido desde o último scan: queda na quantidade anunciada
			if it.q and a.qty < it.q then dd.s = (dd.s or 0) + (it.q - a.qty) end
			it.m, it.q, it.t = math.floor(a.min + 0.5), a.qty, now
			dd.l = dd.l and math.min(dd.l, it.m) or it.m
			dd.a = math.max(dd.a or 0, a.qty)
			it.d[day] = dd
			it.first = it.first or now
			db.items[id] = it
		elseif it and it.q and it.q > 0 then
			-- sumiu da casa de leilões: vendeu (ou foi cancelado)
			local dd = it.d[day] or {}
			dd.s = (dd.s or 0) + it.q
			it.d[day] = dd
			it.q, it.t = 0, now
		end
		if it and it.d then
			for d in pairs(it.d) do
				if tonumber(d) < Day() - KEEP_DAYS then it.d[d] = nil end
			end
		end
	end
	db.last = now
	return found
end

local function Process()
	if scan.phase == "read" then return end   -- o evento pode chegar mais de uma vez
	local n = C_AuctionHouse.GetNumReplicateItems() or 0
	local rel = Own.Relevant()
	local acc, i = {}, 0
	scan.phase, scan.i, scan.n = "read", 0, n
	local RS = ns.RecipeShop
	if RS then pcall(RS.BeginScan) end
	Notify()
	local function step()
		local stop = math.min(n, i + 4000)
		for idx = i, stop - 1 do
			local iname, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(idx)
			if RS and iname and buyout and buyout > 0 and count and count > 0 then RS.OnListing(iname, itemID, buyout / count, count) end
			if itemID and rel[itemID] and buyout and buyout > 0 and count and count > 0 then
				local unit = buyout / count
				local a = acc[itemID]
				if not a then
					acc[itemID] = { min = unit, qty = count }
				else
					if unit < a.min then a.min = unit end
					a.qty = a.qty + count
				end
			end
		end
		i = stop
		scan.i = i
		Notify()
		if i < n then
			C_Timer.After(0, step)
		else
			local found = Store(acc)
			scanning, scan.phase = false, nil
			StopTicker()
			-- aba Compras: guarda o preço com dia e hora (melhor dia/horário para comprar)
			if ns.Buy and ns.Buy.RecordScan then pcall(ns.Buy.RecordScan, acc) end
			if ns.RecipeShop then pcall(ns.RecipeShop.EndScan) end
			ns.Print(string.format(L["scan da casa de leilões concluído: %d anúncios lidos, %d itens das suas receitas."], n, found))
			if ns.Scanner and ns.Scanner.RepriceAll then ns.Scanner.RepriceAll() end
			Notify()
		end
	end
	step()
end

-- ===== vendedores (NPC) =====
function Own.Vendor(itemID)
	return itemID and LucroCraftDB and LucroCraftDB.vendor and LucroCraftDB.vendor[itemID] or nil
end

local function RecordMerchant()
	if not GetMerchantNumItems then return end
	LucroCraftDB.vendor = LucroCraftDB.vendor or {}
	for i = 1, GetMerchantNumItems() do
		local id = GetMerchantItemID and GetMerchantItemID(i)
		local price, stack, extended
		if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
			local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
			if ok and type(info) == "table" then price, stack, extended = info.price, info.stackCount, info.hasExtendedCost end
		elseif GetMerchantItemInfo then
			local _, _, p, q, _, _, _, ext = GetMerchantItemInfo(i)
			price, stack, extended = p, q, ext
		end
		if id and price and price > 0 and not extended then
			LucroCraftDB.vendor[id] = price / math.max(stack or 1, 1)
		end
	end
end

-- ===== suas vendas (correio da casa de leilões) =====
local function SalesLog()
	LucroCraftDB.salesLog = LucroCraftDB.salesLog or {}
	local k = RealmKey()
	LucroCraftDB.salesLog[k] = LucroCraftDB.salesLog[k] or { list = {}, seen = {} }
	return LucroCraftDB.salesLog[k]
end

local function RecordMail()
	if not (GetInboxNumItems and GetInboxInvoiceInfo and GetInboxHeaderInfo) then return end
	local log = SalesLog()
	for i = 1, GetInboxNumItems() do
		local invoiceType, itemName, _, bid, _, _, _, _, _, count = GetInboxInvoiceInfo(i)
		if invoiceType == "seller" and itemName and bid and bid > 0 then
			local daysLeft = select(7, GetInboxHeaderInfo(i)) or 30
			local received = time() - math.floor((30 - daysLeft) * 86400)
			local bucket = math.floor(received / 10800)
			local base = table.concat({ itemName, count or 1, bid }, "|")
			if not (log.seen[base .. "|" .. bucket] or log.seen[base .. "|" .. (bucket - 1)] or log.seen[base .. "|" .. (bucket + 1)]) then
				log.seen[base .. "|" .. bucket] = received
				table.insert(log.list, { t = received, name = itemName, qty = count or 1, price = bid / math.max(count or 1, 1), char = ns.CharKey() })
			end
		end
	end
	-- guarda 60 dias
	local cutoff = time() - 60 * 86400
	for j = #log.list, 1, -1 do if log.list[j].t < cutoff then table.remove(log.list, j) end end
	for key, t in pairs(log.seen) do if t < cutoff then log.seen[key] = nil end end
end

function Own.Sales()
	return SalesLog().list
end

-- ===== estoque de cada personagem (para somar os alts sem o TSM) =====
local function SnapshotInventory()
	if not (C_Item and C_Item.GetItemCount) then return end
	LucroCraftDB.inv = LucroCraftDB.inv or {}
	local mine = {}
	-- bolsas lidas direto (sempre funciona); GetItemCount soma banco e banco de reagentes
	local rel = Own.Relevant()
	local bags = {}
	if C_Container and C_Container.GetContainerNumSlots then
		local last = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
		for bag = 0, last do
			for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID and rel[info.itemID] then
					bags[info.itemID] = (bags[info.itemID] or 0) + (info.stackCount or 1)
				end
			end
		end
	end
	for id in pairs(rel) do
		local ok, n = pcall(C_Item.GetItemCount, id, true, false, true, false)
		if not ok and not Own.countErr then
			Own.countErr = true
			if ns.Log then ns.Log("estoque: GetItemCount " .. tostring(n)) end
		end
		n = (ok and type(n) == "number") and n or 0
		n = math.max(n, bags[id] or 0)
		if n > 0 then mine[id] = n end
	end
	LucroCraftDB.inv[ns.CharKey()] = { t = time(), items = mine }
	-- banco do bando de guerra (compartilhado): total com o bando − só deste personagem
	local wb = {}
	for id in pairs(Own.Relevant()) do
		local okA, all = pcall(C_Item.GetItemCount, id, true, false, true, true)
		local n = (okA and all or 0) - (mine[id] or 0)
		if n > 0 then wb[id] = n end
	end
	LucroCraftDB.invWarband = { t = time(), items = wb }
end

function Own.AltCount(itemID)
	local me, total = ns.CharKey(), 0
	for char, snap in pairs(LucroCraftDB.inv or {}) do
		if char ~= me and snap.items then total = total + (snap.items[itemID] or 0) end
	end
	return total
end

-- ===== eventos =====
local invPending = false
local f = CreateFrame("Frame")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MAIL_INBOX_UPDATE")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("BANKFRAME_CLOSED")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(_, event)
	if not LucroCraftDB then return end
	if event == "AUCTION_HOUSE_SHOW" then
		ahOpen = true
		C_Timer.After(0.5, Notify)
		-- sem TSM e sem Auctionator o LucroCraft precisa do próprio scan
		if ns.Pricing.Mode() == "LucroCraft" then C_Timer.After(2, function() Own.StartScan(false) end) end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		ahOpen = false
		if scanning and scan.phase == "wait" then
			Abort(L["scan cancelado: a casa de leilões fechou antes de o servidor responder."])
		end
		Notify()
	elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
		if scanning then Process() end
	elseif event == "MERCHANT_SHOW" then
		pcall(RecordMerchant)
	elseif event == "MAIL_INBOX_UPDATE" then
		pcall(RecordMail)
	elseif event == "PLAYER_LOGOUT" or event == "BANKFRAME_CLOSED" then
		pcall(SnapshotInventory)
	elseif event == "BAG_UPDATE_DELAYED" then
		if invPending then return end
		invPending = true
		C_Timer.After(10, function() invPending = false; pcall(SnapshotInventory) end)
	end
end)


-- usado nos testes fora do jogo
Own._Process = Process
