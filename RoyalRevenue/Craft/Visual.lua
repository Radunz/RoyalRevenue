local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- "Tela" com rolagem para abas visuais (ícones, barras, caixas e textos curtos), com widgets reaproveitados
local V = {}
ns.Visual = V

local Canvas = {}
Canvas.__index = Canvas

function V.Create(parent)
	local c = setmetatable({}, Canvas)
	local sf = CreateFrame("ScrollFrame", nil, parent)
	sf:SetPoint("TOPLEFT", 12, -56)   -- abaixo da faixa de abas
	sf:SetPoint("BOTTOMRIGHT", -12, 10)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(100, 100)
	sf:SetScrollChild(child)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 60)))
	end)
	sf:Hide()
	c.frame, c.child = sf, child
	c.pools = { text = {}, icon = {}, bar = {}, box = {}, button = {}, hit = {}, head = {}, line = {} }
	c.used = { text = 0, icon = 0, bar = 0, box = 0, button = 0, hit = 0, head = 0, line = 0 }
	return c
end

-- Área com rolagem própria DENTRO de outra tela (ex.: lista da bolsa na aba Vender), com barra de rolagem visível.
-- Uso: sub = V.CreateSub(cv); sub:Place(x, y, w, h); sub:Begin(); ...desenha...; sub:End(altura)
function V.CreateSub(parent)
	local c = setmetatable({}, Canvas)
	local sf = CreateFrame("ScrollFrame", nil, parent.child)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(100, 100)
	sf:SetScrollChild(child)
	local bar = CreateFrame("Slider", nil, parent.child)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(10)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(1, 1, 1, 0.08)
	bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
	local thumb = bar:GetThumbTexture()
	if thumb then thumb:SetVertexColor(0.83, 0.69, 0.22, 0.85); thumb:SetSize(10, 40) end
	bar.thumb = thumb
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	bar:SetValue(0)
	bar:EnableMouseWheel(true)
	bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	local function wheel(_, delta)
		local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
		bar:SetValue(math.min(maxScroll, math.max(0, sf:GetVerticalScroll() - delta * 40)))
	end
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", wheel)
	bar:SetScript("OnMouseWheel", wheel)
	c.frame, c.child, c.bar, c.parent, c.sub = sf, child, bar, parent, true
	c.pools = { text = {}, icon = {}, bar = {}, box = {}, button = {}, hit = {}, head = {}, line = {} }
	c.used = { text = 0, icon = 0, bar = 0, box = 0, button = 0, hit = 0, head = 0, line = 0 }
	return c
end

-- posição e tamanho da área (só para V.CreateSub); a barra fica à direita
function Canvas:Place(x, y, w, h)
	self.frame:ClearAllPoints()
	self.frame:SetPoint("TOPLEFT", self.parent.child, "TOPLEFT", x, -y)
	self.frame:SetSize(w - 14, h)
	self.bar:ClearAllPoints()
	self.bar:SetPoint("TOPLEFT", self.parent.child, "TOPLEFT", x + w - 10, -y)
	self.bar:SetHeight(h)
	self:UpdateBar()
end

function Canvas:UpdateBar()
	if not self.bar then return end
	local h = self.frame:GetHeight()
	local total = self.child:GetHeight()
	local maxScroll = math.max(0, total - h)
	self.bar:SetMinMaxValues(0, maxScroll)
	if self.bar.thumb and total > 0 then self.bar.thumb:SetHeight(math.max(20, h * h / total)) end
	self.bar:SetShown(maxScroll > 0 and self.frame:IsShown())
	local v = math.min(self.frame:GetVerticalScroll(), maxScroll)
	self.bar:SetValue(v)
	self.frame:SetVerticalScroll(v)
end

function Canvas:Show() self.frame:Show(); if self.bar then self:UpdateBar() end end
function Canvas:Hide() self.frame:Hide(); if self.bar then self.bar:Hide() end end
function Canvas:IsShown() return self.frame:IsShown() end
function Canvas:Width() return self.frame:GetWidth() end

