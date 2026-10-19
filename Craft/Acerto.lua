local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L
local P = ns.Pricing
local Cfg = ns.Cfg

-- ===== Previsto x realizado =====
-- O addon prevê lucro o tempo todo e, até aqui, nada conferia se deu certo. Três correções de preço
-- saíram sem que nenhum número da tela mudasse, e um lucro de 200k do Uriuri era preço de outro
-- reino. O motor de comparação já existia no Sales.lua desde que a aba Vendas foi para o Livro:
-- ninguém chamava o GetRows(). Esta aba é a tela que faltava.
--
-- A pergunta: para cada item que eu VENDI de verdade na janela, quanto o addon tinha previsto?
--   previsto = r.sale (o preço que a aba Receitas usou para calcular o lucro)
--   obtido   = média do que a venda rendeu de fato (TSM Accounting, ou o correio da AH sem TSM)
--   erro     = obtido / previsto - 1
--   impacto  = quantidade x (obtido - previsto) x (1 - comissão)   <- o erro convertido em ouro
-- O impacto é o que importa: 300% de erro em 1 item vendido é ruído, 20% em 400 itens é dinheiro.
local A = {}
ns.Acerto = A

local cache, cacheT

local function Fechados()
	local c = LucroCraftDB.config
	if type(c) ~= "table" or type(c.acertoFechado) ~= "table" then return {} end
	return c.acertoFechado
end

function A.Toggle(char)
	LucroCraftDB.config = LucroCraftDB.config or {}
	local f = LucroCraftDB.config.acertoFechado
	if type(f) ~= "table" then f = {}; LucroCraftDB.config.acertoFechado = f end
	if f[char] then f[char] = nil else f[char] = true end
end

