local ADDON, root = ...
root.Livro = root.Livro or {}
local ns = root.Livro
ns.root = root
local L = ns.L

-- Painel contábil no formato de demonstrações financeiras:
-- Painel (indicadores) · DRE · Fluxo de caixa (com conciliação) · Centros de resultado · Diário · Vendas
local UI = {}
ns.UI = UI

local P = ns.P
local Ledger = ns.Ledger

local TABS = { L["Painel"], L["DRE"], L["Fluxo de caixa"], L["Centros de resultado"], L["Diário"], L["Vendas"] }
local T_PANEL, T_DRE, T_CASH, T_CENTERS, T_JOURNAL, T_SALES = 1, 2, 3, 4, 5, 6
local PERIODS = { { L["Esta sessão"], "session" }, { L["Hoje"], 1 }, { L["7 dias"], 7 }, { L["30 dias"], 30 }, { L["Tudo"], nil } }

-- paleta sóbria (relatório financeiro)
local COL = {
	-- paleta Royal Revenue (Pomerânia): azul-noite, azul pomerano, vermelho do grifo, prata e ouro
	band = { 0.08, 0.13, 0.24, 0.95 }, head = "|cffd4af37", muted = "|cff8a919c", rule = { 0.83, 0.69, 0.22, 0.45 },
	alt = { 0.17, 0.36, 0.66, 0.10 }, hi = "|cffe6e9ee", gold = "|cffd4af37", card = { 0.08, 0.13, 0.24, 0.92 },
	pos = { 0.50, 0.82, 0.55 }, neg = { 0.88, 0.48, 0.48 },
}

local frame, cv
local state = { tab = T_PANEL, period = 3, char = nil, sortKey = "profit", desc = true }

local function ClassName(char, class)
	local name = char:match("^([^-]+)") or char
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) end
	return name
end

local function Hours(sec)
	if not sec or sec <= 0 then return COL.muted .. "—|r" end
	local h = sec / 3600
	if h < 1 then return string.format("%d min", math.floor(sec / 60 + 0.5)) end
	return string.format("%.1f h", h)
end

-- ===== blocos visuais =====
local function Band(y, W, title, right)
	cv:Box(0, y, W, 20, unpack(COL.band))
	cv:Box(0, y + 19, W, 1, 0.85, 0.7, 0.35, 0.5)
	local keep = {}
	local up = title:gsub("|T.-|t", function(t) table.insert(keep, t) return "\001" end):upper()
	up = up:gsub("\001", function() return table.remove(keep, 1) end)
	cv:Text(8, y + 4, COL.head .. up .. "|r", GameFontNormalSmall)
	if right then cv:Text(W - 408, y + 4, COL.muted .. right .. "|r", GameFontDisableSmall, 400, "RIGHT") end
	return y + 26
end

local function Rule(y, x, w, double)
	cv:Box(x, y, w, 1, unpack(COL.rule))
	if double then cv:Box(x, y + 2, w, 1, unpack(COL.rule)) end
end

-- linha de demonstração: rótulo à esquerda + colunas numéricas alinhadas à direita
-- cols = { {x, w}, ... } ; vals = textos já formatados
-- linhas alternadas (zebra), como nas outras telas do addon; recomeça a cada desenho (y voltou para cima)
local zebra, zebraY = 0, 0
local function StmtRow(y, W, cols, label, vals, o)
	o = o or {}
	local h = o.h or 18
	if y < zebraY then zebra = 0 end
	zebraY = y
	if label ~= "" and not o.noZebra and o.alt == nil then
		zebra = zebra + 1
		if o.bold or o.grand then
			cv:Box(0, y - 2, W, h, 0.83, 0.69, 0.22, 0.10)          -- grupo principal: faixa dourada
		elseif (o.indent or 0) <= 1 and o.code then
			cv:Box(0, y - 2, W, h, 0.17, 0.36, 0.66, 0.22)          -- subgrupo: faixa azul
		elseif zebra % 2 == 0 then
			cv:Box(0, y - 2, W, h, unpack(COL.alt))                 -- detalhe: zebra
		end
	end
	if o.alt then cv:Box(0, y - 2, W, h, unpack(COL.alt)) end
	if o.total then Rule(y - 3, cols[1][1] - 20, W - cols[1][1] + 16, false) end
	if o.grand then Rule(y - 4, cols[1][1] - 20, W - cols[1][1] + 16, true) end
	local font = (o.bold or o.total or o.grand) and GameFontHighlight or GameFontHighlightSmall
	local lx = 10 + (o.indent or 0) * 16
	if o.code then
		cv:Text(lx, y, COL.muted .. o.code .. "|r", GameFontDisableSmall, 50)
		lx = lx + 50
	end
	cv:Text(lx, y, (o.bold or o.total or o.grand) and (COL.hi .. label .. "|r") or label, font, cols[1][1] - lx - 10)
	for i, c in ipairs(cols) do
		if vals[i] then cv:Text(c[1], y, vals[i], font, c[2], "RIGHT") end
	end
	if o.tip then cv:Button(0, y - 2, W, h, nil, o.tip) end
	return y + h
end

local function Card(x, y, w, h, title, value, sub)
	cv:Box(x, y, w, h, unpack(COL.card))
	cv:Box(x, y, 3, h, 0.85, 0.7, 0.35, 0.8)
	cv:Text(x + 12, y + 8, COL.muted .. title:upper() .. "|r", GameFontDisableSmall, w - 20)
	cv:Text(x + 12, y + 24, value, GameFontNormalLarge, w - 20)
	if sub then cv:Text(x + 12, y + h - 18, sub, GameFontDisableSmall, w - 20) end
end

-- moedas: nome e ícone pelo jogo
local function CurName(id)
	local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
	local name = info and info.name or (L["moeda"] .. " " .. id)
	local icon = info and info.iconFileID
	return name, icon
end

local function CurLines(tt, cur, title)
	local list = {}
	for id, q in pairs(cur or {}) do table.insert(list, { id = id, q = q }) end
	if #list == 0 then return end
	table.sort(list, function(a, b) return a.q > b.q end)
	tt:AddLine(" ")
	tt:AddLine(title or L["Moedas recebidas"], 0.85, 0.7, 0.35)
	for _, it in ipairs(list) do
		local name, icon = CurName(it.id)
		tt:AddDoubleLine((icon and ("|T" .. icon .. ":14|t ") or "") .. name, tostring(it.q), 1, 1, 1, 1, 1, 1)
	end
end

local function CurShort(cur)
	local parts = {}
	for id, q in pairs(cur or {}) do
		local _, icon = CurName(id)
		table.insert(parts, (icon and ("|T" .. icon .. ":12|t") or "") .. q)
	end
	return table.concat(parts, " ")
end

local function ItemName(id)
	return C_Item.GetItemNameByID(id) or ("item " .. id)
end

-- ===== dados do período =====
local function Period() return PERIODS[state.period][2] end

-- Collect + Merge + DRE do período: guardado enquanto nada mudou no livro (Ledger.rev) e por no máx. 10 s
-- (o Painel e as demonstrações pedem o período atual e o anterior a cada desenho)
local loadCache = {}
local function Load(shift)
	local key = tostring(Period()) .. "|" .. tostring(state.char) .. "|" .. tostring(shift)
	local c = loadCache[key]
	local now = GetTime()
	if c and c.rev == Ledger.rev and now - c.t < 10 then return c.data, c.m, c.d end
	local data = Ledger.Collect(Period(), state.char, shift)
	local m = Ledger.Merge(data)
	local d = Ledger.DRE(m)
	loadCache[key] = { rev = Ledger.rev, t = now, data = data, m = m, d = d }
	return data, m, d
end
function UI.ClearCache() wipe(loadCache) end

local function Prev()
	if not Period() or Period() == "session" then return nil end
	local _, m, d = Load(Period())
	return m, d
end

local function TotalTime(m)
	local s = 0
	for _, v in pairs(m.time) do s = s + v end
	return s
end

-- AH% (análise horizontal) e AV% (análise vertical)
local function AH(cur, prev)
	if not prev or prev == 0 then return nil end
	return (cur - prev) / math.abs(prev)
end

-- ===== Painel =====
local function RenderPanel(W)
	local data, m, d = Load()
	local pm, pd = Prev()
	local secs = TotalTime(m)
	local y = 6
	local cw = math.floor((W - 30) / 4)
	local function cx(i) return (i - 1) * (cw + 10) end
	local ahRes = pd and AH(d.result, pd.result)
	Card(cx(1), y, cw, 64, L["Resultado do período"], P.Acct(d.result, true),
		pd and (L["vs. período anterior"] .. " " .. P.Pct(ahRes, true)) or nil)
	Card(cx(2), y, cw, 64, L["Receita bruta"], P.Acct(d.gross), pd and (L["anterior"] .. " " .. P.Acct(pd.gross)) or nil)
	Card(cx(3), y, cw, 64, L["Despesas operacionais"], P.Acct(-d.out), pd and (L["anterior"] .. " " .. P.Acct(-pd.out)) or nil)
	Card(cx(4), y, cw, 64, L["Margem operacional"], P.Pct(d.margin), COL.muted .. L["resultado ÷ receita bruta"] .. "|r")
	y = y + 74
	local cash, cashKnown = 0, false
	for _, t in ipairs(data.chars) do
		if t.cashClose then cash, cashKnown = cash + t.cashClose, true end
	end
	local diff = m.hasCash and (m.cashClose - (m.cashOpen + (d.actGold + d.comm + d.itemsale - d.cashOut) + (m.xin - m.xout) + m.adj)) or nil
	Card(cx(1), y, cw, 64, L["Ouro por hora"], secs > 0 and P.Acct(d.result / (secs / 3600), true) or COL.muted .. "—|r", COL.muted .. L["resultado ÷ horas ativas"] .. "|r")
	Card(cx(2), y, cw, 64, L["Horas ativas"], Hours(secs), COL.muted .. L["fora de AFK"] .. "|r")
	Card(cx(3), y, cw, 64, L["Saldo em caixa"], cashKnown and P.Acct(cash) or COL.muted .. "—|r", COL.muted .. L["ouro no último registro"] .. "|r")
	local ok = diff and math.abs(diff) < 10000
	Card(cx(4), y, cw, 64, L["Conciliação de caixa"], diff == nil and (COL.muted .. "—|r") or ok and "|cff7fd18b" .. L["Conciliado"] .. "|r"
		or "|cffe0b04a" .. L["Diferença"] .. " " .. P.Acct(diff) .. "|r", COL.muted .. L["saldo calculado × saldo real"] .. "|r")
	y = y + 80

	-- resultado por personagem (centro de custo)
	y = Band(y, W, L["Resultado por personagem"], L["clique para filtrar"])
	local cols = { { W - 610, 100 }, { W - 500, 100 }, { W - 390, 100 }, { W - 280, 70 }, { W - 200, 80 }, { W - 110, 100 } }
	y = StmtRow(y, W, cols, COL.muted .. L["Personagem"] .. "|r", { COL.muted .. L["Receita"] .. "|r", COL.muted .. L["Despesas"] .. "|r",
		COL.muted .. L["Resultado"] .. "|r", COL.muted .. L["Margem"] .. "|r", COL.muted .. L["Horas"] .. "|r", COL.muted .. L["Ouro/h"] .. "|r" })
	local rows = {}
	local all = state.char and Ledger.Collect(Period(), nil) or data
	for _, t in ipairs(all.chars) do
		if t.any then
			local tm = Ledger.Merge({ chars = { t } })
			local td = Ledger.DRE(tm)
			table.insert(rows, { t = t, d = td, s = TotalTime(tm) })
		end
	end
	table.sort(rows, function(a, b) return a.d.result > b.d.result end)
	if #rows == 0 then
		cv:Text(10, y, COL.muted .. L["Nada registrado neste período."] .. "|r")
		return y + 30
	end
	for i, r in ipairs(rows) do
		local sel = state.char == r.t.char
		if sel then cv:Box(0, y - 2, W, 18, 0.85, 0.7, 0.35, 0.12) end
		y = StmtRow(y, W, cols, ClassName(r.t.char, r.t.class) .. COL.muted .. "  " .. (r.t.char:match("%-(.+)$") or "") .. "|r",
			{ P.Acct(r.d.gross), P.Acct(-r.d.out), P.Acct(r.d.result, true), P.Pct(r.d.margin), Hours(r.s),
				r.s > 0 and P.Acct(r.d.result / (r.s / 3600)) or COL.muted .. "—|r" }, { alt = i % 2 == 0 })
		cv:Button(0, y - 20, W, 18, function()
			state.char = (state.char == r.t.char) and nil or r.t.char
			UI.Refresh()
		end)
	end
	y = y + 10

	-- maiores centros de resultado
	y = Band(y, W, L["Principais centros de resultado"], L["receita do período"])
	local list, maxV = {}, 1
	for _, def in ipairs(Ledger.ACTS) do
		local a = m.act[def.key]
		if a then
			local v = a.gold + Ledger.ItemsValue(a.items)
			if v > 0 then table.insert(list, { def = def, v = v }); if v > maxV then maxV = v end end
		end
	end
	table.sort(list, function(a, b) return a.v > b.v end)
	for i, it in ipairs(list) do
		if i > 6 then break end
		cv:Icon(10, y, 18, it.def.icon)
		cv:Text(36, y + 3, it.def.name, GameFontHighlightSmall, 200)
		cv:Bar(240, y + 4, W - 380, 10, it.v, maxV, { 0.85, 0.7, 0.35 })
		cv:Text(W - 130, y + 3, P.Acct(it.v), GameFontHighlightSmall, 120, "RIGHT")
		y = y + 22
	end
	return y
