local ADDON, root = ...

-- Na Midnight, em combate/instância, alguns argumentos de evento chegam "secretos": comparar dá erro.
-- root.AnySecret(...) = true se algum argumento é secreto (o handler deve ignorar o evento).
-- ===== Bolsas: uma leitura por quadro para todos os módulos =====
-- root.BagCounts() → counts[itemID] = quantidade (bolsas 0..reagentes), loot[itemID] = true se dá para abrir.
-- As tabelas são COMPARTILHADAS: só leitura. Lidas de novo em qualquer BAG_UPDATE ou em outro quadro.
local bagC, bagL, bagT, bagDirty = nil, nil, -1, true
local function BagSecret(v) return issecretvalue and issecretvalue(v) end
function root.BagCounts()
	local now = GetTime and GetTime() or 0
	if bagC and not bagDirty and bagT == now then return bagC, bagL end
	local counts, loot = {}, {}
	if C_Container and C_Container.GetContainerNumSlots then
		local last = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
		local GetInfo = C_Container.GetContainerItemInfo
		for bag = 0, last do
			for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
				local info = GetInfo(bag, slot)
				local id = info and info.itemID
				if id and not BagSecret(id) then
					local n = info.stackCount
					if n == nil or BagSecret(n) then n = 1 end
					counts[id] = (counts[id] or 0) + n
					if info.hasLoot then loot[id] = true end
				end
			end
		end
	end
	bagC, bagL, bagT, bagDirty = counts, loot, now, false
	return counts, loot
end
do
	local bf = CreateFrame("Frame")
	for _, ev in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "ITEM_LOCK_CHANGED" }) do pcall(bf.RegisterEvent, bf, ev) end
	bf:SetScript("OnEvent", function() bagDirty = true end)
end

-- ===== Cache de preço do TSM / Auctionator =====
-- A mesma tela pede o mesmo preço muitas vezes (custo, venda, tendência...). O valor fica guardado por 60 s.
local pc, pcT = {}, 0
local function PriceCacheGet(k)
	local now = GetTime and GetTime() or 0
	if now - pcT > 60 then pc, pcT = {}, now end
	return pc[k]
end
function root.TSMPrice(priceStr, itemString)
	if not (TSM_API and TSM_API.GetCustomPriceValue) then return nil end
	local k = priceStr .. "@" .. itemString
	local v = PriceCacheGet(k)
	if v == nil then
		local ok, x = pcall(TSM_API.GetCustomPriceValue, priceStr, itemString)
		v = (ok and type(x) == "number") and x or false
		pc[k] = v
	end
	return v or nil
end
function root.AtrPrice(itemID)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and api.GetAuctionPriceByItemID) then return nil end
	local k = itemID
	local v = PriceCacheGet(k)
	if v == nil then
		local ok, x = pcall(api.GetAuctionPriceByItemID, ADDON, itemID)
		v = (ok and type(x) == "number") and x or false
		pc[k] = v
	end
	return v or nil
end
function root.ClearPriceCache() pc = {} end

-- data "AAAA-MM-DD" (hora local) de um timestamp, com cache por 15 min (date() é caro em laços longos)
local dayCache, dayCacheN = {}, 0
function root.DayKey(t)
	local b = math.floor(t / 900)
	local d = dayCache[b]
	if not d then
		if dayCacheN > 20000 then dayCache, dayCacheN = {}, 0 end
		d = date("%Y-%m-%d", b * 900)
		dayCache[b] = d
		dayCacheN = dayCacheN + 1
	end
	return d
end

function root.AnySecret(...)
	if not issecretvalue then return false end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then return true end
	end
	return false
end

