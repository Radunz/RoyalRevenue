dofile("harness.lua")
local C = RR.Craft; local Q = C.Queue
UnitName = function() return "Uriuri" end; UnitFullName = function() return "Uriuri", "Goldrinn" end; for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
C_Item.GetItemInfoInstant = function(x) return tonumber(tostring(x):match("item:(%d+)")) end
C_TooltipInfo = { GetHyperlink = function(l) if l:find("item:999") then return { lines = { { leftText = "Leatherworking Notes" }, { leftText = "Study to increase your Leatherworking knowledge by 2." } } } end return { lines = { { leftText = "Coisa" } } } end }
C_CraftingOrders = {
  GetCrafterOrders = function() return {
    { orderID = 21, spellID = 1237569, orderType = 3, tipAmount = 300000, consortiumCut = 30000, customerName = "Chel",
      reagents = { { reagent = { itemID = 238511, quantity = 40 } } }, npcOrderRewards = { { itemLink = "|cff|Hitem:888|h[Ouro]|h|r", count = 3 } } },
    { orderID = 22, spellID = 1237513, orderType = 3, tipAmount = 100000, consortiumCut = 0, customerName = "Astalor",
      reagents = {}, npcOrderRewards = { { itemLink = "|cff|Hitem:999|h[Leatherworking Notes]|h|r", count = 1 } } } } end,
  GetClaimedOrder = function() return nil end }
C_TradeSkillUI.GetChildProfessionInfo = function() return { profession = 7, professionID = 2915 } end
print("shop before", #Q.Shopping())
Q.OrdersButton()
for _, x in ipairs(Q.orders) do print(x.id, x.row and x.row.name, "kp", x.kp, "profit", math.floor(x.profit), "rew", #x.rewList) end
local sh = Q.Shopping(); print("shop after", #sh); for _, s in ipairs(sh) do print(" ", s.id, s.need, s.buy) end
C.UI.ShowTab(5); print(pcall(Q.Render, LucroCraftFrame.canvases[5]))
local cv = LucroCraftFrame.canvases[5]
for i = 1, (cv.used.text or 0) do local t = cv.pools.text[i]._text or ""; if t:find("conhecimento") then print("TXT", t) end end
local qc = cv._qList
for i = 1, (qc.used.text or 0) do local t = qc.pools.text[i]._text or ""; if t:find("conhecimento") then print("TXT", t) end end
print("icons", qc.used.icon)
