dofile("harness.lua")
local C = RR.Craft
local RS = C.RecipeShop
local list, hidden = RS.Missing()
local cats = {}
for _, m in ipairs(list) do cats[m.cat] = (cats[m.cat] or 0) + 1 end
print("faltando compráveis", #list, "ah", cats.ah, "vendor", cats.vendor, "ocultas", hidden)
-- simula scan: nome de receita a venda
local ah1
for _, m in ipairs(list) do if m.cat == "ah" then ah1 = m break end end
print("exemplo drop:", ah1.name, ah1.char, ah1.src)
RS.BeginScan()
RS.OnListing("Recipe: " .. ah1.name, 999, 500000, 1)
RS.OnListing("Pattern: Coisa Nenhuma", 998, 1, 1)
RS.EndScan()
-- outro servidor
LucroCraftDB.recipeAH.Azralon = { name = "Azralon", scanT = NOW - 7200, items = { [ah1.rid] = { item = 999, min = 300000, n = 2, t = NOW - 7200 } } }
local res = RS.Build()
print("grupos", #res.groups, "n", res.n, "à venda aqui", res.forSale, "best", res.best and res.best.name, res.best and res.best.gain, "realms", #res.realms)
for _, g in ipairs(res.groups) do
  local m = g.items[1]
  print(g.name, #g.items, "top:", m.name, m.signal, m.char, m.perCraft, m.gain, m.weeks, m.crafts, m.here and m.here.min, #m.others)
end
C.UI.ShowTab(C.UI.TAB.RECIPES)
local cv = LucroCraftFrame.canvases[C.UI.TAB.RECIPES]
print("aba", C.UI.CurrentTab(), "modo", C.UI.ModeOf(C.UI.TAB.RECIPES))
-- tooltip
local m = ah1; local tt = setmetatable({}, {__index=function() return function() end end})
-- browse
C_AuctionHouse.GetBrowseResults = function() return { { itemKey = { itemID = 777 }, minPrice = 123400, totalQuantity = 3 } } end
C_Item.GetItemNameByID = function(id) if id == 777 then return "Receita: " .. list[2].name end return "Item"..id end
FIRE("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
print("browse capturou", LucroCraftDB.recipeAH.Goldrinn.items[list[2].rid] and LucroCraftDB.recipeAH.Goldrinn.items[list[2].rid].min, list[2].cat)
