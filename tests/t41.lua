dofile("harness.lua")
local C = RR.Craft; local S = C.Salvage
UnitName = function() return "Madunz" end; UnitFullName = function() return "Madunz", "Goldrinn" end; for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
GetProfessions = function() return 1, 2 end
GetProfessionInfo = function(i) if i == 1 then return "Alchemy", nil, nil, nil, nil, nil, 171 end return "Cooking", nil, nil, nil, nil, nil, 185 end
ProfessionsFrame = { IsShown = function() return true end }
C_TradeSkillUI.GetChildProfessionInfo = function() return { professionID = CHILD, parentProfessionID = 171 } end
for _, ch in ipairs({ 2906, 2871, 2908 }) do CHILD = ch
  local l = S.Recipes(); local n = {} for _, id in ipairs(l) do n[#n+1] = S._DB().recipes[id].name end
  print(ch, #l, table.concat(n, ", "):sub(1, 200))
end
ProfessionsFrame = nil; LucroCraftDB.last.professionID = 2906; print("fechado", #S.Recipes())
C.UI.ShowTab(4); CHILD = 2906; ProfessionsFrame = { IsShown = function() return true end }
print(pcall(S.Render, LucroCraftFrame.canvases[4]))
