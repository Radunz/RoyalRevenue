dofile("harness.lua")
local C = RR.Craft
local list, total = C.Plan.Build()
print("plan items", #list, total)
for _, it in ipairs(list) do print(it.char, it.e.name, it.gain, #it.used) end
