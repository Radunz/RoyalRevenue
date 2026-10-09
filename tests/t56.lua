dofile("harness10.lua")
C_Item.GetItemInfoInstant = function(id) return tonumber(id) or 1, "", "", "", 0, 7, 5 end
local LV = RR.Livro; local Ledger = LV.Ledger
local BAG = { [238511] = 100, [238513] = 30 }
C_Container = C_Container or {}
C_Container.GetContainerNumSlots = function(b) return b == 0 and 10 or 0 end
local slots = {}
local function rebuild() slots = {}; for id, q in pairs(BAG) do table.insert(slots, { itemID = id, stackCount = q }) end end
C_Container.GetContainerItemInfo = function(b, s) rebuild(); return slots[s] end
LV.P.Value = function(id) return ({ [238511] = 9000, [238513] = 20000, [244587] = 3000000, [999] = 50000 })[id] end
C_TradeSkillUI.GetRecipeInfo = function() return { name = "Smuggler's Leather Tunic" } end
C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionName = "Leatherworking" } end
C_CraftingOrders = { GetClaimedOrder = function() return nil end }
local d = os.date("%Y-%m-%d")
FIRE("TRADE_SKILL_CRAFT_BEGIN", 1237499)
BAG[238511] = 75; BAG[238513] = 15; BAG[244587] = 1
FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1237499)
FIRE("BAG_UPDATE_DELAYED")
local c = LucroLivroDB.chars["Radunz-Goldrinn"]
print("cpv craft", c.days[d].cpv and c.days[d].cpv.craft, "made", c.made and c.made[244587])
-- segundo craft em sequência, usando o produto (feito por mim) como reagente
FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1237499)
BAG[244587] = 0; BAG[238511] = 65
FIRE("BAG_UPDATE_DELAYED")
print("cpv craft 2", c.days[d].cpv.craft, "made", c.made[244587])
for i = #c.journal - 3, #c.journal do local e = c.journal[i]; print(e.a, e.h, e.v, e.i, e.q) end
local m = Ledger.Merge(Ledger.Collect(1)); local r = Ledger.DRE(m)
print("DRE cpv", r.cpv, r.cpvCraft, "prof", m.cpvProf.Leatherworking, "cashOut", r.cashOut, "stock", r.stock)
