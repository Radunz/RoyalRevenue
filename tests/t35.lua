dofile("harness.lua")
local C = RR.Craft; local I = C.Invest
for _, d in ipairs({ "Gain an additional charge of |cffffffffWondrous Synergist|r.", "Gain 2 additional charges of |cffffffffWondrous Synergist|r.",
  "|cffffffffWondrous Synergist|r recharges quicker.", "Gain a second charge of |cffffffffSharpen Your Knife|r.", "Transmutations gain an additional charge.", "+10 Skill" }) do
  local c = I.ChargePerk(d, "Inspired Transmutation"); print(d:sub(1,40), c and c.kind, c and c.n, c and c.target)
end
local e = LucroCraftDB.chars["Madunz-Goldrinn"][2906]
for _, c in ipairs(I.ChargePerks(e)) do print("perk", c.kind, c.n, c.target, c.node, c.points, c.locked) end
print("value", I.ChargeValue(e, "Wondrous Synergist"))
UnitName = function() return "Madunz" end; UnitFullName = function() return "Madunz", "Goldrinn" end; for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
LucroCraftDB.last = { char = "Madunz-Goldrinn", professionID = 2906 }
C.UI.ShowTab(3); local cv = LucroCraftFrame.canvases[3]; print(pcall(I.Render, cv))
local found = false
for i = 1, (cv.used and cv.used.text or 0) do local t = cv.pools.text[i]._text or ""; if t:find("carga") or t:find("recarrega") then print("  UI:", t) end end
