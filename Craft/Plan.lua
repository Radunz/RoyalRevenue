local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- Plano de concentração: para cada personagem/profissão salva, onde gastar a concentração
local Plan = {}
ns.Plan = Plan

local P = ns.Pricing

local function Short(char) return (char:match("^([^-]+)")) or char end

local countCache = {}   -- estoque por personagem: zera a cada desenho da aba (Materiais)
local DEFAULT_RATE = 10.5   -- pontos de concentração por hora (medido nos seus scans)
local HOLD_TOL = 0.05       -- receitas até 5% abaixo da melhor (ouro/ponto) contam como "tão boas quanto"

local function Rate()
	return tonumber(ns.Cfg("concPerHour")) or LucroCraftDB.concRate or DEFAULT_RATE
end

-- Concentração estimada agora: valor do último scan + regeneração desde então
local function EstimatedConc(e)
	local cur, max = e.conc.cur or 0, e.conc.max or 1000
	local hours = math.max(0, (time() - (e.time or time())) / 3600)
	return math.min(max, cur + Rate() * hours), hours
end

Plan.EstimatedConc = EstimatedConc
Plan.Rate = function() return Rate() end

local function Hours(h)
	if h < 1 then return string.format("%d min", math.max(1, math.floor(h * 60 + 0.5))) end
	if h < 48 then return string.format("%.0fh", h) end
	return string.format(L["%.1f dias"], h / 24)
end

-- Distribui uma quantidade de concentração nas receitas de maior ouro/ponto
-- Para COMEÇAR um craft o jogo exige o custo cheio (concCost); a devolução da engenhosidade vem depois.
-- Por isso: só faz o craft se sobrar o custo cheio; o gasto médio por craft é o custo efetivo (concEff).
local function Allocate(cands, conc)
	local left, gold, used = conc, 0, {}
	for _, r in ipairs(cands) do
		local per = r.concEff or r.concCost
		local full = r.concCost or per
		local n = 0
		if left >= full then n = math.floor((left - full) / per) + 1 end
		if n > 0 then
			left = left - n * per
			gold = gold + n * r.perConc * per
			table.insert(used, { row = r, crafts = n, gold = n * r.perConc * per, conc = n * per })
		end
	end
	return gold, used, left
end

-- Monta o plano a partir de tudo que está salvo (todos os personagens)
-- days (aba Compras): soma a concentração que regenera em N dias (supõe que você fabrica antes de a barra encher)
function Plan.Build(days)
	local total, list = 0, {}
	for char, entries in pairs(LucroCraftDB.chars or {}) do
		for profKey, e in pairs(entries) do
			if e.conc and e.conc.max and e.conc.max > 0 then
				local cands = {}
				for _, r in ipairs(e.rows or {}) do
					if r.perConc and r.perConc > 0 and not r.excluded and r.concSale and ns.Recommendable(r, true) then
						table.insert(cands, r)
					end
				end
				table.sort(cands, function(a, b) return a.perConc > b.perConc end)
				local est, age = EstimatedConc(e)
				local item = { char = char, prof = profKey, e = e, cands = cands, est = est, age = age }
				item.budget = est + math.max(0, tonumber(days) or 0) * 24 * Rate()
				item.regen = item.budget - est
				-- Segurar: concentração é o recurso escasso. Gastar pontos numa receita de menos ouro/ponto
				-- é prejuízo se dá para juntar até a melhor (a barra só enche até o máximo).
				-- Só entram a melhor receita que cabe na barra e as que rendem quase o mesmo (até HOLD_TOL abaixo).
				local hold = ns.Cfg("planHold") ~= false
				local best
				for _, r in ipairs(cands) do
					if (r.concCost or r.concEff or 0) <= (e.conc.max or 1000) then best = r; break end
				end
				local pool = cands
				if hold and best then
					pool = {}
					for _, r in ipairs(cands) do
						if r.perConc >= best.perConc * (1 - HOLD_TOL) and (r.concCost or r.concEff or 0) <= (e.conc.max or 1000) then
							table.insert(pool, r)
						end
					end
				end
				item.best = best
				item.gain, item.used, item.left = Allocate(pool, item.budget)
				item.fullGain = Allocate(pool, e.conc.max)
				if hold and best then
					local bestFull = best.concCost or best.concEff
					-- o que o plano antigo (guloso) faria agora
					local altGain, altUsed = Allocate(cands, item.budget)
					if #item.used == 0 and #altUsed > 0 then
						local pts = 0
						for _, u in ipairs(altUsed) do pts = pts + u.conc end
						item.hold = {
							row = best, need = bestFull, waitH = math.max(0, (bestFull - item.budget) / Rate()),
							altGain = altGain, altUsed = altUsed, altPts = pts,
							extra = pts * best.perConc - altGain,   -- os mesmos pontos rendendo na melhor receita
						}
					elseif #item.used > 0 and item.left >= 1 then
						-- sobra: guardada para o próximo craft da melhor (não vai para receita pior)
						item.kept = { pts = item.left, row = best, waitH = math.max(0, (bestFull - item.left) / Rate()) }
					end
				end
				local cheapest
				for _, r in ipairs(cands) do
					local per = r.concCost or r.concEff
					if not cheapest or per < cheapest then cheapest = per end
				end
				if cheapest and #item.used == 0 then item.nextIn = (cheapest - est) / Rate() end
				item.fullIn = (e.conc.max - est) / Rate()
				total = total + item.gain
				table.insert(list, item)
			end
		end
	end
	-- blocos personagem+profissão ordenados pelo lucro de gastar toda a concentração agora
	table.sort(list, function(a, b)
		if a.gain ~= b.gain then return a.gain > b.gain end
		return (a.fullGain or 0) > (b.fullGain or 0)
	end)
	return list, total
