local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- Aba "Configurações": tudo que antes era só por comando /lucro, com campos na janela
local Settings = {}
ns.Settings = Settings

local panel
local controls = {}

local function Cfg(key) return ns.Cfg(key) end
local function Set(key, value)
	LucroCraftDB.config[key] = value
end

local function ReapplyABC()
	for _, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do ns.Scanner.ApplyABC(e.rows or {}) end
	end
end

-- recalcula: se a profissão está aberta, refaz o scan; senão só atualiza o que dá
local function Apply(needsScan)
	ReapplyABC()
	-- preço, custo, stats, estoque e tendência valem já para todos os dados salvos
	if needsScan and ns.Scanner.RepriceAll then ns.Scanner.RepriceAll() end
	if needsScan and C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady() then
		ns.Scanner.Scan(true)
		if panel and panel.note then panel.note:SetText(L["|cff55ff55Aplicado e recalculado.|r"]) end
	elseif panel and panel.note then
		panel.note:SetText(needsScan and L["|cffffd100Salvo. Vale no próximo scan (abra a profissão).|r"] or L["|cff55ff55Salvo.|r"])
	end
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local function Tip(widget, text)
	if not text then return end
	widget:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(text, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- título da seção + linha "afeta: ..." (onde a configuração faz diferença)
local function Header(text, x, y, affects)
	local bar = panel:CreateTexture(nil, "BACKGROUND")
	bar:SetPoint("TOPLEFT", x - 2, y + 3)
	bar:SetSize(470, 34)
	bar:SetColorTexture(0.17, 0.36, 0.66, 0.16)
	local mark = panel:CreateTexture(nil, "ARTWORK")
	mark:SetPoint("TOPLEFT", x - 2, y + 3)
	mark:SetSize(3, 34)
	mark:SetColorTexture(0.70, 0.13, 0.20, 0.95)
	local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", x + 6, y)
	fs:SetText("|cffd4af37" .. text .. "|r")
	if affects then
		local a = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		a:SetPoint("TOPLEFT", x + 6, y - 15)
		a:SetText(L["afeta: "] .. "|cffd9dde3" .. affects .. "|r")
	end
	return y - (affects and 40 or 22)
end

local function Check(x, y, label, key, rescan, tip)
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetSize(22, 22)
	cb:SetPoint("TOPLEFT", x, y)
	local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	fs:SetText(label)
	cb:SetScript("OnClick", function(self)
		Set(key, self:GetChecked() and true or false)
		Apply(rescan)
	end)
	Tip(cb, tip)
	table.insert(controls, function() cb:SetChecked(Cfg(key) and true or false) end)
	return cb
end

-- campo de texto/número; kind = "text" | "number" | "percent" (guarda fração, mostra %)
local function Edit(x, y, label, width, key, kind, rescan, tip, validate)
	local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", x, y - 4)
	fs:SetText(label)
	local eb = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	eb:SetAutoFocus(false)
	eb:SetSize(width, 20)
	eb:SetPoint("LEFT", fs, "RIGHT", 10, 0)
	local function show()
		local v = Cfg(key)
		if kind == "percent" then
			eb:SetText(v and string.format("%g", v * 100) or "")
		else
			eb:SetText(v ~= nil and tostring(v) or "")
		end
		eb:SetCursorPosition(0)
		eb.shown = eb:GetText()
	end
	local function commit(self)
		local t = strtrim(self:GetText() or "")
		if t == strtrim(self.shown or "") then return end   -- nada mudou (Enter + perder foco)
		local value
		if kind == "text" then
			if t == "" then value = nil
			elseif validate and not validate(t) then
				panel.note:SetText(L["|cffff5555Valor inválido: "] .. t .. "|r"); show(); return
			else value = t end
		else
			local n = tonumber((t:gsub(",", ".")))
			if t == "" then value = nil
			elseif not n then panel.note:SetText(L["|cffff5555Número inválido: "] .. t .. "|r"); show(); return
			else value = (kind == "percent") and n / 100 or n end
		end
		Set(key, value)
		show()
		Apply(rescan)
	end
	eb:SetScript("OnEnterPressed", function(self) commit(self); self:ClearFocus() end)
	eb:SetScript("OnEscapePressed", function(self) show(); self:ClearFocus() end)
	eb:SetScript("OnEditFocusLost", function(self) commit(self) end)
	Tip(eb, tip)
	table.insert(controls, show)
	return eb
end

-- botão que alterna entre opções
local function Cycle(x, y, label, key, options, rescan, tip)
	local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", x, y - 4)
	fs:SetText(label)
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(70, 20)
	b:SetPoint("LEFT", fs, "RIGHT", 10, 0)
	local function show()
		local v = tostring(Cfg(key) or options[1])
		b:SetText(v == "LucroCraft" and L["scan próprio"] or L[v])
	end
	b:SetScript("OnClick", function()
		local cur = tostring(Cfg(key) or options[1])
		local idx = 1
		for i, o in ipairs(options) do if tostring(o) == cur then idx = i end end
		local nextV = options[(idx % #options) + 1]
		Set(key, nextV)
		show()
		Apply(rescan)
	end)
	Tip(b, tip)
	table.insert(controls, show)
	return b
end

local function Button(x, y, w, label, fn, tip)
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetPoint("TOPLEFT", x, y)
	b:SetText(label)
	b:SetScript("OnClick", fn)
	Tip(b, tip)
	return b
end

local root   -- moldura com rolagem (panel é o conteúdo dela)

local function Create(parent)
	root = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	root:SetPoint("TOPLEFT", 12, -56)
	root:SetPoint("BOTTOMRIGHT", -30, 26)
	root:Hide()
	panel = CreateFrame("Frame", nil, root)
	panel:SetSize(980, 1100)
	root:SetScrollChild(panel)

	local XL, XR = 6, 500   -- duas colunas
	local y

	-- ===================== coluna esquerda =====================
	y = -6
	y = Header(L["Geral"], XL, y, L["todo o Royal Revenue"])
	-- idioma (vale para os dois módulos; aplica depois de recarregar)
	do
		local LANGS = { { "auto", L["Automático (idioma do jogo)"] }, { "pt", "Português" }, { "en", "English" } }
		local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", XL, y - 4)
		fs:SetText(L["Idioma:"])
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(190, 20)
		b:SetPoint("LEFT", fs, "RIGHT", 10, 0)
		local rl = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		rl:SetSize(90, 20)
		rl:SetPoint("LEFT", b, "RIGHT", 4, 0)
		rl:SetText(L["Recarregar"])
		rl:SetScript("OnClick", function() ReloadUI() end)
		local function show()
			local cur = LucroCraftDB.config.lang or "auto"
			for _, l in ipairs(LANGS) do if l[1] == cur then b:SetText(l[2]) end end
			rl:SetShown(cur ~= (ns.lang or "auto"))
		end
		b:SetScript("OnClick", function()
			local cur = LucroCraftDB.config.lang or "auto"
			local idx = 1
			for i, l in ipairs(LANGS) do if l[1] == cur then idx = i end end
			local v = LANGS[(idx % #LANGS) + 1][1]
			if ns.root and ns.root.SetLang then ns.root.SetLang(v) else LucroCraftDB.config.lang = v end
			show()
			panel.note:SetText(L["|cffffd100Idioma alterado: clique em Recarregar (ou /reload) para aplicar.|r"])
		end)
		Tip(b, L["Idioma dos textos (craft e livro-caixa). Automático = o mesmo do jogo. Vale depois de recarregar a interface."])
		table.insert(controls, show)
		y = y - 26
	end
	do
		local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		cb:SetSize(22, 22)
		cb:SetPoint("TOPLEFT", XL, y)
		local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		fs:SetText(L["Ícone no minimapa"])
		cb:SetScript("OnClick", function(self)
			if ns.root and ns.root.SetMinimap then ns.root.SetMinimap(self:GetChecked() and true or false) end
		end)
		table.insert(controls, function() cb:SetChecked(not (LucroLivroDB and LucroLivroDB.minimap and LucroLivroDB.minimap.hide)) end)
		y = y - 24
	end
	Check(XL, y, L["Abrir junto com a profissão"], "autoOpen", false, L["Abre a janela de craft ao abrir uma profissão."]); y = y - 24
	Check(XL, y, L["Abrir o Mercado junto com a casa de leilões"], "ahAutoOpen", false,
		L["Ao abrir a casa de leilões o addon abre em Mercado > Compras; a aba Vender da casa de leilões leva para Vender."]); y = y - 24
	Check(XL, y, L["Mostrar avisos do log no chat (debug)"], "debug", false); y = y - 30

	y = Header(L["Fonte de preços"], XL, y, L["Receitas, Plano, Fila, Investimento e o valor dos itens no Livro-caixa"])
	Cycle(XL, y, L["Preços:"], "priceSource", { "auto", "TSM", "Auctionator", "LucroCraft" }, true,
		L["auto = usa o TSM se estiver instalado; senão o Auctionator; senão o scan próprio do addon.\nScan próprio = varredura da casa de leilões feita pelo addon (automática ao abrir o leilão, a cada 15 min).\nSem o TSM, vendas/dia e tendência são estimados pelo histórico de preços e quantidades."]); y = y - 26
	Button(XL, y, 150, L["Escanear leilão"], function()
		if ns.Own then ns.Own.StartScan(true) end
	end, L["Escaneia a casa de leilões agora (precisa estar com ela aberta; o jogo permite um scan completo a cada 15 min)."])
	panel.srcNote = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.srcNote:SetPoint("TOPLEFT", XL + 156, y - 5)
	table.insert(controls, function()
		local last = ns.Own and ns.Own.LastScan() or 0
		panel.srcNote:SetText(string.format(L["em uso: |cffffd100%s|r"], ns.Pricing.SourceName())
			.. (last > 0 and string.format(L[" · scan há %s"], ns.Alerts.Hours((time() - last) / 3600)) or ""))
	end)
	y = y - 28
	Edit(XL, y, L["Venda (TSM):"], 300, "saleSource", "text", true,
		L["Custom price do TSM para o preço de venda.\nPadrão: min(first(DBMinBuyout, DBMarket), first(DBRegionSaleAvg, DBRegionMarketAvg))"],
		function(t) return ns.Pricing.Validate(t) end); y = y - 26
	Edit(XL, y, L["Custo (TSM):"], 300, "costSource", "text", true,
		L["Custom price do TSM para o custo dos reagentes.\nPadrão: first(VendorBuy, DBMarket, DBMinBuyout, DBRegionMarketAvg)"],
		function(t) return ns.Pricing.Validate(t) end); y = y - 26
	Edit(XL, y, L["Taxa da AH (%):"], 50, "ahCut", "percent", true, L["Corte do leilão sobre a venda (padrão 5%)."]); y = y - 32

	y = Header(L["Cálculo do lucro"], XL, y, L["Receitas, Plano de concentração e Fila"])
	Cycle(XL, y, L["Qualidade do item final:"], "outputQuality", { "auto", 1, 2, 3, 4, 5 }, true,
		L["auto = a qualidade que a sua skill atinge. Um número força a qualidade."]); y = y - 26
	Check(XL, y, L["Considerar multicraft / resourcefulness / ingenuity"], "useStats", true); y = y - 24
	Check(XL, y, L["Usar custo de fabricar reagentes quando for mais barato"], "useCrafted", true); y = y - 24
	Check(XL, y, L["Otimizar reagentes (qualidade de cima sem concentração)"], "optimizeReagents", true,
		L["Testa trocar parte dos reagentes pela qualidade superior para a receita sair na qualidade de cima sem gastar concentração.\nAparece como linha \"reagentes sup.\" na lista. Se der mais lucro que a concentração, a receita sai do plano de concentração.\nVale no próximo scan (abra a profissão)."]); y = y - 26
	Cycle(XL, y, L["Custo do que já está no estoque:"], "costMode", { "mercado", "estoque" }, true,
		L["mercado = reagente conta pelo preço da AH (custo de oportunidade).\nestoque = reagente que você já tem (todos os personagens + bando) conta 0 — é o seu desembolso.\nA lista de compras sempre desconta o estoque."]); y = y - 32

	y = Header(L["Lista de receitas"], XL, y, L["aba Receitas (seções, curva ABC e avisos de pouca venda)"])
	Check(XL, y, L["Só lucrativos na lista"], "onlyProfit", false); y = y - 24
	Edit(XL, y, L["Classe A até (% acumulado):"], 50, "abcA", "percent", false, L["Padrão 80%."]); y = y - 26
	Edit(XL, y, L["Classe B até (% acumulado):"], 50, "abcB", "percent", false, L["Padrão 95%."]); y = y - 26
	Edit(XL, y, L["Pouca venda abaixo de (vendas/dia):"], 50, "minSoldPerDay", "number", true,
		L["Itens abaixo disso ganham o ! laranja e a "] .. ns.QIcon(2) .. L[" não entra nas recomendações."]); y = y - 26
	Edit(XL, y, L["Seção Volume a partir de (vendas/dia):"], 50, "volumeMinSpd", "number", false,
		L["Receita lucrativa que vende pelo menos isto por dia na região vai para a seção Volume;\nabaixo disso vai para Baixo volume, alto lucro."]); y = y - 26
	Check(XL, y, L["Ignorar itens de coleta no % de vendas e na curva ABC"], "excludeGathered", false,
		L["Itens que também se obtêm por coleta (ex.: motes das transmutações) não entram no % de vendas nem na curva ABC.\nCtrl+clique numa receita marca/desmarca manualmente."]); y = y - 26
	local yLeft = y

	-- ===================== coluna direita =====================
	y = -6
	y = Header(L["Plano de concentração e recomendações"], XR, y, L["Plano de concentração, Fila (itens do plano) e Investimento"])
	Cycle(XR, y, L["Classes recomendadas até:"], "recoMinABC", { "B", "A", "C" }, false,
		L["A = só itens classe A; B = A e B; C = todas."]); y = y - 26
	Edit(XR, y, L["Mínimo das vendas da profissão (%):"], 50, "recoMinShare", "percent", false,
		L["Item precisa ter pelo menos esta participação nas vendas/dia da profissão para ser recomendado."]); y = y - 26
	Edit(XR, y, L["Regeneração de concentração (/h):"], 50, "concPerHour", "number", false,
		L["Vazio = aprendida pelos seus scans (padrão ~10,5/h)."]); y = y - 26
	Check(XR, y, L["Fila inclui o plano de concentração"], "queueIncludePlan", false,
		L["Os crafts do plano do personagem logado entram sozinhos na Fila e na lista de compras."]); y = y - 24
	Check(XR, y, L["Segurar concentração para a receita mais lucrativa"], "planHold", false,
		L["Não gasta concentração numa receita de menos ouro por ponto: mostra \"SEGURE até X\" e quanto rende a mais esperar. Desligado = gasta em qualquer receita lucrativa que caiba agora."]); y = y - 32

	y = Header(L["Tendência e vendas reais"], XR, y, L["Receitas, Plano e a aba Vendas do Livro-caixa"])
	Edit(XR, y, L["Preço caindo abaixo de (% do histórico):"], 50, "trendDrop", "percent", true,
		L["Preço recente (DBRecent) abaixo do histórico de 60 dias (DBHistorical) por mais que isto = caindo (vermelho)."]); y = y - 26
	Edit(XR, y, L["Preço em pico acima de (%):"], 50, "trendSpike", "percent", true,
		L["Preço recente acima do histórico por mais que isto = pico (amarelo): pode não se sustentar."]); y = y - 26
	Edit(XR, y, L["Suas vendas: últimos (dias):"], 50, "salesDays", "number", false,
		L["Janela usada na aba Vendas e na coluna Minhas/dia (TSM Accounting)."]); y = y - 32

	y = Header(L["Destruir"], XR, y, L["aba Destruir (prospecção, trituração, reciclagem)"])
	Check(XR, y, L["Abrir a aba ao selecionar uma receita de destruição"], "salvageFocus", false,
		L["Ao clicar em Prospecção, Trituração, Reciclagem etc. na janela de profissão, a aba Destruir abre sozinha."]); y = y - 32

	y = Header(L["Alertas no login"], XR, y, L["mensagens no chat ao entrar"])
	Check(XR, y, L["Mostrar alertas no chat ao entrar"], "alertsOnLogin", false,
		L["Concentração perto de encher, conhecimento não gasto, reset semanal e scans antigos. /lucro alertas mostra de novo."]); y = y - 26
	Edit(XR, y, L["Concentração: avisar a partir de (%):"], 50, "alertConcPct", "percent", false); y = y - 26
	Edit(XR, y, L["Scan antigo depois de (dias):"], 50, "staleDays", "number", false,
		L["Os preços são atualizados sozinhos no login; skill, stats e concentração só abrindo a profissão."]); y = y - 32

	y = Header(L["Manutenção"], XR, y, L["dados salvos e janela"])
	Button(XR, y, 150, L["Restaurar padrões"], function()
		local keep = { columns = LucroCraftDB.config.columns, sort = LucroCraftDB.config.sort, lang = LucroCraftDB.config.lang }
		LucroCraftDB.config = keep
		Settings.Refresh()
		ReapplyABC()
		Apply(true)
	end, L["Volta todas as configurações ao padrão (mantém colunas, ordenação e idioma)."])
	Button(XR + 156, y, 150, L["Restaurar colunas"], function()
		if ns.UI.ResetColumns then ns.UI.ResetColumns() end
		panel.note:SetText(L["|cff55ff55Colunas restauradas.|r"])
	end); y = y - 26
	Button(XR, y, 150, L["Reposicionar janela"], function()
		LucroCraftDB.pos = nil
		if ns.UI.IsShown() then ns.UI.Show() end
	end)
	Button(XR + 156, y, 150, L["Limpar log"], function()
		LucroCraftDB.log = {}
		panel.note:SetText(L["|cff55ff55Log limpo.|r"])
	end); y = y - 26
	Button(XR, y, 150, L["Reprecificar tudo"], function()
		ns.Scanner.RepriceAll(function() panel.note:SetText(L["|cff55ff55Preços atualizados.|r"]) end)
	end, L["Atualiza preços, vendas/dia e tendência de todos os personagens, sem abrir as profissões."])
	Button(XR + 156, y, 150, L["Apagar tudo (Shift)"], function()
		if not IsShiftKeyDown() then
			panel.note:SetText(L["|cffff8800Segure Shift e clique para apagar tudo.|r"])
			return
		end
		LucroCraftDB = { config = {}, chars = {} }
		Settings.Refresh()
		panel.note:SetText(L["|cffff5555Dados apagados.|r"])
		if ns.UI.Refresh then ns.UI.Refresh() end
	end, L["Apaga os scans salvos de todos os personagens e as configurações de craft (o Livro-caixa não é afetado)."]); y = y - 26
	Button(XR, y, 150, L["Abrir o livro-caixa"], function()
		if ns.root and ns.root.Open then ns.root.Open("livro") end
	end); y = y - 30

	panel:SetHeight(math.max(-yLeft, -y) + 20)

	panel.note = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.note:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 2, -6)
	panel.note:SetText(L["|cff9d9d9dEnter ou clicar fora aplica. Passe o mouse para ver a explicação de cada campo.|r"])
end

function Settings.Refresh()
	for _, fn in ipairs(controls) do fn() end
end

function Settings.Show(parent)
	if not panel then Create(parent) end
	-- mudanças de ABC valem imediatamente para os dados salvos
	ReapplyABC()
	Settings.Refresh()
	panel:SetWidth(math.max(960, root:GetWidth()))
	root:Show()
	if ns.root and ns.root.Skin then ns.root.Skin(panel) end
end

function Settings.Hide()
	if panel then
		ReapplyABC()
		root:Hide()
	end
end
