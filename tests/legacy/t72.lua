dofile("harness.lua")
local C = RR.Craft; local Q = C.Queue
local BAG, WB, ALT = {}, {}, {}
C_Item.GetItemCount = function(id, bank, uses, reag, acct) return (BAG[id] or 0) + (acct and (WB[id] or 0) or 0) + (bank and 1000 or 0) end
local lists = {}
Auctionator = { API = { v1 = { ConvertToSearchString = function(_, t) return t.searchString .. ";" .. t.quantity end,
  CreateShoppingList = function(_, n, terms) lists[n] = terms end, DeleteShoppingList = function(_, n) lists[n] = nil end } } }
local sh = Q.Shopping(); local f = sh[1]
print("first", f.id, "need", f.need, "have", f.have, "buy", f.buy)
Q.ExportAuctionator(); print("lista", #lists["Royal Revenue"])
BAG[f.id] = f.need
FIRE("BAG_UPDATE_DELAYED"); for _, fn in ipairs(TIMERS) do local src = debug.getinfo(fn, "S").short_src; if src:find("Stock") or src:find("Queue") then fn() end end; TIMERS = {}
print("depois", #lists["Royal Revenue"])
WB[sh[2].id] = sh[2].need
FIRE("BAG_UPDATE_DELAYED"); for _, fn in ipairs(TIMERS) do local src = debug.getinfo(fn, "S").short_src; if src:find("Stock") or src:find("Queue") then fn() end end; TIMERS = {}
print("depois bando", lists["Royal Revenue"] and #lists["Royal Revenue"]); for _, s in ipairs(Q.Shopping()) do print(s.id, s.need, s.have, s.buy) end