end

-- ===== DRE =====
local function RenderDRE(W)
	local _, m, d = Load()
	local pm, pd = Prev()
	local y = Band(6, W, L["Demonstração do Resultado"], L["regime de competência · valores em ouro"])
	-- Ouro e Itens só nas receitas de atividades (uma linha por atividade, as duas formas lado a lado)
	local cols = { { W - 700, 100 }, { W - 590, 100 }, { W - 470, 110 }, { W - 350, 60 }, { W - 280, 110 }, { W - 160, 60 } }
	local hasPrev = pd ~= nil
	-- liga/desliga: contas de despesa abertas por centro de custo (atividade)
	local cfg = LucroLivroDB.config
	local centers = cfg.dreCenters and true or false
	cv:Box(10, y + 1, 12, 12, 0.83, 0.69, 0.22, centers and 1 or 0.18)
	cv:Text(28, y, (centers and "|cffffffff" or "|cff8f8f8f") .. L["Centros de custo nas contas"] .. "|r", GameFontHighlightSmall, 220)
	cv:Button(6, y - 2, 230, 18, function() cfg.dreCenters = not centers or nil; UI.Refresh() end, function(tt)
		tt:SetText(L["Centros de custo nas contas"])
		tt:AddLine(L["Liga/desliga: abre as contas por centro de custo logo abaixo de cada uma. CPV: pedidos por item encomendado e fabricação própria por profissão. Reparo: rateado pelo desgaste do equipamento em cada atividade (o que não tem origem fica em \"Sem origem\"). Consumíveis: atividade em que foram usados."], 1, 1, 1, true)
	end)
	y = StmtRow(y, W, cols, "", { COL.muted .. L["Ouro"] .. "|r", COL.muted .. L["Itens"] .. "|r", COL.muted .. L["Período"] .. "|r", COL.muted .. "AV %|r",
		COL.muted .. (hasPrev and L["Anterior"] or "") .. "|r", COL.muted .. (hasPrev and "AH %" or "") .. "|r" })
	local base = d.gross
	local function V(cur, prev, neg, gold, items)
		local c = neg and -cur or cur
		local p = prev and (neg and -prev or prev)
		return { gold and P.Acct(gold, nil, true) or nil, items and P.Acct(items, nil, true) or nil,
			P.Acct(c, nil, true), base > 0 and P.Pct(cur / base) or COL.muted .. "—|r",
			hasPrev and P.Acct(p, nil, true) or nil, hasPrev and P.Pct(AH(cur, prev), true) or nil }
	end
	local function actSum(mm, items)
		local out = {}
		for _, def in ipairs(Ledger.ACTS) do
			local a = mm and mm.act[def.key]
			out[def.key] = a and (items and Ledger.ItemsValue(a.items) or a.gold) or 0
		end
		return out
	end
	local cg, ci = actSum(m, false), actSum(m, true)
	local pg, pi = actSum(pm, false), actSum(pm, true)

	y = StmtRow(y, W, cols, L["RECEITA OPERACIONAL BRUTA"], V(d.gross, pd and pd.gross), { bold = true })
	-- 3.1 Receitas de atividades: ouro e itens (valor de mercado) em colunas
	local actTotal, pActTotal = d.actGold + d.actItems, pd and (pd.actGold + pd.actItems)
	y = StmtRow(y, W, cols, L["Receitas de atividades"], V(actTotal, pActTotal, false, d.actGold, d.actItems), { code = "3.1", indent = 1 })
	for _, def in ipairs(Ledger.ACTS) do
		local g, it = cg[def.key], ci[def.key]
		local pgv, piv = pg[def.key], pi[def.key]
		if g ~= 0 or it ~= 0 or pgv ~= 0 or piv ~= 0 then
			local a = m.act[def.key]
			y = StmtRow(y, W, cols, COL.muted .. def.name .. "|r", V(g + it, pm and (pgv + piv), false, g, it),
				{ code = Ledger.ActCode(def.key), indent = 2, h = 16, tip = (a and it ~= 0) and function(tt)
					tt:SetText(def.name)
					tt:AddDoubleLine(L["Ouro"], P.FormatMoney(g), 1, 0.82, 0, 1, 1, 1)
					tt:AddDoubleLine(L["Itens (valor de mercado)"], P.FormatMoney(it), 1, 0.82, 0, 1, 1, 1)
					tt:AddLine(" ")
					local list = {}
					for id, q in pairs(a.items) do
						if id ~= "sold" then local p = P.Value(id); table.insert(list, { id = id, q = q, v = p and p * q or 0 }) end
					end
					if a.items.sold then table.insert(list, { id = "sold", q = 0, v = a.items.sold }) end
					table.sort(list, function(x, z) return x.v > z.v end)
					for k, itx in ipairs(list) do
						if k > 12 then break end
						local label = itx.id == "sold" and L["Itens vendidos ao vendedor (valor pago)"] or string.format("%dx %s", itx.q, ItemName(itx.id))
						tt:AddDoubleLine(label, P.FormatMoney(itx.v), 1, 1, 1, 1, 1, 1)
					end
				end or nil })
		end
	end
	local ahGross = (m.inc.ahsale or 0) / 0.95
	local pahGross = pm and (pm.inc.ahsale or 0) / 0.95
	y = StmtRow(y, W, cols, L["Receitas comerciais"], V(d.comm + d.ahFee, pd and (pd.comm + pd.ahFee)), { code = "3.3", indent = 1 })
	for _, o in ipairs(Ledger.INC) do
		local cur = o.key == "ahsale" and ahGross or (m.inc[o.key] or 0)
		local prev = pm and (o.key == "ahsale" and pahGross or (pm.inc[o.key] or 0))
		if cur ~= 0 or (prev or 0) ~= 0 then
			y = StmtRow(y, W, cols, COL.muted .. o.name .. "|r", V(cur, prev), { code = Ledger.IncCode(o.key), indent = 2, h = 16 })
		end
	end
	-- 2. Deduções · 3. Receita líquida
	y = StmtRow(y + 2, W, cols, L["(-) DEDUÇÕES"], V(d.ahFee, pd and pd.ahFee, true), { bold = true })
	y = StmtRow(y, W, cols, COL.muted .. L["Comissão da casa de leilões (5%)"] .. "|r", V(d.ahFee, pd and pd.ahFee, true), { code = "3.4.01", indent = 1, h = 16 })
	y = StmtRow(y + 4, W, cols, L["(=) RECEITA OPERACIONAL LÍQUIDA"], V(d.net, pd and pd.net), { total = true })
	y = y + 6
	-- 4. CPV · 5. Lucro bruto
	y = StmtRow(y, W, cols, L["(-) CPV · CUSTO DOS PRODUTOS VENDIDOS"], V(d.cpv, pd and pd.cpv, true), { bold = true, tip = function(tt)
		tt:SetText(L["CPV"])
		tt:AddLine(L["Material gasto ao fabricar, comprado ou coletado, a valor de mercado. Material comprado vai para o estoque e só vira custo quando é usado. O que você mesmo fabricou (pigmento, couro tratado...) não conta de novo."], 1, 1, 1, true)
	end })
	local function centerRows(list, prevList, label)
		local rows = {}
		for k, v in pairs(list or {}) do if v > 0.5 then table.insert(rows, { k = k, v = v, p = prevList and prevList[k] }) end end
		table.sort(rows, function(x, z) return x.v > z.v end)
		for i, rr in ipairs(rows) do
			if i > 12 then break end
			y = StmtRow(y, W, cols, COL.muted .. "· " .. (label and label(rr.k) or rr.k) .. "|r", V(rr.v, pm and (rr.p or 0), true), { indent = 3, h = 15 })
		end
	end
	if d.cpvOrders ~= 0 or (pd and pd.cpvOrders ~= 0) then
		y = StmtRow(y, W, cols, COL.muted .. L["Material gasto em pedidos de fabricação"] .. "|r", V(d.cpvOrders, pd and pd.cpvOrders, true), { code = Ledger.CPV_ORDERS, indent = 2, h = 16 })
		if centers then centerRows(m.cpvOrd, pm and pm.cpvOrd) end
	end
	if d.cpvCraft ~= 0 or (pd and pd.cpvCraft ~= 0) then
		y = StmtRow(y, W, cols, COL.muted .. L["Material gasto na fabricação própria"] .. "|r", V(d.cpvCraft, pd and pd.cpvCraft, true), { code = Ledger.CPV_CRAFT, indent = 2, h = 16 })
		if centers then centerRows(m.cpvProf, pm and pm.cpvProf) end
	end
	if d.cpvLegacyMat ~= 0 or (pd and pd.cpvLegacyMat ~= 0) then
		y = StmtRow(y, W, cols, COL.muted .. L["Material comprado (antes do controle de consumo)"] .. "|r", V(d.cpvLegacyMat, pd and pd.cpvLegacyMat, true),
			{ code = "4.0.08", indent = 2, h = 16, tip = function(tt)
				tt:SetText(L["Registro antigo"])
				tt:AddLine(L["Até a troca para a v1.19 não havia registro do material gasto em cada craft: nesses dias o material comprado (AH e vendedor) conta como custo no dia da compra."], 1, 1, 1, true)
			end })
	end
	if d.cpvLegacyAH ~= 0 or (pd and pd.cpvLegacyAH ~= 0) then
		y = StmtRow(y, W, cols, COL.muted .. L["Compras e depósitos na AH (antes do controle de consumo)"] .. "|r", V(d.cpvLegacyAH, pd and pd.cpvLegacyAH, true),
			{ code = "4.0.09", indent = 2, h = 16, tip = function(tt)
				tt:SetText(L["Registro antigo"])
				tt:AddLine(L["Até a v1.19 a casa de leilões era um gasto só (compras + depósitos), lançado no dia da compra. Esses dias ficam assim no CPV; a partir da v1.19 o depósito vai para as despesas e a compra de material para o estoque."], 1, 1, 1, true)
			end })
	end
	y = StmtRow(y + 4, W, cols, L["(=) LUCRO BRUTO"], V(d.grossProfit, pd and pd.grossProfit), { total = true })
	y = StmtRow(y, W, cols, COL.muted .. L["Margem bruta"] .. "|r", { nil, nil, P.Pct(d.grossMargin), nil, hasPrev and P.Pct(pd.grossMargin) or nil, nil }, { indent = 1 })
	y = y + 6
	-- 6. Despesas operacionais
	y = StmtRow(y, W, cols, L["(-) DESPESAS OPERACIONAIS"], V(d.out, pd and pd.out, true), { bold = true })
	local function actName(k)
		for _, adef in ipairs(Ledger.ACTS) do if adef.key == k then return adef.name end end
		return k
	end
	for _, g in ipairs(Ledger.GROUPS) do
		local gv, pgv = d.groups[g.code] or 0, pd and pd.groups[g.code] or 0
		if gv ~= 0 or pgv ~= 0 then
			y = StmtRow(y, W, cols, g.name, V(gv, pd and pgv, true), { code = g.code, indent = 1 })
			-- consumíveis: centro de custo = atividade em que foram usados
			if g.consum and centers then
				local rows = {}
				for k, e in pairs(m.consumD or {}) do if e.v > 0.5 then table.insert(rows, { k = k, e = e }) end end
				table.sort(rows, function(x, z) return x.e.v > z.e.v end)
				for _, rr in ipairs(rows) do
					local pe = pm and pm.consumD and pm.consumD[rr.k]
					local subs = {}
					for sname, v in pairs(rr.e.sub) do table.insert(subs, { n = sname, v = v }) end
					table.sort(subs, function(x, z) return x.v > z.v end)
					y = StmtRow(y, W, cols, COL.muted .. "· " .. actName(rr.k) .. "|r", V(rr.e.v, pm and (pe and pe.v or 0), true),
						{ indent = 3, h = 15, tip = #subs > 0 and function(tt)
							tt:SetText(L["Consumíveis usados"] .. " · " .. actName(rr.k))
							for i2, sx in ipairs(subs) do
								if i2 > 15 then break end
								tt:AddDoubleLine(sx.n, "-" .. P.FormatMoney(sx.v), 1, 1, 1, 0.9, 0.5, 0.5)
							end
						end or nil })
				end
			end
			for _, k in ipairs(g.keys) do
				local cur, prev = m.out[k] or 0, pm and pm.out[k] or 0
				if cur ~= 0 or prev ~= 0 then
					local def
					for _, o in ipairs(Ledger.OUT) do if o.key == k then def = o end end
					y = StmtRow(y, W, cols, COL.muted .. (def and def.name or k) .. "|r", V(cur, pm and prev, true), { code = Ledger.OutCode(k), indent = 2, h = 16 })
					-- reparo: quanto coube a cada atividade (rateio pelo desgaste) + o que ficou sem origem
					if centers and k == "repair" and cur ~= 0 then
						local used = 0
						for _, adef in ipairs(Ledger.ACTS) do
							local a = m.act[adef.key]
							local pa = pm and pm.act[adef.key]
							local rv, prv = a and a.repair or 0, pa and pa.repair or 0
							if rv > 0.5 or prv > 0.5 then
								used = used + rv
								local subs = {}
								for sname, sx in pairs(a and a.sub or {}) do
									if (sx.repair or 0) > 0.5 then table.insert(subs, { n = sname, v = sx.repair }) end
								end
								table.sort(subs, function(x, z) return x.v > z.v end)
								y = StmtRow(y, W, cols, COL.muted .. "· " .. adef.name .. "|r", V(rv, pm and prv, true),
									{ indent = 3, h = 15, tip = #subs > 0 and function(tt)
										tt:SetText(L["Reparo"] .. " · " .. adef.name)
										for i2, sx in ipairs(subs) do
											if i2 > 15 then break end
											tt:AddDoubleLine(sx.n, "-" .. P.FormatMoney(sx.v), 1, 1, 1, 0.9, 0.5, 0.5)
										end
										tt:AddLine(" ")
										tt:AddLine(L["Rateio pelo desgaste do equipamento em cada atividade."], 0.6, 0.6, 0.6, true)
									end or nil })
							end
						end
						local rest = cur - used
						if rest > 0.5 then
							local prest
							if pm then
								local pu = 0
								for _, a in pairs(pm.act) do pu = pu + (a.repair or 0) end
								prest = (pm.out.repair or 0) - pu
							end
							y = StmtRow(y, W, cols, COL.muted .. "· " .. L["Sem origem"] .. "|r", V(rest, prest, true), { indent = 3, h = 15, tip = function(tt)
								tt:SetText(L["Reparo sem origem"])
								tt:AddLine(L["Desgaste de antes do registro ou reparo fora de instância sem medição."], 1, 1, 1, true)
							end })
						end
					end
				end
			end
		end
	end
	-- 7. EBIT · 8. Lucro líquido
	y = StmtRow(y + 6, W, cols, L["(=) RESULTADO OPERACIONAL (EBIT)"], V(d.result, pd and pd.result), { total = true })
	y = StmtRow(y, W, cols, COL.muted .. L["Margem operacional"] .. "|r", { nil, nil, P.Pct(d.margin), nil, hasPrev and P.Pct(pd.margin) or nil, nil }, { indent = 1 })
	y = StmtRow(y + 6, W, cols, L["(=) LUCRO OU PREJUÍZO LÍQUIDO DO EXERCÍCIO"], V(d.netIncome, pd and pd.netIncome), { grand = true, h = 22, tip = function(tt)
		tt:SetText(L["Lucro líquido"])
		tt:AddLine(L["No jogo não há resultado financeiro (juros) nem impostos sobre o lucro: o lucro líquido é igual ao resultado operacional."], 1, 1, 1, true)
	end })
	y = StmtRow(y, W, cols, COL.muted .. L["Margem líquida"] .. "|r", { nil, nil, P.Pct(d.netMargin), nil, hasPrev and P.Pct(pd.netMargin) or nil, nil }, { indent = 1 })
	y = y + 10
	y = Band(y, W, L["Movimentações não operacionais"], L["fora do resultado"])
	if d.stock ~= 0 or (pd and pd.stock ~= 0) then
		y = StmtRow(y, W, cols, L["Material comprado para o estoque"], { nil, nil, P.Acct(-d.stock, nil, true), nil, hasPrev and P.Acct(-pd.stock, nil, true) or nil }, { indent = 1, tip = function(tt)
			tt:SetText(L["Material comprado para o estoque"])
			tt:AddLine(L["Ouro que saiu do caixa para comprar material (AH e vendedor). Vira custo (CPV) quando é gasto num craft."], 1, 1, 1, true)
		end })
		for _, k in ipairs(Ledger.STOCK_KEYS) do
			local cur = m.out[k] or 0
			if cur ~= 0 then
				local def
				for _, o in ipairs(Ledger.OUT) do if o.key == k then def = o end end
				y = StmtRow(y, W, cols, COL.muted .. (def and def.name or k) .. "|r", { nil, nil, P.Acct(-cur, nil, true) }, { code = Ledger.OutCode(k), indent = 2, h = 16 })
			end
		end
	end
	y = StmtRow(y, W, cols, L["Transferências recebidas"], { nil, nil, P.Acct(m.xin, nil, true) }, { code = Ledger.XIN_CODE, indent = 1 })
	if m.adj ~= 0 then
		y = StmtRow(y, W, cols, L["Ajustes de conciliação (sessões não salvas)"], { nil, nil, P.Acct(m.adj, nil, true) }, { code = Ledger.ADJ_CODE, indent = 1 })
	end
	y = StmtRow(y, W, cols, L["Transferências enviadas"], { nil, nil, P.Acct(-m.xout, nil, true) }, { code = Ledger.XOUT_CODE, indent = 1 })
	y = y + 8
	cv:Text(10, y, COL.muted .. string.format(L["AV = análise vertical (%% da receita bruta) · AH = análise horizontal (variação sobre o período anterior). Itens avaliados ao preço de mercado atual (%s); vinculados ao preço do vendedor."], P.SourceName()) .. "|r",
		GameFontDisableSmall, W - 20)
	return y + 30
