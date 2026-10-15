dofile("t2.lua")
C_Item.GetItemInfoInstant = function(id) return tonumber(id) or 1, "", "", "", 0, 7, 5 end
C_CurrencyInfo = { GetCurrencyInfo = function(id) return { name = "Moeda" .. id } end }
local BAGS = { [1] = { itemID = 238205, stackCount = 10 }, [2] = { itemID = 237359, stackCount = 5 }, [3] = { itemID = 999, stackCount = 3 } }
C_Container = { GetContainerNumSlots = function(b) return b == 0 and 3 or 0 end, GetContainerItemInfo = function(b, s) return BAGS[s] end }
C_CraftingOrders = { GetClaimedOrder = function() return { orderID = 77, spellID = 4242, outputItemHyperlink = "|Hitem:1|h[Sterling Alloy Blade]|h" } end }
local LV = RR.Livro
local c = LucroLivroDB.chars[RR.Craft.CharKey()] or {}
local n0 = #(c.journal or {})
FIRE("TRADE_SKILL_CRAFT_BEGIN", 4242)
BAGS[1].stackCount = 6   -- usou 4 do 238205
BAGS[2].stackCount = 3   -- usou 2 do 237359
FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 4242)
FIRE("BAG_UPDATE_DELAYED")
c = LucroLivroDB.chars[RR.Craft.CharKey()]
for i = n0 + 1, #c.journal do local e = c.journal[i]; print("DIÁRIO", e.a, e.h, e.i, e.q, e.v / 10000) end
local d = c.days[os.date("%Y-%m-%d")]
print("custo mat no dia", d and d.act.orders and d.act.orders.cost and d.act.orders.cost.mat / 10000)
-- outra receita com pedido reivindicado: não conta
FIRE("TRADE_SKILL_CRAFT_BEGIN", 1111); BAGS[1].stackCount = 5; FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 1111); FIRE("BAG_UPDATE_DELAYED")
print("depois de outra receita, lançamentos novos:", #c.journal - n0)
