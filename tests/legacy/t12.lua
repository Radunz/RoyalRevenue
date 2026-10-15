dofile("t11.lua")
local C = RR.Craft
-- classe/subclasse/expansão por item
local META = { [241305] = {7, 5, 11}, [243000] = {0, 6, 11}, [250000] = {4, 1, 11} }
C_Item.GetItemInfo = function(id)
  local mt = META[id] or { (id % 2 == 0) and 7 or 0, (id % 2 == 0) and 9 or 1, (id % 3 == 0) and 10 or 11 }
  local stack = id == 250000 and 1 or 200
  return "Item"..id, "|Hitem:"..id.."|h", 1, 1, 1, "", "", stack, "", 1, 1, mt[1], mt[2], nil, mt[3]
end
EXPANSION_NAME10, EXPANSION_NAME11 = "The War Within", "Midnight"
C_TradeSkillUI.GetTradeSkillDisplayName = function(id) return ({[171]="Alquimia",[197]="Alfaiataria",[333]="Encantamento",[182]="Herborismo"})[id] end
LucroCraftDB.config.sellCollapsed = nil
local res = C.Sell.Build()
for _, xg in ipairs(res.xgroups) do
  print(xg.name, xg.n, math.floor(xg.rev))
  for _, pg in ipairs(xg.profs) do print("   ", pg.name, #pg.items, math.floor(pg.rev)) end
end
C.Sell.Refresh()
local cv = LucroCraftFrame.canvases[C.UI.TAB.SELL]; local sub = cv._sellList
local hdr = {}
for i = 1, sub.used.text do local t = sub.pools.text[i]._text; if t:find("Minus") or t:find("Plus") then table.insert(hdr, t) end end
print("cabecalhos", #hdr); print(hdr[1]); print(hdr[2])
LucroCraftDB.config.sellCollapsed = { ["x:11"] = true }
C.Sell.Refresh(); print("Midnight minimizada: altura", sub.child._h)
LucroCraftDB.config.sellCollapsed = nil; C.Sell.Refresh(); print("expandida: altura", sub.child._h)
