dofile("t26.lua")
local S = RR.Craft.Sell
local m = { id = 241305, a = { now = 30149, typical = 40000 }, signal = "normal" }
C_AuctionHouse.GetCommoditySearchResultInfo = function(id, i) return { unitPrice = 39900, containsOwnerItem = false } end
print("live", S.SuggestPrice(m))
C_AuctionHouse.GetCommoditySearchResultInfo = function() return { unitPrice = 20000 } end
print("crash -> floor", S.SuggestPrice(m))
C_AuctionHouse.GetCommoditySearchResultInfo = function() return nil end
print("stored", S.SuggestPrice(m))
m.signal = "hold"; print("hold", S.SuggestPrice(m))
