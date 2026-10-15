dofile("t12.lua")
local C = RR.Craft
EXPANSION_NAME0, EXPANSION_NAME9 = "Classic", "Dragonflight"
local META2 = {}
local old = C_Item.GetItemInfo
C_Item.GetItemInfo = function(id)
  local r = { old(id) }
  if id % 5 == 0 then r[15] = 0 elseif id % 7 == 0 then r[15] = 9 end
  return unpack(r, 1, 15)
end
GetExpansionLevel = function() return 11 end
local res = C.Sell.Build()
print("ORDEM:")
for _, xg in ipairs(res.xgroups) do
  local ps = {}
  for _, pg in ipairs(xg.profs) do table.insert(ps, pg.name .. "(" .. #pg.items .. ")") end
  print(xg.name, table.concat(ps, ", "))
end
