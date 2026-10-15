-- v1.35.2: o alvo de qualidade depende de quem pede o craft.
-- Situação do print: um pedido de NPC pede qualidade 4 e o personagem já faz qualidade 4 sem
-- concentração — o addon mostrava concentração do mesmo jeito, porque o fallback do OrderConc
-- oferecia o custo de subir rumo à qualidade MÁXIMA. Para NPC isso é desperdício: ele paga igual.
-- Para pedido de JOGADOR a regra é a oposta: vale sempre buscar a máxima, então a opcional fica.
dofile("harness11.lua")
local C = RR.Craft
local Q = C.Queue
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end

-- receita escaneada: faz qualidade 4 sozinha, e tem custo de concentração para subir para 5
local receita = { recipeID = 777, name = "Peça de teste", parts = {},
	quality = 4, maxQuality = 5, concCost = 180, concQuality = 5 }

-- OrderPlan é quem diz se a concentração é OBRIGATÓRIA. Aqui a qualidade pedida já está alcançada,
-- então ele devolve "não obrigatória" — é o fallback do OrderConc que decidia o resto.
local planoReal = Q.OrderPlan
Q.OrderPlan = function(c)
	local q0 = 4                                  -- o personagem faz q4 sem concentração
	if (c.minQ or 0) <= 1 then return false, nil, q0, nil, true end
	if q0 >= (c.minQ or 0) then return false, nil, q0, nil, true end
	return true, 180, q0, q0 + 1, (q0 + 1) >= (c.minQ or 0)
end

local function avalia(rotulo, npc, minQ)
	local x = { row = receita, e = { professionID = 2906 }, npc = npc, minQ = minQ }
	local c = { row = receita, char = C.CharKey(), prof = 2906, minQ = minQ, npc = npc }
	Q.OrderConc(x, c)
	print(string.format("  %-34s minQ=%d  concPts=%-6s opcional=%-6s",
		rotulo, minQ, tostring(x.concPts), tostring(x.concOpt)))
	return x
end

print("=== pedido de NPC (Patrono): o alvo é a qualidade pedida ===")
local npc4 = avalia("NPC pede q4, personagem faz q4", true, 4)
local npc5 = avalia("NPC pede q5, personagem faz q4", true, 5)
local npc1 = avalia("NPC aceita qualquer qualidade", true, 1)

print("")
print("=== pedido de JOGADOR: o alvo é sempre a qualidade máxima ===")
local pl4 = avalia("jogador pede q4, personagem faz q4", false, 4)
local pl5 = avalia("jogador pede q5, personagem faz q4", false, 5)
local pl1 = avalia("jogador aceita qualquer qualidade", false, 1)

print("")
print("=== pedido pego antes desta versão (sem a marca npc) cai no tipo guardado ===")
local L = C.L
local function antigo(tipo, minQ)
	local x = { row = receita, e = { professionID = 2906 }, minQ = minQ }   -- sem x.npc
	local c = { row = receita, char = C.CharKey(), prof = 2906, minQ = minQ, type = tipo }
	Q.OrderConc(x, c)
	return x
end
local velhoNpc = antigo(L["Patrono"], 4)
local velhoPlayer = antigo(L["Público"], 4)
print(string.format("  type=%-10s -> concPts=%s", tostring(L["Patrono"]), tostring(velhoNpc.concPts)))
print(string.format("  type=%-10s -> concPts=%s", tostring(L["Público"]), tostring(velhoPlayer.concPts)))

Q.OrderPlan = planoReal

print("")
local ok = npc4.concPts == nil                    -- o caso do print: nada a mostrar
	and npc1.concPts == nil                        -- NPC sem exigência: nada a gastar
	and npc5.concPts == 180 and not npc5.concOpt    -- NPC exige mais: obrigatória
	and pl4.concPts == 180 and pl4.concOpt          -- jogador: opcional, vale subir
	and pl1.concPts == 180 and pl1.concOpt
	and pl5.concPts == 180 and not pl5.concOpt      -- jogador exigindo mais: obrigatória
	and velhoNpc.concPts == nil and velhoPlayer.concPts == 180
print(ok and "OK: NPC para na qualidade pedida, jogador vai para a maxima"
	or string.format("FALHA (npc4=%s npc1=%s npc5=%s/%s pl4=%s/%s pl1=%s pl5=%s/%s velho=%s/%s)",
		tostring(npc4.concPts), tostring(npc1.concPts), tostring(npc5.concPts), tostring(npc5.concOpt),
		tostring(pl4.concPts), tostring(pl4.concOpt), tostring(pl1.concPts),
		tostring(pl5.concPts), tostring(pl5.concOpt),
		tostring(velhoNpc.concPts), tostring(velhoPlayer.concPts)))
