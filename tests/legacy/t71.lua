dofile("harness11.lua")
local P0 = 4123450000
C_WowTokenPublic = { UpdateMarketPrice = function() end, GetCurrentMarketPrice = function() return P0 end }
local C = RR.Craft
local hist = {}
for d = 10, 1, -1 do for h = 0, 23, 6 do table.insert(hist, { t = time() - d * 86400 + h * 3600, p = 4000000000 + ((d * 7 + h) % 13) * 20000000 }) end end
LucroCraftDB.token = { hist = hist }
C.UI.ShowTab(7)
local cv = LucroCraftFrame.canvases[7]
C.Buy.selected = C.Buy.TOKEN_ITEM
print(pcall(C.Buy.Render, cv))
local lc = cv._buyList
local out = {}
for i = 1, math.min(lc.used.text or 0, 12) do local t = lc.pools.text[i]._text or ""; t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""); table.insert(out, t) end
print(table.concat(out, " | "))
local o2 = {}
for i = 1, (cv.used.text or 0) do local t = cv.pools.text[i]._text or ""; t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""); if t:find("Histórico") or t:find("Preço agora") or t:find("Média") or t:find("Menor") then table.insert(o2, t) end end
print(table.concat(o2, " | "))
print("amostras", #LucroCraftDB.buyHist.items[122284].t)
