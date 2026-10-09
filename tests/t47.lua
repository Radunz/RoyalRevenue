dofile("harness.lua")
local C = RR.Craft; local Q = C.Queue
UnitName = function() return "Radunz" end
LucroCraftDB.config.queueIncludePlan = true
C.UI.ShowTab(5); local cv = LucroCraftFrame.canvases[5]
print(pcall(Q.Render, cv))
print("qList", cv._qList.frame._h, cv._qList.child._h, "sList", cv._sList.frame._h, cv._sList.child._h, "bar shown", LucroCraftFrame.queueBar._shown)
local b = {} for i = 1, cv.used.button do b[#b+1] = cv.pools.button[i]._text end print(table.concat(b, " | "))
