local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root

local Pricing = {}
ns.Pricing = Pricing

ns.DEFAULTS = {
	-- Strings de preço do TSM (qualquer custom price válido do TSM funciona)
	-- venda = o menor entre o preço atual (min buyout) e a média de venda na região:
	-- evita preço "fantasma" de 1 anúncio absurdo em itens que quase não vendem (ex.: equipamento)
	saleSource = "min(first(DBMinBuyout, DBMarket), first(DBRegionSaleAvg, DBRegionMarketAvg))",
	costSource = "first(VendorBuy, DBMarket, DBMinBuyout, DBRegionMarketAvg)",
	outputQuality = "auto", -- "auto" = qualidade que sua skill atinge; ou força 1/2/3...
	ahCut = 0.05,        -- corte da AH (5%)
	abcA = 0.80,         -- até 80% acumulado das vendas/dia = A
	abcB = 0.95,         -- até 95% = B, resto = C
	autoOpen = true,     -- abre a janela junto com a profissão
	onlyProfit = false,
	minSoldPerDay = 1,   -- abaixo disso a receita é marcada como "pouca venda"
	volumeMinSpd = 10,   -- lista de receitas: lucrativa com pelo menos isto de vendas/dia = seção "Volume"
	useStats = true,     -- considera multicraft / resourcefulness / ingenuity
	trendDiscount = true,   -- desconta a tendência de QUEDA do preço na projeção de lucro
	saleMaxOverMarket = 2,  -- anúncio acima de N x o mercado do reino não vira preço (0 = sem teto)
	auditFollow = true,     -- a aba Auditoria segue a receita selecionada na janela da profissão
	capByMarket = true,     -- limita os crafts do plano ao que o mercado absorve
	absorbDays = 7,         -- horizonte de venda considerado (dias)
	absorbShare = 0.05,     -- fatia do giro da região que você consegue tomar
	useCrafted = true,   -- usa custo de fabricar reagentes quando for mais barato que comprar
	recoMinABC = "B",    -- recomendações só para itens classe A e B (C = vende pouco)
	recoMinShare = 0.01, -- e com pelo menos 1% das vendas/dia da profissão (/lucro giro <%>)
	excludeGathered = true, -- itens obtidos também por coleta (motes etc.) ficam fora do % de vendas e da curva ABC
	planHold = true,
	ahAutoOpen = true,   -- abrir o Mercado (Compras) ao abrir a casa de leilões e seguir as abas dela     -- Plano: segura a concentração para a receita de mais ouro/ponto (não gasta em receita pior)
	concPerHour = nil,   -- regeneração de concentração/h (nil = aprendida pelos scans, padrão 10,5)
	optimizeReagents = true, -- testa trocar reagentes pela qualidade superior para subir a qualidade sem concentração
	costMode = "mercado",    -- "mercado" = reagente a preço de AH; "estoque" = o que você já tem custa 0 (desembolso)
	trendDrop = 0.15,    -- preço atual 15% abaixo do histórico = "caindo"
	trendSpike = 0.30,   -- 30% acima = "pico"
	betMaxSpd = 2,       -- apostas: itens que vendem menos que isto por dia
	betRatio = 3,        -- apostas: menor preço anunciado ao menos 3x a referência = "caro demais"
	betFlip = true,      -- apostas: mostra itens anunciados bem abaixo da referência (comprar e revender)
	betFlipBelow = 0.6,  -- apostas: "barato" = menor anúncio até 60% da referência
	betAllChars = true,  -- apostas: receitas de todos os personagens (não só o logado)
	salesDays = 14,      -- janela das suas vendas reais (TSM Accounting)
	alertsOnLogin = true,
	alertConcPct = 0.90, -- avisa quando a barra estimada passa disto
	staleDays = 3,       -- scan (skill/stats) mais velho que isto aparece como antigo
	queueIncludePlan = true, -- fila de fabricação inclui o plano de concentração
	priceSource = "auto",  -- "auto" (TSM > Auctionator > LucroCraft) ou força uma fonte
	salvageFocus = true,   -- abre a aba Destruir ao selecionar uma receita de destruição na profissão
}

local SALE_FALLBACK = "first(DBMinBuyout, DBMarket, DBRegionMarketAvg)"

local function Cfg(key)
	local db = LucroCraftDB and LucroCraftDB.config
	if db and db[key] ~= nil then return db[key] end
	return ns.DEFAULTS[key]