end

local function Render()
	local list, total = Plan.Build()
	local out = {}
	local function add(s) table.insert(out, s) end
	local G = P.FormatGold
	if #list == 0 then
		add(L["Nenhuma profissão com concentração salva. Abra suas profissões para escanear."])
	end
	local i = 0
	for _, it in ipairs(list) do
		if not it.cook then
		i = i + 1
		local e = it.e
		local head = it.gain > 0 and ("|cff55ff55" .. G(it.gain) .. "|r") or "|cff9d9d9d0g|r"
		add(string.format(L["%d. |cffffd100%s|r · %s — usando toda a concentração: %s"],
			i, Short(it.char), e.name or e.skillLine or "?", head))
		add(string.format(L["   |cff66ccffconcentração ~%d/%d|r |cff9d9d9d(%d no scan de há %s; enche em %s)|r"],
			math.floor(it.est), e.conc.max or 0, e.conc.cur or 0,
			ns.Alerts and (ns.Alerts.AgeText(e.time) .. "|cff9d9d9d") or Hours(it.age),
			(it.fullIn and it.fullIn > 0) and Hours(it.fullIn) or "—"))
		if #it.cands == 0 then
			add(L["   |cff9d9d9dnenhuma receita dá lucro com concentração|r"])
		elseif it.hold then
			add(string.format(L["   |cffd4af37SEGURE|r até %d de concentração (~%s) para %s · |cff55ff55+%s|r vs. gastar agora"],
				math.floor(it.hold.need + 0.5), Hours(it.hold.waitH), it.hold.row.name or "?", G(it.hold.extra)))
		elseif #it.used == 0 then
			add(string.format(L["   |cffff8800concentração insuficiente|r · próximo craft em %s · com a barra cheia: %s"],
				Hours(it.nextIn or 0), G(it.fullGain)))
		else
			for _, u in ipairs(it.used) do
				local r = u.row
				local flag = P.TrendFlag(r.concTrend)
				local warn = flag == "down" and string.format(L[" |cffff5555(preço caindo %s)|r"], P.TrendText(r.concTrend))
					or flag == "spike" and string.format(L[" |cffffd100(preço em pico %s)|r"], P.TrendText(r.concTrend)) or ""
				add(string.format(L["   %dx %s %s · %s/ponto · %d conc > %s"],
					u.crafts, r.name, ns.QIcon(r.concQuality or 2, r.maxQuality), G(r.perConc), math.floor(u.conc + 0.5), G(u.gold)) .. warn)
			end
			if it.left >= 1 then
				add(string.format(L["   |cff9d9d9dsobram ~%d de concentração (não fecham mais um craft lucrativo)|r"], math.floor(it.left)))
			end
		end
		add(" ")
		end
	end
	add(string.format(L["|cffffd100Total gastando toda a concentração de todos: %s|r"], G(total)))
	add(string.format(L["|cff9d9d9dConcentração estimada: último scan + %.1f/h (cada profissão tem a sua barra).|r"],
		Rate()))
	return table.concat(out, "\n")
