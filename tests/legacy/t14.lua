dofile("t2.lua")
local C, R = RR.Craft, RR
local function tabs()
  local out = {}
  for i, t in ipairs(LucroCraftFrame.Tabs) do if t._shown then table.insert(out, i .. ":" .. t._text) end end
  return table.concat(out, " | ")
end
R.Open("craft"); print("craft  ->", tabs(), "| titulo:", LucroCraftFrame.titleFS._text, "| last", RoyalRevenueDB.last)
R.Open("mercado"); print("mercado->", tabs(), "| titulo:", LucroCraftFrame.titleFS._text, "| aba", C.UI.CurrentTab(), "| last", RoyalRevenueDB.last)
C.UI.ShowTab(C.UI.TAB.SELL); R.Switch(nil, "craft"); print("volta craft ->", C.UI.CurrentTab(), tabs())
R.Switch(nil, "mercado"); print("volta mercado -> aba", C.UI.CurrentTab(), "(Vender=8)")
SlashCmdList.ROYALREVENUE("plano"); print("/rr plano ->", C.UI.CurrentTab(), C.UI.Mode())
SlashCmdList.ROYALREVENUE("vender"); print("/rr vender ->", C.UI.CurrentTab(), C.UI.Mode(), RoyalRevenueDB.last)
SlashCmdList.ROYALREVENUE("mercado"); print("/rr mercado ->", C.UI.CurrentTab())
R.Open("livro"); print("livro shown", LucroLivroFrame and LucroLivroFrame._shown)
R.Switch(nil, "mercado"); print("livro->mercado: livro", LucroLivroFrame._shown, "craft", LucroCraftFrame._shown, C.UI.Mode())
local t1 = LucroCraftFrame.Tabs[1]
print("aba 1 ancorada em cima?", t1._anchor or "(sem registro)")
for k, id in pairs(C.UI.TAB) do local ok, e = pcall(C.UI.ShowTab, id); if not ok then print("ERRO", k, e) end end
print("ok")
R.Open("mercado", C.UI.TAB.SELL)
LucroCraftFrame.gear._scripts.OnClick()
print("engrenagem ->", C.UI.CurrentTab(), C.UI.Mode(), tabs())
LucroCraftFrame.gear._scripts.OnClick()
print("de novo ->", C.UI.CurrentTab(), C.UI.Mode())
R.Open("craft", C.UI.TAB.PLAN); LucroCraftFrame.gear._scripts.OnClick(); LucroCraftFrame.gear._scripts.OnClick(); print("craft volta ->", C.UI.CurrentTab())
SlashCmdList.ROYALREVENUE("config"); print("/rr config ->", C.UI.CurrentTab())