-- mediana sem mexer na lista de origem
local function Mediana(t)
	if #t == 0 then return nil end
	local c = {}
	for i, v in ipairs(t) do c[i] = v end
	table.sort(c)
	local m = math.floor(#c / 2)
	if #c % 2 == 1 then return c[m + 1] end
	return (c[m] + c[m + 1]) / 2
end

-- Linhas + resumo. O GetRows() relê o CSV inteiro do TSM, então o resultado fica guardado:
-- clicar numa coluna para reordenar não pode custar uma releitura.
function A.Dados(force)
	if cache and not force and cacheT and time() - cacheT < 60 then return cache.rows, cache.sum end
	local rows, sum = ns.Sales.GetRows()
	local cut = Cfg("ahCut") or 0
	local prev, obt, difs = 0, 0, {}
	local acima, abaixo, semPrev = 0, 0, 0
	for _, x in ipairs(rows) do
		if x.sale and x.sale > 0 and x.diff then
			x.impacto = x.qty * (x.avg - x.sale) * (1 - cut)
			prev = prev + x.qty * x.sale
			obt = obt + x.qty * x.avg
			table.insert(difs, math.abs(x.diff))
			if x.diff > 0 then acima = acima + 1 elseif x.diff < 0 then abaixo = abaixo + 1 end
		else
			semPrev = semPrev + 1
		end
	end
	-- erro ponderado pelo volume: é o erro da carteira, não a média de erros soltos
	sum.erroPond = prev > 0 and (obt / prev - 1) or nil
	sum.erroMed = Mediana(difs)
	sum.acima, sum.abaixo, sum.semPrev = acima, abaixo, semPrev
	sum.nItens = #rows
	cache, cacheT = { rows = rows, sum = sum }, time()
	return rows, sum
end

function A.Invalidate() cache, cacheT = nil, nil end

-- ===== ordenação =====
-- erro e impacto ordenam pelo MÓDULO: a tela existe para achar a previsão mais errada, e errar 40%
-- para baixo é tão interessante quanto 40% para cima.
local CHAVES = {
	qty = function(x) return x.qty or 0 end,
	perDay = function(x) return x.perDay or 0 end,
	sale = function(x) return x.sale or 0 end,
	avg = function(x) return x.avg or 0 end,
	diff = function(x) return x.diff and math.abs(x.diff) or -1 end,
	impacto = function(x) return x.impacto and math.abs(x.impacto) or -1 end,
	profit = function(x) return x.profit or 0 end,
	share = function(x) return x.share or -1 end,
	rate = function(x) return x.rate or -1 end,
}

function A.Sort()
	local s = LucroCraftDB.config and LucroCraftDB.config.acertoSort
	if type(s) ~= "table" or not CHAVES[s.key] then return { key = "impacto", desc = true } end
	return s
end

function A.SetSort(key)
	if not CHAVES[key] then return end
	local s = A.Sort()
	LucroCraftDB.config = LucroCraftDB.config or {}
	if s.key == key then
		LucroCraftDB.config.acertoSort = { key = key, desc = not s.desc }
	else
		LucroCraftDB.config.acertoSort = { key = key, desc = true }
	end
end

local function Ordena(linhas)
	local s = A.Sort()
	local f = CHAVES[s.key] or CHAVES.impacto
	table.sort(linhas, function(a, b)
		local va, vb = f(a), f(b)
		if va == vb then return (a.name or "") < (b.name or "") end
		if s.desc then return va > vb end
		return va < vb
	end)
end

-- agrupa por personagem, do que mais errou em ouro para o que menos errou
function A.Grupos(rows)
	local por, ordem = {}, {}
	for _, x in ipairs(rows) do
		local k = x.char or "?"
		if not por[k] then
			por[k] = { char = k, linhas = {}, profit = 0, impacto = 0, qty = 0 }
			table.insert(ordem, por[k])
		end
		local g = por[k]
		table.insert(g.linhas, x)
		g.profit = g.profit + (x.profit or 0)
		g.impacto = g.impacto + (x.impacto or 0)
		g.qty = g.qty + (x.qty or 0)
	end
	for _, g in ipairs(ordem) do Ordena(g.linhas) end
	table.sort(ordem, function(a, b)
		local va, vb = math.abs(a.impacto), math.abs(b.impacto)
		if va == vb then return a.char < b.char end
		return va > vb
	end)
	return ordem
end

-- ===== tela =====
local COL = { qty = 54, perDay = 58, sale = 92, avg = 92, diff = 68, impacto = 100, profit = 100, share = 60, rate = 58 }
local ORDEM = { "qty", "perDay", "sale", "avg", "diff", "impacto", "profit", "share", "rate" }
local GAP, NOME_MIN, ICON = 8, 150, 26
local LINHA = 30
A.LINHA, A.ICON = LINHA, ICON

-- Largura que a tabela precisa para nada se atropelar. O t129 varre as larguras e foi ele que
-- mostrou que abaixo disso o nome do item entrava na coluna Vend. — a mesma classe de defeito da
-- v1.35.1, agora pega antes de ir para o jogo. O UI.TabMinWidth devolve este número para a aba.
local function Necessario()
	local soma = 0
	for _, k in ipairs(ORDEM) do soma = soma + COL[k] end
	return 8 + ICON + 6 + NOME_MIN + GAP + soma + (#ORDEM - 1) * GAP + 8
end
A.MIN_W = Necessario()

function A.Cols(W)
	local c, x = { w = COL }, W - 8
	for i = #ORDEM, 1, -1 do
		local k = ORDEM[i]
		x = x - COL[k]
		c[k] = x
		x = x - GAP
	end
	c.nome = 8 + ICON + 6
	-- o nome fica com tudo que sobra; numa janela menor que o mínimo cede o que der, em vez de
	-- sair com largura negativa
	c.nomeW = math.max(40, c.qty - GAP - c.nome)
	return c
end

-- verde até 10% de erro, amarelo até 30%, vermelho acima: é a leitura de relance que interessa
local function CorErro(d)
	local a = math.abs(d)
	if a <= 0.10 then return "|cff55ff55" end
	if a <= 0.30 then return "|cffffd100" end
	return "|cffff5555"
end

local function Pct(v, comSinal)
	local s = string.format("%.0f%%", v * 100)
	if comSinal and v > 0 then s = "+" .. s end
	return s
end

function A.Render(cv)
	local W = cv:Width()
	local G, V = P.FormatGold, ns.Visual
	cv:Begin()
	local rows, sum = A.Dados()

	-- cabeçalho: o veredito em uma linha
	cv:Box(0, 0, W, 48, 0.17, 0.36, 0.66, 0.18)
	cv:Box(0, 0, 3, 48, 0.70, 0.13, 0.20, 0.9)
	cv:Text(8, 5, L["Previsto x realizado"], GameFontNormalLarge, W - 16)
	local sub
	if sum.erroPond then
		sub = string.format(L["%s itens vendidos em %d dias · a previsão errou %s%s|r no total (mediana %s por item)"],
			root.Num(sum.qty), sum.days or 0, CorErro(sum.erroPond), Pct(sum.erroPond, true),
			sum.erroMed and Pct(sum.erroMed) or "-")
	elseif sum.err then
		sub = "|cffff9e40" .. sum.err .. "|r"
	else
		sub = L["|cff9d9d9dNenhuma venda de item fabricável na janela: nada para conferir ainda.|r"]
	end
	cv:Text(8, 27, sub, GameFontDisableSmall, W - 16)

	if #rows == 0 then
		cv:Text(8, 56, L["|cff9d9d9dEsta tela compara o preço que o addon previu com o que a venda rendeu de fato. Precisa de venda registrada: o histórico do TSM Accounting, ou o correio da casa de leilões aberto depois de vender.|r"],
			GameFontHighlight, W - 16)
		cv:End(110)
		return
	end

	local y = 52
	-- resumo
	cv:Box(0, y, W, 34, 0.08, 0.13, 0.24, 0.6)
	local function Celula(x0, w, rotulo, valor)
		cv:Text(x0, y + 2, "|cff9d9d9d" .. rotulo .. "|r", GameFontDisableSmall, w)
		cv:Text(x0, y + 15, valor, GameFontNormalSmall, w)
	end
	local cw = math.floor((W - 16) / 5)
	Celula(8, cw, L["Receita líquida"], G(sum.net or 0))
	Celula(8 + cw, cw, L["Lucro realizado"], G(sum.profit or 0, true))
	Celula(8 + cw * 2, cw, L["Itens conferidos"],
		string.format(L["%d de %d receitas"], sum.nItens - sum.semPrev, sum.nItens))
	Celula(8 + cw * 3, cw, L["Acima do previsto"], string.format("|cff55ff55%d|r", sum.acima or 0))
	Celula(8 + cw * 4, cw, L["Abaixo do previsto"], string.format("|cffff5555%d|r", sum.abaixo or 0))
	cv:Hit(8 + cw * 2, y, cw, 34, nil, function(tt)
		tt:SetText(L["Itens conferidos"])
		tt:AddLine(L["Só entra na conta do erro o item que tinha preço previsto guardado na receita."], 1, 1, 1, true)
		if (sum.semPrev or 0) > 0 then
			tt:AddDoubleLine(L["Vendidos sem previsão"], tostring(sum.semPrev), 1, 0.82, 0, 1, 0.6, 0.2)
		end
	end)
	y = y + 38

	if sum.own then
		cv:Text(8, y, L["|cff9d9d9dSem o TSM Accounting: as vendas vêm do correio da casa de leilões que o addon leu.|r"],
			GameFontDisableSmall, W - 16)
		y = y + 16
	end

	-- cabeçalho da tabela
	local c = A.Cols(W)
	local s = A.Sort()
	local function Head(x0, w, key, rotulo, just, dica)
		local seta = (s.key == key) and (s.desc and " v" or " ^") or ""
		cv:Header(x0, y, w, 16, "|cffd4af37" .. L[rotulo] .. seta .. "|r", just or "RIGHT",
			{ onClick = function() A.SetSort(key); ns.UI.RefreshTab(ns.UI.TAB.ACERTO) end,
			  tip = function(tt)
				tt:SetText(L[rotulo])
				-- a dica chega JÁ traduzida: rótulo passado por variável é o ponto cego do
				-- loccheck, e foi assim que "Qualidade" chegou em inglês na tela do Simular
				if dica then tt:AddLine(dica, 1, 1, 1, true) end
				tt:AddLine(L["Clique: ordenar por esta coluna"], 1, 1, 1)
			  end })
	end
	cv:Text(c.nome, y + 2, "|cffd4af37" .. L["Item"] .. "|r", GameFontNormalSmall, c.nomeW)
	Head(c.qty, COL.qty, "qty", "Vend.", "RIGHT", L["Quantidade vendida na janela."])
	Head(c.perDay, COL.perDay, "perDay", "Por dia")
	Head(c.sale, COL.sale, "sale", "Previsto", "RIGHT", L["O preço que o addon usou para calcular o lucro desta receita."])
	Head(c.avg, COL.avg, "avg", "Obtido", "RIGHT", L["Média do que a venda rendeu de fato."])
	Head(c.diff, COL.diff, "diff", "Erro", "RIGHT", L["Obtido contra previsto. Ordena pelo módulo: errar para baixo conta igual."])
	Head(c.impacto, COL.impacto, "impacto", "Impacto", "RIGHT", L["O erro em ouro: quantidade x diferença, já sem a comissão."])
	Head(c.profit, COL.profit, "profit", "Lucro", "RIGHT", L["Receita líquida menos o custo de fabricar o que foi vendido."])
	Head(c.share, COL.share, "share", "Part.", "RIGHT", L["Sua parte das vendas do item no mercado."])
	Head(c.rate, COL.rate, "rate", "Taxa", "RIGHT", L["Quanto do que você anuncia acaba vendendo."])
	y = y + 18

	local fechados = Fechados()
	local i = 0
	for _, g in ipairs(A.Grupos(rows)) do
		local fechado = fechados[g.char] and true or false
		cv:Box(0, y, W, 18, 0.08, 0.13, 0.24, 0.95)
		cv:Box(0, y + 17, W, 1, 0.83, 0.69, 0.22, 0.6)
		cv:Text(8, y + 2, string.format("|cffd4af37%s %s|r |cff9d9d9d(%d)|r",
			fechado and "+" or "-", g.char, #g.linhas), GameFontNormalSmall, c.impacto - 16)
		cv:Text(c.impacto, y + 2, CorErro(1) .. G(g.impacto) .. "|r", GameFontDisableSmall, COL.impacto, "RIGHT")
		cv:Text(c.profit, y + 2, G(g.profit, true), GameFontNormalSmall, COL.profit, "RIGHT")
		cv:Hit(0, y, W, 18, function() A.Toggle(g.char); ns.UI.RefreshTab(ns.UI.TAB.ACERTO) end,
			function(tt)
				tt:SetText(g.char)
				tt:AddDoubleLine(L["Impacto em ouro"], G(g.impacto, true), 1, 0.82, 0, 1, 1, 1)
				tt:AddDoubleLine(L["Lucro realizado"], G(g.profit, true), 1, 0.82, 0, 1, 1, 1)
				tt:AddLine(L["Clique: abrir ou fechar o grupo"], 1, 1, 1)
			end)
		y = y + 22
		if not fechado then
			for _, x in ipairs(g.linhas) do
				i = i + 1
				root.Zebra(cv, i, 0, y - 1, W, LINHA)
				cv:Icon(8, y + 1, ICON, V.ItemIcon(x.itemID, x.icon), {
					qTier = x.quality, qMax = x.maxQuality,
					rarity = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(x.itemID) or nil,
					link = select(2, C_Item.GetItemInfo(x.itemID)) })
				local ty = y + math.floor((LINHA - 12) / 2)
				cv:Text(c.nome, ty, V.ItemName(x.itemID) or x.name or "?", GameFontHighlightSmall, c.nomeW)
				cv:Text(c.qty, ty, root.Num(x.qty), GameFontHighlightSmall, COL.qty, "RIGHT")
				cv:Text(c.perDay, ty, string.format("%.1f", x.perDay or 0), GameFontDisableSmall, COL.perDay, "RIGHT")
				cv:Text(c.sale, ty, x.sale and G(x.sale) or "-", GameFontDisableSmall, COL.sale, "RIGHT")
				cv:Text(c.avg, ty, G(x.avg), GameFontHighlightSmall, COL.avg, "RIGHT")
				cv:Text(c.diff, ty, x.diff and (CorErro(x.diff) .. Pct(x.diff, true) .. "|r") or "-",
					GameFontHighlightSmall, COL.diff, "RIGHT")
				cv:Text(c.impacto, ty, x.impacto and G(x.impacto, true) or "-",
					GameFontHighlightSmall, COL.impacto, "RIGHT")
				cv:Text(c.profit, ty, G(x.profit or 0, true), GameFontNormalSmall, COL.profit, "RIGHT")
				cv:Text(c.share, ty, x.share and Pct(x.share) or "-", GameFontDisableSmall, COL.share, "RIGHT")
				cv:Text(c.rate, ty, x.rate and Pct(x.rate) or "-", GameFontDisableSmall, COL.rate, "RIGHT")
				-- a área de clique começa depois do ícone, que tem o seu próprio tooltip
				cv:Hit(c.nome, y - 1, W - c.nome, LINHA,
					x.recipeID and function()
						if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
							pcall(C_TradeSkillUI.OpenRecipe, x.recipeID)
						end
						ns.UI.SelectedRecipeID = x.recipeID
					end or nil,
					function(tt)
						tt:SetText(x.name or "?")
						tt:AddLine(" ")
						tt:AddDoubleLine(L["Vendidos"],
							string.format(L["%s em %d dias"], root.Num(x.qty), sum.days or 0), 1, 0.82, 0, 1, 1, 1)
						tt:AddDoubleLine(L["Previsto"], x.sale and G(x.sale) or L["sem preço"], 1, 0.82, 0, 1, 1, 1)
						tt:AddDoubleLine(L["Obtido"], G(x.avg), 1, 0.82, 0, 1, 1, 1)
						if x.diff then
							local bom = math.abs(x.diff) <= 0.10
							tt:AddDoubleLine(L["Erro"], Pct(x.diff, true), 1, 0.82, 0,
								bom and 0.3 or 1, bom and 1 or 0.4, 0.3)
						end
						if x.impacto then
							tt:AddDoubleLine(L["Impacto em ouro"], G(x.impacto, true), 1, 0.82, 0, 1, 1, 1)
						end
						tt:AddLine(" ")
						tt:AddDoubleLine(L["Receita bruta"], G(x.gold), 1, 0.82, 0, 1, 1, 1)
						tt:AddDoubleLine(L["Custo unitário"], G(x.unit or 0), 1, 0.82, 0, 1, 1, 1)
						if x.npc then
							tt:AddLine(L["O vendedor vende mais barato que fabricar: o custo aqui é o do vendedor."], 1, 0.6, 0.2, true)
						end
						tt:AddDoubleLine(L["Lucro realizado"], G(x.profit or 0), 1, 0.82, 0, 1, 1, 1)
						if x.share then tt:AddDoubleLine(L["Participação"], Pct(x.share), 1, 0.82, 0, 1, 1, 1) end
						if x.rate then tt:AddDoubleLine(L["Taxa de venda"], Pct(x.rate), 1, 0.82, 0, 1, 1, 1) end
						if x.first and x.last then
							tt:AddDoubleLine(L["Período"],
								string.format("%s - %s", date("%d/%m", x.first), date("%d/%m", x.last)),
								1, 0.82, 0, 0.7, 0.7, 0.7)
						end
						if x.recipeID then tt:AddLine(L["Clique: abrir a receita na janela da profissão"], 1, 1, 1) end
					end)
				y = y + LINHA
			end
		end
	end

	if (sum.semPrev or 0) > 0 then
		cv:Text(8, y + 4, string.format(
			L["|cff9d9d9d%d itens vendidos não tinham preço previsto guardado e ficaram fora da conta do erro.|r"],
			sum.semPrev), GameFontDisableSmall, W - 16)
		y = y + 18
	end
	cv:End(y + 10)
end
