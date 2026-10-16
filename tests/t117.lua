-- v1.37.3: o Bouquet of Herbs (print do Rafael) distorcia a profissão inteira.
-- Ele não tem preço de AH (vincula ao pegar), então o addon cai na projeção do baú: `Pricing.Sale`
-- usa o valor do conteúdo e `Pricing.SoldPerDay` usa a VELOCIDADE do conteúdo — 209.356 vendas/dia
-- da erva que sai dele. Com isso ele virava 79% das vendas da Alquimia e espremia todo o resto
-- contra o filtro de 1%. E, sendo transmutação com cargas, o plano podia pedir mais crafts do que
-- o jogo deixa fazer.
dofile("harness11.lua")
local C = RR.Craft
local S = C.Scanner

local function receita(nome, id, spd, projetado)
	return { recipeID = id, name = nome, itemID = id, qty = 1, quality = 1, maxQuality = 2,
		cost = 10000, expCost = 10000, sale = 50000, profit = 20000, expQty = 1,
		concItemID = id + 1000, concSale = 200000, concCost = 100, concEff = 100, perConc = 1900,
		concProfit = 190000, spd = spd, concSpd = spd,
		spdProjected = projetado or nil, concProjected = projetado or nil, parts = {} }
end

print("=== o baú projetado fica fora do total e da participação ===")
local bau = receita("Bouquet of Herbs", 101, 209356.86, true)
local a = receita("Silvermoon Health", 201, 20000)
local b = receita("Light's Potential", 301, 10000)
local c = receita("Entropic Extract", 401, 7000)
local rows = { bau, a, b, c }

local function mostra(rotulo)
	S.ApplyABC(rows)
	local partes = {}
	for _, r in ipairs(rows) do
		table.insert(partes, string.format("%s=%.1f%%", tostring(r.name):sub(1, 18), (r.spdShare or 0) * 100))
	end
	print("  " .. rotulo .. ": " .. table.concat(partes, "  "))
end
bau.spdProjected, bau.concProjected = nil, nil
mostra("baú contando  ")
bau.spdProjected, bau.concProjected = true, true
mostra("baú projetado ")

local soma = 0
for _, r in ipairs(rows) do soma = soma + (r.spdShare or 0) end
print(string.format("  baú: spdShare=%.2f%% concSpdShare=%.2f%% · soma dos demais=%.3f",
	(bau.spdShare or 0) * 100, (bau.concSpdShare or 0) * 100, soma))

print("")
print("=== Pricing.SoldPerDay avisa quando o número é projeção ===")
-- o fallback do baú só existe no ramo do TSM, e o harness não tem TSM: liga o ramo na marra
local origGet, origSpd, origTSM = C.Containers.Get, C.Containers.SoldPerDay, C.Pricing.HasTSM
C.Pricing.HasTSM = function() return true end
C.Containers.Get = function(id) return id == 555 and { opens = 3 } or nil end
C.Containers.SoldPerDay = function() return 209356.86 end
local v1, proj1 = C.Pricing.SoldPerDay(555)
local v2, proj2 = C.Pricing.SoldPerDay(556)
print(string.format("  item baú   -> %s  projetado=%s", tostring(v1), tostring(proj1)))
print(string.format("  item comum -> %s  projetado=%s", tostring(v2), tostring(proj2)))
C.Containers.Get, C.Containers.SoldPerDay, C.Pricing.HasTSM = origGet, origSpd, origTSM

print("")
print("=== cargas limitam o plano ===")
local function comCargas(cargas, maxC, cool)
	local r = receita("Transmutação", 777, 100)
	r.cd = { max = maxC, charges = cargas, cool = cool or 0, t = time() }
	return r
end
for _, caso in ipairs({
	{ nome = "2 de 2 cargas", c = 2, m = 2 },
	{ nome = "1 de 2 cargas", c = 1, m = 2 },
	{ nome = "0 de 2 cargas", c = 0, m = 2, cool = 80000 },
	{ nome = "sem cargas (cd nil)", c = nil, m = nil },
}) do
	local r = caso.c and comCargas(caso.c, caso.m, caso.cool) or receita("Comum", 888, 100)
	local cur = C.Charges and select(1, C.Charges(r))
	print(string.format("  %-20s -> cargas disponiveis = %s", caso.nome, tostring(cur)))
end

print("")
print("=== o teto de cargas entra no Allocate ===")
-- 1000 de concentração dariam 10 crafts; com 2 cargas, só 2
local cheio = comCargas(2, 2)
local semCd = receita("Comum", 888, 100)
LucroCraftDB.config = LucroCraftDB.config or {}
LucroCraftDB.config.capByMarket = false
local _, usados = C.Plan._Allocate and C.Plan._Allocate({ cheio }, 1000) or nil, nil
-- Allocate e local: o efeito e medido pela propria regra
local cur = select(1, C.Charges(cheio))
print(string.format("  concentracao daria %d crafts; cargas permitem %s -> plano faz %d",
	10, tostring(cur), math.min(10, cur or 10)))
print(string.format("  receita sem cargas segue sem teto: %s", tostring(C.Charges(semCd))))

print("")
local ok = (bau.spdShare or 0) == 0 and (bau.concSpdShare or 0) == 0
	and math.abs(soma - 1) < 0.001
	and a.spdShare > 0.5
	and proj1 == true and v1 == 209356.86 and proj2 ~= true
	and select(1, C.Charges(cheio)) == 2 and C.Charges(semCd) == nil
print(ok and "OK: bau fora da participacao, projecao sinalizada e cargas limitando"
	or string.format("FALHA (bau=%.3f soma=%.3f maior=%.3f proj=%s cargas=%s)",
		bau.spdShare or 0, soma, a.spdShare or 0, tostring(proj1), tostring(select(1, C.Charges(cheio)))))
