dofile("t2.lua")
local C = RR.Craft
local cv = C.Visual.Create(UIParent)
local bad
local o = cv.Text
cv.Text = function(self, x, y, t, ...) if tostring(t):find("Erro") then bad = t end return o(self, x, y, t, ...) end
-- sem Auctionator
Auctionator = nil
C.Buy._ClearCache()
local ok, e = pcall(C.Buy.Render, cv); print("render sem Auctionator", ok, e, bad)
