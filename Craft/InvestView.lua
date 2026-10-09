local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- Aba Investimento em versão visual: equipamento, melhorias, valor dos atributos, especialização e perícia
local Invest = ns.Invest
local P = ns.Pricing
local V = ns.Visual

local GOLD_C = { 1, 0.82, 0 }
local WHITE = { 1, 1, 1 }
local GREY = { 0.6, 0.6, 0.6 }

local function Line(tt, left, right, rc)
	rc = rc or WHITE
	tt:AddDoubleLine(left, right, GOLD_C[1], GOLD_C[2], GOLD_C[3], rc[1], rc[2], rc[3])
end

local function Weeks(w)
	if not w then return nil end
	if w > 52 then return L["> 1 ano"] end
	if w >= 10 then return string.format(L["%.0f sem"], w) end
	return string.format(L["%.1f sem"], w)
end

local function PayColor(w)
	if not w then return "|cffff8800" end
	if w <= 2 then return "|cff55ff55" end
	if w <= 6 then return "|cffffd100" end
	if w <= 26 then return "|cffff8800" end
	return "|cffff5555"
end

local MIN_GAIN = 1   -- abaixo de 1 de ouro por semana não vale mostrar como ganho

-- nó da especialização que vale mostrar em destaque (tem ganho de verdade ou libera receita)
local function NodeWorth(node)
	if node.locked then return false end
	if node.cdPerks then
		for _, t in ipairs(node.teeth or {}) do if not t.earned and t.cd then return true end end
	end
	if node.nRecipes == 0 then return false end
	for _, t in ipairs(node.teeth or {}) do
		if not t.earned then
			if t.gain and t.gain >= MIN_GAIN then return true end
			if t.desc and not t.stats then return true end
		end
	end
	return false
end

-- Grupos minimizáveis da aba (como na lista de receitas): LucroCraftDB.config.investCollapsed[chave] = true
local function GroupCollapsed(key)
	local c = LucroCraftDB.config.investCollapsed
	return c and c[key] or false
end
local Group
function Invest._Group(...) return Group(...) end
function Group(cv, y, W, key, title, summary)
	local col = GroupCollapsed(key)
	cv:Box(0, y, W, 24, 0.17, 0.36, 0.66, 0.30)
	cv:Box(0, y, 3, 24, 0.70, 0.13, 0.20, 0.95)
	cv:Box(0, y + 23, W, 1, 0.83, 0.69, 0.22, 0.55)
	local icon = col and "|TInterface\\Buttons\\UI-PlusButton-Up:14:14|t " or "|TInterface\\Buttons\\UI-MinusButton-Up:14:14|t "
	cv:Text(8, y + 5, icon .. "|cffd4af37" .. title .. "|r", GameFontNormal)
	if summary then cv:Text(8, y + 6, summary, GameFontHighlightSmall, W - 16, "RIGHT") end
	cv:Hit(0, y, W, 24, function()
		LucroCraftDB.config.investCollapsed = LucroCraftDB.config.investCollapsed or {}
		LucroCraftDB.config.investCollapsed[key] = not col or nil
		if Invest.Refresh then Invest.Refresh() end
	end, function(tt)
		tt:SetText(title)
		tt:AddLine(col and L["Clique para expandir"] or L["Clique para minimizar"], 1, 1, 1)
	end)
	return y + 30, col
end

local function Section(cv, y, W, title, sub)
	cv:Box(0, y, W, 18, 1, 0.82, 0, 0.10)
	cv:Text(6, y + 3, "|cffffd100" .. title .. "|r" .. (sub and ("  |cff9d9d9d" .. sub .. "|r") or ""), GameFontNormalSmall)
	return y + 24
end

-- tooltip de um candidato a melhoria
-- Ferramenta fabricada ainda sem atributo escolhido: o jogo mostra "+86 Random Stat 1".
-- Troca essa linha pelo atributo que o addon recomenda escolher na hora de fabricar.
local function FixRandomStat(tt, choice)
	if not choice or not tt.GetName or not tt:GetName() then return end
	for i = 1, tt:NumLines() do
		local fs = _G[tt:GetName() .. "TextLeft" .. i]
		local text = fs and fs:GetText()
		if text then
			local low = text:lower()
			if low:find("random stat", 1, true) or low:find("atributo aleat", 1, true) then
				local num = text:match("%+%s*([%d%.,]+)")
				if num then
					fs:SetText(string.format("+%s %s |cff9d9d9d(%s)|r", num, choice, L["escolher ao fabricar"]))
				end
			end
		end
	end
end

local function CandTip(c, r)
	return function(tt)
		if c.outLink then tt:SetHyperlink(c.outLink) else tt:SetItemByID(c.itemID) end
		FixRandomStat(tt, r.statChoice)
		tt:AddLine(" ")
		Line(tt, L["Ganho por semana"], P.FormatMoney(r.gain), { 0.3, 1, 0.3 })
		Line(tt, L["Recupera em"], r.payback and string.format(L["%.1f semanas"], r.payback) or L["sem preço"])
		Line(tt, L["Custo"], (c.price and P.FormatMoney(c.price) or "—") .. " (" .. (c.priceFrom or "?") .. ")")
		Line(tt, L["Atributos"], Invest._StatStr(r.stats))
		if r.statChoice then Line(tt, L["Fabricar com"], r.statChoice, { 0.4, 0.8, 1 }) end
		for _, ch in ipairs(r.allChoices or {}) do
			if ch.label ~= r.statChoice then Line(tt, "   " .. ch.label, P.FormatGold(ch.gain, true), GREY) end
		end
		if r.sameUpgrade then tt:AddLine(L["Mesma peça que você usa, refeita na qualidade máxima"], 1, 0.82, 0, true) end
		if r.showcase or (r.gain or 0) <= 0 then
			tt:AddLine(L["Versão épica: aparece porque você usa uma peça azul. Pelos atributos de hoje não aumenta o lucro."], 0.64, 0.21, 0.93, true)
		end
		if r.beatsHigherRarity then tt:AddLine(L["Raridade menor que a sua, mas com atributos melhores"], 1, 0.82, 0, true) end
		if c.typeUnknown then tt:AddLine(L["Tipo de acessório não identificado: confira o espaço"], 0.6, 0.6, 0.6, true) end
		for k, n in ipairs(r.newNatural or {}) do
			if k > 3 then break end
			tt:AddLine(string.format(L["Passa a sair %s sem concentração: %s"], ns.QIcon(2), n.name), 0.4, 0.8, 1, true)
		end
		tt:AddLine(L["Shift+clique: pôr o link no chat"], 0.6, 0.6, 0.6)
	end
end

-- raridade real da peça (pelo link fabricado, se houver)
local function CandRarity(c)
	local rarity = c.rarity
	if c.outLink then
		local q = select(3, C_Item.GetItemInfo(c.outLink))
		if q then rarity = q end
	end
	return rarity
end

-- melhorias de um espaço (ganho > 0), da que se paga mais rápido.
-- Peça equipada azul: a versão épica (roxa) do mesmo espaço aparece também, mesmo sem ser melhoria agora.
local function Upgrades(inv, idx)
	local ups = {}
	local g = (inv.gear or {})[idx]
	for _, c in ipairs(inv.cands or {}) do
		local r = c.bySlot and c.bySlot[idx]
		if r and r.gain > 0 then table.insert(ups, { c = c, r = r }) end
	end
	table.sort(ups, function(a, b)
		local pa, pb = a.r.payback or math.huge, b.r.payback or math.huge
		if pa ~= pb then return pa < pb end
		return a.r.gain > b.r.gain
	end)
	if g and g.rarity == 3 then
		-- versão épica do MESMO espaço: ferramenta com ferramenta; acessório só com a mesma categoria
		-- (cabeça com cabeça, peito com peito). Sem categoria conhecida não entra (evita peça do outro espaço).
		local shown = {}
		for _, u in ipairs(ups) do shown[u.c.itemID] = true end
		local reeval = ns.Invest._reeval and ns.Invest._reeval[inv]
		local best
		for _, c in ipairs(inv.cands or {}) do
			if not shown[c.itemID] and (CandRarity(c) or 0) >= 4 then
				if not c.cat and ns.Invest._UniqueCategory then c.cat, c.catName = ns.Invest._UniqueCategory(c.itemID) end
				local fits
				if idx == 1 then fits = c.kind == "tool"
				else fits = c.kind ~= "tool" and c.cat ~= nil and g.cat ~= nil and c.cat == g.cat end
				if fits then
					local r = c.bySlot and c.bySlot[idx]
					if not r and reeval then
						local ok, res = pcall(reeval, c, idx)
						if ok and res then
							c.bySlot = c.bySlot or {}
							c.bySlot[idx] = res
							r = res
						end
					end
					r = r or { gain = 0, unknown = true }
					if not best or (not r.unknown and (best.r.unknown or (r.gain or 0) > (best.r.gain or 0))) then
						best = { c = c, r = r, showcase = true }
					end
				end
			end
		end
		if best then table.insert(ups, best) end
	end
	return ups
