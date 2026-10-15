-- v1.36.1: o plano passa a limitar os crafts ao que o mercado absorve (ideia 1).
-- Antes ele respondia "qual receita rende mais por ponto" e fabricava até a concentração acabar,
-- sem perguntar se dava para VENDER aquilo. Foi o que produziu o caso do print: 3 crafts de
-- Refreshing Serum = ~20 unidades de um item cuja qualidade 2 gira 276/dia na REGIÃO inteira.
dofile("harness11.lua")
local C = RR.Craft
local Plan = C.Plan

LucroCraftDB.config = LucroCraftDB.config or {}
local cfg = LucroCraftDB.config
cfg.capByMarket, cfg.absorbDays, cfg.absorbShare = true, 7, 0.05

-- receita no formato que o Allocate consome
local function rec(nome, concSpd, expQty)
	return { recipeID = 1, name = nome, concCost = 100, concEff = 100, perConc = 1000,
		concSpd = concSpd, expQty = expQty, qty = expQty }
end

print("=== o teto: vendas/dia x dias x fatia ===")
for _, c in ipairs({
	{ nome = "gira 276/dia (o print)", spd = 276 },
	{ nome = "gira 22.726/dia",        spd = 22726 },
	{ nome = "gira 10/dia",            spd = 10 },
	{ nome = "sem dado de giro",       spd = nil },
}) do
	local a = Plan.Absorcao(rec(c.nome, c.spd, 6.8))
	print(string.format("  %-24s -> absorve %s unidades em 7 dias",
		c.nome, a and string.format("%.0f", a) or "sem teto"))
end

print("")
print("=== quantos crafts o plano faz com 1000 de concentracao ===")
local function planeja(spd, expQty)
	local gold, used = Plan._Allocate and Plan._Allocate({ rec("x", spd, expQty) }, 1000) or nil
	return used
end
-- Allocate é local; o caminho público é o Plan.Build, então o efeito é medido pelo teto em si
for _, c in ipairs({
	{ nome = "gira 276/dia, 6,8 por craft", spd = 276, q = 6.8 },
	{ nome = "gira 22.726/dia, 6,8/craft",  spd = 22726, q = 6.8 },
}) do
	local a = Plan.Absorcao(rec(c.nome, c.spd, c.q))
	local teto = a and math.floor(a / c.q) or nil
	-- sem teto a concentracao daria 10 crafts (1000 / 100)
	local semTeto = 10
	print(string.format("  %-28s teto=%-6s crafts: %d -> %d",
		c.nome, tostring(teto), semTeto, teto and math.min(semTeto, teto) or semTeto))
end

print("")
print("=== desligado, volta ao comportamento antigo ===")
cfg.capByMarket = false
local semCap = Plan.Absorcao(rec("x", 276, 6.8))
print("  capByMarket=false -> " .. tostring(semCap) .. (semCap == nil and "  ok" or "  FALHA"))
cfg.capByMarket = true

print("")
print("=== os botoes respondem ===")
cfg.absorbDays = 30
local d30 = Plan.Absorcao(rec("x", 276, 6.8))
cfg.absorbDays = 7
cfg.absorbShare = 0.50
local f50 = Plan.Absorcao(rec("x", 276, 6.8))
cfg.absorbShare = 0.05
local base = Plan.Absorcao(rec("x", 276, 6.8))
print(string.format("  padrao(7d,5%%)=%.0f   30 dias=%.0f   fatia 50%%=%.0f", base, d30, f50))

print("")
local ok = Plan.Absorcao(rec("x", nil, 1)) == nil
	and math.abs(base - 276 * 7 * 0.05) < 0.01
	and math.abs(d30 - base * 30 / 7) < 0.01
	and math.abs(f50 - base * 10) < 0.01
	and semCap == nil
print(ok and "OK: teto proporcional ao giro, aos dias e a fatia; sem dado e com a opcao off nao limita"
	or "FALHA")
