dofile("harness.lua")
local C = RR.Craft
local BAG, BANK, WB = { [1] = 5 }, { [1] = 100 }, { [1] = 7 }
C_Item.GetItemCount = function(id, bank, uses, reag, acct) return (BAG[id] or 0) + (bank and (BANK[id] or 0) or 0) + (acct and (WB[id] or 0) or 0) end
print(C.Stock.Usable(1))
