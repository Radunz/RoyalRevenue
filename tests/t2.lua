NOW = os.time({year=2026, month=10, day=4, hour=15})
-- Auctionator falso: 21 dias, terça 10% mais barata, tendência de alta de 1%/dia
local DAY0 = os.time({year=2020, month=1, day=1, hour=0})
local today = math.floor((NOW - DAY0) / 86400)
local function wdOfRaw(raw) return os.date("*t", DAY0 + raw*86400 + 43200).wday end
Auctionator = { Constants = { SCAN_DAY_0 = DAY0 }, API = { v1 = {
	GetAuctionPriceByItemID = function(_, id) return 10000 end,
	ConvertToSearchString = function(_, t) return t.searchString .. ";" .. (t.quantity or "") end,
	CreateShoppingList = function(_, name, terms) SHOP = { name = name, terms = terms } end,
} } }
Auctionator.Database = {
	GetPriceHistory = function(self, key)
		local out = {}
		for raw = today, today - 20, -1 do
			local base = 10000 * (1 + 0.01 * (raw - today))
			local w = wdOfRaw(raw)
			if w == 3 then base = base * 0.9 elseif w == 7 then base = base * 1.08 end
			table.insert(out, { rawDay = tostring(raw), minSeen = math.floor(base), maxSeen = math.floor(base * 1.05) })
		end
		return out
	end,
	GetPrice = function(self, key) return 10600 end,
	GetPriceAge = function(self, key) return 0 end,
	GetMeanPrice = function() return 10000 end,
}
dofile("harness.lua")
local C = RR.Craft
local res = C.Buy.Build()
print("groups", #res.groups, "nBuy", res.nBuy, "costNow", res.costNow, "best", res.best and C.Buy.WD_LONG[res.best], "days", res.days)
for w=1,7 do io.write(string.format("%s %.4f  ", C.Buy.WD_SHORT[w], res.wd[w]/res.costTyp-1)) end print()
local m = res.items[1]
print("item", m.buyId, "need", m.need, "own", m.own, "buy", m.buy, "now", m.a.now, "typ", m.a.typical, "sig", m.a.signal, "conf", m.a.conf, "best", m.a.best)
for w=1,7 do local x=m.a.wd[w]; io.write(string.format("%s %s(%d) ", C.Buy.WD_SHORT[w], x.idx and string.format("%.3f",x.idx) or "-", x.n)) end print()
for _, g in ipairs(res.groups) do print(g.char, #g.order, g.cost) end
-- desenho
local cv = C.Visual.Create(UIParent)
local texts = {}
local origText = cv.Text
cv.Text = function(self, x, y, t, ...) table.insert(texts, t) return origText(self, x, y, t, ...) end
C.Buy.Render(cv)
print("texts", #texts)
for i = 1, 40 do print(texts[i]) end
-- export
C.Buy.ExportAuctionator()
print("shop", SHOP and SHOP.name, SHOP and #SHOP.terms)
-- tab abre
C.UI.ShowTab(C.UI.TAB.BUY)
print("tab ok", C.UI.CurrentTab())
