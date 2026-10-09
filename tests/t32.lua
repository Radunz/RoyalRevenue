dofile("harness.lua")
local C = RR.Craft
print(C.IsTransmute({ name = "Bouquet of Herbs", category = "Transmutations" }), C.IsTransmute({ name = "Box of Rocks", categoryParent = "Transmutações" }), C.IsTransmute({ name = "Amani Extract", category = "Potions" }))
LucroCraftDB.config.transmute = { [1230891] = true, [1230864] = false }
print(C.IsTransmute({ recipeID = 1230891, name = "Box of Rocks" }), C.IsTransmute({ recipeID = 1230864, name = "Transmute: X" }))
print(C.UI.Category({ recipeID = 1230891, name = "Box of Rocks" }))
LucroCraftDB.last = { char = "Madunz-Goldrinn", professionID = 2906 }
C.UI.ShowTab(1); print(pcall(C.UI.Refresh))