end
ns.Cfg = Cfg

-- Ícone de qualidade (o mesmo do jogo). maxQ = 2 para receitas de 2 qualidades do Midnight,
-- 5 para equipamento. Se o atlas não existir, cai para o texto "Q2".
local qCache = {}
local function AtlasOK(name)
	if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
	local ok, info = pcall(C_Texture.GetAtlasInfo, name)
	return ok and info ~= nil
end
-- Tamanho padrão da marca de qualidade em texto. Um só, para a marca não aparecer de um jeito
-- em cada tela (era 10, 11, 12 e 14 conforme o lugar).
ns.QICON_SIZE = 16
-- Marca SOBRE um ícone de item: proporção fixa do ícone, como o jogo faz. Quem desenha é o
-- Canvas:Icon, como TEXTURA (ver ns.QAtlas) — markup de texto nunca encostava no canto.
ns.QICON_FRAC = 0.50   -- metade da altura do ícone: é a proporção que o jogo usa nos reagentes

-- nome do atlas da marca de qualidade (ou nil se o cliente não tiver nenhum deles)
local qAtlas = {}
function ns.QAtlas(q, maxQ)
	if not q then return nil end
	maxQ = maxQ or 2
	local key = q .. ":" .. maxQ
	local v = qAtlas[key]
	if v ~= nil then return v or nil end
	local names = {}
	if maxQ <= 2 then
		table.insert(names, "Professions-Icon-Quality-12-Tier" .. q)
		table.insert(names, "Professions-ChatIcon-Quality-12-Tier" .. q)
	end
	-- o -Small é o que o jogo usa sobre os ícones dos reagentes
	table.insert(names, "Professions-Icon-Quality-Tier" .. q .. "-Small")
	table.insert(names, "Professions-Icon-Quality-Tier" .. q)
	table.insert(names, "Professions-ChatIcon-Quality-Tier" .. q)
	for _, n in ipairs(names) do
		if AtlasOK(n) then qAtlas[key] = n; return n end
	end
	qAtlas[key] = false
	return nil
end

-- largura que mantém a proporção do atlas para uma dada altura
function ns.QAtlasW(atlas, h)
	local okA, info = pcall(C_Texture and C_Texture.GetAtlasInfo or function() end, atlas)
	if okA and info and (info.width or 0) > 0 and (info.height or 0) > 0 then
		return math.max(1, math.floor(h * info.width / info.height + 0.5))
	end
	return h
end

function ns.QIcon(q, maxQ, size)
	if not q then return "" end
	maxQ = maxQ or 2
	size = size or ns.QICON_SIZE
	local key = q .. ":" .. maxQ .. ":" .. size
	if qCache[key] then return qCache[key] end
	local names = {}
	if maxQ <= 2 then
		table.insert(names, "Professions-ChatIcon-Quality-12-Tier" .. q)
		table.insert(names, "Professions-Icon-Quality-12-Tier" .. q .. "-Small")
	end
	table.insert(names, "Professions-ChatIcon-Quality-Tier" .. q)
	table.insert(names, "Professions-Icon-Quality-Tier" .. q .. "-Small")
	local out = "Q" .. q
	for _, n in ipairs(names) do
		if AtlasOK(n) then
			-- A marca do jogo NÃO é quadrada (o link que o próprio jogo gera usa 17 de altura por 15
			-- de largura). Forçar size x size achatava o ícone e era a "proporção diferente do jogo
			-- padrão": a altura manda, e a largura sai da proporção real do atlas.
			local w = size
			local okA, info = pcall(C_Texture and C_Texture.GetAtlasInfo or function() end, n)
			if okA and info and (info.width or 0) > 0 and (info.height or 0) > 0 then
				w = math.max(1, math.floor(size * info.width / info.height + 0.5))
			end
			out = CreateAtlasMarkup(n, w, size)
			break
		end
	end
	qCache[key] = out
	return out
end

