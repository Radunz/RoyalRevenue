dofile("harness.lua")
local C = RR.Craft; local RS = C.RecipeShop
-- TSM falso: valor de mercado 600g para as perneiras, taxa de venda baixa
C.Pricing.FlipReference = function(id) if id == 239681 then return 6000000 end return nil end
C.Pricing.SaleRate = function(id) if id == 262591 then return 0.02 end return nil end
local res = RS.Build()
for _, xg in ipairs(res.xgroups) do
  io.write(xg.name, " (", xg.n, "): ")
  for _, g in ipairs(xg.profs) do io.write(g.name, " ", #g.items, ", ") end print()
end
for _, g in ipairs(res.groups) do for _, m in ipairs(g.items) do
  if m.name:find("Cloth Leggings") or m.name:find("Lounge Cushion") or m.name == "Puffer Plate" then
    print(m.name, "listed", m.listed, "real", m.real, m.realWhy, "pc", math.floor(m.perCraft/1e4), "scan", math.floor(m.perCraftListed/1e4), "gain", m.gain and math.floor(m.gain/1e4), "slow", m.slow, m.signal)
  end end end
C.UI.ShowTab(9); print(pcall(RS.Render, LucroCraftFrame.canvases[9]))
LucroCraftDB.config.sellCollapsed = { ["rx:11"] = true }
print(pcall(RS.Render, LucroCraftFrame.canvases[9]))
