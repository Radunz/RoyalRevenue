-- custo dos eventos frequentes (bolsa cheia simulada)
dofile("harness12.lua")
C_Item.GetItemInfoInstant = function(id) id = tonumber(id); return id, "", "", "", 134400, id % 3 == 0 and 0 or 7, 1 end
C_Container = C_Container or {}
local slots = {}
for b = 0, 5 do slots[b] = {} for s = 1, 36 do slots[b][s] = { itemID = 200000 + b * 100 + s, stackCount = 5 } end end
C_Container.GetContainerNumSlots = function(b) return slots[b] and 36 or 0 end
C_Container.GetContainerItemInfo = function(b, s) local x = slots[b] and slots[b][s]; return x and { itemID = x.itemID, stackCount = x.stackCount, hasLoot = false } end
RUNTIMERS()
local function T(name, fn, n)
  local t = os.clock()
  for i = 1, n do fn(i) end
  print(string.format("%-34s %7.3f ms", name, (os.clock() - t) * 1000 / n))
end
T("BAG_UPDATE + BAG_UPDATE_DELAYED", function(i) slots[0][1].stackCount = i % 7 + 1; FIRE("BAG_UPDATE", 0); FIRE("BAG_UPDATE_DELAYED") end, 200)
T("UNIT_SPELLCAST_SUCCEEDED", function() FIRE("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 12345) end, 500)
T("CHAT_MSG_LOOT (outro jogador)", function() FIRE("CHAT_MSG_LOOT", "Fulano receives loot: |cff0070dd|Hitem:12345::|h[X]|h|r.") end, 500)
T("PLAYER_MONEY", function() FIRE("PLAYER_MONEY") end, 200)
T("UNIT_AURA", function() FIRE("UNIT_AURA", "player") end, 500)