end

local function GearTip(g)
	return function(tt)
		if g.link then tt:SetHyperlink(g.link) else tt:SetText(L["Vazio"]) end
	end
end

-- próximo dente que mexe em cargas/recarga
local function NextCharge(node)
	for _, t in ipairs(node.teeth or {}) do
		if not t.earned and t.cd then return t end
	end
end
local function ChargeLabel(c)
	local tgt = (c.target and c.target ~= "transmut") and c.target or L["transmutação"]
	if c.kind == "rate" then return string.format(L["%s recarrega mais rápido"], tgt) end
	return string.format(L["+%d carga(s) de %s"], c.n or 1, tgt)
end
Invest._ChargeLabel = ChargeLabel

-- próximo dente com valor de um nó da especialização
local function NextTooth(node)
	for _, t in ipairs(node.teeth or {}) do
		if not t.earned then return t end
	end
end

-- Profissão de coleta: só os buffs temporários (comida, frascos, pedra de afiar), com preço e duração.
local GROUP_TITLE = { food = "Comida", phial = "Frascos", stone = "Pedra de afiar" }
-- sigla do atributo no idioma do cliente (3 primeiras letras do nome que o jogo usa)
local function StatTag(k)
	local name = ns.STAT[k] or k or "?"
	return (name:match("^[%z\1-\127\194-\244][\128-\191]*[%z\1-\127\194-\244]?[\128-\191]*[%z\1-\127\194-\244]?[\128-\191]*") or name):upper()
