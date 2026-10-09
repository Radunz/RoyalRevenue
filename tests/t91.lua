dofile("harness12.lua")
RUNTIMERS()
local S = RR.Craft.Scanner
local worst, tot, n = 0, 0, 0
for char, entries in pairs(LucroCraftDB.chars) do for _, e in pairs(entries) do
  local t = os.clock(); S.Reprice(e, char); local d = (os.clock() - t) * 1000
  tot = tot + d; n = n + 1; if d > worst then worst = d end
end end
print(string.format("reprice: %d entradas, total %.0f ms, pior %.1f ms", n, tot, worst))
