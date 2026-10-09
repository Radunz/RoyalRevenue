local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- ===== Baús / caixas que se abrem (ex.: Box of Rocks e Bouquet of Herbs das transmutações) =====
-- O item fabricado não tem preço: o valor está no que sai ao abrir. O addon aprende abrindo:
--   1) janela de saque cuja origem é um item (GetLootSourceInfo "Item-...") → conteúdo direto;
--   2) sem janela (vai direto para a bolsa): o baú (hasLoot) diminui na bolsa e outros itens aumentam
--      no mesmo BAG_UPDATE_DELAYED (ou em até 8 s, se o saque veio depois).
-- LucroCraftDB.containers[itemID] = { opens, out = { [id] = qtd total }, seen = { [id] = vezes }, t }
-- Valor de 1 baú = soma(qtd média × preço de venda do conteúdo). Pricing.Sale/SoldPerDay usam isso
-- quando o baú não tem preço próprio.
local CT = {}
ns.Containers = CT

local function DB()
	LucroCraftDB.containers = LucroCraftDB.containers or {}
	return LucroCraftDB.containers
end

function CT.Get(itemID)
	local c = LucroCraftDB and LucroCraftDB.containers and LucroCraftDB.containers[itemID]
	if c and (c.opens or 0) > 0 then return c end
	return nil
end

-- valor de 1 baú (cobre) e a lista do conteúdo { itemID, avg, chance, price, value }
local depth = 0
function CT.Value(itemID)
	local c = CT.Get(itemID)
	if not c or depth > 2 then return nil end
	depth = depth + 1
	local total, list, any = 0, {}, false
	for id, q in pairs(c.out) do
		local avg = q / c.opens
		local price = ns.Pricing.Sale(id) or ns.Pricing.VendorSell and ns.Pricing.VendorSell(id) or nil
		if price then any = true end
		local value = price and price * avg or nil
		total = total + (value or 0)
		table.insert(list, { itemID = id, avg = avg, chance = math.min(1, (c.seen[id] or 0) / c.opens), price = price, value = value })
	end
	depth = depth - 1
	table.sort(list, function(a, b) return (a.value or 0) > (b.value or 0) end)
	if not any then return nil, list, c.opens end
	return total, list, c.opens
end

-- qualidade de cima de um reagente: pelos espaços das receitas salvas (qualityItems = { q1, q2, ... })
local upMap
local function BuildUp()
	upMap = {}
	for _, es in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(es) do
			for _, list in ipairs({ e.rows or {}, e.unknown or {} }) do
				for _, r in ipairs(list) do
					for _, p in ipairs(r.parts or {}) do
						local q = p.qualityItems
						if q and #q > 1 then for i = 1, #q - 1 do upMap[q[i]] = q[i + 1] end end
					end
				end
			end
		end
	end
end
function CT.Higher(id)
	if not upMap then BuildUp() end
	return upMap[id]
end

-- projeção do baú de qualidade de cima: o mesmo conteúdo, cada item trocado pela qualidade de cima (se existir)
function CT.ProjectHigher(itemID)
	local c = CT.Get(itemID)
	if not c then return nil end
	local total, any = 0, false
	for id, q in pairs(c.out) do
		local up = CT.Higher(id) or id
		local price = ns.Pricing.Sale(up)
		if price then total = total + price * q / c.opens; any = true end
	end
	return any and total or nil
end

-- vendas/dia do conteúdo que mais pesa no valor
function CT.SoldPerDay(itemID)
	local _, list = CT.Value(itemID)
	local top = list and list[1]
	if not top then return nil end
	depth = depth + 1
	local v = ns.Pricing.SoldPerDay(top.itemID)
	depth = depth - 1
	return v
end

local function Record(itemID, n, gains)
	local any = false
	for _ in pairs(gains) do any = true break end
	if not any then return false end
	local c = DB()[itemID] or { opens = 0, out = {}, seen = {} }
	DB()[itemID] = c
	c.opens = c.opens + n
	for id, q in pairs(gains) do
		c.out[id] = (c.out[id] or 0) + q
		c.seen[id] = (c.seen[id] or 0) + math.min(n, q)
	end
	c.t = time()
	if ns.Log then
		local parts = {}
		for id, q in pairs(gains) do table.insert(parts, q .. "x " .. id) end
		ns.Log(string.format("baú %d aberto %dx: %s", itemID, n, table.concat(parts, ", ")))
	end
	return true
end

-- ===== bolsa =====
local snap, boxes = nil, {}
local function Snapshot() return root.BagCounts() end   -- tabelas compartilhadas: só leitura

local pending   -- { item, n, t } baú que saiu da bolsa sem conteúdo ainda
local lootFromItem = false
local function OnBags()
	local now, loot = Snapshot()
	for id in pairs(loot) do boxes[id] = true end
	if snap then
		local drops, gains = {}, {}
		for id, q in pairs(snap) do
			local d = q - (now[id] or 0)
			if d > 0 and boxes[id] then drops[id] = d end
		end
		for id, q in pairs(now) do
			local g = q - (snap[id] or 0)
			if g > 0 then gains[id] = g end
		end
		local box, n
		for id, d in pairs(drops) do box, n = id, d end   -- normalmente um só
		if box and not lootFromItem then
			if not Record(box, n, gains) then pending = { item = box, n = n, t = GetTime() } else pending = nil end
		elseif pending and not box and not lootFromItem and GetTime() - pending.t < 8 then
			if Record(pending.item, pending.n, gains) then pending = nil end
		end
	end
	snap = now
	lootFromItem = false
end

-- janela de saque vinda de um item (baú)
local function OnLoot()
	if not (GetNumLootItems and GetLootSourceInfo) then return end
	local fromItem = false
	local gains = {}
	for i = 1, GetNumLootItems() do
		local guid = GetLootSourceInfo(i)
		if type(guid) == "string" and guid:find("^Item%-") then fromItem = true end
		local link = GetLootSlotLink and GetLootSlotLink(i)
		local id = link and C_Item.GetItemInfoInstant(link)
		if id then
			local _, _, qty = GetLootSlotInfo(i)
			gains[id] = (gains[id] or 0) + ((type(qty) == "number" and qty > 0) and qty or 1)
		end
	end
	if not fromItem then return end
	-- qual baú: o que acabou de sair da bolsa (pendente) ou o que está saindo agora
	local now = Snapshot()
	local box
	if pending and GetTime() - pending.t < 8 then box = pending.item end
	if not box and snap then
		for id, q in pairs(snap) do if boxes[id] and q > (now[id] or 0) then box = id end end
	end
	if box then
		Record(box, pending and pending.n or 1, gains)
		pending = nil
		lootFromItem = true   -- os itens que entrarem na bolsa a seguir já foram contados
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("LOOT_READY")
f:SetScript("OnEvent", function(_, event)
	if not LucroCraftDB then return end
	if event == "LOOT_READY" then pcall(OnLoot)
	elseif event == "PLAYER_ENTERING_WORLD" then snap = nil; pcall(OnBags)
	else pcall(OnBags) end
end)

CT._OnBags, CT._OnLoot, CT._Record = OnBags, OnLoot, Record
