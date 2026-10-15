-- v1.35.3: o filtro "% das vendas da profissão" (recoMinShare) media o item ERRADO na curva de
-- concentração. Receita com concentração vende o item de CIMA (r.concSpd), mas o gate olhava sempre
-- o item base (r.spdShare). No plano real do Radunz isso reprovava as 4 melhores por ouro/ponto e
-- deixava passar justo a pior: Refreshing Serum, cujo Q1 gira 6480/dia (2,06% da profissão) mas cujo
-- Q2 — o que você venderia — gira só 276/dia.
dofile("harness11.lua")
local C = RR.Craft
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
-- v1.36.1: com o teto de absorção ligado o filtro de participação é dispensado de propósito (o teto
-- responde a mesma pergunta melhor, em unidades). Este teste é sobre o filtro, então desliga o teto.
LucroCraftDB.config = LucroCraftDB.config or {}
LucroCraftDB.config.capByMarket = false

-- duas receitas espelhadas: uma gira no item base, a outra no item de cima
local function receita(nome, id, spd, concSpd)
	return { recipeID = id, name = nome, itemID = id, concItemID = id + 1000,
		quality = 1, maxQuality = 2, concQuality = 2, qty = 1, expQty = 1,
		cost = 10000, expCost = 10000, sale = 20000, profit = 10000,
		concSale = 200000, concProfit = 190000, concCost = 100, concEff = 100, perConc = 1900,
		spd = spd, concSpd = concSpd, parts = {} }
end
-- base forte / cima fraco  (era aprovada por engano)
local baseForte = receita("Base forte, cima fraco", 101, 6480, 276)
-- base fraco / cima forte  (era reprovada por engano)
local cimaForte = receita("Base fraca, cima forte", 201, 397, 22726)
-- enchimento: sem ele, com duas receitas qualquer uma passa de 1% e o gate nunca morde
local enchimento = receita("Enchimento", 301, 100000, 50000)
local rows = { baseForte, cimaForte, enchimento }

C.Scanner.ApplyABC(rows)

print("=== as duas participações são medidas em itens diferentes ===")
for _, r in ipairs(rows) do
	print(string.format("  %-24s spd=%7d concSpd=%6d  spdShare=%7.3f%%  concSpdShare=%7.3f%%",
		r.name, r.spd, r.concSpd, (r.spdShare or 0) * 100, (r.concSpdShare or 0) * 100))
end

print("")
print("=== o gate da concentração usa a participação do item de cima ===")
local ok1, por1 = C.Recommendable(baseForte, true)
local ok2, por2 = C.Recommendable(cimaForte, true)
print(string.format("  %-24s conc -> %s", baseForte.name, ok1 and "RECOMENDA" or ("corta: " .. tostring(por1))))
print(string.format("  %-24s conc -> %s", cimaForte.name, ok2 and "RECOMENDA" or ("corta: " .. tostring(por2))))

print("")
print("=== o gate SEM concentração continua no item base ===")
local okA = C.Recommendable(baseForte, false)
local okB = C.Recommendable(cimaForte, false)
print(string.format("  %-24s base -> %s", baseForte.name, okA and "RECOMENDA" or "corta"))
print(string.format("  %-24s base -> %s", cimaForte.name, okB and "RECOMENDA" or "corta"))

print("")
print("=== as duas participações somam 100% cada uma (denominadores separados) ===")
local sShare, cShare = 0, 0
for _, r in ipairs(rows) do sShare = sShare + (r.spdShare or 0); cShare = cShare + (r.concSpdShare or 0) end
print(string.format("  soma spdShare=%.3f  soma concSpdShare=%.3f", sShare, cShare))

print("")
-- a decisao tem de INVERTER entre as duas curvas: cada uma julga pelo seu proprio item
local ok = (ok1 == false) and (ok2 == true)        -- com concentracao: so a de cima forte
	and (okA == true) and (okB == false)            -- sem concentracao: so a de base forte
	and math.abs(sShare - 1) < 0.001 and math.abs(cShare - 1) < 0.001
print(ok and "OK: cada curva julga pelo item que ela realmente vende"
	or string.format("FALHA (conc: baseForte=%s cimaForte=%s | base: baseForte=%s cimaForte=%s | somas=%.3f/%.3f)",
		tostring(ok1), tostring(ok2), tostring(okA), tostring(okB), sShare, cShare))
