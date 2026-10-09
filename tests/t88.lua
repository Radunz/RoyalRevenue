local SECRET = {}
issecretvalue = function(v) return rawequal(v, SECRET) end
dofile("harness12.lua")
print(RR.AnySecret("player", SECRET, "x", 1), RR.AnySecret("player", "Herb", "x", 1), RR.AnySecret(nil, nil, SECRET))