function Canvas:Begin()
	for k, list in pairs(self.pools) do
		for _, w in ipairs(list) do w:Hide() end
		self.used[k] = 0
	end
	-- botões seguros (usar item): só mexe fora de combate
	if self.secure and not (InCombatLockdown and InCombatLockdown()) then
		for _, b in ipairs(self.secure) do b:Hide() end
		self.secureUsed = 0
	end
	self.child:SetWidth(self.frame:GetWidth())
end

function Canvas:End(height)
	if self.sub then
		self.child:SetHeight(math.max(height, 1))
		self:UpdateBar()
		return
	end
	self.child:SetHeight(math.max(height, self.frame:GetHeight()))
	local maxScroll = math.max(0, self.child:GetHeight() - self.frame:GetHeight())
	if self.frame:GetVerticalScroll() > maxScroll then self.frame:SetVerticalScroll(maxScroll) end
end

function Canvas:ResetScroll() self.frame:SetVerticalScroll(0) end

local function acquire(self, kind, make)
	self.used[kind] = self.used[kind] + 1
	local w = self.pools[kind][self.used[kind]]
	if not w then
		w = make()
		table.insert(self.pools[kind], w)
	end
	w:ClearAllPoints()
	w:Show()
	return w
end

local function ShowTip(self)
	if not self.tip then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local ok, err = pcall(self.tip, GameTooltip)
	if not ok then GameTooltip:SetText(tostring(err)) end
	GameTooltip:Show()
end

local function HideTip() GameTooltip:Hide() end

-- Texto curto. font: objeto de fonte; width: largura (nil = natural); justify: LEFT/RIGHT/CENTER
function Canvas:Text(x, y, text, font, width, justify)
	local fs = acquire(self, "text", function() return self.child:CreateFontString(nil, "OVERLAY") end)
	fs:SetFontObject(font or GameFontHighlightSmall)
	fs:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	fs:SetWidth(width or 0)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	fs:SetText(text or "")
	return fs
end

-- Retângulo de fundo (cartão)
function Canvas:Box(x, y, w, h, r, g, b, a)
	local t = acquire(self, "box", function() return self.child:CreateTexture(nil, "BACKGROUND") end)
	t:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	t:SetSize(w, h)
	t:SetColorTexture(r or 1, g or 1, b or 1, a or 0.05)
	return t
end

-- Ícone com borda de qualidade, contador, marca de qualidade, sombra colorida e tooltip.
-- o = { count, quality (texto/atlas), rarity (0-5), border = {r,g,b}, shade = {r,g,b,a}, tip = fn(tt), link, onClick, desaturate }
function Canvas:Icon(x, y, size, texture, o)
	o = o or {}
	local b = acquire(self, "icon", function()
		local btn = CreateFrame("Button", nil, self.child)
		btn.tex = btn:CreateTexture(nil, "ARTWORK")
		btn.tex:SetAllPoints()
		btn.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		-- faixa fina no pé do ícone (tendência do preço), sem tingir o ícone
		btn.shade = btn:CreateTexture(nil, "OVERLAY", nil, 2)
		btn.shade:SetPoint("BOTTOMLEFT", 2, 2)
		btn.shade:SetPoint("BOTTOMRIGHT", -2, 2)
		btn.shade:SetHeight(3)
		btn.border = btn:CreateTexture(nil, "OVERLAY")
		btn.border:SetTexture("Interface\\Common\\WhiteIconFrame")
		btn.border:SetAllPoints()
		btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		btn.count:SetPoint("BOTTOMRIGHT", -2, 2)
		btn.q = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		btn.q:SetPoint("TOPLEFT", 1, -1)
		-- texto pequeno no canto de cima (ex.: tendência do preço "-25%")
		btn.corner = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		btn.corner:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 4, 6)
		btn.corner:SetJustifyH("RIGHT")
		btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		btn:SetScript("OnEnter", ShowTip)
		btn:SetScript("OnLeave", HideTip)
		btn:SetScript("OnClick", function(selfB)
			if selfB.link and IsShiftKeyDown() then
				local insert = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
				if insert then insert(selfB.link) end
				return
			end
			if selfB.onClick then selfB.onClick(selfB) end
		end)
		return btn
	end)
	b:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	b:SetSize(size, size)
	b.tex:SetTexture(texture or 134400)
	b.tex:SetDesaturated(o.desaturate and true or false)
	local br, bg, bb = 0.5, 0.5, 0.5
	if o.border then
		br, bg, bb = o.border[1], o.border[2], o.border[3]
	elseif o.rarity and C_Item.GetItemQualityColor then
		br, bg, bb = C_Item.GetItemQualityColor(o.rarity)
	end
	b.border:SetVertexColor(br, bg, bb)
	if o.shade then
		b.shade:SetColorTexture(o.shade[1], o.shade[2], o.shade[3], 0.95)
		b.shade:Show()
	else
		b.shade:Hide()
	end
	b.count:SetText(o.count or "")
	b.q:SetText(o.quality or "")
	b.corner:SetText(o.corner or "")
	b.tip, b.link, b.onClick = o.tip, o.link, o.onClick
	return b