end

-- ===== Fluxo de caixa =====
local function RenderCash(W)
	local data, m, d = Load()
	local y = Band(6, W, L["Demonstração do Fluxo de Caixa"], L["regime de caixa · só ouro"])
	local cols = { { W - 200, 150 } }
	local opIn = d.actGold + d.comm + d.itemsale
	local opOut = d.cashOut
	local xnet = m.xin - m.xout + m.adj
	local var = opIn - opOut + xnet
	y = StmtRow(y, W, cols, L["Saldo inicial de caixa"], { m.hasCash and P.Acct(m.cashOpen) or COL.muted .. "—|r" }, { bold = true })
	y = y + 6
	y = StmtRow(y, W, cols, L["(+) Recebimentos operacionais"], { P.Acct(opIn, nil, true) }, { bold = true })
	y = StmtRow(y, W, cols, COL.muted .. L["Atividades (ouro recebido)"] .. "|r", { P.Acct(d.actGold, nil, true) }, { indent = 1, code = "3.1" })
	y = StmtRow(y, W, cols, COL.muted .. L["Receitas comerciais"] .. "|r", { P.Acct(d.comm, nil, true) }, { indent = 1, code = "3.3" })
	if d.itemsale ~= 0 then
		y = StmtRow(y, W, cols, COL.muted .. L["Itens das atividades vendidos ao vendedor"] .. "|r", { P.Acct(d.itemsale, nil, true) }, { indent = 1, code = "3.2" })
	end
	y = StmtRow(y, W, cols, L["(-) Pagamentos operacionais"], { P.Acct(-opOut, nil, true) }, { bold = true })
	-- só o que saiu em ouro (consumíveis usados não são pagamento: o pagamento foi a compra)
	for _, g in ipairs(Ledger.GROUPS) do
		if not g.consum then
			local gv = d.groups[g.code] or 0
			if gv ~= 0 then y = StmtRow(y, W, cols, COL.muted .. g.name .. "|r", { P.Acct(-gv) }, { indent = 1, code = g.code }) end
		end
	end
	if d.stock ~= 0 then y = StmtRow(y, W, cols, COL.muted .. L["Material comprado para o estoque"] .. "|r", { P.Acct(-d.stock) }, { indent = 1, code = "5.4" }) end
	if d.cpvLegacyAH ~= 0 then y = StmtRow(y, W, cols, COL.muted .. L["Casa de leilões (compras e depósitos)"] .. "|r", { P.Acct(-d.cpvLegacyAH) }, { indent = 1, code = "4.3.02" }) end
	y = StmtRow(y + 4, W, cols, L["(=) Caixa líquido das operações"], { P.Acct(opIn - opOut, true) }, { total = true })
	y = y + 6
	y = StmtRow(y, W, cols, L["(±) Movimentações não operacionais"], { P.Acct(xnet, nil, true) }, { bold = true })
	y = StmtRow(y, W, cols, COL.muted .. L["Transferências recebidas"] .. "|r", { P.Acct(m.xin, nil, true) }, { indent = 1, code = Ledger.XIN_CODE })
	if m.adj ~= 0 then
		y = StmtRow(y, W, cols, COL.muted .. L["Ajustes de conciliação (sessões não salvas)"] .. "|r", { P.Acct(m.adj, nil, true) }, { indent = 1, code = Ledger.ADJ_CODE,
			tip = function(tt)
				tt:SetText(L["Ajuste de conciliação"])
				tt:AddLine(L["Ao entrar no jogo, o ouro real não batia com o último saldo gravado: a sessão anterior fechou sem salvar (travamento, Gerenciador de Tarefas, queda de energia). A diferença foi lançada aqui para a conciliação fechar; o detalhe dessa sessão se perdeu."], 1, 1, 1, true)
			end })
	end
	y = StmtRow(y, W, cols, COL.muted .. L["Transferências enviadas"] .. "|r", { P.Acct(-m.xout, nil, true) }, { indent = 1, code = Ledger.XOUT_CODE })
	y = StmtRow(y + 4, W, cols, L["(=) Variação líquida de caixa"], { P.Acct(var, true) }, { total = true })
	y = y + 8
	local calc = m.hasCash and (m.cashOpen + var) or nil
	y = StmtRow(y, W, cols, L["Saldo final calculado"], { calc and P.Acct(calc) or COL.muted .. "—|r" }, { bold = true })
	y = StmtRow(y, W, cols, L["Saldo final registrado (ouro do personagem)"], { m.hasCash and P.Acct(m.cashClose) or COL.muted .. "—|r" }, { bold = true })
	local diff = calc and (m.cashClose - calc) or nil
	y = StmtRow(y + 6, W, cols, L["Diferença não conciliada"], { diff and P.Acct(diff, nil, true) or COL.muted .. "—|r" }, { grand = true, h = 22 })
	y = y + 10

	-- conciliação por personagem
	y = Band(y, W, L["Conciliação por personagem"], L["saldo inicial + movimentos registrados = saldo final?"])
	local c2 = { { W - 560, 110 }, { W - 440, 110 }, { W - 320, 110 }, { W - 200, 90 }, { W - 100, 90 } }
	y = StmtRow(y, W, c2, COL.muted .. L["Personagem"] .. "|r", { COL.muted .. L["Saldo inicial"] .. "|r", COL.muted .. L["Movimentos"] .. "|r",
		COL.muted .. L["Saldo final"] .. "|r", COL.muted .. L["Diferença"] .. "|r", COL.muted .. L["Situação"] .. "|r" })
	local n = 0
	for _, t in ipairs(data.chars) do
		if t.any and t.cashOpen and t.cashClose then
			n = n + 1
			local tm = Ledger.Merge({ chars = { t } })
			local td = Ledger.DRE(tm)
			local mv = td.actGold + td.comm + td.itemsale - td.cashOut + tm.xin - tm.xout + tm.adj
			local df = t.cashClose - (t.cashOpen + mv)
			local status = math.abs(df) < 10000 and ("|cff7fd18b" .. L["Conciliado"] .. "|r") or ("|cffe0b04a" .. L["Verificar"] .. "|r")
			y = StmtRow(y, W, c2, ClassName(t.char, t.class), { P.Acct(t.cashOpen), P.Acct(mv, true), P.Acct(t.cashClose), P.Acct(df, nil, true), status },
				{ alt = n % 2 == 0, tip = function(tt)
					tt:SetText(L["Conciliação de caixa"])
					tt:AddLine(L["Diferença = ouro que entrou ou saiu sem ser registrado (ex.: antes do Royal Revenue ser instalado, personagem jogado sem o addon, ou um tipo de movimento ainda não reconhecido)."], 1, 1, 1, true)
				end })
		end
	end
	if n == 0 then cv:Text(10, y, COL.muted .. L["Nada registrado neste período."] .. "|r"); y = y + 20 end
	return y + 10
