dofile("harness.lua")
local C = RR.Craft; local Q = C.Queue
FIRE("BAG_UPDATE_DELAYED")
for i, fn in ipairs(TIMERS) do local inf = debug.getinfo(fn, "S"); fn(); print(i, inf.short_src, inf.linedefined, #Q.Build()) end
