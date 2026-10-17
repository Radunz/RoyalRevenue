-- v1.37.6: a aba Investimento recalculava o lucro pelo preço de HOJE.
-- O desconto de tendência (v1.37.0) mudou a conta do Scanner para usar `saleProj`/`concSaleProj`,
-- mas o Invest refaz a conta por conta própria (`r.sale * q * (1 - cut) - cost`) e ficou no preço
-- cheio. Resultado: o Investimento mais otimista que as Receitas e o Plano, com a mesma receita.
--
-- É a MESMA classe de bug do spdShare x spdPct (v1.37.5): dois lugares respondendo a mesma
-- pergunta com regras diferentes. Este teste existe para travar a classe, não só o caso.
dofile("harness11.lua")
local C = RR.Craft
local S = C.Scanner
LucroCraftDB.config = LucroCraftDB.config or {}

local function receita(trend)
	return { recipeID = 1, name = "teste", qty = 1, expQty = 1, cost = 10000, expCost = 10000,
		sale = 100000, trend = trend, concSale = 200000, concTrend = trend,
		concCost = 100, concEff = 100, parts = {}, skill = 100, difficulty = 200 }
end

print("=== o Scanner desconta a tendência; a conta do Invest tem de usar o mesmo preço ===")
LucroCraftDB.config.trendDiscount = true
local cut = C.Cfg("ahCut")
for _, t in ipairs({ 0, -0.40 }) do
	local r = receita(t ~= 0 and t or nil)
	S.ComputeProfit(r)
	-- a conta que o Invest faz
	local invP = (r.concSaleProj or r.concSale) * (r.expQty or r.qty) * (1 - cut) - (r.expCost or r.cost)
	-- a conta antiga do Invest (preço cheio), para mostrar o tamanho da divergência
	local invAntigo = r.concSale * (r.expQty or r.qty) * (1 - cut) - (r.expCost or r.cost)
	print(string.format("  tendência %5s: Scanner=%9.0f  Invest=%9.0f  %s   (Invest antigo=%9.0f, %+.0f)",
		t == 0 and "0%" or string.format("%.0f%%", t * 100),
		r.concProfit, invP, math.abs(r.concProfit - invP) < 1 and "igual" or "DIVERGE",
		invAntigo, invAntigo - r.concProfit))
end

print("")
print("=== com a opção desligada, os dois voltam ao preço cheio ===")
LucroCraftDB.config.trendDiscount = false
local r = receita(-0.40)
S.ComputeProfit(r)
local invOff = (r.concSaleProj or r.concSale) * (r.expQty or r.qty) * (1 - cut) - (r.expCost or r.cost)
print(string.format("  Scanner=%.0f  Invest=%.0f  %s", r.concProfit, invOff,
	math.abs(r.concProfit - invOff) < 1 and "igual" or "DIVERGE"))
LucroCraftDB.config.trendDiscount = true

print("")
print("=== nenhum lugar do Craft calcula lucro de craft pelo preço cru ===")
-- varredura de fonte: `r.sale`/`r.concSale` multiplicado pela quantidade é a assinatura da conta
-- de lucro. Quem faz isso tem de usar a versão projetada.
local suspeitos = {}
for _, arq in ipairs({ "Invest", "InvestView", "Plan", "Queue", "UI", "Buy", "Sell", "RecipeShop" }) do
	local f = io.open((ADDON_DIR or "../") .. "Craft/" .. arq .. ".lua")
	if f then
		local src = f:read("*a"); f:close()
		local n = 0
		for linha in src:gmatch("[^\n]+") do
			n = n + 1
			-- ignora comentário
			-- a linha que mostra o preco de hoje DE PROPOSITO (rotulada como tal) e a excecao
			if not linha:match("^%s*%-%-") and not linha:find("preco de hoje de proposito", 1, true) then
				if linha:match("r%.concSale%s*%*") or linha:match("r%.sale%s*%*") then
					table.insert(suspeitos, string.format("%s.lua:%d  %s", arq, n, linha:gsub("^%s+", ""):sub(1, 62)))
				end
			end
		end
	end
end
if #suspeitos == 0 then
	print("  nenhum  ok")
else
	for _, l in ipairs(suspeitos) do print("  " .. l) end
end

print("")
local r2 = receita(-0.40)
S.ComputeProfit(r2)
local ok = math.abs(r2.concProfit - ((r2.concSaleProj or r2.concSale) * r2.expQty * (1 - cut) - r2.expCost)) < 1
	and #suspeitos == 0
print(ok and "OK: Scanner e Invest usam o mesmo preco, e ninguem calcula lucro pelo preco cru"
	or string.format("FALHA (suspeitos=%d)", #suspeitos))
