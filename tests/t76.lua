dofile("harness_ah.lua")
local C = RR.Craft
local calls = {}
C_AuctionHouse.StartCommoditiesPurchase = function(id, q) calls.start = { id, q } end
C_AuctionHouse.ConfirmCommoditiesPurchase = function(id, q) calls.confirm = { id, q } end
C_AuctionHouse.GetItemCommodityStatus = function() return 2 end
Enum.ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 }
AuctionHouseFrame = { IsShown = function() return true end }
C.UI.ShowTab(7)
local cv = LucroCraftFrame.canvases[7]
print(pcall(C.Buy.Render, cv))
local lc = cv._buyList
local out = {}
for i = 1, math.min(lc.used.text or 0, 40) do local t = lc.pools.text[i]._text or ""; t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""); table.insert(out, t) end
print(table.concat(out, " | "))
-- botões
local btns = {}
for i = 1, (lc.used.button or 0) do table.insert(btns, lc.pools.button[i]._text or lc.pools.button[i].text or "?") end
print("botões", table.concat(btns, ", "))
-- compra: clica no primeiro "Comprar"
local res = C.Buy.Build(); local qg = res.groups[1]
print("grupo1 fila?", qg.queue, #qg.order, qg.order[1].buyId, qg.order[1].buy, "craft", qg.order[1].craft and qg.order[1].craft.unit)
C.Buy.StartBuy(qg.order[1].buyId, qg.order[1].buy); print("start", calls.start and calls.start[1], C.Buy.pur.state)
FIRE("COMMODITY_PRICE_UPDATED", 9000, 9000 * qg.order[1].buy); print("estado", C.Buy.pur.state)
C.Buy.ConfirmBuy(); print("confirm", calls.confirm and calls.confirm[2])
FIRE("COMMODITY_PURCHASE_SUCCEEDED"); print("pur", C.Buy.pur)
-- quantos marcados como fabricar
local n = 0; for _, g in ipairs(res.groups) do for _, m in ipairs(g.order) do if m.craftBetter then n = n + 1; print("FABRIQUE", m.buyId, m.craft.unit, m.a.now) end end end
