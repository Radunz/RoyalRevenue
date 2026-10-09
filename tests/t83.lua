dofile("harness.lua")
local C = RR.Craft; local Q = C.Queue
RR.Open("craft")
SlashCmdList.ROYALREVENUE("escala 80"); print("scale", RoyalRevenueDB.scale)
-- pedido com tudo fornecido e minQ 3
UnitName = function() return "Uriuri" end; UnitFullName = function() return "Uriuri", "Goldrinn" end; for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
C_Item.GetItemInfoInstant = function(x) return tonumber(tostring(x):match("item:(%d+)")) or tonumber(x) end
local seen
C_TradeSkillUI.GetCraftingOperationInfoForOrder = function(rid, tbl, oid, conc) seen = #tbl; return { craftingQuality = 3, concentrationCost = 50 } end
C_CraftingOrders = { GetCrafterOrders = function() return {
  { orderID = 41, spellID = 1237499, orderType = 3, tipAmount = 500000, consortiumCut = 0, customerName = "T", minQuality = 3,
    reagents = { { reagentInfo = { reagent = { itemID = 238512 }, quantity = 25, dataSlotIndex = 1 } }, { reagentInfo = { reagent = { itemID = 238514 }, quantity = 15, dataSlotIndex = 2 } } }, npcOrderRewards = {} } } end,
  GetClaimedOrder = function() return nil end }
C_TradeSkillUI.GetChildProfessionInfo = function() return { profession = 7, professionID = 2915 } end
Q.OrdersButton()
local x = Q.orders[1]
print("mat", x.mat, "conc", x.concPts, "q0", x.q0, "lucro", x.profit, "tbl enviado", seen)
