local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- Estoque de reagentes: bolsa, banco, correio e alts (TSM) + banco do bando de guerra.
-- Sem TSM: só o personagem atual (bolsa, banco, banco de reagentes) e o banco do bando.
local Stock = {}
ns.Stock = Stock

local cache = {}

function Stock.Invalidate()
	wipe(cache)
end

-- devolve { me, alts, warband, total }
function Stock.Get(itemID)
	if not itemID then return nil end
	local c = cache[itemID]
	if c then return c end
	local me, alts, wb = 0, 0, 0
	local is = "i:" .. itemID
	if ns.Pricing.HasTSM() and TSM_API.GetPlayerTotals then
		local ok, p, a = pcall(TSM_API.GetPlayerTotals, is)
		if ok then me, alts = p or 0, a or 0 end
		if TSM_API.GetWarbankQuantity then
			local ok2, w = pcall(TSM_API.GetWarbankQuantity, is)
			if ok2 and type(w) == "number" then wb = w end
		end
	elseif C_Item and C_Item.GetItemCount then
		local okA, all = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
		local okO, own = pcall(C_Item.GetItemCount, itemID, true, false, true, false)
		me = okO and own or 0
		wb = math.max(0, (okA and all or 0) - me)
		-- alts: estoque que o LucroCraft anotou de cada personagem
		alts = ns.Own and ns.Own.AltCount(itemID) or 0
	end
	c = { me = me, alts = alts, warband = wb, total = me + alts + wb }
	cache[itemID] = c
	return c
end

-- quantos crafts o estoque cobre (reagentes com preço; vinculados não contam)
function Stock.CraftsFor(parts)
	local n
	for _, p in ipairs(parts or {}) do
		if not p.bound and p.qty and p.qty > 0 then
			local id = p.buyItem or p.itemID
			local s = Stock.Get(id)
			local k = math.floor((s and s.total or 0) / p.qty)
			if not n or k < n then n = k end
		end
	end
	return n
end

-- o que dá para usar no craft: bolsas (com a de reagentes) + banco do personagem logado + banco do bando.
-- Item em alt não conta. Leitura direta do jogo (sem cache, sem esperar o TSM atualizar).
-- Compra de commodity na AH: conta no momento da compra (COMMODITY_PURCHASE_SUCCEEDED), antes de o item
-- chegar na bolsa. Some sozinho quando a bolsa alcança (ou em 2 min).
local bought = {}      -- [itemID] = { q, base, t, ok }
-- bolsas + banco do personagem LOGADO + banco do bando (GetItemCount é sempre do personagem atual)
local function RawUsable(itemID)
	local okB, bags = pcall(C_Item.GetItemCount, itemID, false, false, false, false)
	local okK, withBank = pcall(C_Item.GetItemCount, itemID, true, false, true, false)
	local okA, all = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
	bags = okB and bags or 0
	withBank = okK and withBank or bags
	local bank = math.max(0, withBank - bags)
	local wb = math.max(0, (okA and all or withBank) - withBank)
	-- "bags" devolvido = bolsa + banco do personagem (é tudo dele); wb = banco do bando
	return bags + bank + wb, bags + bank, wb, bank
end
function Stock.Usable(itemID)
	if not (itemID and C_Item and C_Item.GetItemCount) then return 0, 0, 0 end
	local total, bags, wb = RawUsable(itemID)
	local b = bought[itemID]
	if b and b.ok then
		if total >= b.base + b.q or GetTime() - b.t > 120 then
			bought[itemID] = nil
		else
			local extra = b.base + b.q - total
			return total + extra, bags + extra, wb
		end
	end
	return total, bags, wb
end
function Stock.OnBuy(itemID, qty)
	if not (itemID and qty and qty > 0) then return end
	local b = bought[itemID]
	if b and b.ok and GetTime() - b.t < 120 then
		b.q, b.t, b.ok = b.q + qty, GetTime(), false
	else
		bought[itemID] = { q = qty, base = (RawUsable(itemID)), t = GetTime(), ok = false }
	end
end

function Stock.Text(s)
	if not s then return "—" end
	return string.format(L["%d (você %d · alts %d · bando %d)"], s.total, s.me, s.alts, s.warband)
end

local f = CreateFrame("Frame")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
f:RegisterEvent("BANKFRAME_CLOSED")
f:RegisterEvent("MAIL_CLOSED")
f:SetScript("OnEvent", function() Stock.Invalidate() end)

-- ===== Lista do Auctionator que se atualiza sozinha (como o CraftSim) =====
-- Quem exporta registra um gerador de termos: Stock.LiveList(nome, "queue"|"buy").
-- A cada mudança na bolsa (comprou, pegou do correio) a lista é refeita só com o que ainda falta;
-- item comprado por completo some da lista; tudo comprado → a lista é apagada.
-- LucroCraftDB.liveLists[nome] = { kind, sig }
local builders = {}
function Stock.RegisterListBuilder(kind, fn) builders[kind] = fn end

