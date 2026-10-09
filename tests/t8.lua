dofile("t2.lua")
local C = RR.Craft
C.Buy.SetDays(3)
local res = C.Sell.Build()
print("grupos", #res.groups, "itens", res.n, "receita", res.revNow, "melhor", res.best and C.Buy.WD_LONG[res.best], "verde", res.nGreen)
for w=1,7 do io.write(string.format("%s %+.3f  ", C.Buy.WD_SHORT[w], res.wd[w]/res.revTyp-1)) end print()
local m = res.items[1]
print("item", m.id, "make", m.make, "own", m.own, "qty", m.qty, "now", m.a.now, "typ", m.a.typical, "sig", m.signal, "bestSell", C.Buy.WD_LONG[m.a.bestSell], "bestBuy", C.Buy.WD_LONG[m.a.best])
C.UI.ShowTab(C.UI.TAB.SELL)
local cv = LucroCraftFrame.canvases[C.UI.TAB.SELL]
local n, err = 0
for _, fs in ipairs(cv.pools.text) do if fs._shown ~= false then n = n + 1 end if tostring(fs._text):find("Erro") then err = fs._text end end
print("textos", n, "erro", err)
for i = 1, 12 do print(cv.pools.text[i]._text) end
for _, k in ipairs({"LIST","PLAN","BUY","SELL","QUEUE","INVEST","SALVAGE","SETTINGS"}) do local ok, e = pcall(C.UI.ShowTab, C.UI.TAB[k]); io.write(k, "=", tostring(ok), " ") end print()
SlashCmdList.ROYALREVENUE("vender 7"); print("dias", C.Buy.Days(), "aba", C.UI.CurrentTab())
C.Sell.ExportAuctionator(); print("lista", SHOP.name, #SHOP.terms)
