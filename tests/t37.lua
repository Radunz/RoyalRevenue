dofile("harness.lua")
local C = RR.Craft; local S = C.Salvage
local price = {}
local function scan(t,d) if d>12 then return end for k,v in pairs(t) do if type(v)=="table" then if k=="prices" then for id,p in pairs(v) do if type(p)=="table" and p.usedCost then price[id]=p end end else scan(v,d+1) end end end end
scan(LucroCraftDB,0)
price[241305] = { usedCost = 10094, DBMinBuyout = 10094, usedSale = 10094 }
C.Pricing.Cost = function(id) return price[id] and price[id].usedCost end
C.Pricing.MarketNow = function(id) return price[id] and price[id].DBMinBuyout end
C.Pricing.VendorBuy = function() return nil end
C.Pricing.Sale = (function(o) return function(id) return price[id] and price[id].usedSale or o(id) end end)(C.Pricing.Sale)
print("BoundCost", S.BoundCost(242651))
UnitName = function() return "Madunz" end
C_TradeSkillUI.GetRecipeInfo = function(id) return { name = "Bouquet of Herbs", recipeID = id, icon = 1, learned = true } end
C_TradeSkillUI.GetRecipeSchematic = function(id) return { outputItemID = 245650, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
  { required = true, reagentType = 1, quantityRequired = 1, reagents = { { itemID = 242651 } } },
  { required = true, reagentType = 1, quantityRequired = 20, reagents = { { itemID = 243599 } } },
  { required = true, reagentType = 1, quantityRequired = 4, reagents = { { itemID = 243602 } } } } } end
C_TradeSkillUI.GetTradeSkillLineForRecipe = function() return 2906 end
S.Capture(1230892)
local r = S._DB().recipes[1230892]; print("input", r.inputs[1], "perCast", r.perCast, "extras", #r.extras)
for _, row in ipairs(S.Inputs(1230892)) do print("cost/vez", row.cost, "net", row.net, "profit", row.profit, row.how) end
print("valor do buquê", C.Containers.Value(245650))