end

-- Botão seguro invisível por cima de um ícone: clicar USA o item (comida, frasco; slot = item aplicado
-- num equipamento, ex.: pedra de afiar na ferramenta). O jogo só deixa criar/mover fora de combate.
function Canvas:SecureItem(x, y, w, h, itemID, slot, tip)
	if InCombatLockdown and InCombatLockdown() then return nil end
	self.secure = self.secure or {}
	self.secureUsed = (self.secureUsed or 0) + 1
	local b = self.secure[self.secureUsed]
	if not b then
		b = CreateFrame("Button", nil, self.child, "SecureActionButtonTemplate")
		b:RegisterForClicks("AnyUp", "AnyDown")
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetScript("OnEnter", ShowTip)
		b:SetScript("OnLeave", HideTip)
		self.secure[self.secureUsed] = b
	end
	b:SetFrameLevel(self.child:GetFrameLevel() + 10)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	b:SetSize(w, h)
	b:SetAttribute("type", "item")
	b:SetAttribute("item", "item:" .. itemID)
	b:SetAttribute("target-slot", slot)
	b.tip = tip
	b:Show()
	return b
end

-- Área clicável invisível (cabeçalho de grupo, linha inteira) com tooltip
function Canvas:Hit(x, y, w, h, onClick, tip)
	local b = acquire(self, "hit", function()
		local btn = CreateFrame("Button", nil, self.child)
		btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		btn:SetScript("OnEnter", ShowTip)
		btn:SetScript("OnLeave", HideTip)
		btn:SetScript("OnClick", function(selfB) if selfB.onClick then selfB.onClick(selfB) end end)
		return btn
	end)
	b:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	b:SetSize(w, h)
	b.onClick, b.tip = onClick, tip
	return b
end

-- Cabeçalho de coluna: clique (ordenar) e arraste (mudar a posição)
-- o = { onClick(btn), onDragStart(btn), onDragStop(btn), tip = fn(tt) }
function Canvas:Header(x, y, w, h, text, justify, o)
	local b = acquire(self, "head", function()
		local btn = CreateFrame("Button", nil, self.child)
		btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		btn.text:SetAllPoints()
		btn:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
		btn:RegisterForClicks("LeftButtonUp")
		btn:RegisterForDrag("LeftButton")
		btn:SetScript("OnEnter", ShowTip)
		btn:SetScript("OnLeave", HideTip)
		btn:SetScript("OnClick", function(selfB)
			if selfB.dragEnded then selfB.dragEnded = false; return end
			if selfB.o and selfB.o.onClick then selfB.o.onClick(selfB) end
		end)
		btn:SetScript("OnDragStart", function(selfB)
			GameTooltip:Hide()
			selfB:SetAlpha(0.4)
			if selfB.o and selfB.o.onDragStart then selfB.o.onDragStart(selfB) end
		end)
		btn:SetScript("OnDragStop", function(selfB)
			selfB:SetAlpha(1)
			selfB.dragEnded = true
			C_Timer.After(0.05, function() selfB.dragEnded = false end)
			if selfB.o and selfB.o.onDragStop then selfB.o.onDragStop(selfB) end
		end)
		return btn
	end)
	b:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	b:SetSize(w, h)
	b:SetAlpha(1)
	b.text:SetJustifyH(justify or "LEFT")
	b.text:SetText(text or "")
	b.o, b.tip = o or {}, o and o.tip
	return b
