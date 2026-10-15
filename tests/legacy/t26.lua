dofile("t9.lua")
local C = RR.Craft
postLoc = nil
AuctionHouseFrame.AuctionatorSellingFrame = nil
AuctionHouseFrameDisplayMode = { Buy = {}, ItemBuy = {}, CommoditiesBuy = {}, ItemSell = {}, CommoditiesSell = {} }
local calls = {}
AuctionHouseFrame.SetDisplayMode = function(self, mode) calls.mode = mode end
AuctionHouseFrame.SetPostItem = function(self, loc) calls.post = loc; self:SetDisplayMode(AuctionHouseFrameDisplayMode.CommoditiesSell) end
AuctionHouseFrame.CommoditiesSellFrame.PriceInput = { SetAmount = function(_, v) calls.price = v end }
AuctionHouseFrame.CommoditiesSellFrame.QuantityInput = { SetQuantity = function(_, v) calls.qty = v end }
ItemLocation = { CreateFromBagAndSlot = function(_, b, s) return { bag = b, slot = s, IsValid = function() return true end } end }
C_AuctionHouse.GetAvailablePostCount = function() return 30 end
C_AuctionHouse.PostCommodity = function(loc, dur, q, p) calls.posted = { loc.slot, dur, q, p } end
C_AuctionHouse.PostItem = function(loc, dur, q, bid, buy) calls.postedItem = { loc.slot, dur, q, buy } end
LucroCraftFrame:Hide()
TIMERS = {}
FIRE("AUCTION_HOUSE_SHOW"); RUNTIMERS()
print("AH abriu -> aba", C.UI.CurrentTab(), "(Compras=7)", "janela", LucroCraftFrame._shown)
AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.CommoditiesSell)
print("AH Vender -> aba", C.UI.CurrentTab(), "(Vender=8)")
AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
print("AH Comprar -> aba", C.UI.CurrentTab())
local res = C.Sell.Build()
local m
for _, it in ipairs(res.items) do if it.id == 241305 then m = it end end
print("item", m.id, "bag/slot", m.bag, m.slot, "qtd", C.Sell.PostQty(m), "preço", C.Sell.SuggestPrice(m), "selo", m.signal)
C.Sell.PutOnAH(m); RUNTIMERS()
print("SetPostItem", calls.post and calls.post.slot, "preço aplicado", calls.price, "qtd aplicada", calls.qty, "aba", C.UI.CurrentTab())
C.Sell.Post(m)
print("PostCommodity", table.concat(calls.posted or {}, ","))
FIRE("AUCTION_HOUSE_AUCTION_CREATED")
local g; for _, it in ipairs(res.items) do if it.gear then g = it end end
C.Sell.Post(g); print("PostItem", table.concat(calls.postedItem or {}, ","))
-- render com AH aberta: botão Postar
C.UI.ShowTab(C.UI.TAB.SELL)
local cv = LucroCraftFrame.canvases[C.UI.TAB.SELL]
local sub = cv._sellList; local n = 0
for i = 1, sub.used.button do if sub.pools.button[i]._text == "Postar" then n = n + 1 end end
print("botões Postar", n)
