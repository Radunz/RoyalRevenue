dofile("harness.lua")
local C = RR.Craft; local Q = C.Queue
C_CraftingOrders = { GetCrafterOrders = function() return { { orderID = 1, spellID = 9, orderType = 3, tipAmount = 1000 } } end }
Q.OrdersButton(); C.UI.ShowTab(5); print(pcall(Q.Render, LucroCraftFrame.canvases[5]))
local cv = LucroCraftFrame.canvases[5]
for i = 1, cv.used.text do local t = cv.pools.text[i]._text or ""; if t:find("ocultos") then print(t) end end
Q.ClearOrders(); print("after clear", #Q.orders)