end

-- ===== Centros de resultado =====
local INSTANCE = { raid = true, dungeon = true, delve = true, pvp = true, scenario = true }
local function RenderCenters(W)
	local _, m, d = Load()
	local y = Band(6, W, L["Centros de resultado"], L["receita - custos (reparo rateado + consumíveis) = resultado · ouro por hora ativa"])
	-- Receita | Reparo | Resultado | Ocorr. | Horas | Ouro/h | AV%
	local cols = { { W - 650, 100 }, { W - 540, 90 }, { W - 440, 100 }, { W - 330, 60 }, { W - 260, 70 }, { W - 180, 90 }, { W - 80, 70 } }
	y = StmtRow(y, W, cols, COL.muted .. L["Centro"] .. "|r", { COL.muted .. L["Receita"] .. "|r", COL.muted .. L["Custos"] .. "|r",
		COL.muted .. L["Resultado"] .. "|r", COL.muted .. L["Ocorr."] .. "|r", COL.muted .. L["Horas"] .. "|r", COL.muted .. L["Ouro/h"] .. "|r", COL.muted .. "AV %|r" })
	local total = d.actGold + d.actItems
	local totRep = 0
	local function row(def, a, secs, indent, alt)
		local iv = Ledger.ItemsValue(a.items)
		local v = a.gold + iv
		local repOnly, cons = a.repair or 0, a.consum or 0
		local rep = repOnly + cons
		local res = v - rep
		local subs = {}
		for sname, s in pairs(a.sub) do
			table.insert(subs, { n = sname, v = s.gold + Ledger.ItemsValue(s.items), c = s.n, cur = s.cur, rep = (s.repair or 0) + (s.consum or 0) })
		end
		table.sort(subs, function(x, z) return (x.v - x.rep) > (z.v - z.rep) end)
		return StmtRow(y, W, cols, def.name,
			{ P.Acct(v), P.Acct(-rep, nil, true), P.Acct(res, true), a.n > 0 and tostring(a.n) or COL.muted .. "—|r",
				secs and Hours(secs) or nil, (secs and secs > 0) and P.Acct(res / (secs / 3600)) or nil, total > 0 and P.Pct(v / total) or nil },
			{ code = Ledger.ActCode(def.key), indent = indent, alt = alt, tip = function(tt)
				tt:SetText(def.name)
				tt:AddDoubleLine(L["Ouro"], P.FormatMoney(a.gold), 1, 0.82, 0, 1, 1, 1)
				tt:AddDoubleLine(L["Itens"], P.FormatMoney(iv), 1, 0.82, 0, 1, 1, 1)
				if repOnly > 0 then tt:AddDoubleLine(L["Reparo rateado"], "-" .. P.FormatMoney(repOnly), 1, 0.82, 0, 0.9, 0.5, 0.5) end
				if cons > 0 then tt:AddDoubleLine(L["Consumíveis usados"], "-" .. P.FormatMoney(cons), 1, 0.82, 0, 0.9, 0.5, 0.5) end
				tt:AddLine(" ")
				for k, s in ipairs(subs) do
					if k > 12 then break end
					local right = P.FormatMoney(s.v - s.rep) .. (s.rep > 0 and ("|cffe07a7a (" .. L["custos"] .. " " .. P.FormatMoney(s.rep) .. ")|r") or "")
					tt:AddDoubleLine(s.n .. (s.c > 0 and (COL.muted .. " ×" .. s.c .. "|r") or ""), right, 1, 1, 1, 1, 1, 1)
				end
			end })
	end
	-- instâncias: tempo próprio
	local n = 0
	for _, def in ipairs(Ledger.ACTS) do
		local a = m.act[def.key]
		if INSTANCE[def.key] and (a or (m.time[def.key] or 0) > 0) then
			n = n + 1
			totRep = totRep + (a and ((a.repair or 0) + (a.consum or 0)) or 0)
			y = row(def, a or { gold = 0, items = {}, n = 0, sub = {} }, m.time[def.key], 0, n % 2 == 0)
		end
	end
	-- mundo aberto: o tempo é do grupo inteiro (missões, eventos, coleta e saques acontecem juntos)
	local grp = { gold = 0, items = {}, n = 0, sub = {}, repair = 0, consum = 0 }
	local any = false
	for _, def in ipairs(Ledger.ACTS) do
		local a = m.act[def.key]
		if not INSTANCE[def.key] and a then
			any = true
			grp.gold, grp.n, grp.repair, grp.consum = grp.gold + a.gold, grp.n + a.n, grp.repair + (a.repair or 0), grp.consum + (a.consum or 0)
			for id, q in pairs(a.items) do grp.items[id] = (grp.items[id] or 0) + q end
		end
	end
	totRep = totRep + grp.repair + grp.consum
	if any or (m.time.world or 0) > 0 then
		y = y + 4
		y = row({ key = "world", name = L["Mundo aberto (grupo)"] }, grp, m.time.world, 0, false)
		for _, def in ipairs(Ledger.ACTS) do
			local a = m.act[def.key]
			if not INSTANCE[def.key] and a then y = row(def, a, nil, 1, false) end
		end
	end
	local secs = TotalTime(m)
	y = StmtRow(y + 6, W, cols, L["TOTAL DAS ATIVIDADES"], { P.Acct(total), P.Acct(-totRep, nil, true), P.Acct(total - totRep, true), nil,
		Hours(secs), secs > 0 and P.Acct((total - totRep) / (secs / 3600)) or nil, total > 0 and "100,0%" or nil }, { grand = true, h = 22 })
	local repAlloc = 0
	for _, a in pairs(m.act) do repAlloc = repAlloc + (a.repair or 0) end
	local unalloc = (m.out.repair or 0) - repAlloc
	if unalloc > 1 then
		y = StmtRow(y, W, cols, COL.muted .. L["Reparo sem origem (desgaste de antes do registro)"] .. "|r", { nil, P.Acct(-unalloc, nil, true) }, { indent = 1 })
	end
	-- serviços: pedidos de fabricação = comissão recebida − materiais próprios usados
	local oa = m.act.orders
	local orderInc, orderMat = m.inc.order or 0, oa and oa.mat or 0
	if orderInc ~= 0 or orderMat ~= 0 then
		y = y + 8
		y = Band(y, W, L["Serviços"], L["comissão recebida − materiais próprios usados"])
		local subs = {}
		for sname, s in pairs(oa and oa.sub or {}) do
			if (s.mat or 0) > 0 then table.insert(subs, { n = sname, v = s.mat }) end
		end
		table.sort(subs, function(x, z) return x.v > z.v end)
		y = StmtRow(y, W, cols, L["Pedidos de fabricação"], { P.Acct(orderInc), P.Acct(-orderMat, nil, true), P.Acct(orderInc - orderMat, true) },
			{ code = Ledger.IncCode("order"), indent = 1, tip = function(tt)
				tt:SetText(L["Pedidos de fabricação"])
				tt:AddDoubleLine(L["Comissão recebida (3.3.03)"], P.FormatMoney(orderInc), 1, 0.82, 0, 0.3, 1, 0.3)
				tt:AddDoubleLine(L["Materiais próprios usados (4.5.02)"], "-" .. P.FormatMoney(orderMat), 1, 0.82, 0, 0.9, 0.5, 0.5)
				tt:AddDoubleLine(L["Resultado"], P.FormatMoney(orderInc - orderMat), 1, 0.82, 0, 1, 1, 1)
				if #subs > 0 then
					tt:AddLine(" ")
					tt:AddLine(L["Materiais por pedido"], 0.85, 0.7, 0.35)
					for k, s in ipairs(subs) do
						if k > 12 then break end
						tt:AddDoubleLine(s.n, "-" .. P.FormatMoney(s.v), 1, 1, 1, 0.9, 0.5, 0.5)
					end
				end
				tt:AddLine(" ")
				tt:AddLine(L["Material que o cliente mandou não conta (não é seu). O detalhe item a item fica no Diário."], 0.6, 0.6, 0.6, true)
			end })
	end
	y = y + 8
	cv:Text(10, y, COL.muted .. L["Rateio: o desgaste do equipamento (custo de reparo de cada peça) é anotado na atividade onde aconteceu (morte, combate); o reparo pago é dividido entre essas atividades na mesma proporção. Consumíveis usados entram pelo preço de mercado (custo de reposição); os ganhos de graça (caldeirão, recompensa, saque) não custam. Visão gerencial: a DRE continua com as compras quando acontecem. Passe o mouse num centro para ver o detalhe."] .. "|r",
		GameFontDisableSmall, W - 20)
	return y + 34
