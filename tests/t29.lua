dofile("harness.lua")
local C = RR.Craft; local RS = C.RecipeShop
local list = RS.Missing()
local function find(n) for _, m in ipairs(list) do if m.name == n then return m end end end
local nos, oog, emb = find("Alluring Nostrum"), find("Ooey-Gooey Chocolate"), find("Thalassian Competitor's Emblem")
-- vendedor: receita vinculada
GetMerchantNumItems = function() return 2 end
GetMerchantItemLink = function(i) return i == 1 and "|cff|Hitem:5001|h[Recipe: Alluring Nostrum]|h|r" or "|cff|Hitem:5002|h[Pattern: Thalassian Competitor's Emblem]|h|r" end
C_MerchantFrame = { GetItemInfo = function(i) return { price = i == 1 and 0 or 2500000 } end }
local gi = C_Item.GetItemInfo
C_Item.GetItemInfo = function(x) local id = tonumber(tostring(x):match("item:(%d+)") or x); if id == 5001 then return "R", "l", 1,1,1,"","",1,"",1,1,9,0,1 end if id == 5002 then return "R","l",1,1,1,"","",1,"",1,1,9,0,2 end return gi(x) end
FIRE("MERCHANT_SHOW")
-- scan: emblem à venda, depois some no scan seguinte
RS.BeginScan(); RS.OnListing("Pattern: " .. emb.name, 5002, 1800000, 2); RS.EndScan()
NOW = NOW + 86400
RS.BeginScan(); RS.EndScan()
local res = RS.Build()
for _, g in ipairs(res.groups) do for _, m in ipairs(g.items) do
  if m == nil then end
  if m.name == nos.name or m.name == oog.name or m.name == emb.name then
    print(m.name, "vText", m.vText, "vCopper", m.vCopper, "bind", m.bind, "noAH", m.noAH, "here", m.here and m.here.min, "seen", m.hereSeen and m.hereSeen.seenMin, "price", m.price, m.buyAt, m.signal, m.crafts, m.weeks)
  end end end
print(RS._Category and "ok")
print(pcall(RS.Render, (function() C.UI.ShowTab(9) return LucroCraftFrame.canvases[9] end)()))
