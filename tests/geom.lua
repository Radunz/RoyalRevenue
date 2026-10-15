-- Conferências de geometria de UI, para os testes.
-- O harness grava o SetPoint (ver o bloco Widget:SetPoint), então dá para afirmar onde cada widget
-- está. Isto existe porque a sobreposição do nome do item sobre a coluna Custo (v1.35.1) foi achada
-- por acidente, não por teste.
--
-- Só confere o que é inequívoco. Sobreposição horizontal entre textos NÃO entra: o canvas desenha
-- de propósito rótulo-à-esquerda e valor-à-direita na mesma faixa e com a mesma largura, então
-- qualquer regra genérica de sobreposição acusaria dezenas de falsos positivos.
local M = {}

local TOL = 2   -- folga de arredondamento

-- Percorre os widgets posicionados de um canvas (e dos sub-canvas dele).
local function Each(cv, fn, nome)
	for tipo, pool in pairs(cv.pools or {}) do
		local usados = (cv.used and cv.used[tipo]) or #pool
		for i = 1, math.min(usados, #pool) do
			local w = pool[i]
			if w and w.Rect then
				local x, y, x2, y2 = w:Rect()
				if x then fn(w, tipo, x, y, x2, y2, nome or "canvas") end
			end
		end
	end
	for chave, sub in pairs(cv) do
		if type(sub) == "table" and type(chave) == "string" and chave:match("^_%a")
			and sub.pools and sub ~= cv then
			Each(sub, fn, (nome or "canvas") .. chave)
		end
	end
end
M.Each = Each

local function Limpo(s)
	return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		:gsub("|T.-|t", "##"):gsub("|A.-|a", "##"))
end

-- Extensão horizontal real de um widget.
-- Largura 0 num texto NÃO é defeito: `Canvas:Text` faz SetWidth(width or 0) e no WoW isso quer
-- dizer "largura natural". Mas aí a extensão é a do texto, não zero — e é justamente assim que um
-- rótulo sem largura some para fora da tela. O harness dá 6px por caractere (GetStringWidth).
local function Extensao(w, tipo)
	local largura = w._w or 0
	if tipo == "text" and largura <= 0 then return #Limpo(w._text) * 6 end
	return largura
end

-- Nada desenhado fora da largura do canvas (nem à esquerda do zero).
function M.Check(cv, largura)
	local W = largura or cv:Width()
	local fora, total = {}, 0
	Each(cv, function(w, tipo, x, y, _, _, onde)
		total = total + 1
		local x2 = x + Extensao(w, tipo)
		if x < -TOL or x2 > W + TOL then
			table.insert(fora, string.format("%s/%s x=%d..%d (W=%d) %s", onde, tipo, x, x2, W,
				Limpo(w._text):sub(1, 30)))
		end
	end)
	return total, fora
end

-- Confere um conjunto de colunas { {x=, w=, nome=}, ... }: cada uma tem de terminar antes da seguinte.
function M.Colunas(cols)
	local ruins = {}
	table.sort(cols, function(a, b) return a.x < b.x end)
	for i = 1, #cols - 1 do
		local a, b = cols[i], cols[i + 1]
		if a.x + a.w > b.x + TOL then
			table.insert(ruins, string.format("%s (%d..%d) invade %s (comeca em %d)",
				a.nome, a.x, a.x + a.w, b.nome, b.x))
		end
	end
	return ruins
end

return M
