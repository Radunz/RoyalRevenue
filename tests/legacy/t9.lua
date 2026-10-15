dofile("t2.lua")
local C = RR.Craft
-- bolsa: 2 reagentes empilháveis, 1 equipamento, 1 vinculado, 1 de missão, 1 cinza
BAG = {
  [1] = { itemID = 241305, stackCount = 25, quality = 2, hyperlink = "|Hitem:241305|h[Bright Linen Bolt]|h" },
  [2] = { itemID = 241305, stackCount = 5, quality = 2, hyperlink = "|Hitem:241305|h[Bright Linen Bolt]|h" },
  [3] = { itemID = 243000, stackCount = 3, quality = 3, hyperlink = "|Hitem:243000|h[Void-Touched Augment Rune]|h" },
  [4] = { itemID = 250000, stackCount = 1, quality = 3, hyperlink = "|Hitem:250000::::ilvl|h[Linen Robe]|h" },
  [5] = { itemID = 6948, stackCount = 1, quality = 1, isBound = true },
  [6] = { itemID = 300, stackCount = 1, quality = 1 },
  [7] = { itemID = 301, stackCount = 2, quality = 0 },
}
C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and 7 or 0 end, GetContainerItemInfo = function(bag, slot) return BAG[slot] end }
local INFO = { [241305] = 200, [243000] = 20, [250000] = 1, [300] = 1, [301] = 20 }
C_Item.GetItemInfo = function(id) local cls = id == 300 and 12 or 7; return "Item"..id, "|Hitem:"..id.."|h", 1, 1, 1, "", "", INFO[id] or 1, "", 1, 1, cls end
C_Item.GetItemID = function(loc) return loc.id end
C_Item.GetItemLink = function(loc) return "|Hitem:" .. loc.id .. "|h[Void-Touched Augment Rune]|h" end
C_Item.GetStackCount = function(loc) return loc.n end
local function Loc(id, n) return { id = id, n = n, IsValid = function() return true end } end
local postLoc
AuctionHouseFrame = { IsShown = function() return true end,
  CommoditiesSellFrame = { IsShown = function() return true end, GetItem = function() return postLoc end },
  ItemSellFrame = { IsShown = function() return false end } }
C.Buy._ClearCache()
C.UI.ShowTab(C.UI.TAB.PLAN)
local res = C.Sell.Build()
print("itens", res.n, "ocultos", res.hidden, "receita", res.revNow, "posting", res.posting)
for _, m in ipairs(res.items) do print(" ", m.id, m.count, m.gear, m.signal, m.a.now, m.a.bestSell and C.Buy.WD_LONG[m.a.bestSell]) end
-- coloca o item para vender: deve pular para a aba Vender
postLoc = Loc(243000, 3)
C.Sell._CheckPosting()
print("aba", C.UI.CurrentTab(), "SELL=", C.UI.TAB.SELL)
local cv = LucroCraftFrame.canvases[C.UI.TAB.SELL]
local seen = {}
for _, fs in ipairs(cv.pools.text) do table.insert(seen, fs._text) end
for i = 1, 14 do print(seen[i]) end
for _, t in ipairs(seen) do if tostring(t):find("Erro") then print("ERRO", t) end end
-- Auctionator selling
postLoc = nil
AuctionHouseFrame.AuctionatorSellingFrame = { IsShown = function() return true end, SaleItemFrame = { itemInfo = { itemLink = "|Hitem:241305|h[Bright Linen Bolt]|h", count = 30, location = Loc(241305, 30) } } }
C.Sell._CheckPosting()
print("auctionator posting", C.Sell.Build().posting.id)
-- inglês ok? tab ids
print(C.Buy.Tracked()[243000], C.Buy.Tracked()[250000])
