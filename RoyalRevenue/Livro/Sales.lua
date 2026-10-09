local ADDON, root = ...
root.Livro = root.Livro or {}
local ns = root.Livro
ns.root = root
local L = ns.L

-- Vendas na casa de leilões (veio do LucroCraft): TSM Accounting ou o correio, com o lucro real
-- usando o custo de fabricar que o LucroCraft calcula (se estiver instalado).
local Sales = {}
ns.Sales = Sales

local P = ns.P
local DAYS = 14
local CUT = 0.05

local function Norm(realm) return ((realm or ""):gsub("[%s%-']", "")) end

local function WantedRealms()
	local set = { [Norm(GetRealmName())] = true }
	for char in pairs(LucroLivroDB.chars or {}) do
		local realm = char:match("%-(.+)$")
		if realm then set[Norm(realm)] = true end
	end
	return set
end

-- ===== vendas pelo correio (sem TSM) =====
local function SalesLog()
	LucroLivroDB.salesLog = LucroLivroDB.salesLog or {}
	local k = Norm(GetRealmName())
	LucroLivroDB.salesLog[k] = LucroLivroDB.salesLog[k] or { list = {}, seen = {} }
	return LucroLivroDB.salesLog[k]
end

function Sales.RecordMail()
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
	local cutoff = time() - 60 * 86400
	for j = #log.list, 1, -1 do if log.list[j].t < cutoff then table.remove(log.list, j) end end
	for key, t in pairs(log.seen) do if t < cutoff then log.seen[key] = nil end end
end

-- ===== receitas do LucroCraft: itemID -> custo de fabricar e venda prevista =====
local function RecipeMap()
	local map, byName = {}, {}
	if type(LucroCraftDB) ~= "table" then return map, byName end
	local function put(id, info)
		if id and not map[id] then
			map[id] = info
			local name = C_Item.GetItemNameByID(id)
			if name then byName[name] = byName[name] or {}; byName[name][id] = info.sale or 0 end
		end
	end
	for char, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do
			for _, r in ipairs(e.rows or {}) do
				local q = r.expQty or r.qty or 1
				if q <= 0 then q = 1 end
				local unit = (r.expCost or r.cost or 0) / q
				put(r.itemID, { char = char, r = r, quality = r.quality, sale = r.sale, unit = unit })
				if r.concItemID then put(r.concItemID, { char = char, r = r, quality = r.concQuality, sale = r.concSale, unit = unit }) end
				if r.mix and r.mix.itemID then
					put(r.mix.itemID, { char = char, r = r, quality = r.mix.quality, sale = r.mixSale, unit = (r.mixExpCost or unit * q) / q })
				end
			end
		end
	end
	return map, byName
end

local function VendorBuy(id)
	return type(LucroCraftDB) == "table" and LucroCraftDB.vendor and LucroCraftDB.vendor[id] or nil
end

-- ===== leitura =====
function Sales.Load()
	local data = { items = {}, days = DAYS, total = 0, gold = 0 }
	local cutoff = time() - DAYS * 86400
	local map, byName = RecipeMap()
	data.map = map
	local db = TradeSkillMasterDB
	if type(db) ~= "table" then
		data.own = true
		local list = SalesLog().list
		for _, s in ipairs(list) do
			if s.t >= cutoff then
				-- nome -> itemID (Q1 e Q2 têm o mesmo nome: escolhe o de preço mais próximo)
				local best, bestD
				for id, sale in pairs(byName[s.name] or {}) do
					local d = math.abs((sale or 0) - s.price)
					if not bestD or d < bestD then best, bestD = id, d end
				end
				local key = best or ("n:" .. s.name)
				local it = data.items[key] or { qty = 0, gold = 0, first = s.t, last = s.t, name = s.name }
				it.qty, it.gold = it.qty + s.qty, it.gold + s.price * s.qty
				if s.t < it.first then it.first = s.t end
				if s.t > it.last then it.last = s.t end
				data.items[key] = it
				data.total, data.gold = data.total + s.qty, data.gold + s.price * s.qty
			end
		end
		if #list == 0 then data.err = L["Nenhuma venda registrada ainda: abra o correio depois de vender na casa de leilões."] end
		return data
	end
	local wanted = WantedRealms()
	for key, csv in pairs(db) do
		local realm = type(key) == "string" and key:match("^r@(.-)@internalData@csvSales$")
		if realm and type(csv) == "string" and wanted[Norm(realm)] then
			for line in csv:gmatch("[^\n]+") do
				local is, _, qty, price, _, _, t, source = line:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)$")
				t = tonumber(t)
				if t and t >= cutoff and source == "Auction" then
					local id = tonumber(is:match("^i:(%d+)") or "")
					qty, price = tonumber(qty), tonumber(price)
					if id and qty and price then
						local it = data.items[id] or { qty = 0, gold = 0, first = t, last = t }
						it.qty, it.gold = it.qty + qty, it.gold + price * qty
						if t < it.first then it.first = t end
						if t > it.last then it.last = t end
						data.items[id] = it
						data.total, data.gold = data.total + qty, data.gold + price * qty
					end
				end
			end
		end
	end
	return data
end

-- linhas da aba Vendas (todos os itens vendidos; lucro real quando o LucroCraft conhece a receita)
function Sales.GetRows()
	local d = Sales.Load()
	local rows, sum = {}, { qty = 0, net = 0, profit = 0, days = d.days, err = d.err, own = d.own, allQty = d.total, allGold = d.gold }
	if d.err then return rows, sum end
	for key, it in pairs(d.items) do
		local id = type(key) == "number" and key or nil
		local m = id and d.map[id]
		local avg = it.gold / it.qty
		local net = it.gold * (1 - CUT)
		local unit, npc = m and m.unit, nil
		local vb = id and VendorBuy(id)
		if vb and (not unit or vb < unit) then unit, npc = vb, true end
		local profit = unit and (net - it.qty * unit) or nil
		table.insert(rows, {
			itemID = id,
			icon = id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or 134400,
			name = (m and m.r.name) or (id and C_Item.GetItemNameByID(id)) or it.name or "?",
			char = m and (m.char:match("^([^-]+)")) or "",
			qty = it.qty, perDay = it.qty / d.days, avg = avg, gold = it.gold, net = net,
			sale = m and m.sale, diff = (m and m.sale and m.sale > 0) and (avg / m.sale - 1) or nil,
			unit = unit, npc = npc, craftUnit = m and m.unit, profit = profit,
			first = it.first, last = it.last,
		})
		sum.qty = sum.qty + it.qty
		sum.net = sum.net + net
		sum.profit = sum.profit + (profit or 0)
	end
	return rows, sum
end

local f = CreateFrame("Frame")
f:RegisterEvent("MAIL_INBOX_UPDATE")
f:SetScript("OnEvent", function()
	if LucroLivroDB then pcall(Sales.RecordMail) end
end)