end
Plan.GetText = Render

-- ===== Versão visual da aba =====
-- Agrupado por personagem: 1ª coluna = lucro do personagem (soma das profissões com concentração),
-- 2ª = personagem, 3ª = uma linha por profissão com concentração (até 2; Culinária fica fora: não usa concentração).
function Plan.Render(cv)
	wipe(countCache)
	local V = ns.Visual
	local G = P.FormatGold
	local list, total = Plan.Build()
	local W = cv:Width()
	local me = ns.CharKey()
	cv:Begin()
	cv:Text(8, 4, L["Total gastando toda a concentração de todos:"], GameFontNormal)
	cv:Text(8, 4, G(total, true), GameFontNormalLarge, W - 16, "RIGHT")
	cv:Text(8, 22, string.format(L["|cff9d9d9dcada profissão tem a sua barra · regenera %.1f/h · %% no ícone = tendência do preço (|cffff5555caindo|r|cff9d9d9d / |cffffd100em pico|r|cff9d9d9d) · passe o mouse para detalhes|r"], Rate()),
		GameFontDisableSmall)
	local y = 42
	if #list == 0 then
		cv:Text(8, y, L["Nenhuma profissão com concentração salva. Abra suas profissões para escanear."], GameFontHighlight)
		cv:End(y + 32)
		return
	end

	-- agrupa por personagem
	local groups, byChar = {}, {}
	for _, it in ipairs(list) do
		local g = byChar[it.char]
		if not g then
			g = { char = it.char, items = {}, gain = 0, full = 0, class = it.e.class }
			byChar[it.char] = g
			table.insert(groups, g)
		end
		table.insert(g.items, it)
		g.gain = g.gain + (it.gain or 0)
		g.full = g.full + (it.fullGain or 0)
		g.class = g.class or it.e.class
	end
	for _, g in ipairs(groups) do
		table.sort(g.items, function(a, b)
			if (a.cook or false) ~= (b.cook or false) then return not a.cook end   -- Culinária por último
			return (a.gain or 0) > (b.gain or 0)
		end)
	end
	table.sort(groups, function(a, b)
		if a.gain ~= b.gain then return a.gain > b.gain end
		return a.full > b.full
	end)

	-- cabeçalho das colunas
	local X_GOLD, X_CHAR, X_PROF = 8, 116, 240
	cv:Text(X_GOLD, y, L["|cff9d9d9dLucro|r"], GameFontDisableSmall, 100, "RIGHT")
	cv:Text(X_CHAR, y, L["|cff9d9d9dPersonagem|r"], GameFontDisableSmall)
	cv:Text(X_PROF, y, L["|cff9d9d9dProfissões|r"], GameFontDisableSmall)
	local MAT_W = 150
	local X_MAT = W - MAT_W - 4
	cv:Text(X_MAT, y, L["|cff9d9d9dMateriais|r"], GameFontDisableSmall, MAT_W, "CENTER")
	y = y + 16

	local SUB_H = 54
	for _, g in ipairs(groups) do
		local mine = g.char == me
		local h = #g.items * SUB_H
		cv:Box(0, y, W, h - 4, mine and 1 or 1, mine and 0.82 or 1, mine and 0 or 1, mine and 0.10 or 0.04)
		-- 1ª coluna: lucro do personagem
		local midY = y + math.floor(h / 2) - 14
		cv:Text(X_GOLD, midY, g.gain > 0 and G(g.gain, true) or "|cff9d9d9d0|r", GameFontNormalLarge, 100, "RIGHT")
		cv:Text(X_GOLD, midY + 20, L["gastando tudo agora"], GameFontDisableSmall, 100, "RIGHT")
		-- 2ª coluna: personagem
		cv:Text(X_CHAR, midY + 4, V.ClassName(g.char, g.class), GameFontNormal, 120)
		local realm = g.char:match("%-(.+)$")
		if realm then cv:Text(X_CHAR, midY + 20, "|cff9d9d9d" .. realm .. "|r", GameFontDisableSmall, 120) end

		-- 3ª coluna: uma linha por profissão
		for k, it in ipairs(g.items) do
			local e = it.e
			local sy = y + (k - 1) * SUB_H
			if k > 1 then cv:Box(X_PROF, sy - 2, W - X_PROF - 4, 1, 1, 1, 1, 0.08) end
			cv:Icon(X_PROF, sy + 6, 32, V.ProfIcon(it.char, e), { border = { 0.6, 0.6, 0.6 }, tip = function(tt)
				tt:SetText((e.name or "?") .. " — " .. it.char)
				tt:AddLine(string.format(L["varredura há %s"], ns.Alerts and ns.Alerts.AgeText(e.time) or "?"), 1, 1, 1)
				if it.cook then tt:AddLine(L["Sem concentração: o limite é quanto o mercado compra por dia."], 0.8, 0.8, 0.8, true) end
			end })
			cv:Text(X_PROF + 38, sy + 4, e.name or e.skillLine or "?", GameFontHighlightSmall, 150)
			local x = X_PROF + 300
			if it.cook then
				cv:Text(X_PROF + 38, sy + 22, L["|cff9d9d9dsem concentração · lucro por fabricação|r"], GameFontDisableSmall, 170)
				local best = it.cands[1]
				cv:Text(X_PROF + 196, sy + 8, best and G(best.profit, true) or "|cff9d9d9d—|r", GameFontNormal, 96, "RIGHT")
				cv:Text(X_PROF + 196, sy + 26, L["melhor por craft"], GameFontDisableSmall, 96, "RIGHT")
				if #it.cands == 0 then
					cv:Text(x, sy + 18, L["|cff9d9d9dnenhuma receita com lucro que venda o mínimo por dia|r"])
				end
				for _, r in ipairs(it.cands) do
					if x + 52 > W - 8 then break end
					cv:Icon(x + 6, sy + 4, 32, V.ItemIcon(r.itemID, r.icon), {
						count = r.spd and (r.spd >= 10 and root.Num(r.spd, 0) or root.Num(r.spd, 1)) or nil,
						corner = r.trend and P.TrendText(r.trend) or nil,
						link = r.itemID and select(2, C_Item.GetItemInfo(r.itemID)) or nil,
						tip = function(tt)
							if r.itemID then tt:SetItemByID(r.itemID) else tt:SetText(r.name or "?") end
							tt:AddLine(" ")
							tt:AddDoubleLine(L["Lucro por fabricação"], P.FormatMoney(r.profit), 1, 0.82, 0, 0.3, 1, 0.3)
							tt:AddDoubleLine(L["Vendas/dia"], r.spd and root.Num(r.spd, 1) or "?", 1, 0.82, 0, 1, 1, 1)
							tt:AddDoubleLine(L["Custo"], P.FormatMoney(r.cost), 1, 0.82, 0, 1, 1, 1)
							if r.trend then tt:AddDoubleLine(L["Tendência do preço"], P.TrendText(r.trend), 1, 0.82, 0, 1, 1, 1) end
							tt:AddLine(L["Número no ícone = vendas por dia"], 0.6, 0.6, 0.6)
						end })
					cv:Text(x, sy + 38, G(r.profit, true), GameFontHighlightSmall, 48, "CENTER")
					x = x + 52
				end
			else
				-- barra de concentração
				local pct = it.est / (e.conc.max or 1000)
				local col = pct >= 0.999 and { 1, 0.25, 0.25 } or pct >= (tonumber(ns.Cfg("alertConcPct")) or 0.9) and { 1, 0.6, 0.1 } or { 0.25, 0.6, 1 }
				local fullTxt = (it.fullIn and it.fullIn > 0) and (L["cheia em "] .. Hours(it.fullIn)) or L["cheia"]
				cv:Bar(X_PROF + 38, sy + 22, 150, 13, it.est, e.conc.max or 1000, col,
					string.format("%s/%d · %s", ns.ConcStr(math.floor(it.est), e.professionID), e.conc.max or 0, fullTxt), nil, function(tt)
						tt:SetText(L["Concentração"])
						tt:AddDoubleLine(L["Estimada agora"], string.format("%d / %d", math.floor(it.est), e.conc.max or 0), 1, 0.82, 0, 1, 1, 1)
						tt:AddDoubleLine(L["No último scan"], string.format(L["%d (há %s)"], e.conc.cur or 0, Hours(it.age)), 1, 0.82, 0, 1, 1, 1)
						tt:AddDoubleLine(L["Enche em"], (it.fullIn and it.fullIn > 0) and Hours(it.fullIn) or "—", 1, 0.82, 0, 1, 1, 1)
					end)
				cv:Text(X_PROF + 196, sy + 8, it.gain > 0 and G(it.gain, true) or "|cff9d9d9d0|r", GameFontNormal, 96, "RIGHT")
				-- fabricações
				if #it.cands == 0 then
					cv:Text(x, sy + 18, L["|cff9d9d9dnenhuma receita dá lucro com concentração|r"])
				elseif it.hold then
					Plan.DrawHold(cv, x, sy, X_MAT - x - 6, it)
				elseif #it.used == 0 then
					cv:Text(x, sy + 10, string.format(L["|cffff8800concentração insuficiente|r · próximo em %s"], Hours(it.nextIn or 0)))
					cv:Text(x, sy + 26, string.format(L["|cff9d9d9dcom a barra cheia: %s|r"], G(it.fullGain)))
				else
					for _, u in ipairs(it.used) do
						if x + 52 > X_MAT - 70 then break end
						local r = u.row
						cv:Icon(x + 6, sy + 4, 32, V.ItemIcon(r.concItemID, r.icon), {
							count = tostring(u.crafts), quality = ns.QIcon(r.concQuality or 2, r.maxQuality, 12),
							corner = r.concTrend and P.TrendText(r.concTrend) or nil,
							rarity = r.concItemID and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(r.concItemID) or nil,
							link = r.concItemID and select(2, C_Item.GetItemInfo(r.concItemID)) or nil,
							tip = function(tt)
								if r.concItemID then tt:SetItemByID(r.concItemID) else tt:SetText(r.name or "?") end
								tt:AddLine(" ")
								tt:AddDoubleLine(L["Fabricações"], tostring(u.crafts), 1, 0.82, 0, 1, 1, 1)
								tt:AddDoubleLine(L["Concentração gasta"], ns.ConcStr(math.floor(u.conc + 0.5), e.professionID), 1, 0.82, 0, 1, 1, 1)
								tt:AddDoubleLine(L["Lucro por ponto"], P.FormatMoney(r.perConc), 1, 0.82, 0, 1, 1, 1)
								tt:AddDoubleLine(L["Lucro total"], P.FormatMoney(u.gold), 1, 0.82, 0, 0.3, 1, 0.3)
								if r.concTrend then
									tt:AddDoubleLine(L["Tendência do preço"], P.TrendText(r.concTrend), 1, 0.82, 0, 1, 1, 1)
								end
							end,
						})
						cv:Text(x, sy + 38, G(u.gold, true), GameFontHighlightSmall, 48, "CENTER")
						x = x + 52
					end
					if it.kept then
						cv:Text(X_MAT - 70, sy + 12, string.format(L["|cffd4af37guarda ~%d|r"], math.floor(it.kept.pts)), GameFontDisableSmall, 62, "RIGHT")
						cv:Text(X_MAT - 70, sy + 26, string.format(L["|cff9d9d9dpróximo em %s|r"], Hours(it.kept.waitH)), GameFontDisableSmall, 62, "RIGHT")
						cv:Hit(X_MAT - 70, sy + 8, 62, 32, nil, function(tt)
							tt:SetText(L["Concentração guardada"])
							tt:AddLine(string.format(L["Os ~%d pontos que sobram ficam para o próximo %s (de novo em ~%s), em vez de ir para uma receita que rende menos por ponto."],
								math.floor(it.kept.pts), it.kept.row.name or "?", Hours(it.kept.waitH)), 1, 1, 1, true)
						end)
					elseif it.left >= 1 then
						cv:Text(X_MAT - 70, sy + 18, string.format(L["|cff9d9d9dsobram ~%d|r"], math.floor(it.left)), GameFontDisableSmall, 62, "RIGHT")
					end
					Plan.DrawMaterials(cv, X_MAT, sy + 2, MAT_W, it)
				end
			end
		end
		y = y + h
	end
	cv:End(y + 8)
