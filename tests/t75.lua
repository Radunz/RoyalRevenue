
dofile("harness_ah.lua")
local C = RR.Craft; local Q = C.Queue
local BAG = {}
C_Item.GetItemCount = function(id, bank, uses, reag, acct) return BAG[id] or 0 end
local lists = {}
Auctionator = { API = { v1 = { ConvertToSearchString = function(_, t) return t.searchString .. ";" .. t.quantity end,
  CreateShoppingList = function(_, n, terms) lists[n] = terms end, DeleteShoppingList = function(_, n) lists[n] = nil end } } }
local sh = Q.Shopping(); local f = sh[1]
Q.ExportAuctionator(); print("lista", #lists["Royal Revenue"], lists["Royal Revenue"][1])
C_AuctionHouse.ConfirmCommoditiesPurchase(f.id, 12)
FIRE("COMMODITY_PURCHASE_SUCCEEDED")
print("logo apos compra (bolsa ainda vazia)", #lists["Royal Revenue"], lists["Royal Revenue"][1])
C_AuctionHouse.ConfirmCommoditiesPurchase(f.id, 8)
FIRE("COMMODITY_PURCHASE_SUCCEEDED")
print("segunda compra", #lists["Royal Revenue"], lists["Royal Revenue"][1])
BAG[f.id] = 20
print("bolsa chegou: usable", C.Stock.Usable(f.id))
