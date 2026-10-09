dofile("harness.lua")
local C = RR.Craft; local S = C.Salvage
local price = {}
local function scan(t,d) if d>12 then return end for k,v in pairs(t) do if type(v)=="table" then if k=="prices" then for id,p in pairs(v) do if type(p)=="table" and p.usedCost then price[id]=p end end else scan(v,d+1) end end end end
scan(LucroCraftDB,0)
price[241305] = { usedCost = 10094, DBMinBuyout = 10094, usedSale = 10094 }
C.Pricing.Cost = function(id) return price[id] and price[id].usedCost end
C.Pricing.MarketNow = function(id) return price[id] and price[id].DBMinBuyout end
C.Pricing.VendorBuy = function() return nil end
C.Pricing.HasAnySource = function() return true end
C.Pricing.Sale = (function(o) return function(id) return price[id] and price[id].usedSale or o(id) end end)(C.Pricing.Sale)
print("up 236761 ->", C.Containers.Higher(236761), "up 236778 ->", C.Containers.Higher(236778))
print("valor q1", C.Containers.Value(245650), "proj q2", C.Containers.ProjectHigher(245650))
UnitName = function() return "Madunz" end
C_TradeSkillUI.GetRecipeInfo = function(id) return { name = "Bouquet of Herbs", recipeID = id, icon = 1, learned = true } end
C_TradeSkillUI.GetRecipeSchematic = function(id) return { outputItemID = 245650, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
  { required = true, reagentType = 1, quantityRequired = 1, reagents = { { itemID = 242651 } } },
  { required = true, reagentType = 1, quantityRequired = 20, reagents = { { itemID = 243599 }, { itemID = 243600 } } },
  { required = true, reagentType = 1, quantityRequired = 4, reagents = { { itemID = 243602 }, { itemID = 243603 } } } } } end
C_TradeSkillUI.GetTradeSkillLineForRecipe = function() return 2906 end
S.Capture(1230892)
local rows = S.Inputs(1230892); print("linhas", #rows, rows[1].itemID, rows[1].cost)
local pj = S.ConcProjection(S._DB().recipes[1230892], 1230892, rows[1].cost)
print("proj", pj.how, pj.vBase, pj.vTop, pj.profitBase, pj.profitTop, pj.extra, pj.perPoint)
C.UI.ShowTab(4); S._DB().selRecipe = 1230892
local cv = LucroCraftFrame.canvases[4]; print(pcall(S.Render, cv))
for i = 1, (cv.used and cv.used.text or 0) do local t = cv.pools.text[i]._text or ""; if true then print("  UI:", t) end end
-- receitas: concSale projetada
local e = LucroCraftDB.chars["Madunz-Goldrinn"][2906]; C.Scanner.Reprice(e, "Madunz-Goldrinn")
for _, r in ipairs(e.rows) do if r.recipeID == 1230892 then print("scan row sale", r.sale, "concSale", r.concSale, r.concProjected, "profit", r.profit, "concProfit", r.concProfit, "perConc", r.perConc) end end
