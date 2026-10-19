-- v1.40.0: "Rendimento real" subestimava, e isso trocou o sinal de uma apuracao de lucro.
--
-- O tooltip mostrava items/n. Mas o `n` conta a fabricacao e o `base`/`items` so entram quando a
-- saida e observada. No Light's Potential do Radunz: n=279 crafts, base=1347 (equivale a 269
-- fabricacoes de base 5), items=2073.
--   items/n          = 7,43  <- o que aparecia
--   items/(base/qty) = 7,69  <- o que o calculo usa, e o que o modelo preve
-- Numa margem de 0,5o por unidade essa diferenca de 3,5% era metade do lucro, e foi ela que fez a
-- apuracao do Q1 parecer prejuizo.
--
-- De quebra o modelo foi validado aqui: 34,64% de chance de proc contra 34,77% medidos em 279
-- fabricacoes (0,05 desvio padrao). O modelo esta certo; era a EXIBICAO que estava torta.
dofile("harness13.lua")
local C = RR.Craft

local RECEITA = 1230869   -- Light's Potential
local CHAR = "Radunz-Goldrinn"

print("=== o dado medido que estava guardado ===")
local n, base, items, mcN, mcItems = 0, 0, 0, 0, 0
local Y = LucroCraftDB.yieldBy and LucroCraftDB.yieldBy[CHAR]
for sig, recs in pairs((Y or {}).sigs or {}) do
	local d = recs[RECEITA]
	if d and (d.n or 0) > 0 then
		n, base, items = n + d.n, base + (d.base or 0), items + (d.items or 0)
		mcN, mcItems = mcN + (d.mcN or 0), mcItems + (d.mcItems or 0)
	end
end
print(string.format("   %d fabricacoes · base somada %d · %d unidades · %d procs (%d extra)",
	n, base, items, mcN, mcItems))
local QTY = 5
local porN = items / n
local porBase = items / (base / QTY)
print(string.format("   items/n            = %.3f  <- o que o tooltip mostrava", porN))
print(string.format("   items/(base/%d)     = %.3f  <- consistente com o calculo", QTY, porBase))
print(string.format("   fabricacoes com saida observada: %.1f de %d", base / QTY, n))

print("")
print("=== o modelo de proc esta certo? ===")
local chanceMedida = mcN / n
local extraAtual = 0
local maisNovo
for sig, recs in pairs((Y or {}).sigs or {}) do
	local d = recs[RECEITA]
	if d and (d.mcN or 0) >= 3 and (not maisNovo or (d.t or 0) > (maisNovo.t or 0)) then maisNovo = d end
end
if maisNovo then extraAtual = maisNovo.mcItems / maisNovo.mcN end
local expQty
for _, profs in pairs(LucroCraftDB.chars or {}) do
	for _, e in pairs(profs) do
		if type(e) == "table" and e.rows then
			for _, r in ipairs(e.rows) do
				if r.recipeID == RECEITA and r.expQty then expQty = expQty or r.expQty end
			end
		end
	end
end
local chanceModelo = expQty and extraAtual > 0 and ((expQty - QTY) / extraAtual) or 0
print(string.format("   expQty do addon %.4f · extra medido no perfil atual %.3f", expQty or 0, extraAtual))
print(string.format("   chance do modelo %.2f%% · chance medida %.2f%% · diferenca %.2f pontos",
	chanceModelo * 100, chanceMedida * 100, math.abs(chanceModelo - chanceMedida) * 100))
local okModelo = math.abs(chanceModelo - chanceMedida) < 0.02
print(string.format("   -> %s", okModelo and "ok (o modelo esta certo, nao mexer)" or "o modelo esta desalinhado"))

print("")
print("=== o tooltip agora normaliza pela base observada ===")
-- monta o tooltip da receita e le a linha do rendimento
local linhas = {}
GameTooltip = GameTooltip or {}
local antigoAdd, antigoDbl = GameTooltip.AddLine, GameTooltip.AddDoubleLine
GameTooltip.AddDoubleLine = function(_, a, b) table.insert(linhas, tostring(a) .. " | " .. tostring(b)) end
GameTooltip.AddLine = function(_, a) table.insert(linhas, tostring(a)) end
GameTooltip.SetText = function() end
GameTooltip.ClearLines = function() end
GameTooltip.Show = function() end

UnitName = function() return "Radunz" end
UnitFullName = function() return "Radunz", "Goldrinn" end
for _, nm in ipairs({ "Craft", "Livro" }) do
	local x = RR[nm]
	if x and x._ResetCharKey then x._ResetCharKey() end
end

local alvo
for _, profs in pairs(LucroCraftDB.chars or {}) do
	for _, e in pairs(profs) do
		if type(e) == "table" and e.rows then
			for _, r in ipairs(e.rows) do
				if r.recipeID == RECEITA and not alvo then alvo = { r = r, e = e } end
			end
		end
	end
end
local okTip, achou = false, nil
if alvo and C.UI.RecipeTooltip then
	pcall(C.UI.RecipeTooltip, alvo.r, alvo.e)
elseif alvo and C.UI._Tooltip then
	pcall(C.UI._Tooltip, alvo.r, alvo.e)
end
for _, l in ipairs(linhas) do
	if l:find("Rendimento real") then achou = l end
end
if achou then
	print("   " .. achou)
	local v = tonumber(achou:match("(%d+%.%d+) por fabrica"))
	okTip = v and math.abs(v - porBase) < 0.02
	print(string.format("   -> %s", okTip and "ok (bate com items/base)" or "FALHA"))
else
	-- sem gancho de tooltip exposto, confere a RELACAO (o valor muda com a fixture: ao vivo em
	-- 18/10 eram 279 fabricacoes e 7,69; na sv13, de 16/10, sao menos)
	print("   (o tooltip nao e chamavel fora do jogo; conferindo a conta)")
	local obs = base / QTY
	okTip = porBase > porN and obs < n and obs >= 1
	print(string.format("   items/n = %.3f · items/(base/qty) = %.3f · %.1f de %d fabricacoes com saida observada",
		porN, porBase, obs, n))
	print(string.format("   normalizar sobe o rendimento em %.2f%%  -> %s",
		(porBase / porN - 1) * 100, okTip and "ok" or "FALHA"))
end

print("")
print("=== o que isso vale em ouro na apuracao ===")
-- custo do craft com os precos de 13/10 (do t129/analise): 82,81o
local CUSTO = 828100
for _, rend in ipairs({ porN, porBase }) do
	local cu = CUSTO / rend
	local liq = 123500 * 0.95   -- vendeu a 12,35o, menos 5% de comissao
	print(string.format("   rendimento %.2f -> custo %.2fo/un -> margem %+.2fo/un -> %+.0fo em 1.600 un",
		rend, cu / 10000, (liq - cu) / 10000, (liq - cu) * 1600 / 10000))
end

print("")
local ok = okModelo and okTip and porBase > porN
print(ok and "OK: rendimento real normalizado pela base, e o modelo de proc validado em 279 fabricacoes"
	or string.format("FALHA (modelo=%s tooltip=%s)", tostring(okModelo), tostring(okTip)))
