dofile("harness12.lua")
local Lg = RR.Livro.Ledger
for _, d in ipairs({ 1, 7, 30, false }) do
  local l = Lg.Journal(d or nil)
  local ok = true
  for i = 2, #l do if l[i].t > l[i-1].t then ok = false end end
  -- referência: varredura simples
  local n = 0
  local from = Lg.Range(d or nil)
  for c, x in pairs(LucroLivroDB.chars) do for _, e in ipairs(x.journal or {}) do if date("%Y-%m-%d", e.t) >= from then n = n + 1 end end end
  print(d, #l, n, ok)
end
-- fora de ordem
local c = next(LucroLivroDB.chars); local j = LucroLivroDB.chars[c].journal
table.insert(j, { t = j[1].t, a = "4.9.01", v = 1 })
local l = Lg.Journal(nil); local ok = true; for i = 2, #l do if l[i].t > l[i-1].t then ok = false end end
print("desordenado", #l, ok)
local t = os.clock(); for i = 1, 10 do Lg.Journal(30) end; print(string.format("Journal(30) %.1f ms", (os.clock() - t) * 100))