-- ===== Ícone da concentração =====
-- A concentração é uma MOEDA por profissão (C_TradeSkillUI.GetConcentrationCurrencyID), e o ícone
-- é o dela — o mesmo que o jogo e o CraftSim mostram. Sem a API (ou profissão desconhecida),
-- fica só o número, como era antes.
local concTex = {}
function ns.ConcTexture(skillLine)
	local key = tonumber(skillLine) or 0
	local c = concTex[key]
	if c ~= nil then return c or nil end
	local tex
	if key > 0 and C_TradeSkillUI and C_TradeSkillUI.GetConcentrationCurrencyID then
		local ok, cur = pcall(C_TradeSkillUI.GetConcentrationCurrencyID, key)
		if ok and cur and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
			local ok2, info = pcall(C_CurrencyInfo.GetCurrencyInfo, cur)
			if ok2 and type(info) == "table" and info.iconFileID then tex = info.iconFileID end
		end
	end
	concTex[key] = tex or false
	return tex
end
-- "<ícone> 179" para FontStrings e tooltips. n = nil mostra só o ícone.
function ns.ConcStr(n, skillLine, size)
	size = size or 14
	local tex = ns.ConcTexture(skillLine)
	local num = n and root.Num(n, 0) or ""
	if not tex then return num end
	return string.format("|T%s:%d:%d:0:0|t%s", tostring(tex), size, size, num ~= "" and (" " .. num) or "")
end

-- ===== Fontes de dados =====
-- Ordem automática: TSM > Auctionator > LucroCraft (scan próprio da casa de leilões).
-- A configuração priceSource pode forçar uma delas ("auto" | "TSM" | "Auctionator" | "LucroCraft").
function Pricing.TSMInstalled()
	return TSM_API ~= nil and TSM_API.GetCustomPriceValue ~= nil
end

function Pricing.AuctionatorInstalled()
	return Auctionator ~= nil and Auctionator.API ~= nil and Auctionator.API.v1 ~= nil
end

function Pricing.Mode()
	local pref = Cfg("priceSource") or "auto"
	if pref == "TSM" and Pricing.TSMInstalled() then return "TSM" end
	if pref == "Auctionator" and Pricing.AuctionatorInstalled() then return "Auctionator" end
	if pref == "LucroCraft" then return "LucroCraft" end
	if Pricing.TSMInstalled() then return "TSM" end
	if Pricing.AuctionatorInstalled() then return "Auctionator" end
	return "LucroCraft"
end

-- "usar o TSM" (instalado e escolhido)
function Pricing.HasTSM()
	return Pricing.TSMInstalled() and Pricing.Mode() == "TSM"
end

-- Auctionator entra como fonte principal ou como reserva do TSM
function Pricing.HasAuctionator()
	local m = Pricing.Mode()
	return Pricing.AuctionatorInstalled() and (m == "Auctionator" or m == "TSM")
end

function Pricing.HasAnySource()
	return true   -- o scan próprio sempre existe (pode estar vazio)
end

function Pricing.SourceName()
	local m = Pricing.Mode()
	if m == "LucroCraft" then return ns.L["scan próprio"] end
	return m
end

local function TSMValue(priceStr, itemID) return root.TSMPrice(priceStr, "i:" .. itemID) end

-- ===== preço fora de escala =====
-- Medido no SavedVariables real: o Auctionator traz valor absurdo em 8 de 5.555 itens — o 241307
-- a 17.000,84g contra 5,02g do TSM (3.386x), o 268475 a 26.535g (41x). Com o TSM configurado como
-- fonte nada acontece, mas com o Auctionator na frente isso vira lucro fantasioso no plano e na
-- curva ABC, e o número sai errado sem nenhum sinal. Quando dá para comparar com o TSM, um valor
-- assim é descartado em vez de usado.
Pricing.SANE_RATIO = 20

-- ===== teto do preço de venda =====
-- Um anúncio sozinho muito acima do mercado não é o preço que você vai conseguir: você entraria
-- abaixo dele. Quando o menor anúncio passa de `saleMaxOverMarket` vezes o valor de mercado do
-- reino, a projeção usa o mercado. Medido nos dados do Uriuri, onde o DBMinBuyout batia 3,6x o
-- DBMarket em várias peças de Couro — exatamente o "o valor vai a 1/4" que ele relatou.
function Pricing.BoundBySale(v, ref)
	if not v or not ref or ref <= 0 then return v end
	local k = tonumber(ns.Cfg("saleMaxOverMarket")) or 2
	if k <= 0 then return v end
	if v > ref * k then return ref end
	return v
