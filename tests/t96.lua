-- v1.29.0: ícone da concentração (moeda da profissão, como no jogo/CraftSim), concentração dos
-- pedidos mostrada mesmo quando é opcional, e ícone das recompensas em MOEDA (Moxie).
dofile("harness11.lua")
local C = RR.Craft
local Q = C.Queue

print("=== ns.ConcStr ===")
print("sem API de moeda:        [" .. C.ConcStr(179, 2906) .. "]")
C_TradeSkillUI.GetConcentrationCurrencyID = function(sl) return sl == 2906 and 3300 or nil end
C_CurrencyInfo = { GetCurrencyInfo = function(id) return { name = "Concentration", iconFileID = 4643986 } end }
C.Pricing._ClearConcCache = nil
-- o cache guarda por linha de profissão: usa outra linha para ver a API funcionando
C_TradeSkillUI.GetConcentrationCurrencyID = function(sl) return 3300 end
print("com API (linha nova):    [" .. C.ConcStr(179, 2913) .. "]")
print("só o ícone (n = nil):    [" .. C.ConcStr(nil, 2913) .. "]")
print("profissão desconhecida:  [" .. C.ConcStr(42, nil) .. "]")

print("")
print("=== pedido: concentração obrigatória x opcional ===")
-- minQuality 2 e a qualidade natural é 1 -> precisa de concentração (obrigatória)
Q.OrderPlan = function(c) return true, 177, 1, 2, true end
local obrig = { row = { concCost = 179, quality = 1, maxQuality = 2 } }
Q.OrderConc(obrig, { minQ = 2, char = "Madunz-Goldrinn", prof = 2906 })
print(string.format("obrigatória: concPts=%s concOpt=%s", tostring(obrig.concPts), tostring(obrig.concOpt)))

-- minQuality 1: a qualidade natural já serve, mas a receita TEM custo de concentração
Q.OrderPlan = function(c) return false, nil, 1, nil, true end
local opc = { row = { concCost = 179, quality = 1, maxQuality = 2 } }
Q.OrderConc(opc, { minQ = 1, char = "Madunz-Goldrinn", prof = 2906 })
print(string.format("opcional:    concPts=%s concOpt=%s", tostring(opc.concPts), tostring(opc.concOpt)))

-- receita que já sai na qualidade máxima: concentração não ajuda, não mostra nada
local maxq = { row = { concCost = 179, quality = 2, maxQuality = 2 } }
Q.OrderConc(maxq, { minQ = 1, char = "Madunz-Goldrinn", prof = 2906 })
print(string.format("já no máximo: concPts=%s concOpt=%s", tostring(maxq.concPts), tostring(maxq.concOpt)))

print("")
print("=== o lucro só desconta a concentração obrigatória ===")
for _, caso in ipairs({ { "obrigatória", obrig }, { "opcional", opc } }) do
	local nome, x = caso[1], caso[2]
	local lucro = 1000000
	if x.concValue and not x.concOpt then lucro = lucro - x.concValue end
	print(string.format("  %-12s lucro %s (concValue=%s)", nome, tostring(lucro), tostring(x.concValue)))
end
