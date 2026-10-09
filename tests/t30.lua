dofile("harness.lua")
local C = RR.Craft; local RS = C.RecipeShop
local list = RS.Missing()
local emb; for _, m in ipairs(list) do if m.name == "Thalassian Competitor's Emblem" then emb = m end end
RS.BeginScan(); RS.OnListing("Pattern: " .. emb.name, 5002, 9990000, 9); RS.EndScan()
LucroCraftDB.recipeAH.Stormrage = { name = "Stormrage", scanT = NOW - 3600, items = { [emb.rid] = { item = 5002, min = 4000000, n = 2, t = NOW - 3600, seenT = NOW - 3600, seenMin = 4000000 } } }
local res = RS.Build()
for _, g in ipairs(res.groups) do for _, m in ipairs(g.items) do if m == nil then end if m.rid == emb.rid then
 print(m.cheap.realm, m.cheap.min, m.cheap.here, m.ahRealms, m.price, m.buyAt, m.signal) end end end
C.UI.ShowTab(9); print(pcall(RS.Render, LucroCraftFrame.canvases[9]))
