dofile("harness11.lua")
C_Item.GetItemInfoInstant = function(id) return tonumber(id) or 1, "", "", "", 0, 7, 5 end
local Ledger = RR.Livro.Ledger
local G = function(c) return c and string.format("%.2f", c / 10000) or "nil" end
for _, ch in ipairs({ "Riwariel-Goldrinn", "Drafael-Goldrinn", "Radunz-Goldrinn", "Nazdru-Goldrinn" }) do
  local c = LucroLivroDB.chars[ch]
  local ds = {}; for d in pairs(c.days) do table.insert(ds, d) end; table.sort(ds)
  print("==", ch, "lastMoney", G(c.lastMoney))
  local prevClose
  for _, d in ipairs(ds) do
    local day = c.days[d]
    local t = Ledger.Collect(nil, ch); -- unused
    -- movimento do dia
    local one = { chars = {} }
    local tt = { char = ch, act = {}, out = {}, inc = {}, xin = 0, xout = 0, adj = 0, time = {} }
    local m = Ledger.Merge(Ledger.CollectDay and Ledger.CollectDay(ch, d) or { chars = {} })
    local inc = 0; for _, a in pairs(day.act or {}) do inc = inc + (a.gold or 0) end
    for k, v in pairs(day.inc or {}) do inc = inc + v end
    local out = 0; for k, v in pairs(day.out or {}) do out = out + v end
    local mv = inc - out + (day.xin or 0) - (day.xout or 0) + (day.adj or 0)
    local df = (day.cashOpen and day.cashClose) and (day.cashClose - day.cashOpen - mv) or nil
    local gap = (prevClose and day.cashOpen) and (day.cashOpen - prevClose) or nil
    print(d, "open", G(day.cashOpen), "close", G(day.cashClose), "mv", G(mv), "diff", G(df), "gap desde ontem", G(gap))
    prevClose = day.cashClose
  end
end
