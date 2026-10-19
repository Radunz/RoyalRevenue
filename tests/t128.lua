-- v1.40.0: TSM simulado no harness (ideia 2).
-- Três correções de preço saíram com ZERO diferença na suíte — o Livro passando a usar
-- min(reino, região) (v1.38.3), o teto do anúncio fora do mercado (v1.38.3) e o atlas da marca de
-- qualidade (v1.39.3). Não porque estivessem certas: sem TSM o `root.TSMPrice` devolve nil e o
-- caminho inteiro nunca roda. Este teste existe para esses caminhos passarem a ser exercitados.
dofile("harness13.lua")
local TSM = dofile("tsmstub.lua")
local C = RR.Craft

print("=== o stub sai dos precos que o proprio addon ja gravou ===")
local n = TSM.Install()
print(string.format("  %d itens com preco · HasTSM=%s", n, tostring(C.Pricing.HasTSM())))

print("")
print("=== a linguagem de preco do TSM ===")
TSM.Set(900001, { DBMarket = 100, DBMinBuyout = 40, DBRegionMarketAvg = 300, DBRegionSaleAvg = 250 })
TSM.Set(900002, { DBMarket = 100 })   -- sem dado da regiao
local casos = {
	{ "DBMarket", 900001, 100 },
	{ "first(DBMinBuyout, DBMarket)", 900001, 40 },
	{ "first(NaoExiste, DBMarket)", 900001, 100 },
	{ "min(DBMarket, DBRegionMarketAvg)", 900001, 100 },
	{ "max(DBMarket, DBRegionMarketAvg)", 900001, 300 },
	{ "DBMarket * 1000", 900001, 100000 },
	{ "min(first(DBMinBuyout, DBMarket), first(DBRegionSaleAvg, DBRegionMarketAvg))", 900001, 40 },
	-- sem o par da regiao o min() NAO resolve: e a suposicao com que o SaleByLink foi escrito
	{ "min(first(DBMinBuyout, DBMarket), first(DBRegionSaleAvg, DBRegionMarketAvg))", 900002, nil },
	{ "NaoExiste", 900001, nil },
}
local okLing = true
for _, c in ipairs(casos) do
	local v = TSM.Avalia(c[1], c[2])
	if v ~= c[3] then okLing = false end
	print(string.format("  %-62s -> %-8s %s", c[1]:sub(1, 62), tostring(v), v == c[3] and "ok" or "FALHA"))
end

print("")
print("=== Livro: o menor entre reino e regiao (v1.38.3, antes nao testado) ===")
local L = RR.Livro
TSM.Set(900003, { DBMarket = 1678654208, DBRegionMarketAvg = 420000000 })   -- o caso da imersao
local vLivro = L.P._TSMValue(900003)
print(string.format("  reino 167.865g · regiao 42.000g -> %.2fg  %s", (vLivro or 0) / 10000,
	vLivro == 420000000 and "ok (pegou o menor)" or "FALHA"))

print("")
print("=== Craft: teto do anuncio fora do mercado (v1.38.3, antes nao testado) ===")
LucroCraftDB.config = LucroCraftDB.config or {}
LucroCraftDB.config.saleMaxOverMarket = 2
-- DBMinBuyout 3,7x o DBMarket, como nos dados reais de Couro do Uriuri
local limitado = C.Pricing.BoundBySale(100706500, 27543200)
print(string.format("  anuncio 10.070g · mercado 2.754g (3,7x) -> %.2fg  %s", limitado / 10000,
	limitado == 27543200 and "ok (limitou ao mercado)" or "FALHA"))

print("")
print("=== Pricing.Sale sobre dado real da fixture ===")
local comPreco, semPreco = 0, 0
local exemplo
for _, profs in pairs(LucroCraftDB.chars or {}) do
	for _, e in pairs(profs) do
		if type(e) == "table" and e.rows then
			for _, r in ipairs(e.rows) do
				if r.itemID then
					local v = C.Pricing.Sale(r.itemID)
					if v then
						comPreco = comPreco + 1
						if not exemplo and TSM.Precos(r.itemID) then exemplo = { r = r, v = v } end
					else
						semPreco = semPreco + 1
					end
				end
			end
		end
	end
end
print(string.format("  receitas com preco de venda: %d · sem: %d", comPreco, semPreco))
if exemplo then
	local p = TSM.Precos(exemplo.r.itemID)
	print(string.format("  exemplo %s: Sale=%.2fg (reino %.2fg, regiao %.2fg)",
		tostring(exemplo.r.name):sub(1, 24), exemplo.v / 10000,
		(p.DBMinBuyout or p.DBMarket or 0) / 10000, (p.DBRegionSaleAvg or p.DBRegionMarketAvg or 0) / 10000))
	-- a venda nunca passa do menor entre reino e regiao, que e o que o saleSource promete
	local reino = p.DBMinBuyout or p.DBMarket
	local regiao = p.DBRegionSaleAvg or p.DBRegionMarketAvg
	local teto = (reino and regiao) and math.min(reino, regiao) or (reino or regiao)
	print(string.format("  respeita o teto do saleSource: %s", tostring(not teto or exemplo.v <= teto + 1)))
end

print("")
print("=== trocar o preco no meio do teste vale na hora ===")
-- O root.TSMPrice guarda o valor por 60 s e o GetTime do harness quase nao anda: sem zerar o cache
-- o segundo Set seria ignorado, e um teste futuro mediria o preco antigo achando que mudou.
TSM.Set(900004, { DBMarket = 10000 })
local antes = RR.TSMPrice("DBMarket", "i:900004")
TSM.Set(900004, { DBMarket = 70000 })
local depois = RR.TSMPrice("DBMarket", "i:900004")
print(string.format("  1g -> %s · troca para 7g -> %s  %s", tostring(antes and antes / 10000),
	tostring(depois and depois / 10000), (antes == 10000 and depois == 70000) and "ok" or "FALHA"))
local okCache = antes == 10000 and depois == 70000

print("")
print("=== Remove() devolve o estado anterior ===")
TSM.Remove()
print(string.format("  HasTSM depois do Remove: %s  %s", tostring(C.Pricing.HasTSM()),
	C.Pricing.HasTSM() == false and "ok" or "FALHA"))

print("")
local ok = okLing and n > 100 and vLivro == 420000000 and limitado == 27543200
	and comPreco > 100 and C.Pricing.HasTSM() == false and okCache
print(ok and "OK: TSM simulado cobre os caminhos de preco que antes nao rodavam no teste"
	or string.format("FALHA (ling=%s n=%d livro=%s teto=%s comPreco=%d)",
		tostring(okLing), n, tostring(vLivro), tostring(limitado), comPreco))
