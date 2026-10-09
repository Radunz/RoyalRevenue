dofile("harness11.lua")
local C = RR.Craft
C_WowTokenPublic = { UpdateMarketPrice = function() end, GetCurrentMarketPrice = function() return 2930400000 end }
C_Item.GetItemInfoInstant = function(id) id = tonumber(id); local sub = ({ [241301] = 1, [241305] = 1, [212264] = 8, [241325] = 3 })[id] or 8; return id, "", "", "", 0, 0, sub end
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end; for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
LucroCraftDB.config.buyList = "cons"
local res = C.Buy.Build()
for _, g in ipairs(res.groups) do print(g.char, #g.order); for _, m in ipairs(g.order) do print("  ", m.buyId, "usou", m.usedQ, "need", m.need, "own", m.own, "buy", m.buy, m.kind) end end
C.UI.ShowTab(7); local cv = LucroCraftFrame.canvases[7]; print(pcall(C.Buy.Render, cv))
local lc = cv._buyList; local out = {}
for i = 1, math.min(lc.used.text or 0, 20) do table.insert(out, ((lc.pools.text[i]._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
print(table.concat(out, " | "))
LucroCraftDB.config.buyAllChars = true
res = C.Buy.Build(); local n = 0; for _, g in ipairs(res.groups) do n = n + #g.order end; print("todos sem poções: grupos", #res.groups, "itens", n)
for _, g in ipairs(res.groups) do for _, m in ipairs(g.order) do print("ALL", g.char, m.buyId, m.usedQ) end end
