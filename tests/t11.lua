dofile("t10.lua")
local C = RR.Craft
-- muitos itens na bolsa
for i = 8, 40 do BAG[i] = { itemID = 241305 + i, stackCount = 2, quality = 1, hyperlink = "|Hitem:" .. (241305+i) .. "|h[X" .. i .. "]|h" } end
C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 40 or 0 end
LucroCraftDB.config.sellHist.table = false
C.Sell.Select(nil)
C.UI.ShowTab(C.UI.TAB.SELL)
local cv = LucroCraftFrame.canvases[C.UI.TAB.SELL]
local sub = cv._sellList
print("sub", sub ~= nil, "linhas na sub", sub.used.text, "altura filho", sub.child._h, "frame h", sub.frame._h, "barra", sub.bar._shown)
local function has(c, pat) for i = 1, c.used.text do if tostring(c.pools.text[i]._text):find(pat) then return true end end return false end
print("hist no outer", has(cv, "Histórico de preço"), "itens no outer", has(cv, "Receita líquida"), "itens na sub", has(sub, "Receita líquida"))
-- minimiza lista e histórico
LucroCraftDB.config.sellCollapsed = { bag = true, hist = true }
C.Sell.Refresh()
print("minimizado: sub visível", sub.frame._shown, "grafico", has(cv, "Menor do período"), "cabecalho hist", has(cv, "Histórico de preço"))
LucroCraftDB.config.sellCollapsed = nil; C.Sell.Refresh()
print("expandido: sub", sub.frame._shown, "grafico", has(cv, "Menor do período"))
