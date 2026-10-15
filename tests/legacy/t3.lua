dofile("t2.lua")
local C = RR.Craft
-- amostras com hora: madrugada mais barata
local id = 241305
C.Buy.Tracked()[id] = true
for d = 1, 10 do
  for _, h in ipairs({2, 6, 10, 14, 18, 22}) do
    local t = os.time({year=2026, month=10, day=4, hour=h}) - d*86400
    local p = 10000 * (h < 4 and 0.93 or 1.0)
    -- amostras de todos os materiais
    for _, m in ipairs(C.Buy.Build().items) do C.Buy.Record(m.buyId, p, t) end
  end
end
local res = C.Buy.Build()
for b=1,6 do local x=res.band[b]; io.write(string.format("b%d %s n%d d%d  ", b, x.idx and string.format("%.3f", x.idx) or "-", x.n, x.days)) end print("best band", res.bestBand)
-- busca na AH
AH_SEARCH = { [id] = 9000 }
FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", id)
local it = LucroCraftDB.buyHist.items[id]
print("last sample", it.p[#it.p], #it.t)
C.Buy._ClearCache()
local a = C.Buy.Analyze(id)
print("now", a.now, a.nowSrc, "sig", a.signal, "diff", a.diff)
-- Auctionator scan: m muda
FIRE("AUCTION_HOUSE_SHOW"); FIRE("AUCTION_HOUSE_CLOSED")
RUNTIMERS()
print("UI tab", C.UI.TAB.BUY, C.UI.TAB.SETTINGS)
C.UI.ShowTab(C.UI.TAB.BUY); print("current", C.UI.CurrentTab())
for _, k in ipairs({"PLAN","QUEUE","INVEST","SALVAGE","SETTINGS","LIST"}) do local ok, e = pcall(C.UI.ShowTab, C.UI.TAB[k]); print(k, ok, e) end
SlashCmdList.ROYALREVENUE("compras"); print("after /rr compras", C.UI.CurrentTab())
