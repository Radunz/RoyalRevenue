dofile("t2.lua")
local C = RR.Craft
for _, d in ipairs({0, 1, 3, 7}) do
  C.Buy.SetDays(d)
  local res = C.Buy.Build()
  local crafts = 0
  for _, g in ipairs(res.groups) do crafts = crafts + g.crafts end
  print(string.format("dias %d: grupos %d crafts %d materiais %d custo %.0f lucro %.0f", d, #res.groups, crafts, res.nBuy, res.costNow, res.gain))
end
local cv = C.Visual.Create(UIParent)
local texts = {}
local o = cv.Text
cv.Text = function(self, x, y, t, ...) table.insert(texts, t) return o(self, x, y, t, ...) end
C.Buy.SetDays(3)
C.Buy.Render(cv)
for i = 1, 8 do print(texts[i]) end
for _, t in ipairs(texts) do if t:find("fabricações") then print(t) end end
SlashCmdList.ROYALREVENUE("compras 10"); print("days", C.Buy.Days(), C.UI.CurrentTab())
-- plano não mudou
local l = C.Plan.Build(); print("plano", l[1].gain)
