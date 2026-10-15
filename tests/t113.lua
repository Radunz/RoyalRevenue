-- v1.36.1: desconto pela tendência de preço (ideia 2, com liga/desliga).
-- O lucro era projetado pelo preço de HOJE, mas o item é vendido ao longo de dias. Com o preço
-- caindo isso superestima sempre — o Refreshing Serum do print estava com -23% de tendência e
-- mesmo assim entrava na conta pelo preço cheio. A tendência já era calculada (r.trend,
-- r.concTrend); só não entrava em lugar nenhum.
dofile("harness11.lua")
local C = RR.Craft
local S = C.Scanner
local Proj = S.Projected

LucroCraftDB.config = LucroCraftDB.config or {}

print("=== a regra (metade da tendencia, so na queda, piso -50%) ===")
local casos = {
	{ nome = "sem tendencia",        venda = 100000, t = nil,   esperado = 100000 },
	{ nome = "estavel (0%)",         venda = 100000, t = 0,     esperado = 100000 },
	{ nome = "subindo +40%",         venda = 100000, t = 0.40,  esperado = 100000 },
	{ nome = "caindo -10%",          venda = 100000, t = -0.10, esperado = 95000 },
	{ nome = "caindo -23% (o print)",venda = 100000, t = -0.23, esperado = 88500 },
	{ nome = "caindo -60%",          venda = 100000, t = -0.60, esperado = 70000 },
	{ nome = "caindo -300% (piso)",  venda = 100000, t = -3.00, esperado = 50000 },
}
LucroCraftDB.config.trendDiscount = true
local ok = true
for _, c in ipairs(casos) do
	local v = Proj(c.venda, c.t)
	local bate = math.abs(v - c.esperado) < 1
	if not bate then ok = false end
	print(string.format("  %-24s %8d -> %8.0f (esperado %d)  %s",
		c.nome, c.venda, v, c.esperado, bate and "ok" or "FALHA"))
end

print("")
print("=== desligado, nada muda ===")
LucroCraftDB.config.trendDiscount = false
local off = Proj(100000, -0.60)
print(string.format("  caindo -60%% com a opcao desligada -> %.0f  %s", off, off == 100000 and "ok" or "FALHA"))
LucroCraftDB.config.trendDiscount = true

print("")
print("=== efeito no lucro de uma receita ===")
local function receita(trend, concTrend)
	return { recipeID = 1, name = "teste", qty = 1, cost = 10000, sale = 100000, trend = trend,
		concSale = 200000, concTrend = concTrend, concCost = 100, parts = {} }
end
local a = receita(nil, nil)
local b = receita(-0.40, -0.40)
S.ComputeProfit(a)
S.ComputeProfit(b)
print(string.format("  sem tendencia: lucro=%.0f  concLucro=%.0f", a.profit, a.concProfit))
print(string.format("  caindo -40%%:   lucro=%.0f  concLucro=%.0f", b.profit, b.concProfit))
local caiu = b.profit < a.profit and b.concProfit < a.concProfit
print("  a queda reduz os dois: " .. tostring(caiu))

print("")
print("=== o preco de hoje continua intacto (e o que a tela mostra) ===")
print(string.format("  r.sale=%s (nao mexido)  r.saleProj=%.0f (usado na conta)",
	tostring(b.sale), b.saleProj))
local intacto = b.sale == 100000 and b.concSale == 200000

print("")
print((ok and off == 100000 and caiu and intacto)
	and "OK: desconta so na queda, respeita o piso, liga/desliga, e nao mexe no preco exibido"
	or "FALHA")
