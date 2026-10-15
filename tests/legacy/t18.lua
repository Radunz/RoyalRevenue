dofile("t2.lua")
C_Item.GetItemInfoInstant = function(id) return tonumber(id) or 1, "", "", "", 0, 7, 5 end
C_CurrencyInfo = { GetCurrencyInfo = function(id) return { name = "Moeda" .. id } end }
local LV = RR.Livro
local orig = LV.Canvas.Create
local CV
LV.Canvas.Create = function(...) CV = orig(...); local ot = CV.Text; CV._texts = {}; CV.Text = function(self, x, y, t, ...) table.insert(CV._texts, { x = x, y = y, t = t }); return ot(self, x, y, t, ...) end
  local ob = CV.Box; CV._boxes = 0; CV.Box = function(self, ...) CV._boxes = CV._boxes + 1; return ob(self, ...) end
  local obeg = CV.Begin; CV.Begin = function(self, ...) CV._texts = {}; CV._boxes = 0; return obeg(self, ...) end
  return CV end
RR.Open("livro")
local f = LucroLivroFrame
f.Tabs[2]._scripts.OnClick(f.Tabs[2])
local rows = {}
for _, e in ipairs(CV._texts) do rows[e.y] = rows[e.y] or {}; table.insert(rows[e.y], e.t) end
local ys = {}
for y in pairs(rows) do table.insert(ys, y) end
table.sort(ys)
for i, y in ipairs(ys) do if i <= 26 then print(table.concat(rows[y], " | "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end end
print("caixas", CV._boxes)