local function AuctAPI()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.CreateShoppingList and api.ConvertToSearchString then return api end
	return nil
end

-- termos de pesquisa a partir de { {id, qty} } (mesmo formato nas duas listas)
function Stock.Terms(rows)
	local api = AuctAPI()
	local terms, missing = {}, 0
	if not api then return terms, 0 end
	for _, x in ipairs(rows) do
		local name = C_Item.GetItemNameByID(x.id)
		if name and x.qty > 0 then
			local term = { searchString = name, isExact = true, quantity = x.qty }
			local q = ns.Scanner and ns.Scanner.ReagentQuality and ns.Scanner.ReagentQuality(x.id)
			if q then term.tier = q end
			local ok, str = pcall(api.ConvertToSearchString, ADDON, term)
			if ok and str then table.insert(terms, str) else missing = missing + 1 end
		elseif x.qty > 0 then
			missing = missing + 1
		end
	end
	return terms, missing
end

function Stock.LiveList(name, kind, terms)
	LucroCraftDB.liveLists = LucroCraftDB.liveLists or {}
	LucroCraftDB.liveLists[name] = { kind = kind, sig = table.concat(terms, "\n") }
end

local function UpdateLists()
	-- v1.22: a compra pelo Auctionator saiu (compra-se direto em Mercado > Comprar); listas antigas param de ser mexidas
	if LucroCraftDB and LucroCraftDB.liveLists then LucroCraftDB.liveLists = nil end
	do return end
	local lists = LucroCraftDB and LucroCraftDB.liveLists
	local api = AuctAPI()
	if not (lists and api) then return end
	for name, L0 in pairs(lists) do
		local fn = builders[L0.kind]
		if fn then
			Stock.Invalidate()
			local okB, rows = pcall(fn)
			if okB and rows then
				local terms, missing = Stock.Terms(rows)
				local sig = table.concat(terms, "\n")
				if missing == 0 and sig ~= L0.sig then
					if #terms == 0 then
						if api.DeleteShoppingList then pcall(api.DeleteShoppingList, ADDON, name) end
						lists[name] = nil
						ns.Print(string.format(L["lista \"%s\": tudo comprado."], name))
					else
						local ok = pcall(api.CreateShoppingList, ADDON, name, terms)
						if ok then L0.sig = sig end
					end
				end
			end
		end
	end
end
Stock.UpdateLists = UpdateLists

local function AfterBuy()
	cache = {}
	pcall(UpdateLists)
	local fr = LucroCraftFrame
	if fr and fr:IsShown() and ns.UI and fr.currentTab and (fr.currentTab == ns.UI.TAB.QUEUE or fr.currentTab == ns.UI.TAB.BUY) then
		if ns.Buy and ns.Buy._ClearCache then ns.Buy._ClearCache() end
		pcall(ns.UI.RefreshTab, fr.currentTab)
	end
end
if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
	hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, qty) pcall(Stock.OnBuy, itemID, qty) end)
end
do
	local bf = CreateFrame("Frame")
	pcall(bf.RegisterEvent, bf, "COMMODITY_PURCHASE_SUCCEEDED")
	pcall(bf.RegisterEvent, bf, "COMMODITY_PURCHASE_FAILED")
	bf:SetScript("OnEvent", function(_, ev)
		if not LucroCraftDB then return end
		for id, b in pairs(bought) do
			if not b.ok then
				if ev == "COMMODITY_PURCHASE_SUCCEEDED" then b.ok, b.t = true, GetTime() else bought[id] = nil end
			end
		end
		if ev == "COMMODITY_PURCHASE_SUCCEEDED" then AfterBuy() end
	end)
end

local lf, pending = CreateFrame("Frame"), false
lf:RegisterEvent("BAG_UPDATE_DELAYED")
lf:RegisterEvent("MAIL_CLOSED")
for _, ev in ipairs({ "COMMODITY_PURCHASE_SUCCEEDED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "ITEM_PURCHASED", "PLAYERBANKSLOTS_CHANGED", "BANKFRAME_CLOSED" }) do
	pcall(lf.RegisterEvent, lf, ev)
end
lf:SetScript("OnEvent", function()
	if pending or not (LucroCraftDB and LucroCraftDB.liveLists and next(LucroCraftDB.liveLists)) then return end
	pending = true
	-- a compra de commodity chega na bolsa em partes: confere agora e de novo 4 s depois
	C_Timer.After(1, function() pcall(UpdateLists) end)
	C_Timer.After(4, function() pending = false; pcall(UpdateLists) end)
end)
