dofile("harness11.lua")
C_CurrencyInfo = C_CurrencyInfo or { GetCurrencyInfo = function(id) return { name = "Moeda" .. id } end }
C_Item.GetItemInfoInstant = function(id) return tonumber(id) or 1, "", "", "", 0, 7, 5 end
local LV = RR.Livro
local orig = LV.Canvas.Create
local CV
LV.Canvas.Create = function(...) CV = orig(...); local ot = CV.Text; CV._texts = {}; CV.Text = function(self, x, y, t, ...) table.insert(CV._texts, { x = x, y = y, t = t }); return ot(self, x, y, t, ...) end
  local obeg = CV.Begin; CV.Begin = function(self, ...) CV._texts = {}; return obeg(self, ...) end
  return CV end
local Ledger = LV.Ledger
-- migração Cuzolth
local n = 0
for _, c in pairs(LucroLivroDB.chars) do for _, e in ipairs(c.journal or {}) do if e.h == "Cuzolth" and e.v < 0 and e.c then n = n + 1 end end end
local function dump()
  local rows = {}
  for _, e in ipairs(CV._texts) do rows[e.y] = rows[e.y] or {}; table.insert(rows[e.y], e.t) end
  local ys = {}; for y in pairs(rows) do table.insert(ys, y) end; table.sort(ys)
  for _, y in ipairs(ys) do print((table.concat(rows[y], " | "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
end
print("cuzolth lancamentos", n)
RR.Open("livro")
local f = LucroLivroFrame
f.Tabs[2]._scripts.OnClick(f.Tabs[2])
dump()
print("======== centros ON")
LucroLivroDB.config.dreCenters = true
LV.UI.Refresh()
dump()
