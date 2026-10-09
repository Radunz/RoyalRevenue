local ADDON, root = ...
root.Livro = root.Livro or {}
local ns = root.Livro
ns.root = root
local L = ns.L

-- Preço dos itens recebidos: TSM > Auctionator > preço de venda ao vendedor.
-- Item vinculado (não vai para a casa de leilões) vale o preço do vendedor.
local P = {}
ns.P = P

local TSM_STR = "first(DBMarket, DBRegionMarketAvg, DBMinBuyout)"

local function TSMValue(itemID)
	local v = root.TSMPrice(TSM_STR, "i:" .. itemID)
	if v and v > 0 then return v end
end

local function AuctionatorValue(itemID)
	local v = root.AtrPrice(itemID)
	if v and v > 0 then return v end
end

function P.SourceName()
	if TSM_API then return "TSM" end
	if Auctionator and Auctionator.API then return "Auctionator" end
	return L["vendedor"]
end

-- valor de UMA unidade e de onde veio ("ah", "vendor" ou nil)
-- vínculos que não vão para a AH: ao pegar, missão, conta/bando de guerra
local BOUND = { [1] = true, [4] = true, [7] = true, [8] = true, [9] = true }
-- vendorOnly: avaliar pelo vendedor (equipamento de recompensa de missão: acaba vendido ou desencantado)
-- valor de desencantar (TSM "Destroy"), se houver
local function DisenchantValue(itemID)
	local v = root.TSMPrice("Destroy", "i:" .. itemID)
	if v and v > 0 then return v end
end

-- Equipamento (armas e armaduras): o preço da AH do item base não serve. Cada peça tem nível/bônus
-- diferentes e quase não vende; um único anúncio absurdo vira o "valor de mercado" (ex.: 2.000–3.200g
-- para peça que vale 20g no vendedor). O destino real é vendedor ou desencantar: vale o maior dos dois.
function P.Value(itemID, vendorOnly)
	if not itemID then return nil end
	local _, _, _, _, _, _, _, _, _, _, sell, classID, _, bind = C_Item.GetItemInfo(itemID)
	if not classID then classID = select(6, C_Item.GetItemInfoInstant(itemID)) end
	if classID == 2 or classID == 4 then
		local de = DisenchantValue(itemID)
		local v = math.max(sell or 0, de or 0)
		return v > 0 and v or nil, (de and de > (sell or 0)) and "de" or "vendor"
	end
	local vi = type(LucroLivroDB) == "table" and LucroLivroDB.vendorItems
	if vendorOnly or BOUND[bind] or (vi and vi[itemID]) then return sell and sell > 0 and sell or nil, "vendor" end
	local v = TSMValue(itemID) or AuctionatorValue(itemID)
	if v then return v, "ah" end
	if sell and sell > 0 then return sell, "vendor" end
	return nil
end

function P.Sale(itemID)
	return TSMValue(itemID) or AuctionatorValue(itemID)
end

function P.FormatGold(copper, colorize)
	if not copper then return "|cff808080—|r" end
	local neg = copper < 0
	local g = math.abs(copper) / 10000
	local s
	s = root.Num(g, 2) .. ns.GOLD   -- 000.000.000,00
	if neg and math.abs(copper) >= 50 then s = "-" .. s end
	if colorize then
		if neg then return "|cffff5555" .. s .. "|r" end
		if copper > 0 then return "|cff55ff55" .. s .. "|r" end
	end
	return s
end

-- formato contábil: números alinhados, negativos entre parênteses; ouro inteiro acima de 100
-- tone: nil = neutro, true = verde/vermelho suave conforme o sinal
function P.Acct(copper, tone, dash)
	if copper == nil then return "|cff6f6f6f—|r" end
	if dash and math.abs(copper) < 1 then return "|cff6f6f6f—|r" end
	local g = math.abs(copper) / 10000
	local s
	s = root.Num(g, 2)   -- 000.000.000,00
	s = s .. ns.GOLD
	if copper < 0 then s = "(" .. s .. ")" end
	if tone then
		if copper < 0 then return "|cffe07a7a" .. s .. "|r" end
		if copper > 0 then return "|cff7fd18b" .. s .. "|r" end
	elseif copper < 0 then
		return "|cffe07a7a" .. s .. "|r"
	end
	return s
end

function P.Pct(v, tone)
	if not v or v ~= v or v == math.huge or v == -math.huge then return "|cff6f6f6f—|r" end
	local s = root.Num(v * 100, 1) .. "%"
	if tone then
		if v < 0 then return "|cffe07a7a" .. s .. "|r" end
		if v > 0 then return "|cff7fd18b+" .. s .. "|r" end
	end
	return s
end

function P.FormatMoney(copper)
	if not copper then return "—" end
	local s = GetMoneyString(math.abs(math.floor(copper + 0.5)), true)
	if copper < 0 then return "-" .. s end
	return s
end
