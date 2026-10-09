dofile("harness.lua")
local C = RR.Craft; local S = C.Salvage
UnitName = function() return "Madunz" end; UnitFullName = function() return "Madunz", "Goldrinn" end; for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
GetProfessions = function() return 1 end
GetProfessionInfo = function() return "Alchemy", nil, nil, nil, nil, nil, 171, nil, nil, nil, 2906 end
C.UI.ShowTab(4)
S._DB().selRecipe = 1233129
local cv = LucroCraftFrame.canvases[4]
print(pcall(S.Render, cv))
print("listH", cv._salvListH, "sub shown", cv._salvIn and cv._salvIn.frame._shown, "sub h", cv._salvIn and cv._salvIn.frame._h, "child h", cv._salvIn and cv._salvIn.child._h)
S._DB().selRecipe = 1230892
print(pcall(S.Render, cv), "sub shown (trans)", cv._salvIn and cv._salvIn.frame._shown)
