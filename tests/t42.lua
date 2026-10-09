dofile("harness.lua")
local C = RR.Craft
UIParent._w, UIParent._h = 1920, 1080
local f = CreateFrame("Frame"); f._w, f._h = 1300, 1500
f.GetLeft = function() return 900 end; f.GetTop = function() return 1000 end
local pts = {}; f.SetPoint = function(self, ...) pts = { ... } end; f.ClearAllPoints = function() end
print("fit", RR.FitToScreen(f), f._w, f._h, pts[1], pts[4], pts[5])
print("max", RR.ScreenMax(f))
C.UI.ShowTab(1); print("craft w,h", LucroCraftFrame._w, LucroCraftFrame._h)
LucroCraftDB.size = { 3000, 2000 }; C.UI.ApplyTabSize(1); print("após size gigante", LucroCraftFrame._w, LucroCraftFrame._h)
SlashCmdList.ROYALREVENUE("reset"); print("reset", LucroCraftDB.size, LucroCraftFrame._w, LucroCraftFrame._h)
