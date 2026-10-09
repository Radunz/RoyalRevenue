-- agendamento do scan: fabricando em sequência não reescaneia a cada craft
dofile("harness12.lua")
RUNTIMERS()
local scans = 0
RR.Craft.Scanner.Scan = function() scans = scans + 1; return { professionID = 2906 } end
C_TradeSkillUI.GetChildProfessionInfo = function() return { professionID = 2906 } end
RR.Craft.UI.Select = function() end
-- timers com hora: guarda (quando, fn)
local Q = {}
C_Timer.After = function(s, fn) table.insert(Q, { at = HTIME + s, fn = fn }) end
local function advance(to) while true do table.sort(Q, function(a, b) return a.at < b.at end); local x = Q[1]; if not x or x.at > to then break end; table.remove(Q, 1); HTIME = x.at; x.fn() end; HTIME = to end
FIRE("TRADE_SKILL_SHOW"); advance(HTIME + 1); print("abriu", scans)
for i = 1, 10 do FIRE("TRADE_SKILL_LIST_UPDATE"); advance(HTIME + 2) end
print("10 crafts a cada 2 s (20 s)", scans)
advance(HTIME + 5); print("parou de fabricar +5 s", scans)
for i = 1, 25 do FIRE("TRADE_SKILL_LIST_UPDATE"); advance(HTIME + 2) end
print("50 s fabricando (máx. 30 s)", scans)
C_TradeSkillUI.GetChildProfessionInfo = function() return { professionID = 2907 } end
FIRE("TRADE_SKILL_LIST_UPDATE"); advance(HTIME + 1); print("trocou expansão", scans)
