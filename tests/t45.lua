dofile("harness.lua")
local C = RR.Craft; local Q = C.Queue
UnitName = function() return "Uriuri" end; UnitFullName = function() return "Uriuri", "Goldrinn" end; for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
C_Item.GetItemInfoInstant = function(x) return tonumber(tostring(x):match("item:(%d+)")) end
local calls = {}
C_CraftingOrders = {
  GetCrafterOrders = function() return {
    { orderID = 21, spellID = 1237569, itemID = 1, orderType = 3, tipAmount = 300000, consortiumCut = 30000, customerName = "Chel",
      reagents = { { reagent = { itemID = 238511, quantity = 40 } }, { reagent = { itemID = 238513, quantity = 20 } } }, npcOrderRewards = {} },
    { orderID = 22, spellID = 1237513, itemID = 2, orderType = 3, tipAmount = 500000, consortiumCut = 0, customerName = "Astalor",
      reagents = { { reagentInfo = { reagent = { itemID = 238511 } } }, { reagentInfo = { reagent = { itemID = 238513 } } } } } } end,
  ClaimOrder = function(id, prof) calls.claim = id end,
  FulfillOrder = function(id, note, prof) calls.ful = id end,
  ReleaseOrder = function(id, prof) calls.rel = id end,
  GetClaimedOrder = function() return nil end }
C_TradeSkillUI.GetChildProfessionInfo = function() return { profession = 7, professionID = 2915 } end
C_TradeSkillUI.CraftRecipe = function(rid, n, tbl, lvl, orderID, conc) calls.craft = { rid, orderID, #tbl } end
Q.OrdersButton()
for _, x in ipairs(Q.orders) do print(x.id, x.row and x.row.name, "mat", math.floor(x.mat), "profit", math.floor(x.profit)) end
Q.ClaimOrder(Q.orders[1])
print("claimed", calls.claim, "orders left", #Q.orders)
local items = Q.Build(); print("first item", items[1].source, items[1].row.name)
ProfessionsFrame = { IsShown = function() return true end }
C_TradeSkillUI.GetProfessionInfo = function() return { professionID = 2915 } end
Q.CraftItem(items[1]); print("craft", calls.craft and calls.craft[1], calls.craft and calls.craft[2], calls.craft and calls.craft[3])
FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1237569)
print("crafted flag", LucroCraftDB.queue.claimed[21].crafted)
C.UI.ShowTab(5); print(pcall(Q.Render, LucroCraftFrame.canvases[5]))
Q.FulfillOrder(LucroCraftDB.queue.claimed[21]); print("fulfill", calls.ful)
FIRE("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", 0, 21); print("after", LucroCraftDB.queue.claimed[21])
print("debug snap", LucroCraftDB.ordersDebug and #LucroCraftDB.ordersDebug)
