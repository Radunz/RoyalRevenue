dofile("harness.lua")
local C = RR.Craft; local Q = C.Queue
local BAG = {}
C_Item.GetItemCount = function(id, bank, uses, reag, acct) return (acct and (BAG[id] or 0)) or 0 end
local sh = Q.Shopping()
for _, s in ipairs(sh) do print(s.id, "need", s.need, "have", s.have, "buy", s.buy) end
-- dar a qualidade de cima de um reagente com 2 qualidades
local target
for _, it in ipairs(Q.ShopItems()) do for _, p in ipairs(it.parts or it.row.parts or {}) do if p.qualityItems and #p.qualityItems > 1 and not target then target = p end end end
print("reagente", target.itemID, "qualidades", table.concat(target.qualityItems, ","))
BAG[target.qualityItems[#target.qualityItems]] = 6000
for _, s in ipairs(Q.Shopping()) do if s.id == (target.buyItem or target.itemID) then print("depois", s.id, "need", s.need, "have", s.have, "buy", s.buy) end end
