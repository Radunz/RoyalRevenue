local ADDON, root = ...
local print = function(...) return root.Out(...) end   -- mensagens vão para a aba de log
root.Livro = root.Livro or {}
local ns = root.Livro
ns.root = root
local L = ns.L

-- Botão no minimapa (arrastável em volta do mapa) + entrada no menu de addons do minimapa (Addon Compartment)
-- LucroLivroDB.minimap = { angle = graus, hide = true/nil }
local MM = {}
ns.Minimap = MM

local ICON = "Interface\\AddOns\\RoyalRevenue\\Media\\icon"   -- livro com o grifo da Pomerânia na capa
local btn

local function Cfg()
	LucroLivroDB.minimap = LucroLivroDB.minimap or { angle = 200 }
	return LucroLivroDB.minimap
end

local function Place()
	local a = math.rad(Cfg().angle or 200)
	local r = (Minimap:GetWidth() / 2) + 6
	local x, y = math.cos(a) * r, math.sin(a) * r
	-- minimapa quadrado (alguns addons de interface): encosta nos cantos
	if GetMinimapShape and GetMinimapShape() == "SQUARE" then
		x = math.max(-r, math.min(r, x * 1.4))
		y = math.max(-r, math.min(r, y * 1.4))
	end
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function Tooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("|cffd4af37Royal Revenue|r")
	GameTooltip:AddLine(L["Clique: abrir/fechar"], 1, 1, 1)
	GameTooltip:AddLine(L["Clique direito: escolher Craft, Livro-caixa ou Configurações"], 1, 1, 1)
	GameTooltip:AddLine(L["Arraste: mover em volta do minimapa"], 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function Create()
	btn = CreateFrame("Button", "RoyalRevenueMinimapButton", Minimap)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")
	btn:SetScript("OnClick", function(self, button)
		if button == "RightButton" then ns.root.Menu(self) else ns.root.Toggle() end
	end)
	btn:SetScript("OnEnter", Tooltip)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- arrastar: acompanha o cursor em volta do minimapa
	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			cx, cy = cx / scale, cy / scale
			Cfg().angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
			Place()
		end)
	end)
	btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	Place()
end

function MM.Init()
	if not Minimap then return end
	if not btn then Create() end
	btn:SetShown(not Cfg().hide)
end

function MM.Toggle()
	local c = Cfg()
	c.hide = not c.hide or nil
	MM.Init()
	print("|cffd4af37Royal Revenue|r: " .. (c.hide and L["ícone do minimapa escondido (/livro minimapa para mostrar)."] or L["ícone do minimapa visível."]))
end

-- menu de addons do minimapa (Addon Compartment), declarado no .toc
function RoyalRevenue_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then ns.root.Menu(nil) else ns.root.Toggle() end
end
function RoyalRevenue_OnAddonCompartmentEnter(_, menuButton)
	Tooltip(menuButton)
end
function RoyalRevenue_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

-- no login o minimapa já tem tamanho final (outros addons de interface podem mudá-lo)
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
	if LucroLivroDB then
		pcall(MM.Init)
		if btn then pcall(Place) end
	end
end)