end

-- ===== Diário =====
local function RenderJournal(W)
	local list = {}
	for _, it in ipairs(Ledger.Journal(Period(), state.char)) do
		if not it.e.m then table.insert(list, it) end
	end
	local y = Band(6, W, L["Livro Diário"], string.format(L["%d lançamentos · mais recentes primeiro"], #list))
	local X = { date = 8, char = 110, code = 210, acc = 262, hist = 470, inn = W - 210, out = W - 110 }
	cv:Text(X.date, y, COL.muted .. L["Data"] .. "|r", GameFontDisableSmall)
	cv:Text(X.char, y, COL.muted .. L["Personagem"] .. "|r", GameFontDisableSmall)
	cv:Text(X.code, y, COL.muted .. L["Conta"] .. "|r", GameFontDisableSmall)
	cv:Text(X.hist, y, COL.muted .. L["Histórico"] .. "|r", GameFontDisableSmall)
	cv:Text(X.inn, y, COL.muted .. L["Entrada"] .. "|r", GameFontDisableSmall, 95, "RIGHT")
	cv:Text(X.out, y, COL.muted .. L["Saída"] .. "|r", GameFontDisableSmall, 95, "RIGHT")
	y = y + 16
	Rule(y - 2, 0, W)
	local MAX = 400
	for i, it in ipairs(list) do
		if i > MAX then
			cv:Text(8, y + 4, COL.muted .. string.format(L["... mais %d lançamentos (escolha um período menor ou um personagem)"], #list - MAX) .. "|r", GameFontDisableSmall)
			y = y + 20
			break
		end
		local e = it.e
		if i % 2 == 0 then cv:Box(0, y - 1, W, 16, unpack(COL.alt)) end
		cv:Text(X.date, y, date("%d/%m %H:%M", e.t), GameFontHighlightSmall)
		cv:Text(X.char, y, ClassName(it.char, it.class), GameFontHighlightSmall, 95)
		cv:Text(X.code, y, COL.muted .. e.a .. "|r", GameFontDisableSmall)
		cv:Text(X.acc, y, Ledger.AccountName(e.a), GameFontHighlightSmall, X.hist - X.acc - 8)
		local hist = e.h or ""
		if e.i then hist = string.format("%dx %s", e.q or 1, ItemName(e.i)) .. (hist ~= "" and (COL.muted .. " · " .. hist .. "|r") or "") end
		if e.m then
			local name, icon = CurName(e.m)
			hist = (icon and ("|T" .. icon .. ":12|t ") or "") .. string.format("%d %s", e.q or 1, name) .. (hist ~= "" and (COL.muted .. " · " .. hist .. "|r") or "")
		end
		cv:Text(X.hist, y, hist, GameFontHighlightSmall, X.inn - X.hist - 10)
		if e.m then cv:Text(X.inn, y, COL.muted .. L["moeda"] .. "|r", GameFontDisableSmall, 95, "RIGHT")
		elseif e.x then cv:Text(X.inn, y, COL.muted .. "(" .. P.Acct(e.x) .. ")|r", GameFontDisableSmall, 95, "RIGHT")
		elseif e.v >= 0 then cv:Text(X.inn, y, P.Acct(e.v), GameFontHighlightSmall, 95, "RIGHT")
		else cv:Text(X.out, y, P.Acct(-e.v), GameFontHighlightSmall, 95, "RIGHT") end
		if not e.c then cv:Text(W - 12, y, COL.muted .. "*|r", GameFontDisableSmall) end
		if e.i then
			cv:Button(0, y - 1, W, 16, function()
				if IsShiftKeyDown() then
					local link = select(2, C_Item.GetItemInfo(e.i))
					local insert = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
					if link and insert then insert(link) end
				end
			end, function(tt) tt:SetItemByID(e.i) end)
		end
		y = y + 16
	end
	if #list == 0 then cv:Text(10, y + 4, COL.muted .. L["Nada registrado neste período."] .. "|r"); y = y + 24 end
	y = y + 8
	cv:Text(10, y, COL.muted .. L["* = lançamento de competência (item avaliado a preço de mercado na data); os demais movimentaram ouro."] .. "|r", GameFontDisableSmall, W - 20)
	return y + 24
end

-- ===== Vendas =====
local SALES_COLS = {
	{ key = "name",   label = L["Item"],        w = 230, align = "LEFT" },
	{ key = "char",   label = L["Fabrica"],     w = 70,  align = "LEFT" },
	{ key = "qty",    label = L["Vendidos"],    w = 56,  align = "RIGHT" },
	{ key = "perDay", label = L["Por dia"],     w = 50,  align = "RIGHT" },
	{ key = "avg",    label = L["Preço médio"], w = 80,  align = "RIGHT" },
	{ key = "sale",   label = L["Previsto"],    w = 76,  align = "RIGHT" },
	{ key = "diff",   label = L["Dif."],        w = 50,  align = "RIGHT" },
	{ key = "unit",   label = L["Custo un"],    w = 80,  align = "RIGHT" },
	{ key = "profit", label = L["Lucro real"],  w = 90,  align = "RIGHT" },
}

local function RenderSales(W)
	local ok, rows, sum = pcall(ns.Sales.GetRows)
	if not ok then cv:Text(8, 8, "|cffe07a7a" .. tostring(rows) .. "|r"); return 40 end
	if sum.err then
		local y = Band(6, W, L["Vendas na casa de leilões"])
		cv:Text(10, y, "|cffe0b04a" .. sum.err .. "|r", GameFontHighlight, W - 20)
		return y + 30
	end
	local y = Band(6, W, L["Vendas na casa de leilões"], string.format(L["últimos %d dias · %d itens · líquido %s · lucro real %s"],
		sum.days, sum.qty, P.Acct(sum.net), P.Acct(sum.profit)))
	local k, desc = state.sortKey, state.desc
	table.sort(rows, function(a, b)
		local va, vb = a[k], b[k]
		if va == vb then return (a.name or "") < (b.name or "") end
		if va == nil then return false end
		if vb == nil then return true end
		if desc then return va > vb end
		return va < vb
	end)
	local x = 26
	for _, c in ipairs(SALES_COLS) do
		local arrow = (c.key == state.sortKey) and (state.desc and " v" or " ^") or ""
		cv:Text(x, y, COL.muted .. c.label .. arrow .. "|r", GameFontDisableSmall, c.w, c.align)
		cv:Button(x, y - 2, c.w, 16, function()
			if state.sortKey == c.key then state.desc = not state.desc
			else state.sortKey, state.desc = c.key, c.key ~= "name" and c.key ~= "char" end
			UI.Refresh()
		end)
		c.x = x
		x = x + c.w + 6
	end
	y = y + 16
	Rule(y - 2, 0, W)
	for i, r in ipairs(rows) do
		if i % 2 == 0 then cv:Box(0, y - 1, W, 17, unpack(COL.alt)) end
		cv:Icon(6, y, 15, r.icon)
		local vals = {
			name = r.name, char = COL.muted .. (r.char or "") .. "|r", qty = tostring(r.qty),
			perDay = string.format(r.perDay >= 10 and "%.0f" or "%.1f", r.perDay), avg = P.Acct(r.avg),
			sale = P.Acct(r.sale), diff = P.Pct(r.diff, true),
			unit = P.Acct(r.unit) .. (r.npc and " |cff66ccffN|r" or ""), profit = P.Acct(r.profit, true),
		}
		for _, c in ipairs(SALES_COLS) do cv:Text(c.x, y + 1, vals[c.key], GameFontHighlightSmall, c.w, c.align) end
		cv:Button(0, y - 1, W, 17, function()
			if IsShiftKeyDown() and r.itemID then
				local link = select(2, C_Item.GetItemInfo(r.itemID))
				local insert = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
				if link and insert then insert(link) end
			end
		end, function(tt)
			if r.itemID then tt:SetItemByID(r.itemID) else tt:SetText(r.name) end
			tt:AddLine(" ")
			tt:AddDoubleLine(L["Vendidos"], tostring(r.qty), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Preço médio"], P.FormatMoney(r.avg), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L["Lucro real"], r.profit and P.FormatMoney(r.profit) or L["sem custo (Royal Revenue não tem a receita)"], 1, 0.82, 0, 1, 1, 1)
			if r.npc then tt:AddLine(string.format(L["Revenda: o vendedor vende por %s, mais barato que fabricar (%s)."],
				P.FormatMoney(r.unit), P.FormatMoney(r.craftUnit or 0)), 0.4, 0.8, 1, true) end
			tt:AddLine(L["Shift+clique: linkar item"], 0.6, 0.6, 0.6)
		end)
		y = y + 17
	end
	y = y + 8
	cv:Text(10, y, COL.muted .. (sum.own and L["Vendas registradas pelo Royal Revenue no correio da casa de leilões. Lucro real = venda × 0,95 - custo de fabricar hoje (Royal Revenue) ou do vendedor (|cff66ccffN|r) se for mais barato."]
		or L["TSM Accounting, dados até o seu último logout. Lucro real = venda × 0,95 - custo de fabricar hoje (Royal Revenue) ou do vendedor (|cff66ccffN|r) se for mais barato."]) .. "|r",
		GameFontDisableSmall, W - 20)
	return y + 30
end

-- ===== Livro de uma moeda (seletor de moeda) =====
-- Ouro usa as demonstrações acima. Outras moedas (cristas, Remnant, chaves...) têm o próprio livro:
-- entradas por atividade, saídas por categoria, saldo inicial/final e conciliação, centros e diário.
local function Num(n, tone)
	if n == nil then return COL.muted .. "—|r" end
	local v = math.floor(math.abs(n) + 0.5)
	local txt = root.Num(v, 0)
	if n < 0 then txt = "(" .. txt .. ")" end
	if tone and n > 0 then return "|cff7fd18b" .. txt .. "|r" end
	if n < 0 then return "|cffe07a7a" .. txt .. "|r" end
	return txt
end

-- moedas com o mesmo nome (o jogo às vezes tem dois IDs para a mesma moeda): tratadas como uma só
local CurrencyList
local CatMembers, CatName, CatTitle, RenderCatPanel, RenderCatMatrix, RenderCatJournal, RenderCurJournal
local function CurSet(id)
	local set = { [id] = true }
	local name = CurName(id)
	for _, it in ipairs(CurrencyList(true)) do if it.name == name then set[it.id] = true end end
	return set
end
local function CurQ(tbl, set)
	local q = 0
	for gid in pairs(set) do q = q + (tbl and tbl[gid] or 0) end
	return q
end

-- números de uma moeda num conjunto já somado (Merge)
local function CurFigures(m, id)
	local set = CurSet(id)
	local f = { inAct = {}, inTotal = 0, out = {}, outTotal = 0, set = set }
	for k, a in pairs(m.act) do
		local q = CurQ(a.cur, set)
		if q ~= 0 then f.inAct[k] = q; f.inTotal = f.inTotal + q end
	end
	for gid in pairs(set) do
		for k, v in pairs(m.curOut[gid] or {}) do f.out[k] = (f.out[k] or 0) + v; f.outTotal = f.outTotal + v end
		if m.curOpen[gid] then f.open = (f.open or 0) + m.curOpen[gid] end
		if m.curClose[gid] then f.close = (f.close or 0) + m.curClose[gid] end
	end
	f.conv = CurQ(m.curConv, set)
	f.net = f.inTotal + f.conv - f.outTotal
	return f
end

local function CurTitle(id)
	local name, icon = CurName(id)
	return (icon and ("|T" .. icon .. ":16|t ") or "") .. name
end

local function RenderCurPanel(W, id)
	local data, m = Load()
	local f = CurFigures(m, id)
	local secs = TotalTime(m)
	local y = 6
	local cw = math.floor((W - 30) / 4)
	local function cx(i) return (i - 1) * (cw + 10) end
	Card(cx(1), y, cw, 64, L["Recebido"], Num(f.inTotal, true), CurTitle(id))
	Card(cx(2), y, cw, 64, L["Gasto"], Num(-f.outTotal))
	Card(cx(3), y, cw, 64, L["Variação líquida"], Num(f.net, true))
	Card(cx(4), y, cw, 64, L["Por hora"], secs > 0 and Num(f.inTotal / (secs / 3600)) or COL.muted .. "—|r", COL.muted .. L["recebido ÷ horas ativas"] .. "|r")
	y = y + 74
	local diff = (f.open and f.close) and (f.close - (f.open + f.net)) or nil
	Card(cx(1), y, cw, 64, L["Saldo atual"], f.close and Num(f.close) or COL.muted .. "—|r", COL.muted .. L["no último registro"] .. "|r")
	Card(cx(2), y, cw, 64, L["Horas ativas"], Hours(secs))
	Card(cx(3), y, cw, 64, L["Conciliação"], diff == nil and (COL.muted .. "—|r") or (math.abs(diff) < 1 and "|cff7fd18b" .. L["Conciliado"] .. "|r"
		or "|cffe0b04a" .. L["Diferença"] .. " " .. Num(diff) .. "|r"), COL.muted .. L["saldo calculado × saldo real"] .. "|r")
	y = y + 80
	y = Band(y, W, L["Por personagem"], L["clique para filtrar"])
	local cols = { { W - 500, 100 }, { W - 390, 100 }, { W - 280, 100 }, { W - 170, 70 }, { W - 90, 80 } }
	y = StmtRow(y, W, cols, COL.muted .. L["Personagem"] .. "|r", { COL.muted .. L["Recebido"] .. "|r", COL.muted .. L["Gasto"] .. "|r",
		COL.muted .. L["Líquido"] .. "|r", COL.muted .. L["Horas"] .. "|r", COL.muted .. L["Por hora"] .. "|r" })
	local all = state.char and Ledger.Collect(Period(), nil) or data
	local rows = {}
	for _, t in ipairs(all.chars) do
		if t.any then
			local tm = Ledger.Merge({ chars = { t } })
			local tf = CurFigures(tm, id)
			if tf.inTotal ~= 0 or tf.outTotal ~= 0 then table.insert(rows, { t = t, f = tf, s = TotalTime(tm) }) end
		end
	end
	table.sort(rows, function(a, b) return a.f.inTotal > b.f.inTotal end)
	if #rows == 0 then cv:Text(10, y, COL.muted .. L["Nada registrado neste período."] .. "|r"); return y + 30 end
	for i, r in ipairs(rows) do
		if state.char == r.t.char then cv:Box(0, y - 2, W, 18, 0.85, 0.7, 0.35, 0.12) end
		y = StmtRow(y, W, cols, ClassName(r.t.char, r.t.class) .. COL.muted .. "  " .. (r.t.char:match("%-(.+)$") or "") .. "|r",
			{ Num(r.f.inTotal), Num(-r.f.outTotal), Num(r.f.net, true), Hours(r.s), r.s > 0 and Num(r.f.inTotal / (r.s / 3600)) or COL.muted .. "—|r" },
			{ alt = i % 2 == 0 })
		cv:Button(0, y - 20, W, 18, function()
			state.char = (state.char == r.t.char) and nil or r.t.char
			UI.Refresh()
		end)
	end
	return y + 10
end

local function RenderCurStatement(W, id)
	local _, m = Load()
	local f = CurFigures(m, id)
	local y = Band(6, W, L["Movimentação da moeda"] .. " · " .. CurTitle(id), L["quantidades"])
	local cols = { { W - 200, 150 } }
	y = StmtRow(y, W, cols, L["Saldo inicial"], { f.open and Num(f.open) or COL.muted .. "—|r" }, { bold = true })
	y = y + 6
	y = StmtRow(y, W, cols, L["(+) Entradas por atividade"], { Num(f.inTotal) }, { bold = true })
	for _, def in ipairs(Ledger.ACTS) do
		local q = f.inAct[def.key]
		if q then
			local a = m.act[def.key]
			y = StmtRow(y, W, cols, COL.muted .. def.name .. "|r", { Num(q) }, { code = Ledger.ActCode(def.key, true), indent = 1, h = 16,
				tip = function(tt)
					tt:SetText(def.name)
					local subs = {}
					for sname, sb in pairs(a.sub or {}) do
						local v = CurQ(sb.cur, f.set)
						if v > 0 then table.insert(subs, { n = sname, v = v }) end
					end
					table.sort(subs, function(x, z) return x.v > z.v end)
					for k, sb in ipairs(subs) do
						if k > 12 then break end
						tt:AddDoubleLine(sb.n, Num(sb.v), 1, 1, 1, 1, 1, 1)
					end
				end })
		end
	end
	if f.conv ~= 0 then
		y = StmtRow(y, W, cols, L["(+) Conversões e trocas"], { Num(f.conv) }, { bold = true, code = Ledger.CONV_CODE })
	end
	y = StmtRow(y, W, cols, L["(-) Saídas"], { Num(-f.outTotal) }, { bold = true })
	for _, c in ipairs(Ledger.CUR_OUT) do
		if f.out[c.key] then y = StmtRow(y, W, cols, COL.muted .. c.name .. "|r", { Num(-f.out[c.key]) }, { indent = 1, h = 16 }) end
	end
	y = StmtRow(y + 4, W, cols, L["(=) Variação líquida"], { Num(f.net, true) }, { total = true })
	y = y + 8
	local calc = f.open and (f.open + f.net) or nil
	y = StmtRow(y, W, cols, L["Saldo final calculado"], { calc and Num(calc) or COL.muted .. "—|r" }, { bold = true })
	y = StmtRow(y, W, cols, L["Saldo final registrado"], { f.close and Num(f.close) or COL.muted .. "—|r" }, { bold = true })
	local diff = (calc and f.close) and (f.close - calc) or nil
	y = StmtRow(y + 6, W, cols, L["Diferença não conciliada"], { diff and Num(diff) or COL.muted .. "—|r" }, { grand = true, h = 22 })
	y = y + 10
	cv:Text(10, y, COL.muted .. L["Moedas não têm valor em ouro: o livro mostra quantidades. Diferença = moeda que entrou ou saiu sem registro (antes da instalação, ganhos com vendedor, correio ou banco abertos)."] .. "|r",
		GameFontDisableSmall, W - 20)
	return y + 34
end

local function RenderCurCenters(W, id)
	local _, m = Load()
	local f = CurFigures(m, id)
	local y = Band(6, W, L["Centros de resultado"] .. " · " .. CurTitle(id), L["recebido por atividade · por hora ativa"])
	local cols = { { W - 420, 100 }, { W - 310, 60 }, { W - 240, 70 }, { W - 160, 80 }, { W - 70, 60 } }
	y = StmtRow(y, W, cols, COL.muted .. L["Centro"] .. "|r", { COL.muted .. L["Recebido"] .. "|r", COL.muted .. L["Ocorr."] .. "|r",
		COL.muted .. L["Horas"] .. "|r", COL.muted .. L["Por hora"] .. "|r", COL.muted .. "AV %|r" })
	local n = 0
	for _, def in ipairs(Ledger.ACTS) do
		local q = f.inAct[def.key]
		if q then
			n = n + 1
			local a = m.act[def.key]
			local secs = INSTANCE[def.key] and m.time[def.key] or nil
			y = StmtRow(y, W, cols, def.name, { Num(q), a.n > 0 and tostring(a.n) or COL.muted .. "—|r", secs and Hours(secs) or nil,
				(secs and secs > 0) and Num(q / (secs / 3600)) or nil, f.inTotal > 0 and P.Pct(q / f.inTotal) or nil },
				{ code = Ledger.ActCode(def.key, true), alt = n % 2 == 0, tip = function(tt)
					tt:SetText(def.name)
					for sname, sb in pairs(a.sub or {}) do
						local v = CurQ(sb.cur, f.set)
						if v > 0 then tt:AddDoubleLine(sname, Num(v), 1, 1, 1, 1, 1, 1) end
					end
				end })
		end
	end
	if n == 0 then cv:Text(10, y, COL.muted .. L["Nada registrado neste período."] .. "|r"); y = y + 20 end
	local secs = TotalTime(m)
	y = StmtRow(y + 6, W, cols, L["TOTAL DAS ATIVIDADES"], { Num(f.inTotal), nil, Hours(secs), secs > 0 and Num(f.inTotal / (secs / 3600)) or nil, f.inTotal > 0 and "100.0%" or nil },
		{ grand = true, h = 22 })
	return y + 20
end

function RenderCurJournal(W, id, set, title)
	local list = {}
	set = set or CurSet(id)
	for _, it in ipairs(Ledger.Journal(Period(), state.char)) do
		if it.e.m and set[it.e.m] then table.insert(list, it) end
	end
	local y = Band(6, W, L["Livro Diário"] .. " · " .. (title or CurTitle(id)), string.format(L["%d lançamentos · mais recentes primeiro"], #list))
	local X = { date = 8, char = 110, code = 210, acc = 262, hist = 470, inn = W - 210, out = W - 110 }
	cv:Text(X.date, y, COL.muted .. L["Data"] .. "|r", GameFontDisableSmall)
	cv:Text(X.char, y, COL.muted .. L["Personagem"] .. "|r", GameFontDisableSmall)
	cv:Text(X.code, y, COL.muted .. L["Conta"] .. "|r", GameFontDisableSmall)
	cv:Text(X.hist, y, COL.muted .. L["Histórico"] .. "|r", GameFontDisableSmall)
	cv:Text(X.inn, y, COL.muted .. L["Entrada"] .. "|r", GameFontDisableSmall, 95, "RIGHT")
	cv:Text(X.out, y, COL.muted .. L["Saída"] .. "|r", GameFontDisableSmall, 95, "RIGHT")
	y = y + 16
	Rule(y - 2, 0, W)
	for i, it in ipairs(list) do
		if i > 400 then break end
		local e = it.e
		if i % 2 == 0 then cv:Box(0, y - 1, W, 16, unpack(COL.alt)) end
		cv:Text(X.date, y, date("%d/%m %H:%M", e.t), GameFontHighlightSmall)
		cv:Text(X.char, y, ClassName(it.char, it.class), GameFontHighlightSmall, 95)
		cv:Text(X.code, y, COL.muted .. e.a .. "|r", GameFontDisableSmall)
		cv:Text(X.acc, y, Ledger.AccountName(e.a), GameFontHighlightSmall, X.hist - X.acc - 8)
		cv:Text(X.hist, y, e.h or "", GameFontHighlightSmall, X.inn - X.hist - 10)
		local q = e.q or 0
		if q >= 0 then cv:Text(X.inn, y, Num(q), GameFontHighlightSmall, 95, "RIGHT")
		else cv:Text(X.out, y, Num(-q), GameFontHighlightSmall, 95, "RIGHT") end
		y = y + 16
	end
	if #list == 0 then cv:Text(10, y + 4, COL.muted .. L["Nada registrado neste período."] .. "|r"); y = y + 24 end
	return y + 10
end

-- moedas internas do jogo (contadores de limite semanal, sistemas): não aparecem no seletor
local function CurHidden(name, id)
	if not name then return true end
	if id and Ledger.CurIgnored(id) then return true end
	if name:find(" %- ") and (name:find("Tracker") or name:find("System") or name:find("Cap") or name:find("Rastreador") or name:find("Sistema")) then return true end
	return false
end
-- categoria pelo nome (inglês e português)
local CUR_CATS = {
	{ L["Brasões"], { "Crest", "crest", "Brasão" } },
	{ L["Pedidos de fabricação"], { "Moxie", "Artisan", "Artesão" } },
	{ L["Imersões (Delves)"], { "Coffer Key", "Cofre", "Undercoin", "Delve" } },
	{ L["Renome"], { "Renown", "Renome" } },
}
local function CurCategory(name)
	for i, c in ipairs(CUR_CATS) do
		for _, w in ipairs(c[2]) do if name:find(w, 1, true) then return i end end
	end
	return #CUR_CATS + 1
end

-- moedas conhecidas (registradas em qualquer personagem); all = inclui repetidas e internas
function CurrencyList(all)
	local set = {}
	for id in pairs(LucroLivroDB.currencies or {}) do set[id] = true end
	for _, c in pairs(LucroLivroDB.chars or {}) do
		for _, day in pairs(c.days or {}) do
			for _, a in pairs(day.act or {}) do
				for id in pairs(a.cur or {}) do set[id] = true end
			end
		end
	end
	local list, seen = {}, {}
	local ids = {}
	for id in pairs(set) do table.insert(ids, id) end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local name = CurName(id)
		if all or (not seen[name] and not CurHidden(name, id)) then
			seen[name] = true
			table.insert(list, { id = id, name = name, cat = CurCategory(name) })
		end
	end
	table.sort(list, function(a, b) if a.cat ~= b.cat then return a.cat < b.cat end return a.name < b.name end)
	return list
end

-- ===== categoria inteira (ex.: todos os brasões lado a lado) =====
function CatMembers(key)
	local n = tonumber(tostring(key):match("^cat:(%d+)$"))
	local list = {}
	if not n then return list end
	for _, it in ipairs(CurrencyList()) do if it.cat == n then table.insert(list, it) end end
	return list
end
function CatName(key)
	local n = tonumber(tostring(key):match("^cat:(%d+)$"))
	return (n and CUR_CATS[n] and CUR_CATS[n][1]) or L["Outras moedas"]
end
function CatTitle(key)
	local first = CatMembers(key)[1]
	local _, icon = first and CurName(first.id)
	return (icon and ("|T" .. icon .. ":16|t ") or "") .. CatName(key)
end
-- nome curto para cabeçalho de coluna: "Veteran Mistcrest" -> "Veteran"
local function ShortCur(id)
	local name, icon = CurName(id)
	local short = name
	if name:find("crest") or name:find("Brasão") then short = name:match("^(%S+)") or name end
	return (icon and ("|T" .. icon .. ":14|t ") or "") .. short
end

function RenderCatPanel(W, key)
	local _, m = Load()
	local members = CatMembers(key)
	local secs = TotalTime(m)
	local y = Band(6, W, CatName(key), L["quantidades · uma linha por moeda"])
	local cols = { { W - 610, 90 }, { W - 510, 90 }, { W - 410, 90 }, { W - 310, 90 }, { W - 210, 90 }, { W - 110, 90 } }
	y = StmtRow(y, W, cols, COL.muted .. L["Moeda"] .. "|r", { COL.muted .. L["Saldo inicial"] .. "|r", COL.muted .. L["Recebido"] .. "|r",
		COL.muted .. L["Gasto"] .. "|r", COL.muted .. L["Líquido"] .. "|r", COL.muted .. L["Saldo atual"] .. "|r", COL.muted .. L["Por hora"] .. "|r" })
	for i, it in ipairs(members) do
		local f = CurFigures(m, it.id)
		local inn = f.inTotal + f.conv
		y = StmtRow(y, W, cols, CurTitle(it.id), { f.open and Num(f.open) or COL.muted .. "—|r", Num(inn), Num(-f.outTotal), Num(f.net, true),
			f.close and Num(f.close) or COL.muted .. "—|r", secs > 0 and Num(f.inTotal / (secs / 3600)) or COL.muted .. "—|r" }, { alt = i % 2 == 0 })
		cv:Button(0, y - 20, W, 18, function() state.cur = it.id; LucroLivroDB.config.cur = it.id; UI.Refresh() end)
	end
	y = y + 8
	cv:Text(10, y, COL.muted .. L["Clique numa moeda para ver só ela."] .. "|r", GameFontDisableSmall, W - 20)
	return y + 24
end

-- origem e destino de cada moeda da categoria (linhas = atividades e saídas, colunas = moedas)
function RenderCatMatrix(W, key)
	local _, m = Load()
	local members = CatMembers(key)
	local shown = {}
	for i, it in ipairs(members) do if i <= 8 then table.insert(shown, it) end end
	local y = Band(6, W, L["Movimentação"] .. " · " .. CatName(key), L["quantidades"])
	local labelW = 240
	local cw = math.max(70, math.floor((W - labelW - 10) / math.max(#shown, 1)))
	local cols = {}
	for i = 1, #shown do cols[i] = { labelW + (i - 1) * cw, cw - 6 } end
	local F = {}
	for i, it in ipairs(shown) do F[i] = CurFigures(m, it.id) end
	local function vals(fn) local v = {} for i = 1, #shown do v[i] = fn(F[i]) end return v end
	local head = {}
	for i, it in ipairs(shown) do head[i] = ShortCur(it.id) end
	y = StmtRow(y, W, cols, COL.muted .. L["Moeda"] .. "|r", head)
	y = StmtRow(y, W, cols, L["Saldo inicial"], vals(function(f) return f.open and Num(f.open) or COL.muted .. "—|r" end), { bold = true })
	y = y + 4
	y = StmtRow(y, W, cols, L["(+) Entradas por atividade"], vals(function(f) return Num(f.inTotal) end), { bold = true })
	for _, def in ipairs(Ledger.ACTS) do
		local any = false
		for i = 1, #shown do if F[i].inAct[def.key] then any = true end end
		if any then
			y = StmtRow(y, W, cols, COL.muted .. def.name .. "|r", vals(function(f) return f.inAct[def.key] and Num(f.inAct[def.key]) or COL.muted .. "—|r" end),
				{ code = Ledger.ActCode(def.key, true), indent = 1, h = 16 })
		end
	end
	local anyConv = false
	for i = 1, #shown do if F[i].conv ~= 0 then anyConv = true end end
	if anyConv then
		y = StmtRow(y, W, cols, L["(+) Conversões e trocas"], vals(function(f) return f.conv ~= 0 and Num(f.conv) or COL.muted .. "—|r" end), { bold = true, code = Ledger.CONV_CODE })
	end
	y = StmtRow(y, W, cols, L["(-) Saídas"], vals(function(f) return Num(-f.outTotal) end), { bold = true })
	for _, c in ipairs(Ledger.CUR_OUT) do
		local any = false
		for i = 1, #shown do if F[i].out[c.key] then any = true end end
		if any then
			y = StmtRow(y, W, cols, COL.muted .. c.name .. "|r", vals(function(f) return f.out[c.key] and Num(-f.out[c.key]) or COL.muted .. "—|r" end), { indent = 1, h = 16 })
		end
	end
	y = StmtRow(y + 4, W, cols, L["(=) Variação líquida"], vals(function(f) return Num(f.net, true) end), { total = true })
	y = StmtRow(y + 4, W, cols, L["Saldo final registrado"], vals(function(f) return f.close and Num(f.close) or COL.muted .. "—|r" end), { bold = true })
	y = StmtRow(y + 4, W, cols, L["Diferença não conciliada"], vals(function(f)
		if not (f.open and f.close) then return COL.muted .. "—|r" end
		return Num(f.close - (f.open + f.net))
	end), { grand = true, h = 22 })
	y = y + 10
	if #members > #shown then
		cv:Text(10, y, COL.muted .. string.format(L["Mostrando %d de %d moedas."], #shown, #members) .. "|r", GameFontDisableSmall, W - 20)
		y = y + 16
	end
	return y + 10
end

function RenderCatJournal(W, key)
	local set = {}
	for _, it in ipairs(CatMembers(key)) do for gid in pairs(CurSet(it.id)) do set[gid] = true end end
	return RenderCurJournal(W, nil, set, CatTitle(key))
end

function UI.CurMenu(owner)
	local list = CurrencyList()
	local function choose(id)
		state.cur = id
		LucroLivroDB.config = LucroLivroDB.config or {}
		LucroLivroDB.config.cur = id
		UI.Refresh()
	end
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			root:CreateRadio("|TInterface\\MoneyFrame\\UI-GoldIcon:14|t " .. L["Ouro"], function() return state.cur == nil end, function() choose(nil) end)
			if #list > 0 then
				root:CreateDivider()
				root:CreateTitle(L["Moedas"])
				local function isSel(it) return type(state.cur) == "number" and CurSet(it.id)[state.cur] == true end
				-- uma entrada por categoria, com as moedas num submenu
				local groups, order = {}, {}
				for _, it in ipairs(list) do
					if not groups[it.cat] then groups[it.cat] = {}; table.insert(order, it.cat) end
					table.insert(groups[it.cat], it)
				end
				for _, cat in ipairs(order) do
					local items = groups[cat]
					local cname = CUR_CATS[cat] and CUR_CATS[cat][1] or L["Outras moedas"]
					local catKey = "cat:" .. cat
					local any = state.cur == catKey
					for _, it in ipairs(items) do if isSel(it) then any = true end end
					local sub = root:CreateButton((any and "|cffffd100" or "") .. cname .. (any and "|r" or "") .. COL.muted .. "  (" .. #items .. ")|r")
					-- a categoria inteira: todas as moedas dela lado a lado
					if #items > 1 then
						sub:CreateRadio(L["Todas"] .. " — " .. cname, function() return state.cur == catKey end, function() choose(catKey) end)
						if sub.CreateDivider then sub:CreateDivider() end
					end
					for _, it in ipairs(items) do
						sub:CreateRadio(CurTitle(it.id), function() return isSel(it) end, function() choose(it.id) end)
					end
				end
			end
		end)
	else
		-- cliente sem o menu novo: alterna ouro -> moedas
		local idx = 0
		for i, it in ipairs(list) do if it.id == state.cur then idx = i end end
		idx = idx + 1
		choose(list[idx] and list[idx].id or nil)
	end
end

-- ===== janela =====
local function CharList()
	local list = {}
	for char in pairs(LucroLivroDB.chars or {}) do table.insert(list, char) end
	table.sort(list)
	return list
end

local function CycleChar(dir)
	local list = CharList()
	local idx = 0
	for i, c in ipairs(list) do if c == state.char then idx = i end end
	idx = idx + dir
	if idx < 0 then idx = #list end
	if idx > #list then idx = 0 end
	state.char = idx > 0 and list[idx] or nil
	UI.Refresh()
end

-- menu suspenso: conta inteira ou um personagem (agrupados por reino)
local function Choose(char)
	state.char = char
	UI.Refresh()
end

function UI.PeriodMenu(owner)
	local function choose(i) state.period = i; UI.Refresh() end
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			for i, p in ipairs(PERIODS) do
				root:CreateRadio(p[1], function() return state.period == i end, function() choose(i) end)
				if i == 1 then root:CreateDivider() end
			end
		end)
	else
		choose(state.period % #PERIODS + 1)
	end
end

function UI.CharMenu(owner)
	local list = CharList()
	table.sort(list, function(a, b)
		local ra, rb = a:match("%-(.+)$") or "", b:match("%-(.+)$") or ""
		if ra ~= rb then return ra < rb end
		return a < b
	end)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			root:CreateRadio(L["Conta (todos os personagens)"], function() return state.char == nil end, function() Choose(nil) end)
			root:CreateDivider()
			local lastRealm
			for _, char in ipairs(list) do
				local realm = char:match("%-(.+)$") or ""
				if realm ~= lastRealm then
					root:CreateTitle(realm)
					lastRealm = realm
				end
				local cdb = LucroLivroDB.chars[char]
				root:CreateRadio(ClassName(char, cdb and cdb.class), function() return state.char == char end, function() Choose(char) end)
			end
		end)
	else
		-- cliente sem o menu novo: alterna conta -> personagens
		CycleChar(1)
	end
end

local function Create()
	frame = CreateFrame("Frame", "LucroLivroFrame", UIParent, "BasicFrameTemplateWithInset")
	local sz = LucroLivroDB.size
	frame:SetSize(sz and sz[1] or 1000, sz and sz[2] or 640)
	frame:SetPoint("CENTER")
	-- camada normal das janelas (como as de outros addons): quem foi clicada por último fica por cima
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		LucroLivroDB.pos = { p, rp, x, y }
	end)
	frame:Hide()
	table.insert(UISpecialFrames, "LucroLivroFrame")
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText("|cffd4af37Royal|r |cff6f9be0Revenue|r |cffd9dde3— " .. L["Livro-caixa"] .. "|r")
	frame.titleFS = title
	if LucroLivroDB.pos then
		local p = LucroLivroDB.pos
		frame:ClearAllPoints()
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	end

	-- cabeçalho do relatório: entidade e período
	frame.entity = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.entity:SetPoint("TOPLEFT", 16, -58)
	frame.range = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.range:SetPoint("TOPLEFT", frame.entity, "BOTTOMLEFT", 0, -3)

	-- filtros à direita: personagem (◀ ▶) e período
	-- período: menu suspenso (sessão, hoje, 7 dias, 30 dias, tudo)
	local perB = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	perB:SetSize(130, 20)
	perB:SetPoint("TOPRIGHT", -14, -58)
	perB:SetText(" ")
	local pfs = perB:GetFontString()
	if pfs then
		pfs:ClearAllPoints()
		pfs:SetPoint("LEFT", 8, 0)
		pfs:SetPoint("RIGHT", -20, 0)
		pfs:SetJustifyH("LEFT")
	end
	local parrow = perB:CreateTexture(nil, "OVERLAY")
	parrow:SetSize(12, 12)
	parrow:SetPoint("RIGHT", -6, 0)
	parrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	parrow:SetRotation(-math.pi / 2)
	perB:SetScript("OnClick", function(self) UI.PeriodMenu(self) end)
	frame.perBtn = perB
	local anchor = perB
	-- seletor: conta inteira ou um personagem (menu suspenso)
	local acc = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	acc:SetSize(210, 20)
	acc:SetPoint("RIGHT", anchor, "LEFT", -16, 0)
	acc:SetText(" ")
	local fs = acc:GetFontString()
	if fs then
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", 8, 0)
		fs:SetPoint("RIGHT", -20, 0)
		fs:SetJustifyH("LEFT")
	end
	local arrow = acc:CreateTexture(nil, "OVERLAY")
	arrow:SetSize(12, 12)
	arrow:SetPoint("RIGHT", -6, 0)
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetRotation(-math.pi / 2)
	acc:SetScript("OnClick", function(self) UI.CharMenu(self) end)
	frame.accBtn = acc

	local curB = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	curB:SetSize(190, 20)
	curB:SetPoint("RIGHT", acc, "LEFT", -6, 0)
	curB:SetText(" ")
	local cfs = curB:GetFontString()
	if cfs then
		cfs:ClearAllPoints()
		cfs:SetPoint("LEFT", 8, 0)
		cfs:SetPoint("RIGHT", -20, 0)
		cfs:SetJustifyH("LEFT")
	end
	local carrow = curB:CreateTexture(nil, "OVERLAY")
	carrow:SetSize(12, 12)
	carrow:SetPoint("RIGHT", -6, 0)
	carrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	carrow:SetRotation(-math.pi / 2)
	curB:SetScript("OnClick", function(self) UI.CurMenu(self) end)
	frame.curBtn = curB

	-- engrenagem: opções (idioma, minimapa)
	local gear = CreateFrame("Button", nil, frame)
	gear:SetSize(18, 18)
	gear:SetPoint("TOPRIGHT", -30, -4)
	gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
	gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	gear:SetScript("OnClick", function() if ns.Options then ns.Options.Open() end end)
	gear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L["Opções"])
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- fundo do relatório
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	bg:SetPoint("TOPLEFT", 10, -94)
	bg:SetPoint("BOTTOMRIGHT", -10, 8)
	bg:SetColorTexture(0.05, 0.055, 0.07, 0.92)
	local line = frame:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 10, -93)
	line:SetPoint("TOPRIGHT", -10, -93)
	line:SetHeight(1)
	line:SetColorTexture(0.85, 0.7, 0.35, 0.6)

	cv = ns.Canvas.Create(frame)
	cv.frame:SetPoint("TOPLEFT", 16, -100)
	cv.frame:SetPoint("BOTTOMRIGHT", -16, 12)

	frame.Tabs = {}
	local strip = ns.root.MakeTabStrip(frame)
	local prevTab
	for i, label in ipairs(TABS) do
		local tab = ns.root.MakeTab(strip, "LucroLivroFrameTab" .. i, label, i, function(self) state.tab = self:GetID(); UI.Refresh() end)
		if prevTab then tab:SetPoint("LEFT", prevTab, "RIGHT", 2, 0) else tab:SetPoint("LEFT", strip, "LEFT", 4, 0) end
		frame.Tabs[i] = tab
		prevTab = tab
	end
	frame.numTabs = #TABS
	frame:SetScript("OnShow", function()
		if root.FitToScreen and root.FitToScreen(frame) then
			local p, _, rp, x, y = frame:GetPoint()
			LucroLivroDB.pos = { p, rp, x, y }
			LucroLivroDB.size = { math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5) }
		end
		UI.Refresh()
	end)

	-- janela redimensionável: alça no canto inferior direito (duplo clique = tamanho padrão)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		local mw, mh = 2000, 1400
		if root.ScreenMax then mw, mh = root.ScreenMax(frame) end
		frame:SetResizeBounds(780, 460, math.max(mw, 780), math.max(mh, 460))
	elseif frame.SetMinResize then
		frame:SetMinResize(780, 460); frame:SetMaxResize(2000, 1400)
	end
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetFrameLevel(frame:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		if root.FitToScreen then root.FitToScreen(frame) end
		LucroLivroDB.size = { math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5) }
		local p, _, rp, x, y = frame:GetPoint()
		LucroLivroDB.pos = { p, rp, x, y }
		UI.Refresh()
	end)
	grip:SetScript("OnDoubleClick", function()
		LucroLivroDB.size = nil
		frame:SetSize(1000, 640)
		UI.Refresh()
	end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(L["Arraste para mudar o tamanho"])
		GameTooltip:AddLine(L["Duplo clique: tamanho padrão"], 1, 1, 1)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- enquanto arrasta: redesenha no máximo a cada 0,1 s
	local pendingSize = false
	frame:SetScript("OnSizeChanged", function()
		if pendingSize then return end
		pendingSize = true
		C_Timer.After(0.1, function() pendingSize = false; UI.Refresh() end)
	end)
end

local function RangeText()
	local days = Period()
	if not days then return L["todo o histórico"] end
	if days == "session" then
		local who = Ledger.SessionChar(state.char)
		local c = LucroLivroDB.chars[who]
		local s = c and c.session
		if not s then return L["sem sessão registrada"] end
		return string.format(L["sessão de %s desde %s"], (who:match("^([^%-]+)") or who), date("%d/%m %H:%M", s.t))
	end
	local from, to = Ledger.Range(days)
	local function br(d) local yy, mm, dd = d:match("(%d+)-(%d+)-(%d+)"); return dd .. "/" .. mm .. "/" .. yy end
	return string.format(L["período de %s a %s"], br(from), br(to))
end

function UI.Refresh()
	if not frame or not frame:IsShown() then return end
	ns.root.SelectTab(frame.Tabs, state.tab)
	frame.perBtn:SetText(PERIODS[state.period][1])
	local c = state.char and LucroLivroDB.chars[state.char]
	local entity = state.char and ClassName(state.char, c and c.class) or L["Conta (todos os personagens)"]
	if Period() == "session" and not state.char then
		local who = Ledger.SessionChar(nil)
		local cc = LucroLivroDB.chars[who]
		entity = ClassName(who, cc and cc.class)
	end
	frame.entity:SetText(entity)
	frame.accBtn:SetText(state.char and ClassName(state.char, c and c.class) or L["Conta (todos os personagens)"])
	local isSales = state.tab == T_SALES
	LucroLivroDB.config = LucroLivroDB.config or {}
	if state.cur == nil and LucroLivroDB.config.cur then state.cur = LucroLivroDB.config.cur end
	local cur = (not isSales) and state.cur or nil
	local isCat = type(state.cur) == "string"
	if isCat and not CatMembers(state.cur)[1] then state.cur = nil; isCat = false; cur = nil end
	frame.curBtn:SetText(state.cur and (isCat and CatTitle(state.cur) or CurTitle(state.cur)) or ("|TInterface\\MoneyFrame\\UI-GoldIcon:14|t " .. L["Ouro"]))
	frame.range:SetText(isSales and L["vendas dos últimos 14 dias"] or (RangeText() .. " · " .. (cur and (L["quantidades de"] .. " " .. (isCat and CatName(cur) or CurName(cur))) or L["valores em ouro"])))
	frame.perBtn:SetShown(not isSales)
	frame.accBtn:SetShown(not isSales)
	frame.curBtn:SetShown(not isSales)
	cv:Begin()
	local W = cv:Width()
	local ok, h = pcall(function()
		if cur and type(cur) == "string" then
			if state.tab == T_PANEL then return RenderCatPanel(W, cur)
			elseif state.tab == T_JOURNAL then return RenderCatJournal(W, cur)
			else return RenderCatMatrix(W, cur) end
		end
		if cur then
			if state.tab == T_PANEL then return RenderCurPanel(W, cur)
			elseif state.tab == T_DRE or state.tab == T_CASH then return RenderCurStatement(W, cur)
			elseif state.tab == T_CENTERS then return RenderCurCenters(W, cur)
			elseif state.tab == T_JOURNAL then return RenderCurJournal(W, cur) end
		end
		if state.tab == T_PANEL then return RenderPanel(W)
		elseif state.tab == T_DRE then return RenderDRE(W)
		elseif state.tab == T_CASH then return RenderCash(W)
		elseif state.tab == T_CENTERS then return RenderCenters(W)
		elseif state.tab == T_JOURNAL then return RenderJournal(W)
		else return RenderSales(W) end
	end)
	if not ok then
		cv:Text(10, 10, "|cffe07a7a" .. tostring(h) .. "|r", GameFontHighlight, W - 20)
		h = 60
	end
	cv:End((h or 0) + 10)
end

local dirty = false
function UI.Dirty()
	if dirty or not frame or not frame:IsShown() then return end
	dirty = true
	C_Timer.After(1, function() dirty = false; UI.Refresh() end)
end

function UI.Toggle()
	if not frame then Create() end
	frame:SetShown(not frame:IsShown())
end

function UI.Show(tab)
	if not frame then Create() end
	if tab then state.tab = tab end
	frame:Show()
	UI.Refresh()
end
