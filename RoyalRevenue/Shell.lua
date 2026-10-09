local ADDON, root = ...
local print = function(...) return root.Out(...) end   -- mensagens vão para a aba de log

-- Casca do Royal Revenue: janela única (Craft e Livro-caixa trocam no mesmo lugar), menu, minimapa,
-- comando /rr e a pele com as cores da Pomerânia.
local B = root.Brand
local C = root.Craft
local LV = root.Livro

local function L(k) return (C.L and C.L[k]) or k end

-- ===== pele =====
local function TintTex(t, r, g, b)
	if type(t) ~= "table" or not t.SetVertexColor then return end
	if t.SetDesaturated then t:SetDesaturated(true) end
	t:SetVertexColor(r, g, b)
end

function root.SkinButton(btn)
	if not btn or btn.rrSkinned then return end
	local parts = { btn.Left, btn.Middle, btn.Right, btn.LeftActive, btn.MiddleActive, btn.RightActive }
	local any = false
	for _, t in ipairs(parts) do
		if type(t) == "table" then TintTex(t, 0.42, 0.62, 1.0); any = true end
	end
	if any then btn.rrSkinned = true end
end

function root.Skin(frame, depth)
	if not frame or (depth or 0) > 6 then return end
	root.SkinButton(frame)
	for _, child in ipairs({ frame:GetChildren() }) do root.Skin(child, (depth or 0) + 1) end
end

local function Decorate(frame, which)
	if not frame or frame.rrDecorated then return end
	frame.rrDecorated = true
	-- fundo azul-noite por cima do mármore e barra de título vermelha (grifo)
	local host = frame.Inset or frame
	local tint = host:CreateTexture(nil, "BORDER", nil, -7)
	tint:SetAllPoints(host)
	tint:SetColorTexture(B.navy[1], B.navy[2], B.navy[3], 0.55)
	if frame.TitleBg then TintTex(frame.TitleBg, B.red[1] + 0.25, B.red[2] + 0.2, B.red[3] + 0.2) end
	-- faixa dourada fina abaixo do título
	local line = frame:CreateTexture(nil, "OVERLAY")
	line:SetPoint("TOPLEFT", 4, -22)
	line:SetPoint("TOPRIGHT", -4, -22)
	line:SetHeight(1)
	line:SetColorTexture(B.gold[1], B.gold[2], B.gold[3], 0.7)
	-- menu na barra de título: ícone + Royal Revenue | Craft · Mercado · Livro-caixa (o título antigo some)
	if frame.titleFS then frame.titleFS:Hide() end
	local bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -1)
	bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -56, -1)
	bar:SetHeight(20)
	bar:SetFrameLevel(frame:GetFrameLevel() + 10)
	local icon = bar:CreateTexture(nil, "ARTWORK")
	icon:SetSize(16, 16)
	icon:SetPoint("LEFT", 0, 0)
	icon:SetTexture("Interface\\AddOns\\RoyalRevenue\\Media\\icon")
	local name = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
	name:SetText("|cffd4af37Royal|r |cff6f9be0Revenue|r")
	local sep = bar:CreateTexture(nil, "ARTWORK")
	sep:SetSize(1, 14)
	sep:SetPoint("LEFT", name, "RIGHT", 10, 0)
	sep:SetColorTexture(B.gold[1], B.gold[2], B.gold[3], 0.6)
	frame.rrBar = bar

	local function Btn(label, target, anchor)
		local b = CreateFrame("Button", nil, bar)
		b:SetHeight(20)
		local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint("CENTER", 0, 1)
		b:SetFontString(fs)
		b:SetText(label)
		b:SetWidth(math.max(70, (fs:GetStringWidth() or 60) + 28))
		if anchor then b:SetPoint("LEFT", anchor, "RIGHT", 2, 0) else b:SetPoint("LEFT", sep, "RIGHT", 6, 0) end
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.08)
		b.sel = b:CreateTexture(nil, "BACKGROUND")
		b.sel:SetAllPoints()
		b.sel:SetColorTexture(B.blue and B.blue[1] or 0.17, B.blue and B.blue[2] or 0.36, B.blue and B.blue[3] or 0.66, 0.35)
		b.under = b:CreateTexture(nil, "OVERLAY")
		b.under:SetPoint("BOTTOMLEFT", 6, 0); b.under:SetPoint("BOTTOMRIGHT", -6, 0); b.under:SetHeight(2)
		b.under:SetColorTexture(B.gold[1], B.gold[2], B.gold[3], 1)
		b.label = label
		b:SetScript("OnClick", function() root.Switch(nil, target) end)
		return b
	end
	-- zoom da janela (monitor pequeno/grande): A− / A+ no canto da barra
	local function ZBtn(label, delta, anchorTo)
		local z = CreateFrame("Button", nil, bar)
		z:SetSize(26, 18)
		local fs = z:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("CENTER", 0, 0)
		z:SetFontString(fs)
		z:SetText("|cffd9dde3" .. label .. "|r")
		local hl = z:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.1)
		if anchorTo then z:SetPoint("RIGHT", anchorTo, "LEFT", -2, 0) else z:SetPoint("RIGHT", bar, "RIGHT", -26, 0) end
		z:SetScript("OnClick", function() root.SetScale(root.GetScale() + delta) end)
		z:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(L("Tamanho da janela"))
			GameTooltip:AddLine(string.format(L("Agora: %d%%. Também: /rr escala 80"), math.floor(root.GetScale() * 100 + 0.5)), 1, 1, 1)
			GameTooltip:Show()
		end)
		z:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return z
	end
	local zp = ZBtn("A+", 0.05)
	ZBtn("A-", -0.05, zp)
	local b1 = Btn("Craft", "craft")
	local b2 = Btn(L("Mercado"), "mercado", b1)
	local b3 = Btn(L("Livro-caixa"), "livro", b2)
	frame.rrNav = { craft = b1, mercado = b2, livro = b3 }
	root.UpdateNav(frame, which == "livro" and "livro" or (C.UI.Mode and C.UI.Mode() == "market" and "mercado" or "craft"))
	root.Skin(frame)
	root.ApplyScale(frame)
	frame:HookScript("OnShow", function(self)
		root.ApplyScale(self)
		RoyalRevenueDB.last = (which == "livro") and "livro" or (C.UI.Mode and C.UI.Mode() == "market" and "mercado" or "craft")
		root.Skin(self)
	end)
