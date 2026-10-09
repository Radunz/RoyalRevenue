-- v1.31.0: pedidos de fabricação em tabela com colunas (Item · Custo · Recompensa · Lucro ·
-- Reagentes · Tempo · Pegar pedido), ordenável pelo título, conhecimento como ícone de recompensa,
-- concentração como reagente e só UM pedido pode ser pego por vez.
dofile("harness11.lua")
local C = RR.Craft
local Q = C.Queue
UnitName = function() return "Uriuri" end; UnitFullName = function() return "Uriuri", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
C_CurrencyInfo = { GetCurrencyInfo = function(id) return { name = "Moxie", iconFileID = 5931173 } end }

print("=== colunas (QW = 1000) ===")
local OC = Q.OrderCols(1000)
local ordem = { "item", "cost", "reward", "profit", "reag", "time", "claim" }
local last = 0
local cresce = true
for _, k in ipairs(ordem) do
	local w = (k == "item") and OC.itemW or OC.w[k]
	print(string.format("  %-7s x=%4d w=%3d", k, OC[k], w))
	if OC[k] < last then cresce = false end
	last = OC[k]
end
print(cresce and "OK: colunas em ordem, sem sobreposição" or "FALHA: coluna fora de ordem")

print("")
print("=== tempo restante ===")
for _, s in ipairs({ -1, 900, 7200, 200000 }) do print("  " .. tostring(s) .. "s -> " .. Q.ShortTime(s)) end
print("  nil -> " .. Q.ShortTime(nil))

print("")
print("=== ordenar pelo título da coluna ===")
local base = {
	{ row = { name = "Bravo" }, mat = 300, tip = 1000, cut = 0, rew = 0, profit = 700, exp = 500 },
	{ row = { name = "Alfa" }, mat = 100, tip = 900, cut = 0, rew = 0, profit = 800, exp = 900 },
	{ row = { name = "Charlie" }, mat = 50, tip = 400, cut = 0, rew = 0, profit = 350, exp = 100 },
}
for _, key in ipairs({ "profit", "cost", "reward", "item", "time" }) do
	LucroCraftDB.config.orderSort = nil
	Q.SetOrderSort(key)
	local cp = {}
	for i, o in ipairs(base) do cp[i] = o end
	Q.SortOrders(cp)
	local nomes = {}
	for _, o in ipairs(cp) do table.insert(nomes, o.row.name) end
	print(string.format("  %-7s (desc=%-5s): %s", key, tostring(Q.OrderSort().desc), table.concat(nomes, ", ")))
end
-- clicar de novo na mesma coluna inverte
Q.SetOrderSort("profit"); local d1 = Q.OrderSort().desc
Q.SetOrderSort("profit"); local d2 = Q.OrderSort().desc
print("  clicar duas vezes inverte: " .. tostring(d1) .. " -> " .. tostring(d2))

print("")
print("=== desenho da tabela ===")
local e = select(2, next(LucroCraftDB.chars["Uriuri-Goldrinn"]))
local r = e.rows[1]
local function Pedidos()
	return {
		{ row = r, e = e, id = 1, type = "Patron", customer = "Zalle", tip = 730917, cut = 36546, rew = 1200,
			mat = 500000, profit = 195371, kp = 1, exp = time() + 7200, minQ = 2, concPts = 162, parts = {},
			order = { itemID = r.itemID, expirationTime = time() + 7200 },
			rewList = { { id = 246448, n = 1, v = 1200, kp = 1 }, { currency = 3263, icon = 5931173, n = 30 } } },
		{ row = r, e = e, id = 2, type = "Patron", customer = "Koraud", tip = 400000, cut = 20000, rew = 0,
			mat = 90000, profit = 290000, exp = time() + 600, parts = {},
			order = { itemID = r.itemID, expirationTime = time() + 600 }, rewList = {} },
	}
end
Q.SetOrderSort("profit")
Q.orders = Pedidos(); Q.ordersT = time()
C.UI.ShowTab(C.UI.TAB.QUEUE)
local cv = LucroCraftFrame.canvases[C.UI.TAB.QUEUE]
print("  render:", pcall(Q.Render, cv))
local qc = cv._qList
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end
local heads = {}
for i = 1, (qc.used and qc.used.head or 0) do table.insert(heads, strip(qc.pools.head[i].text._text or "")) end
print("  títulos: " .. table.concat(heads, " | "))

print("")
print("=== só um pedido pode ser pego por vez ===")
local function BotoesClaim()
	local on, off = 0, 0
	for i = 1, (qc.used and qc.used.button or 0) do
		local b = qc.pools.button[i]
		if strip(b._text or ""):find("Pegar") then
			if b._enabled == false then off = off + 1 else on = on + 1 end
		end
	end
	return on, off
end
local on, off = BotoesClaim()
print(string.format("  sem pedido pego:  habilitados=%d desabilitados=%d", on, off))
-- com um pedido já pego, os botões ficam desabilitados
LucroCraftDB.queue = LucroCraftDB.queue or {}
LucroCraftDB.queue.claimed = { [99] = { id = 99, char = "Uriuri-Goldrinn" } }
Q.orders = Pedidos(); Q.ordersT = time()
pcall(Q.Render, cv)
on, off = BotoesClaim()
print(string.format("  com um pedido pego: habilitados=%d desabilitados=%d", on, off))
print(off > 0 and on == 0 and "OK: com um pedido pego, nenhum outro pode ser pego" or "FALHA: deixou pegar mais de um")
