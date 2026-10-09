dofile("harness11.lua")
C_WowTokenPublic = { UpdateMarketPrice = function() end, GetCurrentMarketPrice = function() return 4123450000 end }
local C = RR.Craft
LucroCraftDB.token = { hist = { { t = time() - 2 * 86400, p = 4000000000 }, { t = time() - 90000, p = 4050000000 }, { t = time() - 3 * 86400, p = 4300000000 } } }
C.UI.ShowTab(7)
local cv = LucroCraftFrame.canvases[7] or LucroCraftFrame.canvas
print(pcall(C.Buy.Render, cv))
local lc = cv._buyList
local out = {}
for i = 1, math.min(lc.used.text or 0, 12) do local t = lc.pools.text[i]._text or ""; t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""); table.insert(out, t) end
print(table.concat(out, " | "))
LucroCraftDB.config.sellCollapsed = { buyToken = true }
C.Buy.Render(cv)
print("collapsed texts first:", (lc.pools.text[1]._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), lc.pools.text[3] and lc.pools.text[3]._text)
