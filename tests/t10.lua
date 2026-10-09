dofile("t9.lua")
local C = RR.Craft
-- amostras com hora para o item 241305
for d = 0, 9 do for _, hh in ipairs({3, 15}) do C.Buy.Record(241305, 10000 + d * 50 + hh, os.time({year=2026,month=10,day=4,hour=hh}) - d*86400) end end
postLoc = nil; AuctionHouseFrame.AuctionatorSellingFrame = nil
C.Sell.Select({ id = 241305 })
C.UI.ShowTab(C.UI.TAB.SELL)
local cv = LucroCraftFrame.canvases[C.UI.TAB.SELL]
local function dump(tag)
  local out, err = {}, nil
  for i = 1, cv.used.text do local t = cv.pools.text[i]._text; table.insert(out, t); if tostring(t):find("Erro") then err = t end end
  print(tag, "textos", cv.used.text, "linhas", cv.used.line, "erro", err)
  return out
end
local out = dump("30d")
local start
for i, t in ipairs(out) do if tostring(t):find("Histórico de preço") then start = i end end
for i = start, start + 22 do print(out[i]) end
LucroCraftDB.config.sellHist.range = 7; LucroCraftDB.config.sellHist.table = true; C.Sell.Refresh(); dump("7d+tabela")
LucroCraftDB.config.sellHist.show.min = false; LucroCraftDB.config.sellHist.range = 0; C.Sell.Refresh(); dump("tudo sem menor")
-- equipamento
C.Sell.Select({ id = 250000, gear = true, link = "|Hitem:250000::::ilvl|h[Linen Robe]|h" }); dump("equip")
