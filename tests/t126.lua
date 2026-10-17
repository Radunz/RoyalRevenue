-- v1.39.0: aba Simular — todas as combinações de qualidade dos reagentes.
-- "quero saber qual é a melhor opção entre craftar com os materiais mais vagabundos contra os
-- melhores, e todas as combinações, e quanto isso afeta a concentração e quantas vezes eu
-- conseguiria craftar mais vezes se mudar o material."
--
-- A combinação mexe em três coisas ao mesmo tempo — custo, perícia (logo a qualidade que sai de
-- graça) e custo de concentração — e é por isso que não dá para decidir de cabeça. Reagente barato
-- que exige mais concentração pode render MENOS no total, porque a concentração é o limite.
dofile("harness11.lua")
local C = RR.Craft
local Sim = C.Simulate
local G = dofile("geom.lua")
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end

-- receita de 2 slots com 2 qualidades cada = 4 combinações, para a conta caber na cabeça
local r = {
	recipeID = 4242, name = "Receita de Teste", itemID = 5001, qty = 1, quality = 1, maxQuality = 3,
	skill = 300, cost = 0, stats = { mc = 0, res = 0, ing = 0 },
	qIDs = { [1] = 5001, [2] = 5002, [3] = 5003 },
	parts = {
		{ slot = 1, itemID = 101, qty = 2, qualityItems = { 101, 102 } },
		{ slot = 2, itemID = 201, qty = 3, qualityItems = { 201, 202 } },
	},
}
local entry = { professionID = 2906, sig = "x", conc = { cur = 1000, max = 1000 }, time = time() }

-- preços: a qualidade 2 custa bem mais cara
local PRECO = { [101] = 10000, [102] = 50000, [201] = 10000, [202] = 50000,
	[5001] = 50000, [5002] = 300000, [5003] = 900000 }
local origCost, origSale = C.Pricing.Cost, C.Pricing.Sale
C.Pricing.Cost = function(id) return PRECO[id] end
C.Pricing.Sale = function(id) return PRECO[id] end

-- API do jogo: cada slot em qualidade alta dá +40 de perícia; mais perícia = melhor qualidade de
-- saída e concentração mais barata para subir a próxima
C_TradeSkillUI.GetCraftingOperationInfo = function(recipeID, tbl)
	local bonus = 0
	for _, t in ipairs(tbl or {}) do
		if (t.quantity or 0) > 0 and (t.reagent.itemID == 102 or t.reagent.itemID == 202) then bonus = bonus + 40 end
	end
	local skill = 300 + bonus
	local q = (skill >= 380 and 3) or (skill >= 340 and 2) or 1
	return { baseSkill = 300, bonusSkill = bonus, craftingQuality = q,
		-- a concentração cai MUITO com reagente melhor: é o que faz render mais crafts
		concentrationCost = (q < 3) and (500 - bonus * 5) or 0, ingenuityRefund = 0,
		upperSkillTreshold = 400 }
end

print("=== as 4 combinações ===")
local linhas, total, cortou, conc = Sim.Run(r, entry)
print(string.format("  %d linhas de %d · concentração disponível %s", #linhas, total, tostring(conc)))
Sim.SetSort("cost"); Sim.SetSort("cost")   -- garante ascendente
local s = Sim.Sort()
Sim.SortRows(linhas)
print(string.format("  %-8s %9s %6s %5s %6s %9s %7s %11s", "combo", "custo", "pericia", "qual", "conc", "lucro", "crafts", "total"))
for _, x in ipairs(linhas) do
	print(string.format("  %-8s %9.2f %6s %5s %6s %9.2f %7s %11.2f",
		table.concat(x.combo, "-"), (x.cost or 0) / 10000, tostring(x.skill), tostring(x.quality),
		tostring(x.conc), ((x.concProfit or x.profit) or 0) / 10000,
		tostring(x.crafts), (x.totalGold or 0) / 10000))
end

print("")
print("=== o ponto da tela: o mais barato NÃO é o melhor ===")
local barato, melhor
for _, x in ipairs(linhas) do
	if not barato or x.cost < barato.cost then barato = x end
	if not melhor or (x.totalGold or 0) > (melhor.totalGold or 0) then melhor = x end
end
print(string.format("  mais barato: combo %s · custo %.2fg · conc %s · %s crafts · total %.2fg",
	table.concat(barato.combo, "-"), barato.cost / 10000, tostring(barato.conc),
	tostring(barato.crafts), (barato.totalGold or 0) / 10000))
print(string.format("  melhor:      combo %s · custo %.2fg · conc %s · %s crafts · total %.2fg",
	table.concat(melhor.combo, "-"), melhor.cost / 10000, tostring(melhor.conc),
	tostring(melhor.crafts), (melhor.totalGold or 0) / 10000))
print(string.format("  diferença: %.2fg e %s crafts a mais",
	((melhor.totalGold or 0) - (barato.totalGold or 0)) / 10000,
	tostring((melhor.crafts or 0) - (barato.crafts or 0))))

print("")
print("=== combinação que não precisa de concentração ===")
local semConc
for _, x in ipairs(linhas) do if x.semConc then semConc = x end end
print("  existe: " .. tostring(semConc ~= nil) ..
	(semConc and ("  combo " .. table.concat(semConc.combo, "-") .. " sai direto na ★3") or ""))

print("")
print("=== receita sem escolha de qualidade: nada a simular ===")
local simples = { recipeID = 1, name = "simples", itemID = 1, qty = 1, parts = { { slot = 1, itemID = 9, qty = 1 } } }
local l2 = Sim.Run(simples, entry)
print("  linhas: " .. #l2 .. (#l2 == 0 and "  ok" or "  FALHA"))

print("")
print("=== a aba desenha ===")
C.auditOut = { row = r, e = entry, query = "teste", t = time(), lines = {} }
C.UI.ShowTab(C.UI.TAB.SIM)
C.UI.RefreshTab(C.UI.TAB.SIM)
local cv = LucroCraftFrame.canvases[C.UI.TAB.SIM]
local tot, fora = G.Check(cv)
print(string.format("  %d widgets · %d fora do canvas · %d textos", tot, #fora, cv.used.text or 0))
for i = 1, math.min(3, #fora) do print("     " .. fora[i]) end

C.Pricing.Cost, C.Pricing.Sale = origCost, origSale

print("")
-- a linha sem concentração não compete no mesmo eixo: o limite dela é material/ouro
local semConcLivre = semConc and semConc.crafts == nil and semConc.semConc
local ok = #linhas == 4 and barato ~= melhor
	and (melhor.totalGold or 0) > (barato.totalGold or 0)
	and (melhor.crafts or 0) > (barato.crafts or 0)
	and semConcLivre
	and #l2 == 0 and #fora == 0 and (cv.used.text or 0) > 10
print(ok and "OK: simula todas as combinacoes, mostra que o barato rende menos, e a aba desenha limpa"
	or string.format("FALHA (linhas=%d barato=%s melhor=%s fora=%d)",
		#linhas, tostring(barato and barato.totalGold), tostring(melhor and melhor.totalGold), #fora))
