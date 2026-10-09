dofile("harness.lua")
local C = RR.Craft
LucroCraftDB.last = { char = "Madunz-Goldrinn", professionID = 2906 }
for c, es in pairs(LucroCraftDB.chars) do if true then for _, e in pairs(es) do if e.parentID == 171 then
  for _, r in ipairs(e.rows) do if C.IsTransmute(r) then r.cd = { cool = 3600 * 5, day = true, charges = 0, max = 1, t = NOW - 3600 } end end
end end end end
local r = { cd = { cool = 3600 * 5, charges = 0, max = 1, t = NOW - 3600 } }
print("charges", C.Charges(r))
r.cd.t = NOW - 3600 * 6; print("charges+", C.Charges(r))
r.cd = { cool = 3600, charges = 1, max = 3, t = NOW - 3600 * 2 }; print("3max", C.Charges(r))
C.UI.ShowTab(1); print(pcall(C.UI.Refresh))
for _, sec in ipairs(LucroCraftFrame.sections or {}) do print(sec.title._text) end
