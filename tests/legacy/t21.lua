dofile("t20.lua")
local LV = RR.Livro
local orig = LV.Canvas.Create
local CV
LV.Canvas.Create = function(...) CV = orig(...); local ot = CV.Text; CV._t = {}; CV.Text = function(self, x, y, t, ...) table.insert(CV._t, { y = y, t = t }); return ot(self, x, y, t, ...) end
  local ob = CV.Begin; CV.Begin = function(self, ...) CV._t = {}; return ob(self, ...) end; return CV end
local c = LucroLivroDB.chars[RR.Craft.CharKey()]
local d = c.days[os.date("%Y-%m-%d")]
d.inc.order = (d.inc.order or 0) + 771853
RR.Open("livro")
LucroLivroFrame.Tabs[4]._scripts.OnClick(LucroLivroFrame.Tabs[4])
local rows = {}
for _, e in ipairs(CV._t) do rows[e.y] = rows[e.y] or {}; table.insert(rows[e.y], e.t) end
local ys = {} for y in pairs(rows) do table.insert(ys, y) end table.sort(ys)
for _, y in ipairs(ys) do local l = table.concat(rows[y], " | "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""); if l:find("Serviços") or l:find("Pedidos de fabrica") or l:find("TOTAL") then print(l) end end