end

-- ===== Segurar a concentração para a melhor receita =====
function Plan.DrawHold(cv, x, sy, w, it)
	local V, G = ns.Visual, P.FormatGold
	local hd = it.hold
	local r = hd.row
	local function tip(tt)
		tt:SetText(L["Segure a concentração"])
		tt:AddLine(string.format(L["%s rende %s por ponto, mas precisa de %d de concentração para começar."],
			r.name or "?", P.FormatMoney(r.perConc), math.floor(hd.need + 0.5)), 1, 1, 1, true)
		tt:AddDoubleLine(L["Concentração agora"], string.format("%d", math.floor(it.est)), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L["Chega lá em"], Hours(hd.waitH), 1, 0.82, 0, 1, 1, 1)
		tt:AddLine(" ")
		tt:AddLine(L["Se gastar agora (receitas que rendem menos por ponto):"], 1, 0.82, 0)
		for _, u in ipairs(hd.altUsed) do
			tt:AddDoubleLine(string.format(L["%dx %s"], u.crafts, u.row.name or "?"),
				string.format("%s · %s/%s", G(u.gold), P.FormatMoney(u.row.perConc), L["ponto"]), 1, 1, 1, 0.8, 0.8, 0.8)
		end
		tt:AddDoubleLine(L["Os mesmos pontos na melhor receita"], G(hd.altPts * r.perConc), 1, 0.82, 0, 0.3, 1, 0.3)
		tt:AddDoubleLine(L["Ganho por esperar"], "+" .. G(hd.extra), 1, 0.82, 0, 0.3, 1, 0.3)
		tt:AddLine(" ")
		tt:AddLine(L["Dá para desligar nas Configurações (Plano de concentração)."], 0.6, 0.6, 0.6, true)
	end
	cv:Icon(x + 6, sy + 4, 32, V.ItemIcon(r.concItemID, r.icon), {
		count = "1", desaturate = true, border = { 0.83, 0.69, 0.22 },
		quality = ns.QIcon(r.concQuality or 2, r.maxQuality, 12), tip = tip })
	cv:Box(x + 46, sy + 5, 64, 18, 0.83, 0.69, 0.22, 0.95)
	cv:Text(x + 46, sy + 8, "|cff14213d" .. L["SEGURE"] .. "|r", GameFontNormalSmall, 64, "CENTER")
	cv:Text(x + 116, sy + 8, string.format(L["até %s · ~%s"], ns.ConcStr(math.floor(hd.need + 0.5), it.e and it.e.professionID), Hours(hd.waitH)), GameFontHighlightSmall, w - 120)
	cv:Text(x + 46, sy + 28, string.format(L["|cff55ff55+%s|r vs. gastar agora em %s"], G(hd.extra), (hd.altUsed[1] and hd.altUsed[1].row.name) or "?"),
		GameFontDisableSmall, w - 50)
	cv:Hit(x + 46, sy + 4, w - 50, 40, nil, tip)
