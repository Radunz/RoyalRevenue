dofile("t2.lua")
local C = RR.Craft
C_Item.GetItemID = function(loc) return loc.id end
C_TradeSkillUI.CraftSalvage = function() end
FIRE("PLAYER_LOGIN")
STOCK = { [275285] = 100 }
LucroCraftDB.salvage.recipes[1296450] = { kind = "salvage", prof = "Cooking", name = "Plant Protein", chars = { [C.CharKey()] = true }, inputs = { 275285 }, perCast = 1 }
local function cast(saved, withField)
  if not saved then STOCK[275285] = STOCK[275285] - 1 end
  FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 1296450)
  FIRE("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 242640, quantity = 3, resourcesReturned = withField and (saved and { { itemID = 275285, quantity = 1 } } or {}) or nil })
  FIRE("BAG_UPDATE_DELAYED")
end
C_TradeSkillUI.CraftSalvage(1296450, 10, { id = 275285 })
FIRE("TRADE_SKILL_CRAFT_BEGIN", 1296450)
for i = 1, 10 do cast(i == 3 or i == 7, false) end
local use, res, how, n = C.Salvage.UsePerCast(1296450, 275285, 1)
print("bolsa: gasto/destruição", use, "economia", res, how, n)
-- linhas da aba
for _, row in ipairs(C.Salvage.Inputs(1296450)) do print("linha", row.itemID, "per", row.per, "use", row.use, "res", row.res, "custo", row.cost) end
local o = LucroCraftDB.salvage.obs[C.CharKey()][1296450][275285]
print("casts", o.casts, "bagCasts", o.bagCasts, "bagUsed", o.bagUsed, "savedCasts", o.savedCasts, "resSeen", o.resSeen)
