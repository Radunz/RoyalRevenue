dofile("t2.lua")
local C = RR.Craft
GetProfessions = function() return 1, nil end
GetProfessionInfo = function(i) return "Alquimia", 1, 100, 100, 0, 0, 171 end
UnitRace = function() return "Gnomo", "Gnome" end
C_Item.GetItemInfoInstant = function(id) return id, "", "", "", 0, 7, 9 end
local res = C.SecondProf.Build()
print("FAB:")
for _, it in ipairs(res.craft) do print(string.format("  %-14s valor %s racial %s (%s) total %s par %s via %s", it.name, it.value and math.floor(it.value/10000) or "-", it.racialGain and math.floor(it.racialGain/10000) or "-", it.racialText or "", math.floor((it.total or 0)/10000), it.pair or "", it.char or "")) end
print("COLETA:")
for _, it in ipairs(res.gather) do print(string.format("  %-14s valor/h %s racial %s total %s par %s", it.name, it.value and math.floor(it.value/10000) or "-", it.racialGain and math.floor(it.racialGain/10000) or "-", math.floor((it.total or 0)/10000), it.pair or "")) end
C.UI.ShowTab(C.UI.TAB.INVEST)
local cv = LucroCraftFrame.canvases[C.UI.TAB.INVEST]
local n, err = 0
for i = 1, cv.used.text do local t = tostring(cv.pools.text[i]._text); if t:find("Erro") then err = t end if t:find("Segunda") then n = n + 1 end end
print("render: segunda profissão", n, "erro", err)
GetProfessions = function() return 1, 2 end
C.UI.RefreshTab(C.UI.TAB.INVEST)
n = 0 for i = 1, cv.used.text do if tostring(cv.pools.text[i]._text):find("Segunda") then n = n + 1 end end
print("com 2 profissões, grupo aparece?", n)
