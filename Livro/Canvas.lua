local ADDON, root = ...
root.Livro = root.Livro or {}
local ns = root.Livro
ns.root = root

-- Tela com rolagem e widgets reaproveitados (texto, caixa, ícone, barra, botão)
local Canvas = {}
Canvas.__index = Canvas
ns.Canvas = Canvas

function Canvas.Create(parent)
	local c = setmetatable({}, Canvas)
	local sf = CreateFrame("ScrollFrame", nil, parent)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(100, 100)
	sf:SetScrollChild(child)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(self, delta)
		local maxS = math.max(0, child:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.min(maxS, math.max(0, self:GetVerticalScroll() - delta * 40)))
	end)
	c.frame, c.child = sf, child
	c.pool = { text = {}, box = {}, icon = {}, bar = {}, button = {} }
	c.used = { text = 0, box = 0, icon = 0, bar = 0, button = 0 }
	return c
end

function Canvas:Width() return self.frame:GetWidth() end

function Canvas:Begin()
	self.child:SetWidth(self.frame:GetWidth())
	for k in pairs(self.used) do
		for i = 1, #self.pool[k] do self.pool[k][i]:Hide() end
		self.used[k] = 0
	end
end

function Canvas:End(h)
	self.child:SetHeight(math.max(h or 0, 1))
	local maxS = math.max(0, (h or 0) - self.frame:GetHeight())
	if self.frame:GetVerticalScroll() > maxS then self.frame:SetVerticalScroll(maxS) end
end

local function acquire(self, kind, make)
	self.used[kind] = self.used[kind] + 1
	local o = self.pool[kind][self.used[kind]]
	if not o then o = make(); table.insert(self.pool[kind], o) end
	o:ClearAllPoints()
	o:Show()
	return o
end

local function SetTip(f, tip)
	f.tipFn = tip
	if tip then
		f:EnableMouse(true)
		f:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			self.tipFn(GameTooltip)
			GameTooltip:Show()
		end)
		f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	else
		f:SetScript("OnEnter", nil)
		f:SetScript("OnLeave", nil)
	end
end

function Canvas:Text(x, y, text, font, width, justify)
	local fs = acquire(self, "text", function() return self.child:CreateFontString(nil, "OVERLAY") end)
	fs:SetFontObject(font or GameFontHighlightSmall)
	fs:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	fs:SetWidth(width or 0)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(width and true or false)
	fs:SetText(text or "")
	return fs
end

function Canvas:Box(x, y, w, h, r, g, b, a)
	local t = acquire(self, "box", function() return self.child:CreateTexture(nil, "BACKGROUND") end)
	t:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	t:SetSize(w, h)
	t:SetColorTexture(r, g, b, a or 1)
	return t
end

function Canvas:Icon(x, y, size, texture, tip, count)
	local f = acquire(self, "icon", function()
		local b = CreateFrame("Frame", nil, self.child)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		b.count:SetPoint("BOTTOMRIGHT", -1, 1)
		return b
	end)
	f:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	f:SetSize(size, size)
	f.tex:SetTexture(texture or 134400)
	f.count:SetText(count or "")
	SetTip(f, tip)
	return f
end

function Canvas:Bar(x, y, w, h, value, max, color, tip)
	local f = acquire(self, "bar", function()
		local b = CreateFrame("StatusBar", nil, self.child)
		b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(1, 1, 1, 0.06)
		return b
	end)
	f:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	f:SetSize(math.max(w, 1), h)
	f:SetMinMaxValues(0, math.max(max or 1, 1))
	f:SetValue(math.max(value or 0, 0))
	f:SetStatusBarColor(color[1], color[2], color[3], 0.85)
	SetTip(f, tip)
	return f
end

-- área clicável invisível (com destaque ao passar o mouse)
function Canvas:Button(x, y, w, h, onClick, tip)
	local b = acquire(self, "button", function()
		local btn = CreateFrame("Button", nil, self.child)
		btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		btn:RegisterForClicks("LeftButtonUp")
		return btn
	end)
	b:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	b:SetSize(w, h)
	b:SetScript("OnClick", onClick)
	SetTip(b, tip)
	return b
end