end
local avisado = {}
local function Sane(itemID, v, ref)
	if not v or v <= 0 or not ref or ref <= 0 then return v end
	local r = Pricing.SANE_RATIO
	if v > ref * r or v * r < ref then
		if not avisado[itemID] then
			avisado[itemID] = true
			-- Pricing.FormatMoney é definida mais abaixo neste arquivo; aqui só roda em tempo de execução
			local F = Pricing.FormatMoney or tostring
			if ns.Log then
				ns.Log(string.format("preço descartado por estar fora de escala: item %s = %s (referência %s)",
					tostring(itemID), F(v), F(ref)))
			end
		end
		return nil
	end
	return v
end
Pricing._Sane = Sane

local function AuctionatorValue(itemID)
	local v = root.AtrPrice(itemID)
	-- referência do TSM (já cacheada por 60 s); sem TSM não há com o que comparar e o valor passa
	if v and Pricing.HasTSM() then v = Sane(itemID, v, TSMValue("DBMarket", itemID)) end
	return v
end

local function OwnMin(itemID)
	return ns.Own and ns.Own.Min(itemID) or nil
end

function Pricing.Sale(itemID)
	if not itemID then return nil end
	if Pricing.HasTSM() then
		local v = TSMValue(Cfg("saleSource"), itemID)
		if v then return v end
		-- sem o par da região o min() do saleSource não resolve: o fallback vem cru e precisa de teto
		v = Pricing.BoundBySale(TSMValue(SALE_FALLBACK, itemID),
			TSMValue("first(DBMarket, DBRegionMarketAvg, DBHistorical)", itemID))
		if v then return v end
	end
	if Pricing.HasAuctionator() then
		local v = AuctionatorValue(itemID)
		if v then return v end
	end
	local own = OwnMin(itemID)
	if own then return own end
	-- baú/caixa sem preço próprio: valor médio do que sai ao abrir
	-- baú: além do valor, diz que é PROJEÇÃO e de quantas aberturas saiu. Sem isso um valor tirado
	-- de 3 aberturas tinha a mesma cara de um preço do TSM com milhares de anúncios.
	if ns.Containers then
		local v, _, opens = ns.Containers.Value(itemID)
		if v then return v, true, opens end
		return nil
	end
	return nil
end

-- Preço de compra no vendedor (NPC): TSM ou o que o LucroCraft anotou ao abrir vendedores
function Pricing.VendorBuy(itemID)
	if not itemID then return nil end
	if Pricing.HasTSM() then
		local v = TSMValue("VendorBuy", itemID)
		if v and v > 0 then return v end
	end
	local own = ns.Own and ns.Own.Vendor(itemID)
	if own and own > 0 then return own end
	return nil
end

-- Preço para comprar um item pronto (ex.: equipamento de profissão)
function Pricing.Buy(itemID)
	if not itemID then return nil end
	if Pricing.HasTSM() then
		local v = TSMValue("first(DBMinBuyout, DBMarket, DBRegionSaleAvg)", itemID)
		if v then return v end
	end
	if Pricing.HasAuctionator() then
		local v = AuctionatorValue(itemID)
		if v then return v end
	end
	return OwnMin(itemID)
end

function Pricing.Cost(itemID)
	if not itemID then return nil end
	if Pricing.HasTSM() then
		local v = TSMValue(Cfg("costSource"), itemID)
		if v then return v end
	end
	local vendor = ns.Own and ns.Own.Vendor(itemID)
	if vendor and vendor > 0 then return vendor end
	if Pricing.HasAuctionator() then
		local v = AuctionatorValue(itemID)
		if v then return v end
		local ok, av = pcall(Auctionator.API.v1.GetVendorPriceByItemID, ADDON, itemID)
		if ok and type(av) == "number" and av > 0 then return av end
	end
	return OwnMin(itemID)
end

-- Vendas por dia: TSM (região, exato). Sem TSM: estimativa pela queda da quantidade anunciada
-- (histórico diário do Auctionator ou os scans do próprio LucroCraft).
function Pricing.SoldPerDay(itemID)
	if not itemID then return nil end
	if Pricing.HasTSM() then
		local v = TSMValue("DBRegionSoldPerDay * 1000", itemID)
		if v then return v / 1000 end
		-- 2º retorno = "isto é projeção do conteúdo do baú, não venda DESTE item". O Bouquet of
		-- Herbs herdava as 209.356 vendas/dia da erva que sai dele e virava 76% da profissão.
		if ns.Containers and ns.Containers.Get(itemID) then
			return ns.Containers.SoldPerDay(itemID), true
		end
		return nil
	end
	if not ns.Own then return nil end
	if Pricing.HasAuctionator() then
		local v = ns.Own.AtrSoldPerDay(itemID)
		if v then return v end
	end
	return ns.Own.SoldPerDay(itemID)
