dofile("t2.lua")
local N = RR.Num
for _, v in ipairs({0, 7.7, 42632, 106436.4, 1234567.891, -12761.5, 999.995, 1e9}) do io.write(N(v, 2), "  ", N(v, 0), " | ") end print()
print(RR.Craft.Pricing.FormatGold(127610000), RR.Craft.Pricing.FormatGold(12345), RR.Craft.Pricing.FormatGold(-5))
