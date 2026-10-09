dofile("harness11.lua")
C_Item.GetItemInfoInstant = function(id) return tonumber(id) or 1, "", "", "", 0, 7, 5 end
C_WowTokenPublic = { UpdateMarketPrice = function() end, GetCurrentMarketPrice = function() return 4123450000 end }
local LV = RR.Livro
local orig = LV.Canvas.Create
local CV
LV.Canvas.Create = function(...) CV = orig(...); local ot = CV.Text; CV._texts = {}; CV.Text = function(self, x, y, t, ...) table.insert(CV._texts, { x = x, y = y, t = t }); return ot(self, x, y, t, ...) end
  local obeg = CV.Begin; CV.Begin = function(self, ...) CV._texts = {}; return obeg(self, ...) end
  return CV end
RR.Open("livro")
local f = LucroLivroFrame
f.Tabs[1]._scripts.OnClick(f.Tabs[1])
for _, e in ipairs(CV._texts) do local t = e.t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""); if e.y < 260 then io.write(t, " | ") end end
print()
