local ADDON, root = ...
root.Livro = root.Livro or {}
local ns = root.Livro
ns.root = root
local L = ns.L

-- Opções do LucroLivro no menu do jogo (Esc > Opções > AddOns > LucroLivro) e pelo botão de engrenagem do painel
local Options = {}
ns.Options = Options

local LANGS = { { "auto", L["Automático (idioma do jogo)"] }, { "pt", "Português" }, { "en", "English" } }
local panel, category

local function Build()
	panel = CreateFrame("Frame")
	panel.name = "Royal Revenue"
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("|cffd4af37Royal|r |cff6f9be0Revenue|r — " .. L["Opções"])

	-- idioma
	local lab = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	lab:SetPoint("TOPLEFT", 16, -56)
	lab:SetText(L["Idioma"])
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(210, 22)
	b:SetPoint("LEFT", lab, "RIGHT", 12, 0)
	local rl = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	rl:SetSize(100, 22)
	rl:SetPoint("LEFT", b, "RIGHT", 6, 0)
	rl:SetText(L["Recarregar"])
	rl:SetScript("OnClick", function() ReloadUI() end)
	local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 16, -84)
	local function show()
		local cur = LucroLivroDB.config.lang or "auto"
		for _, l in ipairs(LANGS) do if l[1] == cur then b:SetText(l[2]) end end
		local changed = cur ~= (ns.lang or "auto")
		rl:SetShown(changed)
		note:SetText(changed and ("|cffffd100" .. L["Idioma alterado: clique em Recarregar (ou /reload) para aplicar."] .. "|r") or "")
	end
	b:SetScript("OnClick", function()
		local cur = LucroLivroDB.config.lang or "auto"
		local idx = 1
		for i, l in ipairs(LANGS) do if l[1] == cur then idx = i end end
		ns.root.SetLang(LANGS[(idx % #LANGS) + 1][1])
		show()
	end)

	-- ícone do minimapa
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", 12, -110)
	local cbt = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	cbt:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	cbt:SetText(L["Mostrar ícone no minimapa"])
	cb:SetScript("OnClick", function(self)
		LucroLivroDB.minimap = LucroLivroDB.minimap or {}
		LucroLivroDB.minimap.hide = (not self:GetChecked()) or nil
		if ns.Minimap then ns.Minimap.Init() end
	end)

	local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	open:SetSize(180, 22)
	open:SetPoint("TOPLEFT", 16, -150)
	open:SetText(L["Abrir o livro-caixa"])
	open:SetScript("OnClick", function() ns.root.Open("livro") end)
	local cfg = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	cfg:SetSize(220, 22)
	cfg:SetPoint("LEFT", open, "RIGHT", 8, 0)
	cfg:SetText(L["Todas as configurações"])
	cfg:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
		ns.root.Open("settings")
	end)

	panel:SetScript("OnShow", function()
		show()
		cb:SetChecked(not (LucroLivroDB.minimap and LucroLivroDB.minimap.hide))
	end)
end

function Options.Register()
	if category then return end
	Build()
	if Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, "Royal Revenue")
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
		category = panel
	end
end

function Options.Open()
	Options.Register()
	if Settings and Settings.OpenToCategory and category and category.GetID then
		Settings.OpenToCategory(category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end
