local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- Vendas reais x esperadas: lê o histórico de vendas do TSM Accounting (TradeSkillMasterDB, dados até
-- o último logout) e compara com o que o addon previu para cada receita.
local Sales = {}
ns.Sales = Sales

local P = ns.Pricing
local Cfg = ns.Cfg

local data, loadedAt

local function Norm(realm) return ((realm or ""):gsub("[%s%-']", "")) end

-- reinos dos seus personagens salvos no LucroCraft (+ o atual)
local function WantedRealms()
	local set = { [Norm(GetRealmName())] = true }
	for char in pairs(LucroCraftDB.chars or {}) do
		local realm = char:match("%-(.+)$")
		if realm then set[Norm(realm)] = true end
	end
	return set
end

function Sales.Load(force)
	if data and not force and loadedAt and time() - loadedAt < 600 then return data end
	local days = tonumber(Cfg("salesDays")) or 14
	data = { items = {}, days = days, total = 0, gold = 0 }
	loadedAt = time()
	local db = TradeSkillMasterDB
	local cutoff = time() - days * 86400
	if type(db) ~= "table" or not ns.Pricing.HasTSM() then
		-- sem TSM: vendas que o próprio LucroCraft registrou pelo correio da casa de leilões
		data.own = true
		local list = ns.Own and ns.Own.Sales() or {}
		-- nome do item -> itens fabricados com esse nome (Q1 e Q2 têm o mesmo nome: escolhe pelo preço mais próximo)
		local byName = {}
		for _, entries in pairs(LucroCraftDB.chars or {}) do
			for _, e in pairs(entries) do
				for _, r in ipairs(e.rows or {}) do
					for _, v in ipairs({ { r.itemID, r.sale }, { r.concItemID, r.concSale }, { r.mix and r.mix.itemID, r.mixSale } }) do
						local id = v[1]
						local name = id and C_Item.GetItemNameByID(id)
						if name then
							byName[name] = byName[name] or {}
							byName[name][id] = v[2] or byName[name][id] or 0
						end
					end
				end
			end
		end
		for _, s in ipairs(list) do
			if s.t >= cutoff and byName[s.name] then
				local best, bestD
				for id, sale in pairs(byName[s.name]) do
					local d = math.abs((sale or 0) - s.price)
					if not bestD or d < bestD then best, bestD = id, d end
				end
				local it = data.items[best] or { qty = 0, gold = 0, first = s.t, last = s.t }
				it.qty = it.qty + s.qty
				it.gold = it.gold + s.price * s.qty
				if s.t < it.first then it.first = s.t end
				if s.t > it.last then it.last = s.t end
				data.items[best] = it
			end
			if s.t >= cutoff then
				data.total = data.total + s.qty
				data.gold = data.gold + s.price * s.qty
			end
		end
		if #list == 0 then data.err = L["Nenhuma venda registrada ainda: abra o correio depois de vender na casa de leilões."] end
		return data
	end
	local wanted = WantedRealms()
	for key, csv in pairs(db) do
		local realm = type(key) == "string" and key:match("^r@(.-)@internalData@csvSales$")
		if realm and type(csv) == "string" and wanted[Norm(realm)] then
			-- itemString,stackSize,quantity,price,otherPlayer,player,time,source
			for line in csv:gmatch("[^\n]+") do
				local is, _, qty, price, _, _, t, source = line:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)$")
				t = tonumber(t)
				if t and t >= cutoff and source == "Auction" then
					local id = tonumber(is:match("^i:(%d+)") or "")
					qty, price = tonumber(qty), tonumber(price)
					if id and qty and price then
						local it = data.items[id] or { qty = 0, gold = 0, first = t, last = t }
						it.qty = it.qty + qty
						it.gold = it.gold + price * qty
						if t < it.first then it.first = t end
						if t > it.last then it.last = t end
						data.items[id] = it
						data.total = data.total + qty
						data.gold = data.gold + price * qty
					end
				end
			end
		end
	end
	return data
end

-- { qty, gold, avg, perDay } do item na janela configurada
function Sales.Get(itemID)
	if not itemID then return nil end
	local d = Sales.Load()
	local it = d.items[itemID]
	if not it then return nil end
	it.avg = it.gold / it.qty
	it.perDay = it.qty / d.days
	return it
end

function Sales.PerDay(itemID)
	local it = Sales.Get(itemID)
	return it and it.perDay or nil
end

-- itemID -> receita que o fabrica (qualquer personagem), com o custo e a venda previstos da variante
local function RecipeMap()
	local map = {}
	local function put(id, info)
		if id and not map[id] then map[id] = info end
	end
	for char, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do
			for _, r in ipairs(e.rows or {}) do
				local q = r.expQty or r.qty or 1
				if q <= 0 then q = 1 end
				local unit = (r.expCost or r.cost or 0) / q
				put(r.itemID, { char = char, e = e, r = r, quality = r.quality, sale = r.sale, unit = unit, spd = r.spd })
				if r.concItemID then
					put(r.concItemID, { char = char, e = e, r = r, quality = r.concQuality, sale = r.concSale, unit = unit, spd = r.concSpd })
				end
				if r.mix and r.mix.itemID then
					put(r.mix.itemID, { char = char, e = e, r = r, quality = r.mix.quality, sale = r.mixSale,
						unit = (r.mixExpCost or unit * q) / q, spd = r.mixSpd })
				end
			end
		end
	end
	return map
end

local function Short(char) return (char:match("^([^-]+)")) or char end

-- Linhas da aba Histórico: uma por item fabricável vendido na janela
function Sales.GetRows()
	local d = Sales.Load(true)
	local rows, sum = {}, { qty = 0, net = 0, profit = 0, days = d.days, err = d.err, allQty = d.total, allGold = d.gold, own = d.own }
	if d.err then return rows, sum end
	local cut = Cfg("ahCut")
	local map = RecipeMap()
	for id, it in pairs(d.items) do
		local m = map[id]
		if m then
			local avg = it.gold / it.qty
			local net = it.gold * (1 - cut)
			-- item que o vendedor (NPC) vende mais barato que fabricar: foi revenda, o custo é o do vendedor
			local unit, npc = m.unit or 0, nil
			local vb = P.VendorBuy and P.VendorBuy(id)
			if vb and vb < unit then unit, npc = vb, true end
			local profit = net - it.qty * unit
			local r = m.r
			table.insert(rows, {
				itemID = id, recipeID = r.recipeID,
				icon = (C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or r.icon,
				name = r.name or C_Item.GetItemNameByID(id) or ("item " .. id),
				quality = m.quality, maxQuality = r.maxQuality,
				char = Short(m.char),
				qty = it.qty, perDay = it.qty / d.days, avg = avg, gold = it.gold,
				sale = m.sale, diff = (m.sale and m.sale > 0) and (avg / m.sale - 1) or nil,
				unit = unit, profit = profit, npc = npc, craftUnit = m.unit,
				share = (m.spd and m.spd > 0) and ((it.qty / d.days) / m.spd) or nil,
				rate = P.MySaleRate(id),
				first = it.first, last = it.last,
			})
			sum.qty = sum.qty + it.qty
			sum.net = sum.net + net
			sum.profit = sum.profit + profit
		end
	end
	return rows, sum
end

function Sales.Refresh()
	-- a tela de vendas foi para o LucroLivro; aqui só ficam os dados (coluna Minhas/dia)
end