end

-- ===== escala das janelas (as duas juntas), guardada por conta =====
function root.GetScale()
	local v = RoyalRevenueDB and tonumber(RoyalRevenueDB.scale) or 1
	return math.max(0.5, math.min(1.5, v))
end
function root.ApplyScale(f)
	if not f then return end
	local s = root.GetScale()
	if math.abs((f:GetScale() or 1) - s) > 0.001 then
		f:SetScale(s)
		if root.FitToScreen then root.FitToScreen(f) end
	end
end
function root.SetScale(v)
	RoyalRevenueDB = RoyalRevenueDB or {}
	v = math.max(0.5, math.min(1.5, math.floor(v * 100 + 0.5) / 100))
	RoyalRevenueDB.scale = v
	for _, f in ipairs({ _G.LucroCraftFrame, _G.LucroLivroFrame }) do
		if f then
			-- mantém o canto de cima à esquerda no mesmo lugar da tela
			local l, t, old = f:GetLeft(), f:GetTop(), f:GetScale() or 1
			f:SetScale(v)
			if l and t then
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * old / v, t * old / v)
			end
			if root.FitToScreen then root.FitToScreen(f) end
		end
	end
	print(root.NAME .. ": " .. string.format(L("tamanho da janela: %d%%."), math.floor(v * 100 + 0.5)))
end

-- destaca o módulo atual no menu de cima
function root.UpdateNav(frame, current)
	if not (frame and frame.rrNav) then return end
	for key, b in pairs(frame.rrNav) do
		local on = key == current
		b:SetText(on and ("|cffd4af37" .. b.label .. "|r") or ("|cffd9dde3" .. b.label .. "|r"))
		if b.sel then b.sel:SetShown(on) end
		if b.under then b.under:SetShown(on) end
	end
end

local function CraftFrame() return _G.LucroCraftFrame end
local function LivroFrame() return _G.LucroLivroFrame end

-- ===== abrir / trocar =====
function root.Open(which, tab)
	which = which or RoyalRevenueDB.last or "craft"
	if which == "settings" then
		C.UI.ShowTab(C.UI.TAB.SETTINGS)
		Decorate(CraftFrame(), "craft")
		return
	end
	if which == "livro" then
		LV.UI.Show(tab)
		Decorate(LivroFrame(), "livro")
	else
		-- Craft e Mercado usam a mesma janela; a aba diz qual grupo aparece
		if tab and C.UI.ModeOf then which = (C.UI.ModeOf(tab) == "market") and "mercado" or "craft" end
		local mode = which == "mercado" and "market" or "craft"
		C.UI.ShowTab(tab or C.UI.LastTab(mode))
		Decorate(CraftFrame(), "craft")
		root.UpdateNav(CraftFrame(), which)
	end
	RoyalRevenueDB.last = which
