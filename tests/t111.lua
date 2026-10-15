-- v1.36.1: melhoria sem outLink aparecia na qualidade MAIS BAIXA.
-- Print do Rafael: no Saalla, o acessório 1 saía certo e o acessório 2 mostrava o item em ★2.
-- Causa: a tela só conhecia `c.outLink` (o link do scan, sempre Q5 — conferido: os 171 outLink
-- salvos estão todos em Q5). Candidato sem outLink caía em `SetItemByID`, que mostra a peça na
-- qualidade/nível mais baixos. O `CraftedStats` JÁ montava um link na qualidade máxima a partir da
-- peça equipada para ler os atributos, mas esse link era descartado (3º retorno ignorado).
dofile("harness11.lua")
local C = RR.Craft
local Inv = C.Invest
UnitName = function() return "Saalla" end; UnitFullName = function() return "Saalla", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end

-- link de peça equipada no formato da Midnight (bônus 3524, modificador 38 = qualidade)
local EQUIPADO = "|cnIQ4:|Hitem:259205::::::::90:103::13:1:3524:2:40:6778:38:3:::::|h[Peça equipada]|h|r"
local CANDIDATO = 259209

print("=== o link da peça equipada vira modelo na qualidade máxima ===")
local montado = Inv._BuildCraftedLink(EQUIPADO, CANDIDATO, 5)
print(string.format("  equipado  Q%s", tostring(Inv._LinkTier(EQUIPADO))))
print(string.format("  montado   Q%s  itemID=%s", tostring(Inv._LinkTier(montado)),
	tostring(montado and montado:match("item:(%d+)"))))

print("")
print("=== CraftedStats devolve o link que usou (3º retorno) ===")
-- tooltip só com uma linha de atributo, que é o que o ParseStats procura
C_TooltipInfo = C_TooltipInfo or {}
C_TooltipInfo.GetHyperlink = function(link)
	return { lines = { { leftText = "Equip: +45 Multicraft" } } }
end
ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:"

local semOutLink = { itemID = CANDIDATO, kind = "acc" }
local st, conhecido, usado = Inv._CraftedStats(semOutLink, { EQUIPADO }, "Blacksmithing")
print(string.format("  sem outLink: conhecido=%s  multicraft=%s  link devolvido=Q%s",
	tostring(conhecido), tostring(st and st.multicraft), tostring(usado and Inv._LinkTier(usado))))

local comOutLink = { itemID = CANDIDATO, kind = "acc",
	outLink = "|cnIQ4:|Hitem:259209::::::::90:103::13:1:3524:2:40:6780:38:5:::::|h[Do scan]|h|r" }
local st2, conhecido2, usado2 = Inv._CraftedStats(comOutLink, { EQUIPADO }, "Blacksmithing")
print(string.format("  com outLink: conhecido=%s  link devolvido=Q%s (tem de ser o do scan)",
	tostring(conhecido2), tostring(usado2 and Inv._LinkTier(usado2))))

print("")
print("=== a melhoria nunca deve ser mostrada abaixo da qualidade máxima ===")
local t1 = usado and Inv._LinkTier(usado)
local t2 = usado2 and Inv._LinkTier(usado2)
print(string.format("  sem outLink -> Q%s   com outLink -> Q%s", tostring(t1), tostring(t2)))

local ok = Inv._LinkTier(montado) == 5
	and montado and montado:match("item:(%d+)") == tostring(CANDIDATO)
	and conhecido == true and t1 == 5
	and conhecido2 == true and t2 == 5
print("")
print(ok and "OK: com ou sem outLink, a melhoria sai na qualidade maxima"
	or string.format("FALHA (montado=%s semOutLink=%s/%s comOutLink=%s/%s)",
		tostring(Inv._LinkTier(montado)), tostring(conhecido), tostring(t1),
		tostring(conhecido2), tostring(t2)))
