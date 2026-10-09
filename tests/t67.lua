dofile("harness11.lua")
local C = RR.Craft
local HERB = { [236761]=1,[236770]=1,[236778]=1,[236776]=1,[236774]=1,[236767]=1,[236780]=1,[236771]=1,[236779]=1 }
C_Item.GetItemInfoInstant = function(id) id = tonumber(id); if HERB[id] then return id, "", "", "", 0, 7, 9 end; if id and id >= 237359 and id <= 237366 then return id, "", "", "", 0, 7, 7 end; if C.Gather.MOTES[id] then return id, "", "", "", 0, 7, 12 end; return id, "", "", "", 0, 15, 0 end
local PR = { [236761] = 1000, [236949] = 5900, [236770] = 30000, [236778] = 20000, [236776] = 60000, [237497] = 100000, [238465] = 50000, [236774] = 50000, [236767] = 15000, [237359] = 2000, [237362] = 15000, [237364] = 40000, [237361] = 9000, [237363] = 30000 }
C.Pricing.Sale = function(id) return PR[id] or 10000 end
for _, prof in ipairs({ "herb", "mining" }) do
  local an = C.Gather.Analyze(prof)
  print("==", prof, "n", an.n, "rate", an.rate, "nodeValue", an.nodeValue / 10000, "plain", an.plainValue / 10000, "named", an.named)
  for _, m in ipairs(an.mods) do print("  mod", m.key, m.n, string.format("share %.2f avg %.2f delta %.2f", m.share, m.avg / 10000, m.delta / 10000)) end
end
C.UI.ShowTab(3)
local cv = LucroCraftFrame.canvases[3]
cv:Begin()
print(pcall(C.Invest._RenderGathering, cv, { parentID = 182, name = "Herbalism", class = "HUNTER" }, 760))
for i = 1, (cv.used.text or 0) do local t = cv.pools.text[i]._text or ""; t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""); if t ~= "" then io.write(t, " | ") end end
print()