end

-- troca no mesmo lugar da tela
function root.Switch(from, to)
	if not from then
		local lf = LivroFrame()
		from = (lf and lf:IsShown()) and "livro" or ((C.UI.Mode and C.UI.Mode() == "market") and "mercado" or "craft")
	end
	if from == to then return end
	-- Craft <-> Mercado: mesma janela, só troca as abas
	if from ~= "livro" and to ~= "livro" then root.Open(to) return end
	local f = from == "livro" and LivroFrame() or CraftFrame()
	local left, top = f and f:GetLeft(), f and f:GetTop()
	if f then f:Hide() end
	root.Open(to)
	local t = to == "livro" and LivroFrame() or CraftFrame()
	if t and left and top then
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
end

function root.IsShown()
	local a, b = CraftFrame(), LivroFrame()
	return (a and a:IsShown()) or (b and b:IsShown())
end

function root.Toggle()
	if root.IsShown() then
		local a, b = CraftFrame(), LivroFrame()
		if a then a:Hide() end
		if b then b:Hide() end
	else
		root.Open(RoyalRevenueDB.last)
	end
end

function root.SetMinimap(show)
	LucroLivroDB.minimap = LucroLivroDB.minimap or {}
	LucroLivroDB.minimap.hide = (not show) or nil
	if LV.Minimap then LV.Minimap.Init() end
end

-- menu do minimapa / compartimento
function root.Menu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then root.Toggle() return end
	MenuUtil.CreateContextMenu(owner or UIParent, function(_, m)
		m:CreateTitle("Royal Revenue")
		m:CreateButton(L("Receitas"), function() root.Open("craft", C.UI.TAB.LIST) end)
		m:CreateButton(L("Plano de concentração"), function() root.Open("craft", C.UI.TAB.PLAN) end)
		m:CreateButton(L("Investimento"), function() root.Open("craft", C.UI.TAB.INVEST) end)
		m:CreateButton(L("Destruir"), function() root.Open("craft", C.UI.TAB.SALVAGE) end)
		m:CreateButton(L("Fila de craft"), function() root.Open("craft", C.UI.TAB.QUEUE) end)
		m:CreateDivider()
		m:CreateButton(L("Compras"), function() root.Open("mercado", C.UI.TAB.BUY) end)
		m:CreateButton(L("Vender"), function() root.Open("mercado", C.UI.TAB.SELL) end)
		m:CreateButton(L("Comprar receitas"), function() root.Open("mercado", C.UI.TAB.RECIPES) end)
		m:CreateDivider()
		m:CreateButton(L("Livro-caixa"), function() root.Open("livro") end)
		m:CreateButton(L("Vendas"), function() root.Open("livro", 6) end)
		m:CreateDivider()
		m:CreateButton(L("Configurações"), function() root.Open("settings") end)
	end)
end

