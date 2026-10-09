dofile("t45.lua")
local Q = RR.Craft.Queue
LucroCraftDB.queue.claimed[40] = { id = 40, recipeID = 1237513, char = "Uriuri-Goldrinn", prof = 2915, given = { [238511] = true, [238513] = true, [244636] = true }, type = "Patrono", t = 1, profit = 1 }
local shop = Q.Shopping(Q.Build())
for _, s in ipairs(shop) do print(s.id, s.name, s.need) end
print(pcall(Q.Render, LucroCraftFrame.canvases[5]))
