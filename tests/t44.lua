dofile("harness.lua")
local C = RR.Craft
UnitName = function() return "Madunz" end; UnitFullName = function() return "Madunz", "Goldrinn" end; for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
C_Item.GetItemInfoInstant = function(x) return tonumber(tostring(x):match("item:(%d+)")) end
local claimed
C_CraftingOrders = {
  GetCrafterOrders = function() return {
    { orderID = 11, spellID = 1230892, itemID = 245650, orderType = 3, tipAmount = 500000, consortiumCut = 50000, customerName = "Patrono X",
      reagents = { { reagent = { itemID = 243599 } } }, npcOrderRewards = { { itemLink = "|Hitem:236761|h[x]|h", count = 2 } }, minQuality = 2 },
    { orderID = 12, spellID = 999999, itemID = 1, orderType = 0, tipAmount = 100000, consortiumCut = 0 } } end,
  ClaimOrder = function(id, prof) claimed = { id, prof } end }
C_TradeSkillUI.GetChildProfessionInfo = function() return { profession = 4, professionID = 2906 } end
C.Queue.OrdersButton()
for _, x in ipairs(C.Queue.orders) do print(x.id, x.row and x.row.name, x.type, "tip", x.tip, "cut", x.cut, "rew", x.rew, "mat", math.floor(x.mat), "profit", math.floor(x.profit)) end
C.UI.ShowTab(5); print(pcall(C.Queue.Render, LucroCraftFrame.canvases[5]))
C.Queue.ClaimOrder(C.Queue.orders[1]); print("claim", claimed and claimed[1], claimed and claimed[2], "fila", C.Queue.Count("Madunz-Goldrinn", 2906, 1230892, "base"))
-- compras: histórico
C.UI.ShowTab(7); local cv = LucroCraftFrame.canvases[7]; print("buy render", pcall(C.Buy.Render, cv), C.Buy.selected)
local found = false
for i = 1, (cv.used and cv.used.text or 0) do local t = cv.pools.text[i]._text or ""; if t:find("Histórico") or t:find("Sem histórico") then print("  UI:", t:sub(1,80)) end end
