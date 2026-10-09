dofile("t2.lua")
local C = RR.Craft
for _, inp in ipairs({275280, 275281, 275284, 275282}) do
  local use, res, how, n = C.Salvage.UsePerCast(1296449, inp, 1)
  print("real", inp, "gasto", use, "economia", res and string.format("%.1f%%", res*100), how, n)
end
-- simulação: o material sai DEPOIS do BAG_UPDATE
C_Item.GetItemID = function(loc) return loc.id end
C_TradeSkillUI.CraftSalvage = function() end
FIRE("PLAYER_LOGIN")
STOCK = { [999] = 20 }
LucroCraftDB.salvage.recipes[1296449].inputs = { 999 }
TIMERS = {}
for i = 1, 10 do
  C_TradeSkillUI.CraftSalvage(1296449, 1, { id = 999 })   -- uma chamada por destruição
  FIRE("TRADE_SKILL_CRAFT_BEGIN", 1296449)
  FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 1296449)
  FIRE("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 242639, quantity = 3 })
  FIRE("BAG_UPDATE_DELAYED")
  if i ~= 4 then STOCK[999] = STOCK[999] - 1 end   -- consumo chega depois
end
RUNTIMERS()
local o = LucroCraftDB.salvage.obs[C.CharKey()][1296449][999]
print("sim bolsa: casts", o.casts, "bagCasts", o.bagCasts, "bagUsed", o.bagUsed, "->", C.Salvage.UsePerCast(1296449, 999, 1))