-- ===== Saída de mensagens: vai para a aba de chat de log (não polui o chat geral) =====
-- Procura uma aba de chat chamada "Log"/"Logs"/"Royal Revenue"/"RR" (ou a escolhida com /rr log <nome>);
-- sem aba assim, usa o chat padrão.
local rawPrint = print
local LOG_NAMES = { log = true, logs = true, ["royal revenue"] = true, rr = true, registro = true }
local logFrame, logAt = nil, 0
function root.LogFrame()
	if logFrame and GetTime() - logAt < 30 then return logFrame end
	logAt = GetTime()
	logFrame = nil
	local want = RoyalRevenueDB and RoyalRevenueDB.logTab and RoyalRevenueDB.logTab:lower()
	if not GetChatWindowInfo then return nil end
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local ok, name, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, i)
		if not ok then name = nil end
		local f = _G["ChatFrame" .. i]
		if name and f and (shown or docked) then
			local n = strtrim(name):lower()
			if (want and n == want) or (not want and LOG_NAMES[n]) then logFrame = f break end
		end
	end
	return logFrame
end
function root.Out(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	local msg = table.concat(parts, " ")
	local okF, f = pcall(root.LogFrame)
	local fb = DEFAULT_CHAT_FRAME or ChatFrame1
	if okF and f then f:AddMessage(msg) elseif fb then fb:AddMessage(msg) else rawPrint(msg) end
end

-- Royal Revenue: um addon com dois módulos (root.Craft = lucro de craft, root.Livro = livro-caixa).
-- Paleta da Pomerânia, terra da família Radünz: azul-noite, azul pomerano, vermelho do grifo, prata e ouro.
root.Brand = {
	navy   = { 0.08, 0.13, 0.24 },   -- #14213D
	blue   = { 0.17, 0.36, 0.66 },   -- #2B5BA8
	red    = { 0.70, 0.13, 0.20 },   -- #B22234 (grifo)
	silver = { 0.85, 0.87, 0.89 },   -- #D9DDE3
	gold   = { 0.83, 0.69, 0.22 },   -- #D4AF37
	hex = { navy = "ff14213d", blue = "ff2b5ba8", red = "ffb22234", silver = "ffd9dde3", gold = "ffd4af37", light = "ff6f9be0" },
}
root.NAME = "|cffd4af37Royal|r |cff6f9be0Revenue|r"
root.Craft = root.Craft or {}
root.Livro = root.Livro or {}

-- Os dados continuam nas tabelas de antes (LucroCraftDB, LucroLivroDB), agora salvas pelo Royal Revenue.
-- Idioma único: RoyalRevenueDB.lang vale para os dois módulos (lido antes dos arquivos de idioma).
if type(RoyalRevenueDB) ~= "table" then RoyalRevenueDB = {} end
local function ensure(db)
	if type(_G[db]) ~= "table" then _G[db] = {} end
	if type(_G[db].config) ~= "table" then _G[db].config = {} end
end
ensure("LucroCraftDB")
ensure("LucroLivroDB")
if RoyalRevenueDB.lang then
	LucroCraftDB.config.lang = RoyalRevenueDB.lang
	LucroLivroDB.config.lang = RoyalRevenueDB.lang
end

function root.SetLang(v)
	RoyalRevenueDB.lang = v
	LucroCraftDB.config.lang = v
	LucroLivroDB.config.lang = v
end

-- abas no TOPO da janela (penduradas acima da barra de título): usa o modelo de aba de cima se o jogo tiver
function root.TopTabTemplate()
	local ok, info = pcall(function() return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("PanelTopTabButtonTemplate") end)
	if ok and info then return "PanelTopTabButtonTemplate" end
	return "PanelTabButtonTemplate"
end

-- ===== abas planas dentro da janela (faixa logo abaixo da barra de título) =====
root.STRIP = 26   -- altura que o conteúdo desce para caber a faixa
function root.MakeTabStrip(frame)
	local B = root.Brand
	local s = CreateFrame("Frame", nil, frame)
	s:SetPoint("TOPLEFT", 4, -23)
	s:SetPoint("TOPRIGHT", -4, -23)
	s:SetHeight(25)
	local bg = s:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(B.navy[1] * 0.7, B.navy[2] * 0.7, B.navy[3] * 0.7, 0.9)
	local line = s:CreateTexture(nil, "BORDER")
	line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
	line:SetColorTexture(B.gold[1], B.gold[2], B.gold[3], 0.45)
	frame.rrStrip = s
	return s
end

function root.MakeTab(strip, name, label, id, onClick)
	local B = root.Brand
	local b = CreateFrame("Button", name, strip)
	b:SetHeight(24)
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("CENTER", 0, 1)
	b:SetFontString(fs)
	b.label = label
	b:SetText(label)
	b:SetWidth(math.max(64, (fs:GetStringWidth() or 60) + 24))
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.07)
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetAllPoints()
	b.sel:SetColorTexture(B.blue[1], B.blue[2], B.blue[3], 0.35)
	b.under = b:CreateTexture(nil, "OVERLAY")
	b.under:SetPoint("BOTTOMLEFT", 6, 1); b.under:SetPoint("BOTTOMRIGHT", -6, 1); b.under:SetHeight(2)
	b.under:SetColorTexture(B.gold[1], B.gold[2], B.gold[3], 1)
	b.sel:Hide(); b.under:Hide()
	b:SetID(id)
	b:SetScript("OnClick", onClick)
	return b