-- ===== comando =====
SLASH_ROYALREVENUE1 = "/rr"
SLASH_ROYALREVENUE2 = "/royal"
SlashCmdList.ROYALREVENUE = function(msg)
	local cmd = strtrim((msg or ""):lower())
	if cmd == "" then root.Toggle()
	elseif cmd == "craft" or cmd == "receitas" then root.Open("craft", C.UI.TAB.LIST)
	elseif cmd == "livro" or cmd == "book" then root.Open("livro")
	elseif cmd == "vendas" or cmd == "sales" then root.Open("livro", 6)
	elseif cmd == "plano" or cmd == "plan" then root.Open("craft", C.UI.TAB.PLAN)
	elseif cmd == "mercado" or cmd == "market" then root.Open("mercado")
	elseif cmd == "compras" or cmd == "buy" or cmd == "shopping" then root.Open("mercado", C.UI.TAB.BUY)
	elseif cmd:match("^compras%s+%d+$") or cmd:match("^buy%s+%d+$") then
		if C.Buy then C.Buy.SetDays(tonumber(cmd:match("(%d+)$"))) end
		root.Open("craft", C.UI.TAB.BUY)
	elseif cmd == "vender" or cmd == "sell" then root.Open("craft", C.UI.TAB.SELL)
	elseif cmd:match("^vender%s+%d+$") or cmd:match("^sell%s+%d+$") then
		if C.Buy then C.Buy.SetDays(tonumber(cmd:match("(%d+)$"))) end
		root.Open("craft", C.UI.TAB.SELL)
	elseif cmd == "livros" or cmd == "recipes" then root.Open("mercado", C.UI.TAB.RECIPES)
	elseif cmd == "fila" or cmd == "queue" then root.Open("craft", C.UI.TAB.QUEUE)
	elseif cmd == "invest" or cmd == "investir" then root.Open("craft", C.UI.TAB.INVEST)
	elseif cmd == "destruir" or cmd == "salvage" then root.Open("craft", C.UI.TAB.SALVAGE)
	elseif cmd == "config" or cmd == "opcoes" or cmd == "opções" or cmd == "settings" then root.Open("settings")
	elseif cmd == "reset" or cmd == "resetar" then
		-- janelas de volta ao tamanho padrão e ao centro da tela
		if LucroCraftDB then LucroCraftDB.size, LucroCraftDB.pos = nil, nil end
		if LucroLivroDB then LucroLivroDB.size, LucroLivroDB.pos = nil, nil end
		for _, f in ipairs({ _G.LucroCraftFrame, _G.LucroLivroFrame }) do
			if f then f:ClearAllPoints(); f:SetPoint("CENTER") end
		end
		local cf = _G.LucroCraftFrame
		if cf and C.UI.ApplyTabSize then C.UI.ApplyTabSize(C.UI.CurrentTab and C.UI.CurrentTab() or 1); if C.UI.OnResize then pcall(C.UI.OnResize) end end
		local lf = _G.LucroLivroFrame
		if lf then lf:SetSize(1000, 640) end
		print(root.NAME .. ": " .. L("janelas no tamanho padrão e no centro da tela."))
	elseif cmd == "minimapa" or cmd == "minimap" then if LV.Minimap then LV.Minimap.Toggle() end
	elseif cmd:match("^escala") or cmd:match("^scale") then
		-- /rr escala 80 (em %) ou 0.8
		local n = tonumber(cmd:match("([%d%.]+)"))
		if n then root.SetScale(n > 3 and n / 100 or n)
		else print(root.NAME .. ": " .. string.format(L("tamanho da janela: %d%%. Use /rr escala 80 (50 a 150)."), math.floor(root.GetScale() * 100 + 0.5))) end
	elseif cmd:match("^log") then
		-- /rr log <nome da aba> escolhe a aba; /rr log sozinho mostra qual está em uso
		local name = strtrim((msg or ""):match("^%s*%S+%s*(.*)$") or "")
		RoyalRevenueDB = RoyalRevenueDB or {}
		if name ~= "" then RoyalRevenueDB.logTab = name end
		local f = root.LogFrame()
		local tab = f and f.name or (f and GetChatWindowInfo(f:GetID())) or nil
		print(root.NAME .. ": " .. (f and string.format(L("mensagens indo para a aba de chat \"%s\"."), tostring(tab or name))
			or L("nenhuma aba de chat \"Log\" encontrada: usando o chat geral. Crie uma aba chamada Log ou use /rr log <nome da aba>.")))
	else
		print(root.NAME .. ": /rr [craft | livro | vendas | plano | mercado | compras [dias] | vender [dias] | livros | fila | reset | invest | destruir | config | minimapa | log [aba] | escala [50-150]]")
	end
end

-- os comandos antigos continuam: /lucro (craft) e /livro (livro-caixa); as janelas ganham a pele ao abrir
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
	C_Timer.After(1, function()
		for _, pair in ipairs({ { "LucroCraftFrame", "craft" }, { "LucroLivroFrame", "livro" } }) do
			if _G[pair[1]] then pcall(Decorate, _G[pair[1]], pair[2]) end
		end
	end)
end)
-- janelas criadas depois (primeira abertura por /lucro ou /livro)
if C.UI and C.UI.Show then hooksecurefunc(C.UI, "Show", function() pcall(Decorate, CraftFrame(), "craft") end) end
if C.UI and C.UI.ShowTab then hooksecurefunc(C.UI, "ShowTab", function() pcall(Decorate, CraftFrame(), "craft") end) end
if LV.UI and LV.UI.Show then hooksecurefunc(LV.UI, "Show", function() pcall(Decorate, LivroFrame(), "livro") end) end
if LV.UI and LV.UI.Toggle then hooksecurefunc(LV.UI, "Toggle", function() pcall(Decorate, LivroFrame(), "livro") end) end
