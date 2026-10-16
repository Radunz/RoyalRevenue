-- v1.37.5: a coluna "Vendas/dia (%)" tinha o PRÓPRIO denominador.
-- A v1.37.3 tirou o baú projetado da participação no ApplyABC, e com isso o tooltip e o filtro de
-- recomendação acertaram. Mas a coluna da lista calcula a porcentagem dela mesma (`v.spdPct`,
-- em BuildView) e só excluía item de coleta — então o Bouquet of Herbs continuava marcando 41%
-- lá. Duas contas para a mesma pergunta, com regras diferentes.
dofile("harness11.lua")
local C = RR.Craft
local UI = C.UI
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end

-- a lista abre na aba "conc"; o baú não usa concentração, então sem isto ele é filtrado fora
UI.ShowTab(UI.TAB.LIST)
UI.SetRecipeList("noconc")

-- põe um baú gigante em TODAS as profissões do personagem (a view lê só a atual), como o Bouquet:
-- sem preço de AH, com a venda e a velocidade vindas da projeção do conteúdo
local bau = {
	recipeID = 999901, name = "Bau de Teste", itemID = 999901, qty = 1,
	quality = 1, maxQuality = 2, cost = 300000, expCost = 300000, expQty = 1,
	sale = 720542, profit = 360236, spd = 209356.86, spdProjected = true,
	parts = {},
}
local entradas = {}
for _, e in pairs(LucroCraftDB.chars[C.CharKey()] or {}) do
	if type(e) == "table" and e.rows then table.insert(entradas, e); table.insert(e.rows, bau) end
end

local function participacoes()
	local views = UI._BuildView()
	local out, bauPct = {}, nil
	for _, lista in ipairs(views or {}) do
		for _, v in ipairs(lista) do
			if type(v.spd) == "number" and v.spdPct then
				out[#out + 1] = { nome = v.name, pct = v.spdPct }
			end
			if v.recipeID == 999901 then bauPct = v.spdPct end
		end
	end
	table.sort(out, function(a, b) return a.pct > b.pct end)
	return out, bauPct
end

print("=== com a marca de projeção (comportamento novo) ===")
local lista1, bau1 = participacoes()
print("  baú na coluna: " .. tostring(bau1) .. (bau1 == false and "   (fora da conta)" or ""))
for i = 1, math.min(4, #lista1) do
	print(string.format("     %-28s %.1f%%", tostring(lista1[i].nome):sub(1, 28), lista1[i].pct * 100))
end

print("")
print("=== sem a marca (é o que acontecia antes) ===")
bau.spdProjected = nil
local lista2, bau2 = participacoes()
print("  baú na coluna: " .. (bau2 and string.format("%.1f%%", bau2 * 100) or tostring(bau2)))
for i = 1, math.min(4, #lista2) do
	print(string.format("     %-28s %.1f%%", tostring(lista2[i].nome):sub(1, 28), lista2[i].pct * 100))
end
bau.spdProjected = true

print("")
print("=== item que não vai para a AH também fica fora ===")
local semAH = {
	recipeID = 999902, name = "Vinculado de Teste", itemID = 999902, qty = 1,
	quality = 1, maxQuality = 2, cost = 1000, expCost = 1000, expQty = 1,
	sale = 5000, profit = 1000, spd = 50000, notAuctionable = true, parts = {},
}
for _, e in ipairs(entradas) do table.insert(e.rows, semAH) end
local _, _ = participacoes()
local achouSemAH
for _, lista in ipairs(UI._BuildView() or {}) do
	for _, v in ipairs(lista) do if v.recipeID == 999902 then achouSemAH = v.spdPct end end
end
print("  vinculado na coluna: " .. tostring(achouSemAH) .. (achouSemAH == false and "   (fora da conta)" or ""))

print("")
local maiorAntes = lista2[1] and lista2[1].pct or 0
local ok = bau1 == false and bau2 and bau2 > 0.3 and achouSemAH == false
print(string.format("  antes o baú marcava %.1f%%; agora está fora", (bau2 or 0) * 100))
print("")
print(ok and "OK: a coluna exclui o bau projetado e o item sem AH, como o ApplyABC"
	or string.format("FALHA (comMarca=%s semMarca=%s semAH=%s)",
		tostring(bau1), tostring(bau2), tostring(achouSemAH)))
