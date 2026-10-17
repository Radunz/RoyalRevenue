-- v1.38.3: preço que existe no papel e não se realiza.
-- Print do Rafael: uma fórmula de encantamento que caiu numa imersão foi lançada a 167.865g, "é um
-- ganho que não consigo realizar, a receita não vende por esse preço no goldrinn, e se colocar em
-- outros o valor vai a 1/4".
-- Dois caminhos levavam a isso, e os dois são a mesma ideia: UM número alto num mercado raso virando
-- "o preço".
dofile("harness11.lua")
local C = RR.Craft
local L = RR.Livro

print("=== Livro: valor do item = o MENOR entre o reino e a região ===")
-- o Livro é contabilidade: o que entra tem de ser o que dá para realizar
local PRECOS = {}
local origTSM = RR.TSMPrice
RR.TSMPrice = function(str, is)
	local id = tonumber(tostring(is):match("i:(%d+)") or "")
	local p = PRECOS[id]
	return p and p[str] or nil
end

local function valor(reino, regiao, minb)
	PRECOS[777] = { DBMarket = reino, DBRegionMarketAvg = regiao, DBMinBuyout = minb }
	return L.P._TSMValue(777)   -- o modulo de preco do Livro e ns.P, nao ns.Price
end
local casos = {
	{ nome = "o caso da imersão", reino = 1678654208, regiao = 420000000, esperado = 420000000 },
	{ nome = "região mais cara",  reino = 100000, regiao = 400000, esperado = 100000 },
	{ nome = "só o reino",        reino = 250000, regiao = nil,    esperado = 250000 },
	{ nome = "só a região",       reino = nil,    regiao = 250000, esperado = 250000 },
	{ nome = "só o menor anúncio", reino = nil,   regiao = nil,    minb = 90000, esperado = 90000 },
	{ nome = "sem preço nenhum",  reino = nil,    regiao = nil,    esperado = nil },
}
local okLivro = true
for _, c in ipairs(casos) do
	local v = valor(c.reino, c.regiao, c.minb)
	if v ~= c.esperado then okLivro = false end
	print(string.format("  %-20s reino=%-12s regiao=%-12s -> %-12s %s",
		c.nome, tostring(c.reino), tostring(c.regiao), tostring(v), v == c.esperado and "ok" or "FALHA"))
end
RR.TSMPrice = origTSM

print("")
print("=== Craft: anúncio muito acima do mercado não vira preço ===")
-- o saleSource ja faz min(reino, regiao), mas quando a regiao nao tem dado (equipamento, que e
-- precificado pelo item string com o nivel exato) o fallback vinha cru
LucroCraftDB.config = LucroCraftDB.config or {}
LucroCraftDB.config.saleMaxOverMarket = 2
local B = C.Pricing.BoundBySale
local casos2 = {
	{ nome = "no mercado",        v = 27540000, ref = 27540000, esperado = 27540000 },
	{ nome = "1,5x o mercado",    v = 41310000, ref = 27540000, esperado = 41310000 },
	{ nome = "3,7x (dado real)",  v = 100706500, ref = 27543200, esperado = 27543200 },
	{ nome = "sem referência",    v = 100706500, ref = nil,      esperado = 100706500 },
	{ nome = "sem valor",         v = nil,       ref = 27540000, esperado = nil },
}
local okCraft = true
for _, c in ipairs(casos2) do
	local v = B(c.v, c.ref)
	if v ~= c.esperado then okCraft = false end
	print(string.format("  %-18s anuncio=%-11s mercado=%-11s -> %-11s %s",
		c.nome, tostring(c.v), tostring(c.ref), tostring(v), v == c.esperado and "ok" or "FALHA"))
end

print("")
print("=== o teto é configurável (0 desliga) ===")
LucroCraftDB.config.saleMaxOverMarket = 0
local semTeto = B(100706500, 27543200)
LucroCraftDB.config.saleMaxOverMarket = 10
local teto10 = B(100706500, 27543200)
LucroCraftDB.config.saleMaxOverMarket = 2
print(string.format("  desligado -> %s (passa)   ·   teto 10x -> %s (passa, 3,7 < 10)",
	tostring(semTeto), tostring(teto10)))

print("")
local ok = okLivro and okCraft and semTeto == 100706500 and teto10 == 100706500
print(ok and "OK: o Livro usa o menor entre reino e regiao, e o Craft limita anuncio fora do mercado"
	or string.format("FALHA (livro=%s craft=%s)", tostring(okLivro), tostring(okCraft)))
