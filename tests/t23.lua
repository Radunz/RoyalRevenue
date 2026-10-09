dofile("t2.lua")
local C = RR.Craft
GetProfessions = function() return nil, nil, nil, 4, 5 end
GetProfessionInfo = function(i) if i == 5 then return "Cooking", 1, 1, 100, 0, 0, 185 end return "Fishing", 1, 1, 100, 0, 0, 356 end
LucroCraftDB.salvage.recipes[999001] = { kind = "salvage", prof = "Cooking", name = "Practically Pork", chars = { [C.CharKey()] = true }, inputs = { 1 }, perCast = 1 }
local list = C.Salvage.Recipes()
for _, rid in ipairs(list) do print("receita na aba:", LucroCraftDB.salvage.recipes[rid].name) end