end

-- ===== Materiais: o personagem tem o que precisa para os crafts planejados? =====
-- Estoque do personagem: ao vivo se for o logado; senão o último retrato salvo (bolsa + banco + banco de reagentes).
-- Banco do bando: compartilhado (último retrato). Alts: soma dos outros personagens.
-- TSM guarda bolsa/banco/correio de cada alt ("Horde - Goldrinn" etc.)
local function TSMCount(char, id)
	if not (ns.Pricing.HasTSM and ns.Pricing.HasTSM() and TSM_API and TSM_API.GetBagQuantity) then return nil end
	local name, realm = char:match("^([^-]+)%-(.+)$")
	if not name then return nil end
	local is = "i:" .. id
	local best
	local myRealm = GetRealmName and GetRealmName():gsub("%s", "")
	local frs = { "Horde - " .. realm, "Alliance - " .. realm }
	if myRealm == realm:gsub("%s", "") then table.insert(frs, 1, false) end
	for _, fr in ipairs(frs) do
		local function q(fn)
			if not TSM_API[fn] then return 0 end
			local ok, v
			if fr then ok, v = pcall(TSM_API[fn], is, name, fr) else ok, v = pcall(TSM_API[fn], is, name) end
			return (ok and type(v) == "number") and v or 0
		end
		local n = q("GetBagQuantity") + q("GetBankQuantity") + q("GetMailQuantity")
		if n > (best or -1) then best = n end
		if n > 0 then break end
	end
	return best
