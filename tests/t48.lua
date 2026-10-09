dofile("t45.lua")
local Q = RR.Craft.Queue
local calls = {}
C_TradeSkillUI.CraftRecipe = function(rid, n, tbl, lvl, orderID, conc) calls.c = { orderID, conc } end
C_TradeSkillUI.GetCraftingOperationInfoForOrder = function(rid, tbl, oid, conc) return { craftingQuality = conc and 2 or 1, concentrationCost = 120 } end
LucroCraftDB.queue.claimed[30] = { id = 30, recipeID = 1237569, char = "Uriuri-Goldrinn", prof = 2915, given = {}, minQ = 2, type = "Patrono", t = 1 }
Q.CraftOrder(LucroCraftDB.queue.claimed[30]); print("conc", calls.c[1], calls.c[2])
LucroCraftDB.queue.claimed[30].minQ = 3; calls.c = nil
Q.CraftOrder(LucroCraftDB.queue.claimed[30]); print("blocked", calls.c)
LucroCraftDB.queue.claimed[30].minQ = 1
Q.CraftOrder(LucroCraftDB.queue.claimed[30]); print("normal", calls.c[2])
print(pcall(Q.Render, LucroCraftFrame.canvases[5]))
