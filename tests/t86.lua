dofile("harness11.lua")
local C = RR.Craft
local cases = {
 {"WARLOCK", nil, nil, nil}, {"WARLOCK", 4, "DAMAGER", "blunt"}, {"WARLOCK", 2, "DAMAGER", "blade"},
 {"MAGE", nil, nil, nil}, {"PRIEST", 4, "HEALER", "blunt"}, {"DRUID", nil, nil, nil}, {"DRUID", 4, "DAMAGER", "blunt"},
 {"DRUID", 2, "DAMAGER", "blunt"}, {"WARRIOR", nil, nil, nil}, {"ROGUE", 2, "DAMAGER", "blade"}, {"PALADIN", 1, "TANK", "blade"}, {"HUNTER", 2, "DAMAGER", "ranged"},
}
for _, k in ipairs(cases) do
  LucroCraftDB.charInfo = { ["X-Y"] = { class = k[1], primary = k[2], role = k[3], weapon = k[4] } }
  local w = "-"
  for _, s in ipairs(C.Consum.For("X-Y", false)) do if s.cat == "weapon" then w = s.note end end
  local m = false
  for _, s in ipairs(C.Consum.For("X-Y", false)) do if s.cat == "mana" then m = true end end
  print(k[1], k[2], k[3], w, m and "mana" or "")
end
