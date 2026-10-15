dofile("harness_ah.lua")
local C = RR.Craft
C_WowTokenPublic = { UpdateMarketPrice = function() end, GetCurrentMarketPrice = function() return 2930400000 end }
local sel
AuctionHouseFrame = { IsShown = function() return true end, SetDisplayMode = function() end, SelectBrowseResult = function(_, b) sel = b.itemKey end }
AuctionHouseFrameDisplayMode = { Buy = 1 }
C_AuctionHouse.MakeItemKey = function(id) return { itemID = id } end
C.UI.ShowTab(7)
local cv = LucroCraftFrame.canvases[7]
local function dump(tag)
  local out = {}
  for i = 1, math.min(cv.used.text or 0, 14) do local t = cv.pools.text[i]._text or ""; table.insert(out, (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
  print(tag, table.concat(out, " | "))
end
for _, l in ipairs({ "plan", "queue", "cons" }) do
  LucroCraftDB.config.buyList = l
  local ok, err = pcall(C.Buy.Render, cv); print(l, ok, err); dump(l)
  local res = C.Buy.Build(); print("  grupos", #res.groups)
end
LucroCraftDB.config.buyList = "plan"; LucroCraftDB.config.buyAllChars = true
print("plan todos grupos", #C.Buy.Build().groups)
C.Buy.ShowInAH(236774); print("AH item", sel and sel.itemID)
