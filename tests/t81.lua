dofile("harness11.lua")
local C = RR.Craft
C_WowTokenPublic = { UpdateMarketPrice = function() end, GetCurrentMarketPrice = function() return 2930400000 end }
C_Item.GetItemInfoInstant = function(id) id = tonumber(id); return id, "", "", "", 0, 0, 8 end
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end; for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
GetSpecialization = function() return 1 end
GetSpecializationInfo = function() return 1, "Beast Mastery", "", 0, "DAMAGER", 2 end
GetCombatRating = function(cr) return ({ [9] = 900, [18] = 1200, [26] = 2000, [29] = 400 })[cr] or 0 end
UnitClass = function() return "Hunter", "HUNTER" end
GetInventoryItemLink = function() return nil end
C.Consum.ReadMe()
LucroCraftDB.config.buyList = "cons"
local res = C.Buy.Build()
for _, g in ipairs(res.groups) do print(g.char, g.sugg and "SUGG" or "USED", #g.order); if g.sugg then for _, m in ipairs(g.order) do print("  ", m.note, m.buyId, "need", m.need, "buy", m.buy) end end end
C.UI.ShowTab(7); local cv = LucroCraftFrame.canvases[7]; print(pcall(C.Buy.Render, cv))
print("hrs", C.Consum.Activity("Radunz-Goldrinn"))
LucroCraftDB.config.consGroup = true
res = C.Buy.Build(); for _, g in ipairs(res.groups) do if g.sugg then print("com grupo", #g.order) end end
