dofile("harness.lua")
local C = RR.Craft; local Q = C.Queue
TSM_API = nil
local lists = {}
Auctionator = { API = { v1 = {
  ConvertToSearchString = function(_, t) return t.searchString .. ";" .. t.quantity end,
  CreateShoppingList = function(_, n, terms) lists[n] = terms end,
  DeleteShoppingList = function(_, n) lists[n] = nil end } } }
STOCK = {}
local sh = Q.Shopping(); local first = sh[1]
print("itens", #sh, "first", first.id, first.buy)
Q.ExportAuctionator()
print("lista", #lists["Royal Revenue"], lists["Royal Revenue"][1])
STOCK[first.id] = first.buy  -- comprou tudo do 1º
FIRE("BAG_UPDATE_DELAYED"); for _, fn in ipairs(TIMERS) do fn() end; TIMERS = {}
print("lista depois", #lists["Royal Revenue"], lists["Royal Revenue"][1])
for _, s in ipairs(Q.Shopping()) do STOCK[s.id] = (STOCK[s.id] or 0) + s.need end
FIRE("BAG_UPDATE_DELAYED"); for _, fn in ipairs(TIMERS) do fn() end
print("final", lists["Royal Revenue"], LucroCraftDB.liveLists["Royal Revenue"])
