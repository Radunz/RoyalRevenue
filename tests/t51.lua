dofile("harness.lua")
local C = RR.Craft; local S = C.Salvage
UnitName = function() return "Radünz" end; UnitFullName = function() return "Radünz", "Medivh" end; for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
print("limpou", S._DB().obs["Radünz-Medivh"][1235731][236949].casts)
BAG = { [1] = { itemID = 236949, stackCount = 50 }, [2] = { itemID = 243599, stackCount = 10 } }
C_Container = { GetContainerNumSlots = function(b) return b == 0 and 10 or 0 end, GetContainerItemInfo = function(b, s) return BAG[s] end }
C_Item.GetItemID = function(loc) return 236949 end
C_TradeSkillUI.CraftSalvage = function() end
FIRE("PLAYER_LOGIN")
C_TradeSkillUI.CraftSalvage(1235731, 2, {})
FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1235731)
BAG[1].stackCount = 49; BAG[3] = { itemID = 243602, stackCount = 2 }
FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1235731)
BAG[1].stackCount = 48; BAG[3].stackCount = 3
RUNTIMERS()
local o = S._DB().obs["Radünz-Medivh"][1235731][236949]
print("casts", o.casts, "out 243602", o.out[243602], "out 243599", o.out[243599], "bagOut", o.bagOut)
