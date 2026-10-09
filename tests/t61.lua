dofile("fixtures/sv11.lua")
local day0 = "2026-10-01"
local function loc(t) return os.date("!%Y-%m-%d %H:%M:%S", t - 10800) end
for _, ch in ipairs({ "Radunz", "Nazdru" }) do
  local c = LucroLivroDB.chars[ch .. "-Goldrinn"]
  print("=====", ch, "journal 10-01")
  local first, last
  for _, e in ipairs(c.journal) do
    if loc(e.t):sub(1, 10) == day0 and e.c then
      first = first or e.t; last = e.t
      print(loc(e.t), e.a, e.h, e.v / 10000)
    end
  end
  print("--- TSM 10-01")
  for _, fn in ipairs({ "tsm_csvExpense.csv", "tsm_csvBuys.csv", "tsm_csvIncome.csv", "tsm_csvSales.csv" }) do
    local f = io.open("fixtures/" .. fn); local hdr = f:read("*l")
    for line in f:lines() do
      if line:find("," .. ch .. ",") then
        local t = tonumber(line:match(",(%d%d%d%d%d%d%d%d%d%d),") or line:match(",(%d%d%d%d%d%d%d%d%d%d)$"))
        if t and loc(t):sub(1, 10) == day0 then print(fn, loc(t), line) end
      end
    end
  end
end
