-- v1.35.1: a concentração saiu da faixa de reagentes e ganhou coluna própria na tabela de pedidos.
-- Antes ela disputava o mesmo espaço dos reagentes (`if ... and gx <= gmax`), então num pedido com
-- muitos reagentes o ícone simplesmente não era desenhado — sumia a informação que mais pesa na
-- decisão. E a concentração OPCIONAL nunca aparecia na tabela, só no tooltip do item.
dofile("harness11.lua")
local C = RR.Craft
local Q = C.Queue
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end

print("=== a coluna Conc fica entre Reagentes e Recompensa, sem sobrepor ===")
local ordem = { "item", "cost", "reag", "conc", "reward", "profit", "time", "claim", "del" }
local okGeo = true
for _, QW in ipairs({ 1200, 946, 750, 520 }) do
	local OC = Q.OrderCols(QW)
	local cresce, last, pos = true, -1, {}
	for _, k in ipairs(ordem) do
		if OC[k] < last then cresce = false end
		last = OC[k]
		table.insert(pos, string.format("%s=%d", k, OC[k]))
	end
	-- cada coluna tem de terminar antes do início da próxima
	local semSobrepor = (OC.reag + OC.w.reag) <= OC.conc
		and (OC.conc + OC.w.conc) <= OC.reward
		and (OC.item + OC.itemW) <= OC.cost
		and (OC.del + OC.delW) <= QW - 4
	if not (cresce and semSobrepor) then okGeo = false end
	print(string.format("  QW=%4d conc=%4d(w=%d)  %s", QW, OC.conc, OC.w.conc,
		(cresce and semSobrepor) and "ok" or "FALHA"))
end
print("  " .. (okGeo and "OK: na ordem e sem sobreposição em todas as larguras" or "FALHA na geometria"))

print("")
print("=== ordenar pela coluna Conc (opcional conta como 0) ===")
local function ped(id, nome, pts, opt)
	return { id = id, type = "Público", profit = 1000, mat = 100, tip = 1000, cut = 0, rew = 0,
		rewList = {}, parts = {}, exp = 1791900000 + id, concPts = pts, concOpt = opt,
		concValue = pts and pts * 100 or nil,
		order = { orderID = id, spellID = id, itemID = 210796 },
		row = { recipeID = id, name = nome, parts = {} } }
end
Q.ordersChar = C.CharKey()
Q.orders = {
	ped(1, "sem concentracao", nil, nil),
	ped(2, "obrigatoria 379", 379, nil),
	ped(3, "obrigatoria 120", 120, nil),
	ped(4, "opcional 500", 500, true),
}
Q.SetOrderSort("conc")
local s = Q.OrderSort()
Q.SortOrders(Q.orders)
local nomes = {}
for _, x in ipairs(Q.orders) do
	table.insert(nomes, string.format("%s(%s%s)", x.row.name, tostring(x.concPts or 0), x.concOpt and ",opc" or ""))
end
print("  chave=" .. s.key .. " desc=" .. tostring(s.desc))
print("  " .. table.concat(nomes, " | "))
-- a opcional tem de ficar junto das de valor 0, não no topo pelos 500 pontos
local primeiro = Q.orders[1]
local opcNaoPesa = not (primeiro.concOpt and primeiro.concPts == 500)
print("  opcional NÃO pesa na ordenação: " .. tostring(opcNaoPesa))

print("")
print("=== o ícone da concentração não disputa mais espaço com os reagentes ===")
-- um pedido com reagentes de sobra: antes, a concentração só era desenhada se ainda cabia na faixa
local function comReagentes(n, pts, opt)
	local parts = {}
	for i = 1, n do table.insert(parts, { part = { itemID = 210796, qty = i, unit = 100 } }) end
	local x = ped(9, "muitos reagentes", pts, opt)
	x.parts = parts
	return x
end
local function icones(pedido)
	Q.orders = { pedido }
	C.UI.ShowTab(C.UI.TAB.QUEUE)
	C.UI.RefreshTab(C.UI.TAB.QUEUE)
	local cv = LucroCraftFrame.canvases[C.UI.TAB.QUEUE]
	return (cv._qList and cv._qList.used.icon) or 0, cv
end
for _, nreag in ipairs({ 2, 12 }) do
	local semC = icones(comReagentes(nreag, nil, nil))
	local comC = icones(comReagentes(nreag, 379, nil))
	local comOpc = icones(comReagentes(nreag, 500, true))
	print(string.format("  %2d reagentes: sem conc=%d · obrigatoria=%d (+%d) · opcional=%d (+%d)",
		nreag, semC, comC, comC - semC, comOpc, comOpc - semC))
	print("     " .. (((comC - semC) == 1 and (comOpc - semC) == 1)
		and "OK: a concentração sempre desenha, obrigatória e opcional"
		or "FALHA: a concentração deixou de ser desenhada"))
end

print("")
print("=== render sem erro ===")
Q.orders = { ped(1, "a", 379, nil), ped(2, "b", nil, nil), ped(3, "c", 500, true) }
C.UI.ShowTab(C.UI.TAB.QUEUE)
local cv = LucroCraftFrame.canvases[C.UI.TAB.QUEUE]
print("  " .. tostring(pcall(Q.Render, cv)))
