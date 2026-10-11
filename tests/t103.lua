-- v1.34.0: aba Auditoria. O Alt+clique numa receita "não fazia nada" porque a auditoria só saía
-- em texto, pelo root.Out, que escolhe uma aba de chat chamada Log/RR — e aceita aba apenas
-- ENCAIXADA, então o texto caía numa aba que ninguém estava olhando.
dofile("harness11.lua")
local C = RR.Craft
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
for _, profs in pairs(LucroCraftDB.chars) do
	for _, e in pairs(profs) do if e.rows then C.Scanner.ApplyABC(e.rows) end end
end
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

print("=== a aba existe e começa vazia ===")
print("  TAB.AUDIT = " .. tostring(C.UI.TAB.AUDIT))
C.UI.ShowTab(C.UI.TAB.AUDIT)
local cv = LucroCraftFrame.canvases[C.UI.TAB.AUDIT]
print("  canvas: " .. tostring(cv ~= nil))
print("  texto: " .. strip(cv.pools.text[1] and cv.pools.text[1]._text or ""))

print("")
print("=== Alt+clique numa receita enche a aba e troca para ela ===")
IsAltKeyDown = function() return true end
C.UI.ShowTab(1)
C.UI.Refresh()
local alvo
for _, row in ipairs(LucroCraftFrame.rows or {}) do
	if row.data and row.data.recipeID then alvo = row break end
end
print("  receita: " .. tostring(alvo and alvo.data.name))
alvo._scripts.OnClick(alvo, "LeftButton")
local naAba = LucroCraftFrame.currentTab == C.UI.TAB.AUDIT
local linhas = #(C.auditOut and C.auditOut.lines or {})
print(string.format("  aba atual=%s (AUDIT=%s) · linhas coletadas=%d",
	tostring(LucroCraftFrame.currentTab), tostring(C.UI.TAB.AUDIT), linhas))
for i = 1, math.min(4, linhas) do print("    " .. strip(C.auditOut.lines[i]):sub(1, 72)) end

print("")
print("=== nada foi para o chat/log (é o ponto do conserto) ===")
local noLog = 0
local origOut = RR.Out
RR.Out = function() noLog = noLog + 1 end
C.AuditTo(tostring(alvo.data.recipeID))
RR.Out = origOut
print("  linhas mandadas ao log pelo Alt+clique: " .. noLog)

print("")
print("=== o comando /lucro audit continua mandando para o log ===")
local comLog = 0
RR.Out = function() comLog = comLog + 1 end
C.AuditTo(tostring(alvo.data.recipeID), true)
RR.Out = origOut
print("  linhas mandadas ao log pelo comando: " .. comLog)

print("")
print((naAba and linhas > 0 and noLog == 0 and comLog > 0)
	and "OK: a auditoria aparece na aba, sem depender de aba de chat"
	or string.format("FALHA (aba=%s linhas=%d semLog=%d comLog=%d)", tostring(naAba), linhas, noLog, comLog))
