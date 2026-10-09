dofile("harness.lua")
local C = RR.Craft; local Q = C.Queue
print("build0", #Q.Build(), #Q.Shopping())
FIRE("BAG_UPDATE_DELAYED"); print("timers", #TIMERS); for _, fn in ipairs(TIMERS) do fn() end; TIMERS = {}
print("build1", #Q.Build(), #Q.Shopping())
FIRE("BAG_UPDATE_DELAYED"); for _, fn in ipairs(TIMERS) do fn() end; TIMERS = {}
print("build2", #Q.Build(), #Q.Shopping())
