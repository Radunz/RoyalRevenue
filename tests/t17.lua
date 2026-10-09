dofile("t2.lua")
local C = RR.Craft
-- cenário: poção boa (100 ouro/ponto, custa 600) e poção pior (50/ponto, custa 100); concentração 300
local e = { name = "Alchemy", conc = { cur = 300, max = 1000 }, time = NOW, class = "MAGE", rows = {
  { name = "Pote Bom", perConc = 1000000, concCost = 600, concEff = 550, concSale = 1, recipeID = 1, concItemID = 1001, parts = {} },
  { name = "Pote Ruim", perConc = 500000, concCost = 100, concEff = 90, concSale = 1, recipeID = 2, concItemID = 1002, parts = {} },
} }
LucroCraftDB.chars = { ["Madunz-Goldrinn"] = { alch = e } }
local old = C.Recommendable; C.Recommendable = function() return true end
local list = C.Plan.Build()
local it = list[1]
print("hold?", it.hold ~= nil, "usados", #it.used)
if it.hold then print("segure até", it.hold.need, "espera h", string.format("%.1f", it.hold.waitH), "agora daria", it.hold.altGain/10000, "o; esperando +", it.hold.extra/10000, "o") end
-- com concentração suficiente: faz o bom e guarda a sobra
e.conc.cur = 900
list = C.Plan.Build(); it = list[1]
print("900: usados", #it.used, it.used[1] and (it.used[1].crafts .. "x " .. it.used[1].row.name), "guarda", it.kept and math.floor(it.kept.pts), "próximo h", it.kept and string.format("%.1f", it.kept.waitH))
-- desligado: comportamento antigo
LucroCraftDB.config.planHold = false
e.conc.cur = 300; list = C.Plan.Build(); it = list[1]
print("desligado: usados", #it.used, it.used[1] and (it.used[1].crafts .. "x " .. it.used[1].row.name), "hold", it.hold ~= nil)
LucroCraftDB.config.planHold = nil
-- desenho
C.UI.ShowTab(C.UI.TAB.PLAN)
local cv = LucroCraftFrame.canvases[C.UI.TAB.PLAN]
for i = 1, cv.used.text do local t = cv.pools.text[i]._text; if t:find("SEGURE") or t:find("concentração ·") or t:find("vs. gastar") or t:find("Erro") then print(t) end end
print(C.Plan.GetText():match("[^\n]*SEGURE[^\n]*"))