end

local OwnCountRaw
local function OwnCount(char, id)
	local k = char .. "#" .. id
	local v = countCache[k]
	if v == nil then v = OwnCountRaw(char, id); countCache[k] = v end
	return v
end
function OwnCountRaw(char, id)
	if char == ns.CharKey() and C_Item and C_Item.GetItemCount then
		local ok, n = pcall(C_Item.GetItemCount, id, true, false, true, false)
		if ok and type(n) == "number" then return n end
	end
	local snap = LucroCraftDB.inv and LucroCraftDB.inv[char]
	local saved = snap and snap.items and snap.items[id] or 0
	local tsm = TSMCount(char, id)
	return math.max(saved, tsm or 0)
end
local function WarbandCount(id)
	if C_Item and C_Item.GetItemCount then
		local okA, all = pcall(C_Item.GetItemCount, id, true, false, true, true)
		local okO, own = pcall(C_Item.GetItemCount, id, true, false, true, false)
		if okA and okO and all and own then return math.max(0, all - own) end
	end
	local w = LucroCraftDB.invWarband
	return w and w.items and w.items[id] or 0
end
local function AltsCount(char, id)
	local n = 0
	for other in pairs(LucroCraftDB.inv or {}) do
		if other ~= char then n = n + OwnCount(other, id) end
	end
	return n
