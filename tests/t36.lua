dofile("harness.lua")
local C = RR.Craft; local CT = C.Containers
BAG = { [1] = { itemID = 242650, stackCount = 3, hasLoot = true }, [2] = { itemID = 1000, stackCount = 5 } }
C_Container = { GetContainerNumSlots = function(b) return b == 0 and 10 or 0 end, GetContainerItemInfo = function(b, s) return BAG[s] end }
FIRE("BAG_UPDATE_DELAYED")
-- abre 1 caixa: vai direto para a bolsa
BAG[1].stackCount = 2; BAG[2].stackCount = 7; BAG[3] = { itemID = 2000, stackCount = 4 }
FIRE("BAG_UPDATE_DELAYED")
-- abre outra: saque chega depois
BAG[1].stackCount = 1; FIRE("BAG_UPDATE_DELAYED")
BAG[3].stackCount = 10; FIRE("BAG_UPDATE_DELAYED")
local c = CT.Get(242650); print("opens", c.opens, "1000:", c.out[1000], "2000:", c.out[2000])
C.Pricing.Sale = (function(orig) return function(id) if id == 1000 then return 5000 elseif id == 2000 then return 20000 end return orig(id) end end)(C.Pricing.Sale)
local v, list = CT.Value(242650); print("valor", v, #list)
print("Sale(caixa)", C.Pricing.Sale(242650))
print(C.IsTransmute({ recipeID = 1230893, name = "School of Gems" }))
-- Destruir render com Box of Rocks
UnitName = function() return "Madunz" end
C_TradeSkillUI.GetRecipeInfo = function(id) return { name = "Box of Rocks", recipeID = id, icon = 1, learned = true } end
C_TradeSkillUI.GetRecipeSchematic = function(id) return { outputItemID = 242650, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
  { required = true, reagentType = 1, quantityRequired = 18, reagents = { { itemID = 238520 } } },
  { required = true, reagentType = 1, quantityRequired = 1, reagents = { { itemID = 242651 } } } } } end
C_TradeSkillUI.GetTradeSkillLineForRecipe = function() return 2906 end
C.Salvage.Capture(1230891)
C.UI.ShowTab(4); C.Salvage._DB().selRecipe = 1230891
local cv = LucroCraftFrame.canvases[4]; print(pcall(C.Salvage.Render, cv))
for i = 1, (cv.used and cv.used.text or 0) do local t = cv.pools.text[i]._text or ""; if t:find("abrir") or t:find("baú") then print("  UI:", t) end end