end

function root.SelectTab(tabs, id)
	for _, t in pairs(tabs or {}) do
		local on = t:GetID() == id
		t:SetText(on and ("|cffd4af37" .. t.label .. "|r") or ("|cffd9dde3" .. t.label .. "|r"))
		if t.sel then t.sel:SetShown(on) end
		if t.under then t.under:SetShown(on) end
	end
end

-- ===== números no formato brasileiro: 000.000.000,00 =====
function root.Num(n, dec)
	if n == nil then return "—" end
	dec = dec or 0
	local neg = n < 0
	n = math.abs(n)
	local m = 10 ^ dec
	n = math.floor(n * m + 0.5) / m
	if n == 0 then neg = false end
	local int = math.floor(n)
	local frac = n - int
	local s = tostring(int)
	if int >= 1e15 then s = string.format("%.0f", int) end
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if out:sub(1, 1) == "." then out = out:sub(2) end
	if dec > 0 then
		local f = string.format("%0" .. dec .. "d", math.floor(frac * m + 0.5))
		if #f > dec then f = string.rep("0", dec) end
		out = out .. "," .. f
	end
	return (neg and "-" or "") .. out
end

-- cor das linhas alternadas (zebra) em todas as listas do addon
root.ZEBRA = { 0.17, 0.36, 0.66, 0.10 }
function root.Zebra(cv, i, x, y, w, h)
	if i % 2 == 0 then cv:Box(x, y, w, h, root.ZEBRA[1], root.ZEBRA[2], root.ZEBRA[3], root.ZEBRA[4]) end
end


-- ===== janela sempre dentro da tela =====
-- Encolhe para caber e traz de volta para dentro (o canto de redimensionar nunca fica fora da tela).
-- Devolve true se mudou algo.
function root.FitToScreen(f)
	if not (f and f.GetWidth and UIParent) then return false end
	local s = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	if s <= 0 then s = 1 end
	local sw, sh = UIParent:GetWidth() / s, UIParent:GetHeight() / s
	local w, h = f:GetWidth(), f:GetHeight()
	local changed = false
	if w > sw - 8 then w = sw - 8; changed = true end
	if h > sh - 8 then h = sh - 8; changed = true end
	if changed then f:SetSize(w, h) end
	local l, t = f:GetLeft(), f:GetTop()
	if l and t then
		local nl = math.min(math.max(l, 4), sw - w - 4)
		local nt = math.max(math.min(t, sh - 4), h + 4)
		if math.abs(nl - l) > 0.5 or math.abs(nt - t) > 0.5 then
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", nl, nt)
			changed = true
		end
	end
	return changed
end
function root.ScreenMax(f)
	local s = (f and f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	if s <= 0 then s = 1 end
	return math.floor(UIParent:GetWidth() / s - 8), math.floor(UIParent:GetHeight() / s - 8)
end
