dofile("harness11.lua")
C_Item.GetItemInfoInstant = function(id) return tonumber(id) or 1, "", "", "", 0, 7, 5 end
local Ledger = RR.Livro.Ledger
local data = Ledger.Collect(30)
local G = function(c) return string.format("%.2f", (c or 0) / 10000) end
local totMv, totDf = 0, 0
for _, t in ipairs(data.chars) do
  if t.any then
    local tm = Ledger.Merge({ chars = { t } }); local td = Ledger.DRE(tm)
    local mv = td.actGold + td.comm + td.itemsale - td.cashOut + tm.xin - tm.xout + tm.adj
    local df = (t.cashOpen and t.cashClose) and (t.cashClose - (t.cashOpen + mv)) or nil
    totMv = totMv + mv
    print(t.char, "open", G(t.cashOpen), "close", G(t.cashClose), "mv", G(mv), "diff", df and G(df) or "SEM SALDO", "itemsale", G(td.itemsale), t.firstD, t.lastD)
  end
end
print("total mv", G(totMv))
