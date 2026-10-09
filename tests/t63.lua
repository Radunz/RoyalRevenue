dofile("harness11.lua")
local Ledger = RR.Livro.Ledger
for _, ch in ipairs({ "Radunz-Goldrinn", "Nazdru-Goldrinn" }) do
  local c = LucroLivroDB.chars[ch]
  local d = "2026-10-01"
  local day = c.days[d]
  local j = {}
  for _, e in ipairs(c.journal) do if e.c and os.date("%Y-%m-%d", e.t) == d then j[e.a] = (j[e.a] or 0) + e.v end end
  local agg = {}
  for k, a in pairs(day.act or {}) do agg[Ledger.ActCode(k)] = (agg[Ledger.ActCode(k)] or 0) + a.gold end
  for k, v in pairs(day.out or {}) do agg[Ledger.OutCode(k)] = (agg[Ledger.OutCode(k)] or 0) - v end
  for k, v in pairs(day.inc or {}) do local code = k == "itemsale" and "itemsale" or Ledger.IncCode(k); agg[code] = (agg[code] or 0) + v end
  agg.xin = day.xin; agg.xout = -(day.xout or 0); agg.adj = day.adj
  print("==", ch, os.date("%Z"))
  local keys = {}; for k in pairs(j) do keys[k] = true end; for k in pairs(agg) do keys[k] = true end
  for k in pairs(keys) do local a, b = (j[k] or 0) / 10000, (agg[k] or 0) / 10000; if math.abs(a - b) > 0.01 then print(k, "diario", a, "dia", b, "dif", b - a) end end
end