end
function Invest._RenderGathering(cv, e, W)
	local G = P.FormatGold
	local me = ns.CharKey()
	local prof = ns.Gather and ns.Gather.BY_PARENT[e.parentID or 0]
	local an = prof and ns.Gather.Analyze(prof) or { n = 0 }
	cv:Icon(6, 2, 36, V.ProfIcon(me, e), { border = { 0.6, 0.6, 0.6 } })
	cv:Text(50, 4, V.ClassName(me, e.class) .. "  |cffffffff" .. (e.name or "?") .. "|r", GameFontNormal)
	cv:Text(50, 22, string.format(L["|cff9d9d9d%d coletas registradas (todos os personagens)%s|r"], an.n,
		an.rate and string.format(L[" · ~%.0f por hora"], an.rate) or ""), GameFontDisableSmall)
	cv:Text(W - 330, 4, L["Valor de 100 coletas"], GameFontNormalSmall, 200, "RIGHT")
	cv:Text(W - 330, 18, an.value100 and G(an.value100, true) or "|cff9d9d9d—|r", GameFontNormalLarge, 200, "RIGHT")
	local y = 48

	if an.n == 0 then
		y = Section(cv, y, W, L["100 coletas"], L["ainda sem dados"])
		cv:Text(8, y, L["|cff9d9d9dColete normalmente: cada saque de erva, minério ou couro da expansão atual é registrado com os seus atributos daquele momento.|r"],
			GameFontHighlightSmall, W - 16)
		y = y + 30
	else
		-- ===== o que sai em 100 coletas =====
		y = Section(cv, y, W, L["100 coletas"], string.format(L["média real × preço de venda (-5%%) · material base %s · raros %s"],
			G(an.base100 or 0), G(an.rare100 or 0)))
		local x = 8
		for _, it in ipairs(an.items) do
			if x + 56 > W then break end
			cv:Icon(x + 8, y, 34, V.ItemIcon(it.itemID), {
				count = root.Num(it.per100, 0), border = it.base and { 0.6, 0.6, 0.6 } or { 0.4, 0.8, 1 },
				link = select(2, C_Item.GetItemInfo(it.itemID)),
				tip = function(tt)
					tt:SetItemByID(it.itemID)
					tt:AddLine(" ")
					Line(tt, L["Em 100 coletas"], root.Num(it.per100, 1))
					Line(tt, L["Valor em 100 coletas"], P.FormatMoney(it.value100), { 0.3, 1, 0.3 })
					tt:AddLine(it.base and string.format(L["Material base (sai na maioria das coletas): sobe com %s"], ns.STAT.finesse)
						or string.format(L["Raro (sai em poucas coletas): sobe com %s"], ns.STAT.perception), 0.6, 0.6, 0.6, true)
				end })
			cv:Text(x, y + 36, G(it.value100), GameFontHighlightSmall, 50, "CENTER")
			x = x + 56
		end
		y = y + 56
	end

	-- ===== por hora: nós/h como parâmetro =====
	local R, rsrc = 0, nil
	if prof and an.n > 0 then
		R, rsrc = ns.Gather.NodesPerHour(prof, an)
		local perNode = an.nodeValue or 0
		y = Section(cv, y, W, L["Por hora"], string.format(L["%s por nó × nós por hora"], G(perNode)))
		-- controle de nós/h
		cv:Text(8, y + 4, L["Nós por hora"], GameFontHighlight, 120)
		cv:Button(130, y, 30, 22, "-10", function() ns.Gather.SetNodesPerHour(prof, math.max(10, math.floor(R - 10))); Invest.Refresh() end)
		cv:Text(162, y + 2, string.format("|cffffffff%.0f|r", R), GameFontNormalLarge, 60, "CENTER")
		cv:Button(222, y, 30, 22, "+10", function() ns.Gather.SetNodesPerHour(prof, math.floor(R + 10)); Invest.Refresh() end)
		local srcTxt = rsrc == "manual" and L["|cffffd100ajustado por você|r"] or rsrc == "medido" and L["|cff55ff55medido nas suas sessões|r"] or L["|cff9d9d9dpadrão (sem sessão medida)|r"]
		cv:Text(256, y + 5, srcTxt, GameFontDisableSmall, 200)
		if rsrc == "manual" then
			cv:Button(460, y, 90, 22, L["usar medido"], function() ns.Gather.SetNodesPerHour(prof, nil); Invest.Refresh() end)
		end
		cv:Text(W - 330, y, L["Valor por hora"], GameFontNormalSmall, 200, "RIGHT")
		cv:Text(W - 330, y + 14, G(perNode * R, true), GameFontNormalLarge, 200, "RIGHT")
		y = y + 30
		cv:Text(8, y, string.format(L["|cff9d9d9d+10 nós por hora (rota melhor, montado, %s) = |r|cff55ff55+%s/h|r"], ns.STAT.deftness, G(perNode * 10)), GameFontHighlightSmall, W - 16)
		y = y + 22

		-- ===== modificadores dos nós =====
		y = Section(cv, y, W, L["Modificadores dos nós"], string.format(L["ganho por hora a %.0f nós/h · comparado ao nó comum (%s)"], R, G(an.plainValue or 0)))
		local cols = { 8, 230, 300, 380, 470, 570 }
		local hdr = { L["Tipo de nó"], L["% dos nós"], L["Valor/nó"], L["vs comum"], L["Ganho/h"], L["Amostra"] }
		for i, h in ipairs(hdr) do cv:Text(cols[i], y, "|cff9d9d9d" .. h .. "|r", GameFontDisableSmall, 90) end
		y = y + 16
		local MODNAME = { light = L["Lightfused (Mote of Light)"], wild = L["Wild (Mote of Wild Magic)"], primal = L["Primal (Mote of Primal Energy)"], void = L["Voidbound (Mote of Pure Void)"],
			rich = L["Rich"], lush = L["Lush"], seam = L["Seam"] }
		local any = false
		local function row(m, label, perHour, extra)
			any = true
			if m.mote then cv:Icon(cols[1], y - 2, 16, V.ItemIcon(m.mote), { link = select(2, C_Item.GetItemInfo(m.mote)) }) end
			cv:Text(cols[1] + (m.mote and 20 or 0), y, label, GameFontHighlightSmall, 200)
			cv:Text(cols[2], y, m.share and string.format("%.0f%%", m.share * 100) or "—", GameFontHighlightSmall, 60)
			cv:Text(cols[3], y, G(m.avg), GameFontHighlightSmall, 70)
			local d = m.delta or m.gain or 0
			cv:Text(cols[4], y, (d >= 0 and "|cff55ff55+" or "|cffff5555") .. G(d) .. "|r", GameFontHighlightSmall, 80)
			cv:Text(cols[5], y, perHour and ((perHour >= 0 and "|cff55ff55+" or "|cffff5555") .. G(perHour) .. "|r") or "—", GameFontHighlightSmall, 90)
			local conf = m.n >= 30 and "|cff55ff55" or m.n >= 10 and "|cffffd100" or "|cffff8800"
			cv:Text(cols[6], y, conf .. m.n .. "|r" .. (extra or ""), GameFontHighlightSmall, W - cols[6] - 8)
			y = y + 18
		end
		for _, m in ipairs(an.mods or {}) do row(m, MODNAME[m.key] or m.key, R * m.share * m.delta) end
		for _, m in ipairs(an.kinds or {}) do row(m, MODNAME[m.key] or m.key, R * m.share * m.delta) end
		if not any then
			cv:Text(8, y, L["|cff9d9d9dainda sem nós modificados registrados|r"], GameFontDisableSmall, W - 16)
			y = y + 18
		end
		y = y + 4
		-- Overload
		cv:Text(8, y, "|cffffd100" .. L["Overload"] .. "|r", GameFontNormalSmall)
		y = y + 16
		if #(an.overload or {}) == 0 then
			cv:Text(8, y, L["|cff9d9d9dainda sem Overload registrado: use o Overload num nó modificado e o addon mede o ganho (orbes, bichos e o nó) contra o mesmo nó sem Overload.|r"], GameFontDisableSmall, W - 16)
			y = y + 30
		else
			for _, o in ipairs(an.overload) do
				-- quantos Overloads cabem por hora: limitado pelo recarregamento e pelos nós desse tipo que aparecem
				local share
				for _, m in ipairs(an.mods or {}) do if m.key == o.key then share = m.share end end
				local byNodes = R * (share or 0)
				local byCD = an.ovCD and (3600 / an.ovCD) or byNodes
				local perH = math.min(byNodes, byCD)
				row({ mote = o.mote, n = o.n, avg = o.avg, gain = o.gain }, string.format(L["Overload · %s"], MODNAME[o.key] or o.key), o.gain * perH,
					string.format(L[" · ~%.1f/h%s"], perH, an.ovCD and string.format(L[" (recarga %s)"], SecondsToTime and SecondsToTime(an.ovCD) or (math.floor(an.ovCD) .. "s")) or ""))
			end
		end
		-- Wild Perception: +150 Perception por 5 min (matar o elite do Overload Wild)
		if an.per and an.per.per then
			local gathers5 = R * 5 / 60
			local wp = an.per.per / 100 * 150 * gathers5
			y = y + 2
			cv:Icon(8, y - 2, 16, V.ItemIcon(236951))
			cv:Text(28, y, string.format(L["Wild Perception (+150 %s por 5 min) ≈ ~%.0f nós"], ns.STAT.perception, gathers5), GameFontHighlightSmall, 300)
			cv:Text(cols[5], y, "|cff55ff55+" .. G(wp) .. "|r", GameFontHighlightSmall, 90)
			cv:Text(cols[6], y, L["|cff9d9d9dpor buff|r"], GameFontHighlightSmall, 120)
			y = y + 18
		end
		cv:Text(8, y + 2, string.format(L["|cff9d9d9dGanho/h = nós/h × %% dos nós × (valor do nó − nó comum). Valor do nó = saque + extras pegos até 45 s depois (orbes, bichos; 120 s com Overload). Tipo pelo nome do nó (%d de %d coletas têm nome) ou pelo mote do saque. Amostra: verde ≥30, amarelo ≥10.|r"], an.named or 0, an.n),
			GameFontDisableSmall, W - 16)
		y = y + 34
	end

	-- ===== quanto vale cada ponto =====
	y = Section(cv, y, W, L["Quanto vale cada ponto"], L["+10 pontos de cada atributo, a cada 100 coletas"])
	local function Tag(m)
		if not m then return "" end
		if m.measured then return L["|cff55ff55medido|r"] end
		if m.inconclusive then return L["|cffff8800aprox. (medição inconclusiva)|r"] end
		return L["|cffffd100aprox.|r"]
	end
	local rows = {
		{ "+10 " .. ns.STAT.finesse, an.fin and an.fin.per * 10, an.fin },
		{ "+10 " .. ns.STAT.perception, an.per and an.per.per * 10, an.per },
		{ L["+10 de perícia"], an.skill and an.skill.per * 10, an.skill },
	}
	local maxV = 1
	for _, r in ipairs(rows) do if (r[2] or 0) > maxV then maxV = r[2] end end
	for _, r in ipairs(rows) do
		cv:Text(8, y + 1, r[1], GameFontHighlightSmall, 160)
		if r[2] then
			local m = r[3]
			cv:Bar(170, y, W - 400, 13, math.max(r[2], 0), maxV, { 0.3, 0.85, 0.3 }, "", nil, function(tt)
				tt:SetText(r[1])
				tt:AddLine(L["a cada 100 coletas"], 1, 1, 1)
				if m and m.mper then
					tt:AddDoubleLine(L["Medido nas suas coletas"], string.format("%s ± %s", P.FormatMoney(m.mper * 10), P.FormatMoney((m.err or 0) * 10)), 1, 0.82, 0, 1, 1, 1)
				end
				if m and m.measured and m.err then
					tt:AddDoubleLine(L["Margem de erro"], "± " .. P.FormatMoney(m.err * 10), 1, 0.82, 0, 1, 1, 1)
				end
				if m and m.inconclusive then
					tt:AddLine(L["O efeito medido ainda é menor que o ruído (sorte de cada veio e de ★2). Usando a aproximação até ter mais coletas com e sem buff."], 1, 0.53, 0, true)
				end
			end)
			cv:Text(W - 222, y + 1, G(r[2], true), GameFontHighlightSmall, 90, "RIGHT")
			cv:Text(W - 126, y + 1, Tag(r[3]), GameFontDisableSmall, 120)
		else
			cv:Text(170, y + 1, L["|cff9d9d9dprecisa de mais coletas (com o atributo variando) para medir|r"], GameFontDisableSmall, W - 180)
		end
		y = y + 20
	end
	cv:Text(8, y + 1, "+10 " .. ns.STAT.deftness, GameFontHighlightSmall, 160)
	cv:Text(170, y + 1, L["|cff9d9d9dsó velocidade: mais coletas por hora, não muda o que sai de cada uma|r"], GameFontDisableSmall, W - 180)
	y = y + 26

	-- ===== pontos de conhecimento: ouro por hora =====
	local gspec = e.invest and e.invest.gspec
	if gspec and an.n > 0 then
		local Rk = (R and R > 0) and R or (an.rate or 60)
		local val = {
			finesse = an.fin and an.fin.per and an.fin.per / 100 * Rk or 0,
			perception = an.per and an.per.per and an.per.per / 100 * Rk or 0,
			skill = an.skill and an.skill.per and an.skill.per / 100 * Rk or nil,
			deftness = 0,
		}
		local function gainOf(st)
			local g, unk = 0, false
			for k, v in pairs(st or {}) do
				if val[k] then g = g + v * val[k] elseif k == "skill" then unk = true end
			end
			return g, unk
		end
		local function addSt(a2, b2, mult)
			for k, v in pairs(b2 or {}) do a2[k] = (a2[k] or 0) + v * (mult or 1) end
			return a2
		end
		local opts = {}
		for _, tab in ipairs(gspec.tabs or {}) do
			for _, node in ipairs(tab.nodes or {}) do
				if not node.locked and node.rank < node.max then
					-- próximo dente (ou o fim do nó): soma o orbe por ponto + os dentes no caminho
					local acc, flags, descs = {}, {}, {}
					local from = math.max(node.rank, 0)
					for _, t in ipairs(node.teeth) do
						if not t.earned then
							local pts = t.threshold - node.rank
							addSt(acc, node.perRank, t.threshold - from)
							addSt(acc, t.stats)
							from = t.threshold
							for f in pairs(t.flags or {}) do flags[f] = true end
							if t.desc then table.insert(descs, t.desc) end
							local g, unk = gainOf(acc)
							table.insert(opts, { node = node, tab = tab.name, pts = pts, gain = g, per = pts > 0 and g / pts or 0, stats = addSt({}, acc), flags = flags, descs = descs, unk = unk, th = t.threshold })
							break
						end
					end
				end
			end
		end
		table.sort(opts, function(a2, b2) return a2.per > b2.per end)
		local best = opts[1]
		y = Section(cv, y, W, L["Pontos de conhecimento"], best and best.per > 0 and string.format(L["melhor: |cff55ff55+%s/h por ponto|r a %.0f nós/h"], G(best.per), Rk)
			or string.format(L["ganho por hora a %.0f nós/h"], Rk))
		local cols = { 8, 250, 300, 520, 610 }
		local hdr = { L["Nó"], L["Pontos"], L["Próximo dente"], L["Ganho/h"], L["por ponto"] }
		for i, h in ipairs(hdr) do cv:Text(cols[i], y, "|cff9d9d9d" .. h .. "|r", GameFontDisableSmall, 100) end
		y = y + 16
		local STAG = { finesse = ns.STAT.finesse, perception = ns.STAT.perception, deftness = ns.STAT.deftness, skill = L["perícia"] }
		for i, o in ipairs(opts) do
			if i > 14 then break end
			local parts = {}
			for k, v in pairs(o.stats) do table.insert(parts, string.format("+%d %s", v, STAG[k] or k)) end
			if o.flags.mounted then table.insert(parts, L["coletar montado"]) end
			if o.flags.overload then table.insert(parts, L["Overload"]) end
			local what = #parts > 0 and table.concat(parts, ", ") or L["|cff9d9d9dsem atributo no texto|r"]
			local tip = function(tt)
				tt:SetText(o.node.name)
				tt:AddLine(o.tab, 0.6, 0.6, 0.6)
				tt:AddDoubleLine(L["Rank"], string.format("%d / %d", math.max(o.node.rank, 0), o.node.max), 1, 0.82, 0, 1, 1, 1)
				if o.node.desc then tt:AddLine(o.node.desc, 1, 1, 1, true) end
				for _, d in ipairs(o.descs) do tt:AddLine(" "); tt:AddLine(d, 0.3, 1, 0.3, true) end
				tt:AddLine(" ")
				tt:AddLine(string.format(L["Ganho/h = pontos de atributo × valor de 1 ponto por nó × %.0f nós/h."], Rk), 0.6, 0.6, 0.6, true)
				if o.flags.mounted then tt:AddLine(L["Coletar montado aumenta os nós por hora: use +10 nós/h acima para ver quanto vale."], 1, 0.82, 0, true) end
				if (o.stats.deftness or 0) > 0 then tt:AddLine(string.format(L["%s só acelera a coleta (entra nos nós por hora)."], ns.STAT.deftness), 0.6, 0.6, 0.6, true) end
				if o.unk then tt:AddLine(L["Perícia ainda sem valor medido: não entra no ganho."], 0.6, 0.6, 0.6, true) end
			end
			if i == 1 and o.per > 0 then cv:Box(4, y - 2, W - 8, 18, 0.3, 1, 0.3, 0.10) end
			cv:Hit(4, y - 2, W - 8, 18, nil, tip)
			cv:Text(cols[1], y, o.node.name, GameFontHighlightSmall, 240)
			cv:Text(cols[2], y, tostring(o.pts), GameFontHighlightSmall, 40)
			cv:Text(cols[3], y, what, GameFontHighlightSmall, 215)
			cv:Text(cols[4], y, o.gain > 0 and ("|cff55ff55+" .. G(o.gain) .. "|r") or "|cff9d9d9d—|r", GameFontHighlightSmall, 85)
			cv:Text(cols[5], y, o.per > 0 and ("|cff55ff55+" .. G(o.per) .. "|r") or "|cff9d9d9d—|r", GameFontHighlightSmall, 90)
			y = y + 18
		end
		if #opts == 0 then
			cv:Text(8, y, L["|cff9d9d9dnada para avaliar (árvore completa ou ainda não lida: abra a profissão).|r"], GameFontDisableSmall, W - 16)
			y = y + 18
		end
		y = y + 8
	end

	-- ===== buffs temporários =====
	local rateB = (R and R > 0) and R or an.rate
	y = Section(cv, y, W, L["Buffs temporários"], rateB and string.format(L["ganho no tempo do buff a ~%.0f coletas/h"], rateB)
		or L["ganho a cada 100 coletas (sem ritmo medido ainda)"])
	-- primeiro calcula todos (para saber o melhor de cada grupo que está na bolsa)
	local calc = {}
	local bestIn = {}
	for _, b in ipairs(Invest.GATHER_BUFFS or {}) do
		local price = P.Cost(b.itemID) or (P.Buy and P.Buy(b.itemID)) or nil
		local slope = (b.stat == "finesse" and an.fin and an.fin.per) or (b.stat == "perception" and an.per and an.per.per) or nil
		local gain, gathers
		if slope and b.amt then
			if rateB then
				gathers = rateB * (b.minutes or 0) / 60
				gain = slope / 100 * b.amt * gathers
			else
				gain = slope * b.amt
			end
		end
		local have = C_Item.GetItemCount and C_Item.GetItemCount(b.itemID) or 0
		-- na bolsa o custo é de reposição (o mesmo preço); o que importa é o ganho no tempo do buff
		local net = gain and price and (gain - price) or gain
		local c = { b = b, price = price, gain = gain, gathers = gathers, net = net, have = have }
		calc[b] = c
		if have > 0 and (net or 0) > 0 and (not bestIn[b.group] or net > bestIn[b.group].net) then bestIn[b.group] = c end
	end
	-- buff já ativo (frasco/comida): pelo feitiço do item
	local function Active(itemID)
		if not (C_Item.GetItemSpell and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
		local _, spellID = C_Item.GetItemSpell(itemID)
		if not spellID then return nil end
		local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
		if ok and a and a.expirationTime then return math.max(0, a.expirationTime - GetTime()) end
		return nil
	end
	local toolSlot = prof and ns.Gather.ToolSlot and ns.Gather.ToolSlot(prof)
	local x = 8
	local lastGroup
	for _, b in ipairs(Invest.GATHER_BUFFS or {}) do
		local c = calc[b]
		if b.group ~= lastGroup then
			if lastGroup then x = x + 16 end
			cv:Text(x, y, "|cffffd100" .. L[GROUP_TITLE[b.group] or b.group] .. "|r", GameFontNormalSmall)
			lastGroup = b.group
		end
		if x + 56 > W then break end
		local price, gain, gathers, net = c.price, c.gain, c.gathers, c.net
		local good = net and net > 0
		local best = bestIn[b.group] == c
		local left = Active(b.itemID)
		if best then cv:Box(x + 5, y + 13, 40, 40, 0.3, 1, 0.3, 0.35) end
		local tip = function(tt)
			tt:SetItemByID(b.itemID)
			tt:AddLine(" ")
			Line(tt, L["Na bolsa"], tostring(c.have))
			Line(tt, L["Preço"], price and P.FormatMoney(price) or L["sem preço"])
			Line(tt, L["Duração"], string.format(L["%d min"], b.minutes or 0))
			if gain then
				Line(tt, gathers and string.format(L["Ganho em ~%.0f coletas"], gathers) or L["Ganho a cada 100 coletas"], P.FormatMoney(gain), { 0.3, 1, 0.3 })
				if net then Line(tt, L["Saldo por uso"], P.FormatMoney(net), good and { 0.3, 1, 0.3 } or { 1, 0.4, 0.4 }) end
			elseif b.stat == "deftness" then
				tt:AddLine(string.format(L["%s só acelera a coleta."], ns.STAT.deftness), 0.6, 0.6, 0.6, true)
			else
				tt:AddLine(L["Sem o valor do atributo deste item: ganho não calculado."], 0.6, 0.6, 0.6, true)
			end
			if left then tt:AddLine(string.format(L["Ativo: %s restantes"], SecondsToTime and SecondsToTime(left) or (math.floor(left / 60) .. " min")), 0.3, 1, 0.3) end
			tt:AddLine(" ")
			if c.have > 0 then
				tt:AddLine(b.group == "stone" and L["Clique: aplicar na ferramenta da profissão"] or L["Clique: usar"], 0.3, 1, 0.3)
				if best then tt:AddLine(L["Melhor deste grupo entre os que você tem."], 0.3, 1, 0.3) end
			else
				tt:AddLine(L["Você não tem na bolsa."], 0.6, 0.6, 0.6)
			end
		end
		cv:Icon(x + 8, y + 16, 34, V.ItemIcon(b.itemID), {
			count = c.have > 0 and tostring(c.have) or nil, corner = StatTag(b.stat),
			quality = b.quality and ns.QIcon(b.quality, 2, 12) or nil,
			border = left and { 0.3, 0.6, 1 } or (good and { 0.3, 1, 0.3 } or nil),
			desaturate = c.have == 0,
			link = select(2, C_Item.GetItemInfo(b.itemID)), tip = tip })
		if c.have > 0 then
			cv:SecureItem(x + 8, y + 16, 34, 34, b.itemID, b.group == "stone" and toolSlot or nil, tip)
		end
		local txt
		if left then txt = "|cff4d9dff" .. L["ativo"] .. "|r"
		elseif best then txt = "|cff55ff55" .. L["USAR"] .. "|r"
		else txt = net and ((good and "|cff55ff55+" or "|cffff5555") .. G(net) .. "|r") or (price and G(price) or L["|cff9d9d9dsem preço|r"]) end
		cv:Text(x, y + 52, txt, GameFontHighlightSmall, 50, "CENTER")
		x = x + 56
	end
	y = y + 72
	local legend = {}
	for _, k in ipairs({ "finesse", "perception", "deftness" }) do
		table.insert(legend, StatTag(k) .. " " .. ns.STAT[k])
	end
	cv:Text(8, y, L["|cff9d9d9dClique no ícone para usar o que está na bolsa (pedra: vai direto na ferramenta). Fundo verde = o melhor de cada grupo que você tem; borda azul = já ativo.|r"], GameFontDisableSmall, W - 16)
	y = y + 16
	cv:Text(8, y, string.format(L["|cff9d9d9dSigla no ícone = atributo: %s. Comida dura 60 min (beba sentado por 10 s); frascos 30 min e continuam após a morte; pedra 2 h na ferramenta.|r"],
		table.concat(legend, " · ")), GameFontDisableSmall, W - 16)
	y = y + 16
	cv:Text(8, y, string.format(L["|cff9d9d9dMedido = regressão nas suas coletas (precisa de %d coletas e o atributo variando, ex.: com e sem buff). Aprox. = %s +1%% de material base a cada 10 pontos; %s proporcional ao valor dos raros que já saíram.|r"], 30, ns.STAT.finesse, ns.STAT.perception),
		GameFontDisableSmall, W - 16)
	y = y + 36
	if ns.SecondProf then y = ns.SecondProf.Draw(cv, y, W) end
	cv:End(y)
end

function Invest.Render(cv)
	local G = P.FormatGold
	local W = cv:Width()
	cv:Begin()
	local e = Invest._CurrentEntry()
	if not e then
		cv:Text(8, 8, L["Abra a profissão deste personagem para avaliar o equipamento."], GameFontHighlight)
		local yy = 32
		if ns.SecondProf then yy = ns.SecondProf.Draw(cv, yy, W) end
		cv:End(yy + 8)
		return
	end
	local inv = e.invest
	local me = ns.CharKey()
	if inv.gathering then
		Invest._RenderGathering(cv, e, W)
		return
	end
	local perWeek, rate = Invest._ConcPerWeek()

	-- ===== cabeçalho =====
	cv:Icon(6, 2, 36, V.ProfIcon(me, e), { border = { 0.6, 0.6, 0.6 } })
	cv:Text(50, 4, V.ClassName(me, e.class) .. "  |cffffffff" .. (e.name or "?") .. "|r", GameFontNormal)
	cv:Text(50, 22, string.format(L["|cff9d9d9d~%.0f de concentração por semana (%.1f/h)|r"], perWeek, rate))
	local i = inv.info or {}
	cv:Text(W - 330, 4, L["Melhor uso da semana"], GameFontNormalSmall, 200, "RIGHT")
	cv:Text(W - 330, 18, G(i.concGold or 0, true), GameFontNormalLarge, 200, "RIGHT")
	local x = W - 122
	for k, u in ipairs(i.used or {}) do
		if k > 3 then break end
		local r = u.row
		cv:Icon(x, 2, 34, V.ItemIcon(r.concItemID, r.icon), {
			count = root.Num(u.crafts, 0), quality = ns.QIcon(r.concQuality or 2, r.maxQuality, 12),
			tip = function(tt)
				if r.concItemID then tt:SetItemByID(r.concItemID) else tt:SetText(r.name or "?") end
				tt:AddLine(" ")
				Line(tt, L["Fabricações por semana"], string.format("~%.1f", u.crafts))
				Line(tt, L["Lucro por ponto"], P.FormatMoney(u.per))
				Line(tt, L["Lucro na semana"], P.FormatMoney(u.gold), { 0.3, 1, 0.3 })
			end })
		x = x + 40
	end
	local y = 48

	-- resumos para os cabeçalhos
	local bestUp
	for _, c in ipairs(inv.cands or {}) do
		for _, r in pairs(c.bySlot or {}) do
			if (r.gain or 0) > 0 and (not bestUp or r.gain > bestUp) then bestUp = r.gain end
		end
	end
	for _, u in ipairs(inv.enchants or {}) do if (u.gain or 0) > 0 and (not bestUp or u.gain > bestUp) then bestUp = u.gain end end
	local bestBuff
	for _, b in ipairs(inv.buffs or {}) do if b.net and (not bestBuff or b.net > bestBuff) then bestBuff = b.net end end
	local bestPt
	for _, t in ipairs((inv.spec and inv.spec.tabs) or {}) do
		for _, n in ipairs(t.nodes or {}) do
			local tooth = NextTooth(n)
			if tooth and tooth.perPoint and not n.locked and (n.nRecipes or 0) > 0 and (not bestPt or tooth.perPoint > bestPt) then bestPt = tooth.perPoint end
		end
	end

	-- ===================== 1. Equipamento =====================
	local col
	y, col = Group(cv, y, W, "gear", L["Equipamento"], bestUp and string.format(L["melhor melhoria: |cff55ff55+%s/sem|r"], G(bestUp))
		or L["|cff9d9d9dnenhuma melhoria|r"])
	if not col then
		-- ===== equipamento e melhorias =====
		y = Section(cv, y, W, L["Equipamento"], L["peça equipada > melhorias que se pagam mais rápido"])
		local SLOT_NAME = { L["Ferramenta"], L["Acessório 1"], L["Acessório 2"] }
		local colW = math.floor((W - 8) / 3)
		local colH = 0
		for idx = 1, 3 do
			local cx = 4 + (idx - 1) * colW
			local g = (inv.gear or {})[idx]
			local cy = y
			cv:Box(cx, cy, colW - 6, 150, 1, 1, 1, 0.04)
			local slotName = SLOT_NAME[idx]
			if idx > 1 and g and g.catName then slotName = slotName .. " · " .. g.catName end
			cv:Text(cx + 6, cy + 4, slotName, GameFontNormalSmall, colW - 16)
			-- peça atual
			local tex = g and g.itemID and V.ItemIcon(g.itemID) or 136516
			cv:Icon(cx + 6, cy + 20, 40, tex, { rarity = g and g.rarity, desaturate = not (g and g.link), tip = g and GearTip(g), link = g and g.link })
			local nm = g and g.name or L["Vazio"]
			if g and g.rarity and C_Item.GetItemQualityColor then
				local _, _, _, hex = C_Item.GetItemQualityColor(g.rarity)
				if hex then nm = "|c" .. hex .. nm .. "|r" end
			end
			cv:Text(cx + 52, cy + 22, nm, GameFontHighlightSmall, colW - 62)
			cv:Text(cx + 52, cy + 38, "|cff9d9d9d" .. Invest._StatStr(g and g.stats) .. "|r", GameFontHighlightSmall, colW - 62)
			-- melhorias
			local ups = Upgrades(inv, idx)
			local ux = cx + 6
			if #ups == 0 then
				cv:Text(cx + 6, cy + 78, L["|cff9d9d9dnenhuma melhoria que aumente o lucro|r"], GameFontHighlightSmall, colW - 16)
			else
				local anyReal = false
				for _, u in ipairs(ups) do if not u.showcase then anyReal = true end end
				if anyReal then
					cv:Text(cx + 6, cy + 66, L["|cff55ff55melhorias|r"], GameFontDisableSmall)
				else
					cv:Text(cx + 6, cy + 66, L["|cffa335eeversão épica|r |cff9d9d9d(não é melhoria agora)|r"], GameFontDisableSmall, colW - 16)
				end
				for k, u in ipairs(ups) do
					if ux + 50 > cx + colW - 6 then break end
					-- borda = raridade real da peça fabricada (pelo link); a melhor opção ganha um fundo verde
					local rarity = CandRarity(u.c)
					if k == 1 and not u.showcase then cv:Box(ux + 3, cy + 77, 40, 40, 0.3, 1, 0.3, 0.35) end
					if u.showcase then cv:Box(ux + 3, cy + 77, 40, 40, 0.64, 0.21, 0.93, 0.30) end
					-- ferramenta: sigla do atributo a escolher na fabricação no canto do ícone
					local badge = u.r.statChoice and u.r.statChoice:sub(1, 3):upper() or nil
					cv:Icon(ux + 6, cy + 80, 34, V.ItemIcon(u.c.itemID), {
						rarity = rarity, quality = ns.QIcon(5, 5, 12), link = u.c.outLink, tip = CandTip(u.c, u.r),
						count = badge })
					if u.showcase then
						local gain = u.r.gain or 0
						local gtxt = u.r.unknown and L["|cff9d9d9dsem atributos ainda|r"]
							or (gain > 0.5 and ("|cff55ff55+" .. G(gain) .. L["/sem|r"]))
							or (gain < -0.5 and ("|cffff5555" .. G(gain) .. L["/sem|r"]))
							or L["|cff9d9d9dmesmo lucro|r"]
						if not anyReal then
							-- sozinha: nome da peça e a diferença contra a equipada
							local nm = C_Item.GetItemNameByID(u.c.itemID) or u.c.name or "?"
							cv:Text(ux + 48, cy + 82, "|cffa335ee" .. nm .. "|r", GameFontHighlightSmall, colW - 70)
							cv:Text(ux + 48, cy + 98, gtxt .. L[" |cff9d9d9dvs. a equipada|r"], GameFontHighlightSmall, colW - 70)
							if u.r.stats then
								cv:Text(ux + 48, cy + 114, "|cff9d9d9d" .. Invest._StatStr(u.r.stats) .. "|r", GameFontDisableSmall, colW - 70)
							end
							ux = cx + colW   -- ocupa a linha
						else
							cv:Text(ux - 6, cy + 116, gtxt, GameFontHighlightSmall, 60, "CENTER")
							cv:Text(ux, cy + 130, "|cffa335ee" .. L["épica"] .. "|r", GameFontDisableSmall, 48, "CENTER")
						end
					else
						cv:Text(ux, cy + 116, "|cff55ff55+" .. G(u.r.gain) .. "|r", GameFontHighlightSmall, 48, "CENTER")
						cv:Text(ux, cy + 130, PayColor(u.r.payback) .. (Weeks(u.r.payback) or L["sem preço"]) .. "|r", GameFontDisableSmall, 48, "CENTER")
					end
					ux = ux + 50
				end
			end
			colH = 156
		end
		y = y + colH

		-- encantamento da ferramenta
		local tool = (inv.gear or {})[1]
		if tool and tool.link then
			local EI = Invest._ENCHANT_ITEM
			local cur = inv.toolEnchant and EI[inv.toolEnchant]
			cv:Text(8, y + 12, L["Encantamento da ferramenta:"], GameFontNormalSmall)
			cv:Icon(170, y + 2, 32, cur and V.ItemIcon(cur[1]) or 136244, {
				quality = cur and ns.QIcon(cur[2], 2, 12) or nil, desaturate = not cur, border = cur and { 0.6, 0.6, 0.6 } or { 1, 0.3, 0.3 },
				tip = function(tt)
					if cur then tt:SetItemByID(cur[1]) else tt:SetText(L["Sem encantamento"]) end
				end })
			local ex = 214
			local ups = inv.enchants or {}
			if #ups == 0 then
				cv:Text(ex, y + 12, L["|cff9d9d9djá é o melhor para as suas receitas|r"])
			else
				cv:Text(ex, y + 12, ">", GameFontNormal)
				ex = ex + 16
				for _, u in ipairs(ups) do
					cv:Icon(ex, y + 2, 32, V.ItemIcon(u.opt.itemID), {
						quality = ns.QIcon(2, 2, 12), link = select(2, C_Item.GetItemInfo(u.opt.itemID)),
						tip = function(tt)
							tt:SetItemByID(u.opt.itemID)
							tt:AddLine(" ")
							Line(tt, L["Ganho por semana"], P.FormatMoney(u.gain), { 0.3, 1, 0.3 })
							Line(tt, L["Recupera em"], u.payback and string.format(L["%.1f semanas"], u.payback) or L["sem preço"])
							Line(tt, L["Pergaminho"], u.price and P.FormatMoney(u.price) or "—")
						end })
					cv:Text(ex + 36, y + 4, "|cff55ff55+" .. G(u.gain) .. L["/sem|r"])
					cv:Text(ex + 36, y + 18, PayColor(u.payback) .. (Weeks(u.payback) or L["sem preço"]) .. "|r", GameFontDisableSmall)
					ex = ex + 120
				end
			end
			y = y + 42
		end

		-- ===== valor de cada atributo =====
		y = Section(cv, y, W, L["Quanto vale por semana"], L["mais 1 ponto de cada coisa, gastando a concentração da semana"])
		local v = inv.values or {}
		local stats = {
			{ L["+10 de perícia"], v.skill10 },
			{ "+1% " .. ns.STAT.multicraft, v.mc1 },
			{ "+1% " .. ns.STAT.resourcefulness, v.res1 },
			{ "+1% " .. ns.STAT.ingenuity, v.ing1 },
		}
		local maxV = 1
		for _, s in ipairs(stats) do if (s[2] or 0) > maxV then maxV = s[2] end end
		local half = math.floor((W - 8) / 2)
		for k, s in ipairs(stats) do
			local sx = 8 + ((k - 1) % 2) * half
			local sy = y + math.floor((k - 1) / 2) * 20
			cv:Text(sx, sy + 1, s[1], GameFontHighlightSmall, 140)
			cv:Bar(sx + 144, sy, half - 230, 13, math.max(s[2] or 0, 0), maxV, { 0.3, 0.85, 0.3 }, "")
			cv:Text(sx + half - 82, sy + 1, G(s[2] or 0, true), GameFontHighlightSmall, 70, "RIGHT")
		end
		y = y + 46

	end

	-- ===================== 2. Buffs temporários =====================
	y, col = Group(cv, y, W, "buffs", L["Buffs temporários"], bestBuff and ((bestBuff > 0 and "|cff55ff55+" or "|cffff5555") .. G(bestBuff) .. L["|r por uso (melhor)"])
		or L["|cff9d9d9dsem buffs para esta profissão|r"])
	if not col then
		-- ===== buffs temporários =====
		local bf = inv.buffs or {}
		if #bf > 0 then
			y = Section(cv, y, W, L["Buffs temporários"], L["frasco usado numa sessão de concentração (até uma barra cheia)"])
			local bx = 8
			for _, b in ipairs(bf) do
				local good = b.net and b.net > 0
				cv:Icon(bx, y, 34, V.ItemIcon(b.itemID), {
					quality = ns.QIcon(b.quality, 2, 12), link = select(2, C_Item.GetItemInfo(b.itemID)),
					border = good and { 0.3, 1, 0.3 } or { 0.6, 0.6, 0.6 }, desaturate = (b.net ~= nil and not good),
					tip = function(tt)
						tt:SetItemByID(b.itemID)
						tt:AddLine(" ")
						Line(tt, L["Ganho por uso"], P.FormatMoney(b.gain), { 0.3, 1, 0.3 })
						Line(tt, L["Preço"], b.price and P.FormatMoney(b.price) or L["sem preço"])
						if b.net then Line(tt, L["Saldo por uso"], P.FormatMoney(b.net), good and { 0.3, 1, 0.3 } or { 1, 0.4, 0.4 }) end
						Line(tt, L["Se usar a semana toda"], P.FormatMoney(b.weekly), GREY)
						tt:AddLine(string.format(L["Dura %d min: use só na hora de gastar concentração."], b.minutes or 30), 0.6, 0.6, 0.6, true)
					end })
				local txt = b.net and ((good and "|cff55ff55+" or "|cffff5555") .. G(b.net) .. "|r") or ("|cff9d9d9d+" .. G(b.gain) .. "|r")
				cv:Text(bx + 40, y + 4, txt, GameFontHighlightSmall, 110)
				cv:Text(bx + 40, y + 18, "|cff9d9d9d" .. (b.price and G(b.price) or L["sem preço"]) .. "|r", GameFontDisableSmall, 110)
				bx = bx + 160
			end
			cv:Text(bx + 10, y + 10, L["|cff9d9d9dNão existe buff de perícia nem comida para fabricação (os chás da Culinária só ajudam coleta).|r"], GameFontDisableSmall, W - bx - 20)
			y = y + 42
		end
	end

	-- ===================== 3. Conhecimento =====================
	local know = e.knowledge and e.knowledge > 0 and string.format(L["|cffffd100%d pontos para gastar|r  "], e.knowledge) or ""
	y, col = Group(cv, y, W, "know", L["Conhecimento e perícia"], know .. (bestPt and string.format(L["melhor ponto: |cff55ff55%s/pt|r"], G(bestPt)) or ""))
	if not col then
		-- ===== especialização =====
		local spec = inv.spec
		if spec and spec.tabs and #spec.tabs > 0 then
			y = Section(cv, y, W, L["Especialização"], spec.hasCraftSim and L["barra = pontos no orbe · marcas = dentes · valor até o próximo dente"]
				or L["sem dados do CraftSim: só a árvore, sem valor em ouro"])
			-- melhor ouro por ponto entre os próximos dentes
			local bestPer, bestNode = 0, nil
			for _, tab in ipairs(spec.tabs) do
				for _, node in ipairs(tab.nodes) do
					local t = NextTooth(node)
					if t and t.perPoint and t.perPoint > bestPer and not node.locked and node.nRecipes > 0
						and (t.gain or 0) >= MIN_GAIN then
						bestPer, bestNode = t.perPoint, node
					end
				end
			end
			local any = false
			for _, tab in ipairs(spec.tabs) do
				-- nós com ganho (ou receita nova) aparecem com barra; o resto vira uma linha só
				local visible, idle = {}, {}
				for _, node in ipairs(tab.nodes) do
					if NextTooth(node) or node.remaining then
						if NodeWorth(node) then table.insert(visible, node) else table.insert(idle, node) end
					end
				end
				if #visible > 0 or #idle > 0 then
					any = true
					cv:Text(8, y, "|cffffd100" .. tab.name .. "|r", GameFontNormalSmall)
					if #idle > 0 then
						local names = {}
						for _, n in ipairs(idle) do table.insert(names, n.name) end
						cv:Bar(240, y, 170, 13, 0, 1, { 0.4, 0.4, 0.4 }, string.format(L["%d sem ganho"], #idle), nil, function(tt)
							tt:SetText(tab.name)
							tt:AddLine(L["Sem ganho de lucro hoje (bloqueados, não afetam suas receitas ou ganho menor que 1 de ouro):"], 1, 1, 1, true)
							for _, n in ipairs(idle) do
								local st = n.locked and L["bloqueado"] or (n.rank >= 0 and string.format("%d/%d", n.rank, n.max or 0) or "")
								tt:AddDoubleLine("   " .. n.name, st, 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
							end
						end)
						cv:Text(418, y + 1, "|cff9d9d9d" .. table.concat(names, ", ") .. "|r", GameFontDisableSmall, W - 424)
					end
					y = y + 18
					for _, node in ipairs(visible) do
						local indent = math.min(node.depth or 0, 4) * 10
						local useful = node.nRecipes > 0 or node.cdPerks
						local nameCol = node.locked and "|cff808080" or useful and "|cffffffff" or "|cff9d9d9d"
						cv:Text(16 + indent, y + 1, nameCol .. node.name .. "|r", GameFontHighlightSmall, 220 - indent)
						local maxR = math.max(node.max or 0, 1)
						local ticks = {}
						for _, t in ipairs(node.teeth or {}) do
							if not t.final and t.threshold and t.threshold > 0 then
								table.insert(ticks, { f = t.threshold / maxR, r = t.earned and 0.3 or 1, g = t.earned and 1 or 0.82, b = t.earned and 0.3 or 0 })
							end
						end
						local rank = math.max(node.rank or 0, 0)
						cv:Bar(240, y, 170, 13, rank, maxR, node.locked and { 0.4, 0.4, 0.4 } or { 0.55, 0.35, 0.9 },
							node.rank < 0 and L["bloqueado"] or string.format("%d/%d", node.rank, node.max or 0), ticks, function(tt)
								tt:SetText(node.name)
								tt:AddLine(string.format(L["Afeta %d receita(s) suas"], node.nRecipes), 1, 1, 1)
								if node.perRank then tt:AddLine(L["Por ponto: "] .. Invest._StatsText(node.perRank), 0.8, 0.8, 0.8, true) end
								for _, t in ipairs(node.teeth or {}) do
									if not t.earned then
										local what = t.final and L["até o máximo"]
											or (t.cd and t.cd.text)
											or (t.stats and Invest._StatsText(t.stats)) or (t.desc and t.desc:sub(1, 60)) or "?"
										local val = t.gain and P.FormatMoney(t.gain) or (t.desc and not t.stats and L["receita nova"]) or "—"
										tt:AddDoubleLine(string.format(L["rank %d (+%d): %s"], t.threshold, t.points or (t.threshold - node.rank), what), val,
											1, 0.82, 0, 1, 1, 1)
									end
								end
							end)
						local t = NextTooth(node)
						local txt
						if node.locked then
							txt = L["|cff808080bloqueado|r"]
						elseif not useful then
							txt = L["|cff9d9d9dnão afeta suas receitas|r"]
						elseif t and t.gain and t.gain >= 1 then
							txt = string.format(L["|cff55ff55+%s/sem|r em %d pts |cff9d9d9d(%s/pt)|r"], G(t.gain), t.points or 0, G(t.perPoint or 0))
						elseif NextCharge(node) then
							local tc = NextCharge(node)
							txt = string.format(L["|cffffd100%s|r em %d pts"], ChargeLabel(tc.cd), tc.threshold - math.max(node.rank, 0))
						elseif t and t.desc and not t.stats then
							txt = L["|cff66ccfflibera receita nova|r"]
						else
							txt = L["|cff9d9d9dsem ganho hoje|r"]
						end
						if node == bestNode then txt = txt .. L["  |cffffd100< melhor ponto|r"] end
						cv:Text(418, y + 1, txt, GameFontHighlightSmall, W - 424)
						y = y + 18
					end
					y = y + 4
				end
			end
			if not any then
				cv:Text(8, y, L["|cff55ff55Especialização completa nesta profissão.|r"])
				y = y + 18
			end
			y = y + 6
		end

		-- ===== cargas e recarga (transmutações e outras receitas com recarga) =====
		local cps = Invest.ChargePerks and Invest.ChargePerks(e) or {}
		if #cps > 0 then
			y = Section(cv, y, W, L["Cargas e recarga"], L["pontos que dão mais cargas ou recarga mais rápida · do mais barato ao mais caro"])
			for i, c in ipairs(cps) do
				if i > 8 then break end
				root.Zebra(cv, i, 0, y - 2, W, 18)
				local val, best = Invest.ChargeValue(e, c.target)
				cv:Text(16, y + 1, "|cffffd100" .. ChargeLabel(c) .. "|r", GameFontHighlightSmall, 300)
				cv:Text(320, y + 1, (c.locked and "|cff808080" or "|cffffffff") .. c.node .. "|r |cff9d9d9d(" .. c.tab .. ")|r", GameFontHighlightSmall, 260)
				cv:Text(590, y + 1, string.format(L["%d pts"], c.points), GameFontHighlightSmall, 60, "RIGHT")
				local vtxt
				if best then
					vtxt = val > 0 and string.format(L["1 carga = |cff55ff55%s|r (%s)"], G(val), best.name or "?")
						or string.format(L["|cffff55551 carga dá prejuízo hoje|r (%s)"], best.name or "?")
				else vtxt = "|cff9d9d9d—|r" end
				cv:Text(660, y + 1, vtxt, GameFontHighlightSmall, W - 666)
				y = y + 18
			end
			cv:Text(8, y + 2, L["|cff9d9d9dCarga a mais = mais acumulado (sem perder dias sem jogar). Recarga mais rápida = mais por dia. O jogo não informa quanto mais rápido.|r"], GameFontDisableSmall, W - 16)
			y = y + 22
		end

		-- ===== perícia =====
		y = Section(cv, y, W, L["Perícia"], L["degraus alcançáveis: melhor equipamento, depois os pontos de conhecimento que faltam"])
		local ladder = inv.ladder or {}
		if #ladder == 0 then
			cv:Text(8, y, inv.ladderNoSpec and L["|cff9d9d9dSem troca de equipamento que dê mais perícia, e sem dados do CraftSim para a árvore.|r"]
				or L["|cff55ff55Perícia no máximo: equipamento e especialização completos.|r"], GameFontHighlightSmall, W - 16)
			y = y + 20
		else
			local maxL = 1
			for _, l in ipairs(ladder) do if (l.gain or 0) > maxL then maxL = l.gain end end
			local lw = math.floor((W - 16) / math.max(#ladder, 1))
			for k, l in ipairs(ladder) do
				local lx = 8 + (k - 1) * lw
				local h = math.floor(50 * math.max(l.gain or 0, 0) / maxL)
				local last = (k == #ladder)
				local r, g, b = 0.3, 0.85, 0.3
				if l.label == "gear" then r, g, b = 0.4, 0.75, 1 elseif last then r, g, b = 0.83, 0.69, 0.22 end
				cv:Box(lx + 10, y + 56 - h, lw - 20, math.max(h, 1), r, g, b, 0.85)
				cv:Text(lx, y + 60, Invest.LadderLabel(l), GameFontNormalSmall, lw, "CENTER")
				local sub = "+" .. l.skill
				if (l.points or 0) > 0 then sub = sub .. string.format(L[" · %d pts"], l.points) end
				cv:Text(lx, y + 74, sub, GameFontHighlightSmall, lw, "CENTER")
				cv:Text(lx, y + 88, G(l.gain or 0, true), GameFontDisableSmall, lw, "CENTER")
				cv:Hit(lx + 4, y, lw - 8, 100, nil, function(tt)
					tt:SetText(Invest.LadderLabel(l))
					Line(tt, L["Perícia do equipamento"], "+" .. math.floor((l.gearSkill or 0) + 0.5), { 0.4, 0.75, 1 })
					if (l.points or 0) > 0 then
						Line(tt, L["Pontos de conhecimento"], string.format("%d / %d", l.points, inv.ptsLeft or l.points))
					end
					Line(tt, L["Maior perícia numa receita"], "+" .. l.skill)
					Line(tt, L["Ganho por semana"], P.FormatMoney(l.gain or 0), { 0.3, 1, 0.3 })
					if l.top then Line(tt, L["Concentração vai para"], l.top) end
					if (l.nNatural or 0) > 0 then Line(tt, L["Receitas que saem sem conc."], tostring(l.nNatural)) end
					tt:AddLine(" ")
					tt:AddLine(L["Cada receita ganha só a perícia dos nós da árvore que a afetam; o equipamento vale para todas."], 0.6, 0.6, 0.6, true)
				end)
			end
			y = y + 106
			if inv.ladderNoSpec then
				cv:Text(8, y - 4, L["|cff9d9d9dSem dados do CraftSim: só o degrau do equipamento.|r"], GameFontDisableSmall, W - 16)
				y = y + 14
			end
		end
		local ms = inv.milestones or {}
		local function RowOf(name)
			for _, r in ipairs(e.rows or {}) do if r.name == name then return r end end
		end
		local function MsTip(m, row)
			return function(tt)
				if row and row.concItemID then tt:SetItemByID(row.concItemID) else tt:SetText(m.name) end
				tt:AddLine(" ")
				Line(tt, L["Perícia que falta"], "+" .. m.need)
				if (m.needTop or m.need) < m.need then
					Line(tt, string.format(L["Com reagentes %s"], ns.QIcon(2)), "+" .. m.needTop, { 0.4, 0.8, 1 })
				end
				if m.room then
					Line(tt, L["Perícia que ainda dá para ganhar"], "+" .. math.floor(m.room + 0.5),
						(m.needTop or m.need) > m.room and { 1, 0.4, 0.4 } or { 0.3, 1, 0.3 })
				end
				Line(tt, L["Ganho por fabricação"], P.FormatMoney(m.gain), { 0.3, 1, 0.3 })
				Line(tt, L["Concentração que custa hoje"], tostring(m.conc or 0))
				Line(tt, L["Vendas/dia"], m.spd and root.Num(m.spd, 0) or "?")
				if m.path and #m.path > 0 then
					tt:AddLine(" ")
					tt:AddLine(L["Como chegar:"], 1, 0.82, 0)
					for _, o in ipairs(m.path) do
						if o.kind == "gear" then
							tt:AddDoubleLine("   " .. (o.name or "?") .. (o.price and ("  |cff9d9d9d" .. P.FormatMoney(o.price) .. "|r") or ""),
								"+" .. math.floor(o.skill + 0.5), 0.4, 0.8, 1, 0.3, 1, 0.3)
						else
							local extra = o.locked and L[" |cff808080(bloqueado)|r"] or (o.points and o.points > 0 and string.format(L[" |cff9d9d9d(%d pts)|r"], o.points) or "")
							tt:AddDoubleLine("   " .. (o.name or "?") .. extra, "+" .. math.floor(o.skill + 0.5), 0.8, 0.6, 1, 0.3, 1, 0.3)
						end
					end
				elseif not m.room then
					tt:AddLine(L["Sem dados do CraftSim: não dá para dizer de onde vem a perícia."], 0.6, 0.6, 0.6, true)
				end
			end
		end
		if #ms > 0 then
			cv:Text(8, y, string.format(L["Próximos marcos: perícia que falta para sair %s sem concentração"], ns.QIcon(2)), GameFontNormalSmall)
			y = y + 16
			local mx = 8
			for _, m in ipairs(ms) do
				if mx + 56 > W then break end
				local row = RowOf(m.name)
				local withTop = (m.needTop or m.need) < m.need
				cv:Icon(mx + 8, y, 34, row and V.ItemIcon(row.concItemID, row.icon) or 134400, {
					count = "+" .. (m.needTop or m.need), quality = ns.QIcon(2, 2, 12),
					border = withTop and { 0.4, 0.8, 1 } or nil, tip = MsTip(m, row) })
				cv:Text(mx, y + 36, "|cff55ff55+" .. G(m.gain) .. "|r", GameFontHighlightSmall, 50, "CENTER")
				mx = mx + 56
			end
			y = y + 54
		end
	end

	cv:Text(8, y, string.format(L["|cff9d9d9dCusto de concentração por perícia: %s. Peças avaliadas na melhor versão fabricável; encantamento à parte.|r"],
		(i.method == "CraftSim") and L["curva do CraftSim"] or L["aproximação linear"]), GameFontDisableSmall, W - 16)
	y = y + 24
	if ns.SecondProf then y = ns.SecondProf.Draw(cv, y, W) end
	cv:End(y)
end


-- buffs de coleta: mudou a bolsa (usou/comprou), o buff entrou/saiu ou acabou o combate → redesenha a aba
do
	local f, pend = CreateFrame("Frame"), false
	f:RegisterEvent("BAG_UPDATE_DELAYED")
	f:RegisterEvent("UNIT_AURA")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function(_, ev, unit)
		if root.AnySecret(unit) then return end
		if ev == "UNIT_AURA" and unit ~= "player" then return end
		local fr = LucroCraftFrame
		if pend or not (fr and fr:IsShown() and ns.UI and fr.currentTab == ns.UI.TAB.INVEST) then return end
		local e = Invest._CurrentEntry and Invest._CurrentEntry()
		if not (e and e.invest and e.invest.gathering) then return end
		pend = true
		C_Timer.After(0.5, function()
			pend = false
			if not (InCombatLockdown and InCombatLockdown()) then Invest.Refresh() end
		end)
	end)
end
