dofile("harness.lua")
local C = RR.Craft; local Q = C.Queue
local bag = { [238511] = 30, [238513] = 3, [238514] = 20 }
C_Item.GetItemCount = function(id) return bag[id] or 0 end
local parts = { { slot = 1, itemID = 238511, qualityItems = { 238511, 238512 }, qty = 25 }, { slot = 2, itemID = 238513, qualityItems = { 238513, 238514 }, qty = 15 } }
local tbl = C.Scanner.BuildReagentTbl(parts)
local _, miss, sw = C.Scanner.FitToBags(tbl, parts)
for _, e in ipairs(tbl) do print(e.dataSlotIndex, e.reagent.itemID, e.quantity) end
print("miss", #miss, "swaps", table.concat(sw, "; "))
bag[238514] = 5
local tbl2 = C.Scanner.BuildReagentTbl(parts); local _, miss2 = C.Scanner.FitToBags(tbl2, parts)
print("miss2", #miss2, miss2[1] and miss2[1].have, miss2[1] and miss2[1].need)
-- order craft path
local calls = {}
UnitName = function() return "Uriuri" end
C_TradeSkillUI.CraftRecipe = function(...) calls.n = (calls.n or 0) + 1 end
local r = { recipeID = 777, name = "Tunic", parts = parts }
LucroCraftDB.chars = LucroCraftDB.chars or {}
Q.CraftItem({ row = r, variant = "base", n = 1 }); print("craft calls (missing)", calls.n)
bag[238514] = 20
Q.CraftItem({ row = r, variant = "base", n = 1 }); print("craft calls (ok)", calls.n)
for i = math.max(1, #LucroCraftDB.log - 3), #LucroCraftDB.log do print(LucroCraftDB.log[i]) end