end

-- ===== Mercado agora (aba Apostas) =====
-- devolve: menor preço anunciado agora (nil = nada anunciado), quantidade anunciada (se souber), se há dado do item
function Pricing.MarketNow(itemID)
	if not itemID then return nil, nil, false end
	if Pricing.HasTSM() then
		local minb = TSMValue("DBMinBuyout", itemID)
		local known = minb or TSMValue("first(DBMarket, DBRegionMarketAvg, DBRegionSaleAvg)", itemID)
		return minb, nil, known ~= nil
	end
	if Pricing.HasAuctionator() and ns.Own then
		local p, q, known = ns.Own.AtrNow(itemID)
		if known then return p, q, true end
	end
	if ns.Own then return ns.Own.Now(itemID) end
	return nil, nil, false
end

-- preço "justo" de referência: média de venda da região (TSM) ou média de 30 dias (Auctionator / scan próprio)
function Pricing.Reference(itemID)
	if not itemID then return nil end
	if Pricing.HasTSM() then
		return TSMValue("first(DBRegionSaleAvg, DBRegionMarketAvg, DBHistorical)", itemID)
	end
	if Pricing.HasAuctionator() and ns.Own then
		local v = ns.Own.AtrMean(itemID)
		if v then return v end
	end
	return ns.Own and ns.Own.Mean(itemID) or nil
end

-- preço "normal" para revenda: o MENOR entre o valor de mercado do reino, o da região e a venda média da região.
-- A venda média sozinha engana: só conta os anúncios que venderam (alguns venderam caro). Sem TSM: Reference.
function Pricing.FlipReference(itemID)
	if not itemID then return nil end
	if Pricing.HasTSM() then
		local best
		for _, src in ipairs({ "DBMarket", "DBRegionMarketAvg", "DBRegionSaleAvg" }) do
			local v = TSMValue(src, itemID)
			if v and v > 0 and (not best or v < best) then best = v end
		end
		return best
	end
	return Pricing.Reference(itemID)
end

-- chance de um anúncio vender na região (TSM DBRegionSaleRate, 0..1); nil sem TSM
function Pricing.SaleRate(itemID)
	if not itemID or not Pricing.HasTSM() then return nil end
	local v = TSMValue("DBRegionSaleRate * 1000", itemID)
	if v then return v / 1000 end
	return nil
end

-- média atual do mercado (TSM DBMarket; sem TSM, média do Auctionator / scan próprio)
function Pricing.Average(itemID)
	if not itemID then return nil end
	if Pricing.HasTSM() then
		local v = TSMValue("first(DBMarket, DBRegionMarketAvg)", itemID)
		if v then return v end
	end
	if Pricing.HasAuctionator() and ns.Own and ns.Own.AtrMean then
		local v = ns.Own.AtrMean(itemID)
		if v then return v end
	end
	return ns.Own and ns.Own.Mean and ns.Own.Mean(itemID) or nil
end

-- valor de destruir 1 unidade do item, pelas tabelas do TSM (prospecção, moagem...); nil sem TSM
function Pricing.Destroy(itemID)
	if not itemID or not Pricing.HasTSM() then return nil end
	local v = TSMValue("Destroy", itemID)
	if v and v > 0 then return v end
	return nil
end

-- vendas/dia é exato (TSM) ou estimado?
function Pricing.SpdIsEstimate()
	return not Pricing.HasTSM()
end


-- ===== Equipamento: preço pelo item level (item string do TSM a partir do link) =====
local function TSMItemString(link)
	if not link or not Pricing.HasTSM() or not TSM_API.ToItemString then return nil end
	local ok, is = pcall(TSM_API.ToItemString, link)
	if ok and type(is) == "string" then return is end
	return nil
end

local function TSMValueStr(priceStr, itemString) return root.TSMPrice(priceStr, itemString) end

