dofile("harness.lua")
local C = RR.Craft; local Q = C.Queue
UnitName = function() return "Uriuri" end; UnitFullName = function() return "Uriuri", "Goldrinn" end; for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
C_Item.GetItemInfoInstant = function(x) return tonumber(tostring(x):match("item:(%d+)")) or tonumber(x) end
C_TradeSkillUI.GetCraftingOperationInfoForOrder = function() return { craftingQuality = 1, concentrationCost = 188 } end
C_CraftingOrders = {
  GetCrafterOrders = function() return {
    { orderID = 31, spellID = 1237569, orderType = 3, tipAmount = 3000000, consortiumCut = 0, customerName = "Lady Lazaro", minQuality = 2, reagents = {}, npcOrderRewards = {} } } end,
  ClaimOrder = function() end, GetClaimedOrder = function() return nil end }
C_TradeSkillUI.GetChildProfessionInfo = function() return { profession = 7, professionID = 2915 } end
print("valor do ponto", Q.ConcPointValue("Uriuri-Goldrinn", 2915))
Q.OrdersButton()
local x = Q.orders[1]
print("conc", x.concPts, x.concValue and math.floor(x.concValue / 10000), "lucro", math.floor(x.profit / 10000), "unreach", x.unreach)
Q.ClaimOrder(x)
C.UI.ShowTab(5); print(pcall(Q.Render, LucroCraftFrame.canvases[5]))
local qc = LucroCraftFrame.canvases[5]._qList
for i = 1, (qc.used.text or 0) do local t = qc.pools.text[i]._text or ""; if t:find("conc") then print("TXT", (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end end
