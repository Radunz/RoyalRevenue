dofile("fixtures/sv11.lua")
local c = LucroLivroDB.chars["Radunz-Goldrinn"]
local bal = c.days["2026-10-01"].cashOpen
local function loc(t) return os.date("!%m-%d %H:%M:%S", t - 10800) end
for _, e in ipairs(c.journal) do
  if e.c and e.t < 1790924400 then bal = bal + e.v; print(loc(e.t), e.a, string.format("%10.2f %12.2f", e.v / 10000, bal / 10000), e.h) end
end
print("cashClose 10-01", c.days["2026-10-01"].cashClose / 10000, "open 10-02", c.days["2026-10-02"].cashOpen / 10000, "adj", c.days["2026-10-01"].adj, c.days["2026-10-02"].adj)