end

-- usado pela aba Compras (Buy.lua): mesmas contagens de estoque do plano
Plan.Count = { own = OwnCount, warband = WarbandCount, alts = AltsCount }
function Plan.ResetCounts() wipe(countCache) end

-- it = item do plano (uma profissão). Devolve { state = "ok"|"warband"|"alts"|"missing", lines = {...}, missing = n }
function Plan.Materials(it)
	local need, ids = {}, {}
	for _, u in ipairs(it.used or {}) do
		for _, p in ipairs(u.row.parts or {}) do
			if p.qty and p.qty > 0 then
				-- qualquer qualidade do reagente serve
				local list = (p.qualityItems and #p.qualityItems > 0) and p.qualityItems or { p.buyItem or p.itemID }
				local key = list[1]
				if key then
					need[key] = (need[key] or 0) + p.qty * u.crafts
					ids[key] = list
				end
			end
		end
	end
	local res = { state = "ok", lines = {}, missing = 0 }
	local rank = { ok = 1, warband = 2, alts = 3, missing = 4 }
	for key, n in pairs(need) do
		local own, wb, alts = 0, 0, 0
		for _, id in ipairs(ids[key]) do
			own = own + OwnCount(it.char, id)
			wb = wb + WarbandCount(id)
			alts = alts + AltsCount(it.char, id)
		end
		local st = own >= n and "ok" or (own + wb >= n) and "warband" or (own + wb + alts >= n) and "alts" or "missing"
		if rank[st] > rank[res.state] then res.state = st end
		if st == "missing" then res.missing = res.missing + 1 end
		table.insert(res.lines, { id = key, need = n, own = own, wb = wb, alts = alts, st = st })
	end
	table.sort(res.lines, function(a, b) return rank[a.st] > rank[b.st] end)
	return res
end

-- todos os crafts planejados da profissão já estão na fila manual?
local function InQueue(it)
	if not ns.Queue or not ns.Queue.Count then return false end
	for _, u in ipairs(it.used or {}) do
		if ns.Queue.Count(it.char, it.prof, u.row.recipeID, "conc") < u.crafts then return false end
	end
	return #(it.used or {}) > 0
end

local function MatTip(it, mat)
	return function(tt)
		tt:SetText(L["Materiais para os crafts planejados"])
		tt:AddLine(string.format(L["%s · estoque salvo de cada personagem; o logado é ao vivo"], (it.char:match("^([^-]+)")) or it.char), 0.7, 0.7, 0.7, true)
		tt:AddLine(" ")
		local COLORS = { ok = "|cff55ff55", warband = "|cff55ff55", alts = "|cffffd100", missing = "|cffff5555" }
		for _, l in ipairs(mat.lines) do
			local name = ns.Visual.ItemName(l.id)
			tt:AddDoubleLine(COLORS[l.st] .. name .. "|r", string.format(L["precisa %d · tem %d · bando %d · alts %d"], l.need, l.own, l.wb, l.alts), 1, 1, 1, 1, 1, 1)
		end
		tt:AddLine(" ")
		if InQueue(it) then
			tt:AddLine(L["Na fila de compras. Clique para tirar."], 0.4, 0.8, 1, true)
		else
			tt:AddLine(L["Clique para pôr estes crafts na fila: a aba Fila e compras mostra o que comprar."], 0.4, 0.8, 1, true)
		end
	end
end

local function ToggleQueue(it)
	if not ns.Queue then return end
	local inQ = InQueue(it)
	for _, u in ipairs(it.used or {}) do
		local have = ns.Queue.Count(it.char, it.prof, u.row.recipeID, "conc")
		if inQ then
			if have > 0 then ns.Queue.Add(it.char, it.prof, u.row.recipeID, "conc", -have) end
		elseif have < u.crafts then
			ns.Queue.Add(it.char, it.prof, u.row.recipeID, "conc", u.crafts - have)
		end
	end
	Plan.Refresh()
end

-- coluna "Materiais" de uma linha de profissão
function Plan.DrawMaterials(cv, x, y, w, it)
	local mat = Plan.Materials(it)
	local tip = MatTip(it, mat)
	local inQ = InQueue(it)
	if mat.state == "ok" or mat.state == "warband" then
		cv:Text(x, y + 6, mat.state == "ok" and L["|cff55ff55tem os materiais|r"] or L["|cff55ff55tem (banco do bando)|r"], GameFontHighlightSmall, w, "CENTER")
		cv:Button(x + 10, y + 22, w - 20, 18, inQ and L["Na fila"] or L["+ Fila"], function() ToggleQueue(it) end, tip)
		return
	end
	local txt = mat.state == "alts" and L["|cffffd100materiais nos alts|r"]
		or string.format(L["|cffff5555faltam %d materiais|r"], mat.missing)
	cv:Text(x, y + 6, txt, GameFontHighlightSmall, w, "CENTER")
	cv:Button(x + 10, y + 22, w - 20, 18, inQ and L["Na fila"] or L["+ Fila de compras"], function() ToggleQueue(it) end, tip)
end

-- Conteúdo exibido na aba 2 da janela principal
function Plan.Toggle()
	ns.UI.ShowTab(ns.UI.TAB.PLAN)
end

function Plan.Refresh()
	if ns.UI and ns.UI.RefreshTab then ns.UI.RefreshTab(ns.UI.TAB.PLAN) end
end
