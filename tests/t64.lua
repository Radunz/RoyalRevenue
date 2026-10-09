_G.__noFix = true
dofile("harness11.lua")
C_Item.GetItemInfoInstant = function(id) return tonumber(id) or 1, "", "", "", 0, 7, 5 end
