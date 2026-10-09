dofile("harness.lua")
local C = RR.Craft
UnitName = function() return "Madunz" end
LucroCraftDB.last = { char = "Madunz-Goldrinn", professionID = 2906 }
C.UI.ShowTab(1); print(pcall(C.UI.Refresh))
for _, sec in ipairs(LucroCraftFrame.sections or {}) do print((sec.title._text or ""):gsub("|T.-|t",""):sub(1,90)) end
print("cat motes", C.UI.Category({ name = "Transmute: Mote of Light", profit = -5, spd = 400000 }))
