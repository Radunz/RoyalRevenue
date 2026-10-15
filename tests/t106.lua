-- v1.35.0: na aba Fila, a lista de compras foi para BAIXO da fila (era à direita em janela larga)
-- e agora dá para excluir fabricações do plano e pedidos lidos, um a um. A lista de compras é
-- derivada da fila + pedidos, então excluir uma linha tira o material dela da lista de compras —
-- que é justamente o objetivo (tirar o que é caro demais ou que não se quer fazer).
dofile("harness11.lua")
local C = RR.Craft
local Q = C.Queue
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

print("=== a coluna do x existe e fica à direita do Pegar, sem invadir nada ===")
local ordem = { "item", "cost", "reag", "reward", "profit", "time", "claim", "del" }
local okCols = true
for _, QW in ipairs({ 1200, 750, 520 }) do
	local OC = Q.OrderCols(QW)
	local cresce, last = true, -1
	for _, k in ipairs(ordem) do
		if OC[k] < last then cresce = false end
		last = OC[k]
	end
	local cabe = (OC.del + OC.delW) <= QW - 4
	local semInvadir = (OC.claim + OC.w.claim) <= OC.del and (OC.item + OC.itemW) <= OC.cost
	if not (cresce and cabe and semInvadir) then okCols = false end
	print(string.format("  QW=%4d claim=%4d del=%4d(+%d)  %s", QW, OC.claim, OC.del, OC.delW,
		(cresce and cabe and semInvadir) and "ok" or "FALHA"))
end

print("")
print("=== excluir uma fabricação do plano ===")
LucroCraftDB.config = LucroCraftDB.config or {}
LucroCraftDB.config.queueIncludePlan = true
local function planItems()
	local out = {}
	for _, it in ipairs(Q.Build()) do if it.source == "plano" then table.insert(out, it) end end
	return out
end
local antes = planItems()
print("  fabricações do plano na fila: " .. #antes)
local alvo = antes[1]
if alvo then
	print("  alvo: " .. strip(alvo.row.name or "?") .. "  chave=" .. tostring(alvo.skipKey))
	print("  tem chave de exclusão: " .. tostring(alvo.skipKey ~= nil))
	-- o material dele tem de estar na lista de compras antes
	local matAntes = 0
	for _, s in ipairs(select(1, Q.Shopping(Q.ShopItems()))) do matAntes = matAntes + 1 end
	Q.SkipPlan(alvo.skipKey)
	local depois = planItems()
	local sumiu = true
	for _, it in ipairs(depois) do if it.skipKey == alvo.skipKey then sumiu = false end end
	local matDepois = 0
	for _, s in ipairs(select(1, Q.Shopping(Q.ShopItems()))) do matDepois = matDepois + 1 end
	print(string.format("  depois de excluir: %d fabricações (era %d) · saiu da fila=%s", #depois, #antes, tostring(sumiu)))
	print(string.format("  materiais na lista de compras: %d -> %d (%s)", matAntes, matDepois,
		matDepois <= matAntes and "não aumentou" or "AUMENTOU, errado"))
	print("  gravado no SavedVariables: " .. tostring(LucroCraftDB.queue.skip[alvo.skipKey] == true))
	-- o plano não repõe no próximo Build
	local rep = planItems()
	local voltou = false
	for _, it in ipairs(rep) do if it.skipKey == alvo.skipKey then voltou = true end end
	print("  o plano repõe no Build seguinte: " .. tostring(voltou) .. (voltou and "  FALHA" or "  ok"))
end

print("")
print("=== excluir um pedido lido ===")
Q.ordersChar = C.CharKey()
Q.orders = {
	{ id = 111, type = "Público", profit = 500, mat = 100, tip = 600, cut = 0, rew = 0, parts = {},
	  row = { recipeID = 1, name = "Pedido barato", parts = {} } },
	{ id = 222, type = "Público", profit = 300, mat = 90000, tip = 400, cut = 0, rew = 0, parts = {},
	  row = { recipeID = 2, name = "Pedido caro demais", parts = {} } },
}
print("  pedidos na lista: " .. #Q.orders)
Q.SkipOrder(Q.orders[2])
local ids = {}
for _, x in ipairs(Q.orders) do table.insert(ids, x.id) end
print("  depois de excluir o 222: [" .. table.concat(ids, ", ") .. "]")
print("  gravado: " .. tostring(LucroCraftDB.queue.skipOrd[222] ~= nil))

print("")
print("=== contagem e restauração ===")
local nPlan, nOrd = Q.SkipCount()
print(string.format("  excluídos: %d do plano · %d pedidos", nPlan, nOrd))
Q.ClearSkips()
local nPlan2, nOrd2 = Q.SkipCount()
print(string.format("  depois de Mostrar excluídos: %d do plano · %d pedidos", nPlan2, nOrd2))
local voltouPlano = #planItems() == #antes
print("  as fabricações do plano voltaram: " .. tostring(voltouPlano))

print("")
print("=== layout: a lista de compras fica ABAIXO da fila ===")
-- Antes: em janela com W >= 900 a lista de compras ia para a DIREITA da fila (duas colunas).
-- O harness renderiza a 960, que e justamente >= 900 — ou seja, no codigo antigo esta checagem
-- acusaria duas colunas. Agora tem de sair empilhada e em coluna cheia.
Q.orders = {}   -- os pedidos falsos acima nao tem todos os campos do render
C.UI.ShowTab(C.UI.TAB.QUEUE)
C.UI.RefreshTab(C.UI.TAB.QUEUE)
local g = LucroCraftFrame.canvases[C.UI.TAB.QUEUE]._layout
if not g then
	print("  sem geometria  FALHA")
else
	-- no canvas o y cresce para baixo: compras tem de comecar depois do fim da fila
	local abaixo = g.shopTop > g.qBottom
	local colunaCheia = g.shopX == 0 and g.shopW == g.w
	print(string.format("  W=%d (>=900, antes virava 2 colunas)", g.w))
	print(string.format("  fila: y=%d ate %d (altura interna %d)", g.qTop, g.qBottom, g.paneH))
	print(string.format("  compras: y=%d  x=%d  w=%d", g.shopTop, g.shopX, g.shopW))
	print("  compras abaixo da fila: " .. tostring(abaixo))
	print("  compras em coluna cheia: " .. tostring(colunaCheia))
	print((abaixo and colunaCheia) and "  OK: empilhada" or "  FALHA: ainda lado a lado")
end
