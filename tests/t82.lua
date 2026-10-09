dofile("harness11.lua")
local C = RR.Craft
C_Item.GetItemInfoInstant = function(id) id = tonumber(id); return id, "", "", "", 0, 0, 8 end
for _, cls in ipairs({ "HUNTER", "DRUID", "WARRIOR", "SHAMAN", "PALADIN", "MAGE" }) do
  LucroCraftDB.charInfo = { ["X-Y"] = { class = cls, top = "haste", second = "crit", sec = { haste = 1000, crit = 500, mastery = 300, vers = 100 }, primary = 2, role = "DAMAGER" } }
  local list = C.Consum.For("X-Y", true)
  local cats = {}; for _, s in ipairs(list) do table.insert(cats, s.cat) end
  print(cls, table.concat(cats, ","))
end
