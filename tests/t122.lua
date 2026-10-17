-- v1.38.1: fonte única para número derivado (ideia 1).
-- Duas regras estavam escritas em mais de um lugar, e divergir foi a fábrica dos três últimos
-- números errados:
--   "esta linha conta na participação?"  → ApplyABC x BuildView  (deu os 41% do Bouquet)
--   "lucro = venda x qtd - taxa - custo" → Scanner, Invest x2, dois tooltips, a revenda de NPC
-- Agora as duas são `ns.CountsInShare` e `ns.NetProfit`, e este teste trava isso.
dofile("harness11.lua")
local C = RR.Craft

print("=== ns.CountsInShare: uma regra, as duas curvas ===")
local casos = {
	{ nome = "normal",                r = { spd = 100, concSpd = 100 }, base = true,  conc = true },
	{ nome = "coleta",                r = { spd = 100, concSpd = 100, gathered = true }, base = false, conc = false },
	{ nome = "sem AH (base)",         r = { spd = 100, concSpd = 100, notAuctionable = true }, base = false, conc = true },
	{ nome = "sem AH (qualidade 2)",  r = { spd = 100, concSpd = 100, concNotAuctionable = true }, base = true, conc = false },
	{ nome = "projetado (base)",      r = { spd = 100, concSpd = 100, spdProjected = true }, base = false, conc = true },
	{ nome = "projetado (qualid. 2)", r = { spd = 100, concSpd = 100, concProjected = true }, base = true, conc = false },
	{ nome = "sem vendas",            r = { spd = 0, concSpd = 0 }, base = false, conc = false },
	{ nome = "linha nil",             r = nil, base = false, conc = false },
}
local okRegra = true
for _, c in ipairs(casos) do
	local b, k = C.CountsInShare(c.r, false), C.CountsInShare(c.r, true)
	if b ~= c.base or k ~= c.conc then okRegra = false end
	print(string.format("  %-22s base=%-5s conc=%-5s  %s", c.nome, tostring(b), tostring(k),
		(b == c.base and k == c.conc) and "ok" or "FALHA"))
end

print("")
print("=== ns.NetProfit: uma fórmula ===")
local cut = C.Cfg("ahCut")
local v = C.NetProfit(100000, 2, 50000, 0.05)
print(string.format("  100000 x2, taxa 5%%, custo 50000 -> %.0f  (esperado %.0f)", v, 100000 * 2 * 0.95 - 50000))
print("  sem preço -> " .. tostring(C.NetProfit(nil, 2, 50000, 0.05)))
print("  usa a taxa da config quando não passam: " .. tostring(C.NetProfit(100000, 1, 0) == 100000 * (1 - cut)))

print("")
print("=== o Scanner usa a própria função (nada reescrito) ===")
local r = { recipeID = 1, name = "x", qty = 1, expQty = 2, cost = 50000, expCost = 50000,
	sale = 100000, concSale = 300000, concCost = 100, concEff = 100, parts = {} }
C.Scanner.ComputeProfit(r)
local esperado = C.NetProfit(r.saleProj, r.expQty, r.expCost)
local esperadoC = C.NetProfit(r.concSaleProj, r.expQty, r.expCost)
print(string.format("  profit=%.0f  esperado=%.0f  %s", r.profit, esperado,
	math.abs(r.profit - esperado) < 0.01 and "ok" or "FALHA"))
print(string.format("  concProfit=%.0f  esperado=%.0f  %s", r.concProfit, esperadoC,
	math.abs(r.concProfit - esperadoC) < 0.01 and "ok" or "FALHA"))

print("")
print("=== varredura: ninguém mais escreve a fórmula à mão ===")
-- `* (1 - cut)` fora da ns.NetProfit é a assinatura de alguém refazendo a conta.
-- Exceções marcadas no próprio código: o preço de hoje do tooltip e o "empata com" (por unidade).
local suspeitos = {}
for _, arq in ipairs({ "Scanner", "Invest", "InvestView", "UI", "Plan", "Queue" }) do
	local f = io.open((ADDON_DIR or "../") .. "Craft/" .. arq .. ".lua")
	if f then
		local src = f:read("*a"); f:close()
		local n = 0
		for linha in src:gmatch("[^\n]+") do
			n = n + 1
			local ignora = linha:match("^%s*%-%-")
				or linha:find("preco de hoje de proposito", 1, true)
				or linha:find("empata com", 1, true)
				or linha:find("return unit *", 1, true)
			if not ignora and (linha:find("(1 - cut)", 1, true) or linha:find("(1 - ahCut)", 1, true)) then
				table.insert(suspeitos, string.format("%s.lua:%d  %s", arq, n, linha:gsub("^%s+", ""):sub(1, 58)))
			end
		end
	end
end
if #suspeitos == 0 then print("  nenhum  ok") else for _, l in ipairs(suspeitos) do print("  " .. l) end end

print("")
local ok = okRegra and #suspeitos == 0
	and math.abs(r.profit - esperado) < 0.01 and math.abs(r.concProfit - esperadoC) < 0.01
	and C.NetProfit(nil, 1, 0) == nil
print(ok and "OK: uma regra de participacao e uma formula de lucro, chamadas por todo mundo"
	or string.format("FALHA (regra=%s suspeitos=%d)", tostring(okRegra), #suspeitos))
