dofile("harness.lua")
local C = RR.Craft
-- mocks de preço a partir do audit salvo
local price = {}
local function scan(t,d) if d>12 then return end for k,v in pairs(t) do if type(v)=="table" then if k=="prices" then for id,p in pairs(v) do if type(p)=="table" and p.usedCost then price[id]=p end end else scan(v,d+1) end end end end
scan(LucroCraftDB,0)
C.Pricing.Cost = function(id) return price[id] and price[id].usedCost end
C.Pricing.MarketNow = function(id) return price[id] and price[id].DBMinBuyout end
C.Pricing.VendorBuy = function() return nil end
C.Pricing.HasAnySource = function() return true end
C.Pricing.Sale = function(id) return price[id] and price[id].usedSale end
print("BoundCost 242651:", C.Salvage.BoundCost(242651))
local _, info = C.Salvage.BoundCost(242651); print(info and info.name, info and info.input, info and info.perOut, info and info.use)
for c, es in pairs(LucroCraftDB.chars) do if c:find("Madunz") then for _, e in pairs(es) do
  if e.parentID == 171 then
    for _, r in ipairs(e.rows) do if r.name:find("Transmute") then print("ANTES", r.name, math.floor(r.cost), math.floor(r.profit)) end end
    C.Scanner.Reprice(e, c)
    for _, r in ipairs(e.rows) do if r.name:find("Transmute") then
      local s = {} for _, p in ipairs(r.parts) do s[#s+1] = p.qty.."x"..p.itemID.."@"..math.floor(p.unit)..(p.crafted and "(c)" or "")..(p.boundCost and "(b)" or "") end
      print("DEPOIS", r.name, math.floor(r.cost), "profit", math.floor(r.profit), "base", math.floor(r.profitBase), table.concat(s, " ")) end end
    -- outras receitas que usam 242651
    for _, r in ipairs(e.rows) do for _, p in ipairs(r.parts or {}) do if (p.buyItem or p.itemID) == 242651 and not r.name:find("Transmute") then print("usa", r.name, p.qty, math.floor(p.unit), math.floor(r.profit or 0)) end end end
  end end end end
-- UI: aba receitas no Madunz alquimia
C.UI.ShowTab(1)
LucroCraftDB.last = { char = "Madunz-Goldrinn", professionID = 2906 }
local ok, err = pcall(C.UI.Refresh); print("refresh", ok, err)
print("cat", C.UI.Category({ name = "Transmute: Mote of Light", profit = 5 }), C.UI.Category({ name = "X", profit = -1 }))
-- tooltip
for c, es in pairs(LucroCraftDB.chars) do if c:find("Madunz") then for _, e in pairs(es) do if e.parentID == 171 then for _, r in ipairs(e.rows) do if r.name == "Transmute: Mote of Light" then
 local lines = {}
 GameTooltip.AddLine = function(_, t) lines[#lines+1] = tostring(t) end
 GameTooltip.AddDoubleLine = function(_, a, b) lines[#lines+1] = tostring(a) .. " | " .. tostring(b) end
 local row = { data = r }
 -- chamar ShowTooltip via row script: pega de uma linha criada
 for _, rw in ipairs(LucroCraftFrame.rows or {}) do if rw._scripts.OnEnter then rw.data = r; rw._scripts.OnEnter(rw); break end end
 for _, l in ipairs(lines) do print("  ", l) end
end end end end end end
