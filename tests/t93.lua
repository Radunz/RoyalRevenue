-- anúncio absurdo: típico pela mediana, índice do dia limitado, linha usa o típico/fabricar
dofile("harness12.lua")
local B = RR.Craft.Buy
local DAY = 86400
local now = os.time()
local hist = { t = {}, p = {} }
-- 14 dias a ~20g, 3 dias com só um anúncio de 11.111,06g
for d = 14, 1, -1 do
  local p = 200000
  if d == 2 or d == 5 or d == 9 then p = 111110600 end
  table.insert(hist.t, now - d * DAY); table.insert(hist.p, p)
end
table.insert(hist.t, now - 600); table.insert(hist.p, 111110600)   -- agora: 11.111g
LucroCraftDB.buyHist = LucroCraftDB.buyHist or { items = {} }
LucroCraftDB.buyHist.items[999001] = hist
B._ClearCache()
local a = B.Analyze(999001)
print("agora", a.now / 10000, "típico", a.typical / 10000, "fora", a.outlier, "selo", a.signal)
local lo, hi = 9, -9
for w = 1, 7 do local x = a.wd[w].idx; if x then lo = math.min(lo, x); hi = math.max(hi, x) end end
print(string.format("índice do dia: menor %.0f%%  maior %.0f%%", lo * 100, hi * 100))
