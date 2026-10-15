dofile("t2.lua")
local C = RR.Craft
C_AuctionHouse.ReplicateItems = function() end
C_AuctionHouse.GetNumReplicateItems = function() return 9000 end
C_AuctionHouse.GetReplicateItemInfo = function(i) return nil, nil, 1, nil, nil, nil, nil, nil, nil, 5000, nil, nil, nil, nil, nil, nil, 241305 + (i % 50) end
C.UI.ShowTab(C.UI.TAB.BUY)
local frame = LucroCraftFrame
local cv = frame.canvases[C.UI.TAB.BUY]
local bar = cv.pools.bar[1]
local function show(tag) print(tag, bar.text._text, C.Own.ScanStatus().phase) end
show("antes")
FIRE("AUCTION_HOUSE_SHOW"); RUNTIMERS()
LucroCraftDB.ah.Goldrinn.last = 0
C.Own.StartScan(true); show("pedido")
NOW = NOW + 7; C.Buy.ScanProgress(); show("7s")
-- servidor responde
TIMERS = {}
FIRE("REPLICATE_ITEM_LIST_UPDATE"); show("lendo")
local fn = table.remove(TIMERS, 1); fn(); show("passo2")
RUNTIMERS(); show("fim")
print("botao", cv.pools.button[1]._text)
-- cancelamento: fecha a AH esperando
LucroCraftDB.ah.Goldrinn.last = 0
C.Own.StartScan(true); FIRE("AUCTION_HOUSE_CLOSED"); show("fechou")
