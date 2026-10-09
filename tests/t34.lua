dofile("harness.lua")
local C = RR.Craft; local S = C.Salvage
local price = {}
local function scan(t,d) if d>12 then return end for k,v in pairs(t) do if type(v)=="table" then if k=="prices" then for id,p in pairs(v) do if type(p)=="table" and p.usedCost then price[id]=p end end else scan(v,d+1) end end end end
scan(LucroCraftDB,0)
C.Pricing.Cost = function(id) return price[id] and price[id].usedCost end
C.Pricing.MarketNow = function(id) return price[id] and price[id].DBMinBuyout end
C.Pricing.VendorBuy = function() return nil end
C.Pricing.Sale = function(id) return price[id] and price[id].usedSale end
C.Pricing.Average = function(id) return price[id] and price[id].DBMarket end
UnitName = function() return "Madunz" end; UnitFullName = function() return "Madunz", "Goldrinn" end; for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
-- simula a captura da transmutação
C_TradeSkillUI.GetRecipeInfo = function(id) return { name = "Transmute: Mote of Light", recipeID = id, icon = 1, learned = true, categoryID = 77 } end
C_TradeSkillUI.GetCategoryInfo = function(id) return { name = "Transmutations" } end
C_TradeSkillUI.GetRecipeSchematic = function(id) return { outputItemID = 236949, quantityMin = 8, quantityMax = 8, reagentSlotSchematics = {
  { required = true, reagentType = 1, quantityRequired = 10, reagents = { { itemID = 236950 } } },
  { required = true, reagentType = 1, quantityRequired = 2, reagents = { { itemID = 242651 } } } } } end
C_TradeSkillUI.GetRecipeCooldown = function() return 3600 * 3, true, 0, 1 end
C_TradeSkillUI.GetTradeSkillLineForRecipe = function() return 2906 end
print("IsCraftDestroy", S.IsCraftDestroy({ name = "Bouquet of Herbs", recipeID = 1, categoryID = 77 }))
S.Capture(1230890)
local r = S._DB().recipes[1230890]
print("kind", r.kind, "transmute", r.transmute, "perCast", r.perCast, "extras", #r.extras, "cd", r.cdBy and r.cdBy["Madunz-Goldrinn"] and r.cdBy["Madunz-Goldrinn"].max)
print("charges", S.Charges(r, "Madunz-Goldrinn"))
for _, row in ipairs(S.Inputs(1230890)) do print("input", row.itemID, "unit", row.unit, "extra", row.extra, "cost", row.cost, "net", row.net, "profit", row.profit, row.how) end
C.UI.ShowTab(4); S._DB().selRecipe = 1230890
print(pcall(S.Render, LucroCraftFrame.canvases[4]))