end

-- posição X do cursor dentro da tela (para arrastar colunas)
function Canvas:CursorX()
	local scale = self.child:GetEffectiveScale()
	local cx = GetCursorPosition() / scale
	return cx - (self.child:GetLeft() or 0)
end

-- Tabela com colunas arrastáveis e ordenáveis (mesmo comportamento da lista de receitas).
-- spec = {
--   id = "nome" (ordem e ordenação salvas em LucroCraftDB.config.tables[id]),
--   columns = { { key, label, width, align, sort = fn(row) -> número/texto, draw = fn(cv, x, y, w, row) ou text = fn(row) -> texto } },
--   rows, defaultSort = { key =, desc = }, rowH = 24, max = n,
--   selected = fn(row) -> bool, onClick = fn(row), tip = fn(row) -> fn(tt), refresh = fn() (redesenha)
-- }
-- devolve o y depois da tabela e as linhas na ordem mostrada
function V.Table(cv, y, W, spec)
	local cfg = LucroCraftDB.config
	cfg.tables = cfg.tables or {}
	local tc = cfg.tables[spec.id] or {}
	cfg.tables[spec.id] = tc
	local byKey, cols = {}, {}
	for _, c in ipairs(spec.columns) do byKey[c.key] = c end
	-- ordem salva + colunas novas no fim
	local seen = {}
	for _, k in ipairs(tc.order or {}) do
		if byKey[k] and not seen[k] then table.insert(cols, byKey[k]); seen[k] = true end
	end
	for _, c in ipairs(spec.columns) do if not seen[c.key] then table.insert(cols, c) end end
	local sort = tc.sort
	if not sort or not byKey[sort.key] then sort = spec.defaultSort end
	-- ordena
	local rows = {}
	for _, r in ipairs(spec.rows or {}) do table.insert(rows, r) end
	local sc = sort and byKey[sort.key]
	if sc and sc.sort then
		local desc = sort.desc
		table.sort(rows, function(a, b)
			local va, vb = sc.sort(a), sc.sort(b)
			if va == nil and vb == nil then return false end
			if va == nil then return false end   -- sem valor sempre no fim
			if vb == nil then return true end
			if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
			if va == vb then return false end
			if desc then return va > vb end
			return va < vb
		end)
	end
	-- posições
	local x, pos = 8, {}
	for i, c in ipairs(cols) do pos[i] = x; x = x + c.width + 6 end
	local function Save(order, s)
		local o = {}
		for _, c in ipairs(order) do table.insert(o, c.key) end
		tc.order = o
		if s then tc.sort = s end
		if spec.refresh then spec.refresh() end
	end
	local marker = cv.dropMarker
	if not marker then
		marker = cv.child:CreateTexture(nil, "OVERLAY")
		marker:SetColorTexture(0.83, 0.69, 0.22, 0.9)
		marker:SetWidth(2)
		cv.dropMarker = marker
	end
	marker:Hide()
	local function DropIndex(dragKey)
		local cx = cv:CursorX()
		local idx = 1
		for i, c in ipairs(cols) do
			if c.key ~= dragKey and cx > pos[i] + c.width / 2 then idx = idx + 1 end
		end
		return idx
	end
	local hy = y
	for i, c in ipairs(cols) do
		local arrow = ""
		if sort and sort.key == c.key then arrow = sort.desc and " v" or " ^" end
		cv:Header(pos[i], hy, c.width, 16, "|cffd9dde3" .. c.label .. "|r" .. "|cffd4af37" .. arrow .. "|r", c.align, {
			tip = function(tt)
				tt:SetText(c.label)
				if c.desc then tt:AddLine(c.desc, 0.8, 0.8, 0.8, true) end
				tt:AddLine(ns.L["Clique: ordenar por esta coluna"], 1, 1, 1)
				tt:AddLine(ns.L["Arrastar: mudar posição"], 1, 1, 1)
			end,
			onClick = function()
				local desc = c.key ~= "name"
				if sort and sort.key == c.key then desc = not sort.desc end
				Save(cols, { key = c.key, desc = desc })
			end,
			onDragStart = function(btn)
				marker:ClearAllPoints()
				marker:SetHeight(16)
				marker:Show()
				btn:SetScript("OnUpdate", function()
					local idx = DropIndex(c.key)
					local others = {}
					for j, oc in ipairs(cols) do if oc.key ~= c.key then table.insert(others, j) end end
					local mx = others[idx] and (pos[others[idx]] - 3) or (x - 3)
					marker:ClearAllPoints()
					marker:SetPoint("TOPLEFT", cv.child, "TOPLEFT", mx, -hy)
				end)
			end,
			onDragStop = function(btn)
				btn:SetScript("OnUpdate", nil)
				marker:Hide()
				local idx = DropIndex(c.key)
				local order = {}
				for _, oc in ipairs(cols) do if oc.key ~= c.key then table.insert(order, oc) end end
				table.insert(order, math.min(idx, #order + 1), c)
				Save(order)
			end,
		})
	end
	y = y + 18
	local rowH = spec.rowH or 24
	local shown = {}
	for _, r in ipairs(rows) do
		if spec.max and #shown >= spec.max then break end
		table.insert(shown, r)
		ns.root.Zebra(cv, #shown, 0, y - 2, W, rowH)
		if spec.selected and spec.selected(r) then cv:Box(0, y - 2, W, rowH, 0.17, 0.36, 0.66, 0.30) end
		if spec.onClick or spec.tip then
			cv:Hit(0, y - 2, W, rowH, spec.onClick and function() spec.onClick(r) end, spec.tip and spec.tip(r))
		end
		for i, c in ipairs(cols) do
			if c.draw then
				c.draw(cv, pos[i], y, c.width, r)
			else
				cv:Text(pos[i], y + 4, c.text and c.text(r) or "", GameFontHighlightSmall, c.width, c.align)
			end
		end
		y = y + rowH
	end
	return y, shown, #rows - #shown
end

-- Botão de texto com tooltip
function Canvas:Button(x, y, w, h, text, onClick, tip)
	local b = acquire(self, "button", function()
		local btn = CreateFrame("Button", nil, self.child, "UIPanelButtonTemplate")
		btn:SetScript("OnEnter", ShowTip)
		btn:SetScript("OnLeave", HideTip)
		btn:SetScript("OnClick", function(selfB) if selfB.onClick then selfB.onClick(selfB) end end)
		if ns.root and ns.root.SkinButton then ns.root.SkinButton(btn) end
		return btn
	end)
	b:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	b:SetSize(w, h)
	b:SetText(text or "")
	b.onClick, b.tip = onClick, tip
	return b
end

-- Linha reta (gráficos). Coordenadas no canvas (y para baixo).
function Canvas:Line(x1, y1, x2, y2, thick, r, g, b, a)
	local ln = acquire(self, "line", function() return self.child:CreateLine(nil, "ARTWORK") end)
	ln:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
	ln:SetThickness(thick or 1.5)
	ln:SetStartPoint("TOPLEFT", self.child, x1, -y1)
	ln:SetEndPoint("TOPLEFT", self.child, x2, -y2)
	return ln
end

-- Barra de progresso. ticks = { { f = 0..1, r, g, b }, ... } marcam pontos na barra
function Canvas:Bar(x, y, w, h, value, max, color, text, ticks, tip)
	local s = acquire(self, "bar", function()
		local bar = CreateFrame("StatusBar", nil, self.child)
		bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		bar.bg = bar:CreateTexture(nil, "BACKGROUND")
		bar.bg:SetAllPoints()
		bar.bg:SetColorTexture(1, 1, 1, 0.10)
		bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		bar.text:SetPoint("CENTER", 0, 0)
		bar.ticks = {}
		bar:EnableMouse(true)
		bar:SetScript("OnEnter", ShowTip)
		bar:SetScript("OnLeave", HideTip)
		return bar
	end)
	s:SetPoint("TOPLEFT", self.child, "TOPLEFT", x, -y)
	s:SetSize(w, h)
	max = (max and max > 0) and max or 1
	s:SetMinMaxValues(0, max)
	s:SetValue(math.max(0, math.min(value or 0, max)))
	color = color or { 0.2, 0.6, 1 }
	s:SetStatusBarColor(color[1], color[2], color[3])
	s.text:SetText(text or "")
	for _, t in ipairs(s.ticks) do t:Hide() end
	for i, tk in ipairs(ticks or {}) do
		local t = s.ticks[i]
		if not t then
			t = s:CreateTexture(nil, "OVERLAY")
			s.ticks[i] = t
		end
		t:SetColorTexture(tk.r or 1, tk.g or 0.82, tk.b or 0, 0.9)
		t:SetSize(2, h)
		t:ClearAllPoints()
		t:SetPoint("LEFT", s, "LEFT", math.max(0, math.min(w - 2, w * tk.f - 1)), 0)
		t:Show()
	end
	s.tip = tip
	return s
end

-- ===== utilidades comuns =====
function V.ClassName(char, class)
	local short = (char:match("^([^-]+)")) or char
	if class and C_ClassColor and C_ClassColor.GetClassColor then
		local c = C_ClassColor.GetClassColor(class)
		if c then return c:WrapTextInColorCode(short) end
	end
	return "|cffffffff" .. short .. "|r"
end

-- ícone da profissão salvo no scan; para dados antigos tenta achar pelas profissões do personagem atual
function V.ProfIcon(char, e)
	if e.icon then return e.icon end
	if char == ns.CharKey() and GetProfessions then
		for _, idx in pairs({ GetProfessions() }) do
			local name, tex = GetProfessionInfo(idx)
			if name and e.name and name == e.name then return tex end
		end
	end
	local r = e.rows and e.rows[1]
	return r and r.icon or 134400
end

-- Ícone de item. Item que o cliente ainda não carregou (ex.: recompensa de pedido nunca vista) volta sem ícone:
-- pede ao servidor e redesenha a aba aberta quando chegar (uma vez por lote, 0,3 s depois).
local waiting, waitN, redrawPending = {}, 0, false
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
loadFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
loadFrame:SetScript("OnEvent", function(_, _, itemID)
	if not (itemID and waiting[itemID]) then return end
	waiting[itemID] = nil
	waitN = math.max(0, waitN - 1)
	if redrawPending then return end
	redrawPending = true
	C_Timer.After(0.3, function()
		redrawPending = false
		local fr = LucroCraftFrame
		if fr and fr:IsShown() and fr.currentTab and ns.UI and ns.UI.RefreshTab then pcall(ns.UI.RefreshTab, fr.currentTab) end
	end)
end)
function V.ItemIcon(itemID, fallback)
	if type(itemID) == "string" then itemID = tonumber(itemID:match("item:(%d+)")) or tonumber(itemID) end
	if not itemID then return fallback or 134400 end
	local tex = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
	if not tex and C_Item.GetItemInfoInstant then tex = select(5, C_Item.GetItemInfoInstant(itemID)) end
	if not tex and not waiting[itemID] and C_Item.RequestLoadItemDataByID then
		waiting[itemID] = true
		waitN = waitN + 1
		pcall(C_Item.RequestLoadItemDataByID, itemID)
	end
	return tex or fallback or 134400
end

-- nome do item; item que o cliente ainda não carregou: pede ao servidor e a aba é redesenhada quando chegar
function V.ItemName(itemID)
	local name = itemID and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if name and name ~= "" then return name end
	if itemID and not waiting[itemID] and C_Item.RequestLoadItemDataByID then
		waiting[itemID] = true
		waitN = waitN + 1
		pcall(C_Item.RequestLoadItemDataByID, itemID)
	end
	return "item " .. tostring(itemID)
end

function V.TrendShade(t)
	local flag = ns.Pricing.TrendFlag(t)
	if flag == "down" then return { 1, 0.1, 0.1, 0.28 } end
	if flag == "spike" then return { 1, 0.82, 0, 0.22 } end
	return nil
end