-- Venda e vendas/dia da variante exata (item level/bônus) do link; nil se o TSM não tiver dado dela
function Pricing.SaleByLink(link)
	local is = TSMItemString(link)
	if not is or is:match("^i:%d+$") then return nil end
	-- equipamento é precificado pelo item string (nível de item exato), e aí a região quase nunca
	-- tem dado: o saleSource devolve nil e o fallback entrega o DBMinBuyout cru. Daí o teto.
	local v = TSMValueStr(Cfg("saleSource"), is)
	if not v then
		v = Pricing.BoundBySale(TSMValueStr(SALE_FALLBACK, is),
			TSMValueStr("first(DBMarket, DBRegionMarketAvg, DBHistorical)", is))
	end
	local spd = TSMValueStr("DBRegionSoldPerDay * 1000", is)
	return v, spd and spd / 1000 or nil, is
end

function Pricing.BuyByLink(link)
	local is = TSMItemString(link)
	if not is or is:match("^i:%d+$") then return nil end
	return TSMValueStr("first(DBMinBuyout, DBMarket, DBRegionSaleAvg)", is)
end

-- ===== Tendência: preço recente contra o histórico (60 dias) do reino =====
-- devolve fração (-0,20 = 20% abaixo do histórico) ou nil
function Pricing.Trend(itemID)
	if not itemID then return nil end
	if not Pricing.HasTSM() then
		if not ns.Own then return nil end
		if Pricing.HasAuctionator() then
			local t = ns.Own.AtrTrend(itemID)
			if t then return t end
		end
		return ns.Own.Trend(itemID)
	end
	local now = TSMValue("first(DBRecent, DBMarket)", itemID)
	local hist = TSMValue("first(DBHistorical, DBRegionHistorical)", itemID)
	if not now or not hist or hist <= 0 then return nil end
	return now / hist - 1
end

-- "caindo" / "pico" / nil
function Pricing.TrendFlag(t)
	if not t then return nil end
	if t <= -(tonumber(Cfg("trendDrop")) or 0.15) then return "down" end
	if t >= (tonumber(Cfg("trendSpike")) or 0.30) then return "spike" end
	return nil
end

function Pricing.TrendText(t)
	if not t then return "|cff808080—|r" end
	local flag = Pricing.TrendFlag(t)
	local c = flag == "down" and "|cffff5555" or flag == "spike" and "|cffffd100" or "|cff9d9d9d"
	return string.format("%s%+d%%|r", c, math.floor(t * 100 + (t >= 0 and 0.5 or -0.5)))
end

-- Taxa de venda dos SEUS anúncios (TSM Accounting: vendidos ÷ anunciados), 0..1
function Pricing.MySaleRate(itemID)
	if not itemID or not Pricing.HasTSM() then return nil end
	local v = TSMValue("SaleRate * 1000", itemID)
	if v then return v / 1000 end
	return nil
end

-- Auditoria: valor de cada fonte do TSM para o item (em cobre), para conferir de onde veio o preço
local AUDIT_SOURCES = { "DBMinBuyout", "DBMarket", "DBRecent", "DBHistorical", "DBRegionMarketAvg", "DBRegionSaleAvg", "VendorBuy" }
function Pricing.Breakdown(itemID)
	local out = {}
	if not itemID then return out end
	if Pricing.HasTSM() then
		for _, src in ipairs(AUDIT_SOURCES) do
			out[src] = TSMValue(src, itemID)
		end
	end
	if Pricing.HasAuctionator() then
		out.Auctionator = AuctionatorValue(itemID)
	end
	out.usedCost = Pricing.Cost(itemID)
	out.usedSale = Pricing.Sale(itemID)
	return out
end

function Pricing.Validate(priceStr)
	if not Pricing.HasTSM() then return true end
	local ok, valid = pcall(TSM_API.IsCustomPriceValid, priceStr)
	return ok and valid
end

-- Formatação: "1.234,5g" (ouro com 1 casa) — negativos em vermelho
function Pricing.FormatGold(copper, colorize)
	if not copper then return "|cff808080—|r" end
	local neg = copper < 0
	local g = math.abs(copper) / 10000
	local s
	s = root.Num(g, 2) .. ns.GOLD   -- 000.000.000,00
	if neg and math.abs(copper) >= 50 then s = "-" .. s end
	if colorize then
		if neg then return "|cffff5555" .. s .. "|r" end
		return "|cff55ff55" .. s .. "|r"
	end
	return s
end

function Pricing.FormatMoney(copper)
	if not copper then return "—" end
	local s = GetMoneyString(math.abs(math.floor(copper + 0.5)), true)
	if copper < 0 then return "-" .. s end
	return s
end
