-- v1.36.1: aba Auditoria desenhada (ideia 5).
-- Era uma parede de texto: servia para copiar, não para entender. Os três bugs de número que
-- apareceram nesta série foram diagnosticados lendo o SavedVariables com script — o usuário não
-- tinha esse caminho. Agora a aba desenha a partir da LINHA auditada (ns.auditOut.row): a conta
-- aberta, os reagentes com preço unitário, as fontes de preço com a escolhida marcada, e por que a
-- receita é ou não recomendada. O texto cru continua a um clique.
dofile("harness11.lua")
local G = dofile("geom.lua")
local C = RR.Craft
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

print("=== a auditoria guarda a LINHA, nao so o texto ===")
local alvo
for _, e in pairs(LucroCraftDB.chars[C.CharKey()] or {}) do
	for _, r in ipairs(e.rows or {}) do
		if r.perConc and r.perConc > 0 and r.parts and #r.parts > 0 and not alvo then alvo = r end
	end
end
print("  receita escolhida: " .. tostring(alvo and alvo.name))
local out = C.AuditTo(tostring(alvo.recipeID))
print("  linhas de texto: " .. #(out.lines or {}))
print("  out.row preenchida: " .. tostring(out.row ~= nil))
print("  out.row e a receita certa: " .. tostring(out.row == alvo))
print("  out.e (profissao) preenchida: " .. tostring(out.e ~= nil))

print("")
print("=== a aba desenha (modo grafico) ===")
C.auditRaw = false
C.UI.ShowTab(C.UI.TAB.AUDIT)
C.UI.RefreshTab(C.UI.TAB.AUDIT)
local cv = LucroCraftFrame.canvases[C.UI.TAB.AUDIT]
local nTexto = cv.used.text or 0
local nIcone = cv.used.icon or 0
local nCaixa = cv.used.box or 0
print(string.format("  widgets: %d textos, %d icones, %d caixas", nTexto, nIcone, nCaixa))
local secoes = {}
for i = 1, nTexto do
	local t = strip(cv.pools.text[i]._text or "")
	for _, chave in ipairs({ "A conta", "Reagentes", "Preço do item vendido", "Operação e decisão" }) do
		if t:find(chave, 1, true) then secoes[chave] = true end
	end
end
local faltam = {}
for _, chave in ipairs({ "A conta", "Reagentes", "Preço do item vendido", "Operação e decisão" }) do
	if not secoes[chave] then table.insert(faltam, chave) end
end
print("  secoes presentes: " .. (4 - #faltam) .. " de 4"
	.. (#faltam > 0 and ("  (faltam: " .. table.concat(faltam, ", ") .. ")") or ""))

print("")
print("=== nada desenhado fora do canvas ===")
local total, fora = G.Check(cv)
print(string.format("  %d widgets posicionados, %d fora  %s", total, #fora, #fora == 0 and "ok" or "PROBLEMA"))
for i = 1, math.min(3, #fora) do print("     " .. fora[i]) end

print("")
print("=== o texto cru continua acessivel ===")
C.auditRaw = true
C.UI.RefreshTab(C.UI.TAB.AUDIT)
local nCru = cv.used.text or 0
C.auditRaw = false
C.UI.RefreshTab(C.UI.TAB.AUDIT)
local nVolta = cv.used.text or 0
print(string.format("  modo cru: %d textos · de volta ao desenho: %d textos", nCru, nVolta))

print("")
print("=== sem auditoria nenhuma, a aba explica o que fazer ===")
C.auditOut = nil
C.UI.RefreshTab(C.UI.TAB.AUDIT)
local vazio = strip(cv.pools.text[1] and cv.pools.text[1]._text or "")
print("  " .. vazio:sub(1, 64))

print("")
local ok = out.row == alvo and out.e ~= nil and #faltam == 0 and #fora == 0
	and nIcone > 0 and nCru > 0 and nVolta > 0 and vazio:find("Alt", 1, true) ~= nil
print(ok and "OK: a auditoria desenha a conta, os reagentes, os precos e a decisao"
	or string.format("FALHA (row=%s secoes=%d fora=%d icones=%d cru=%d)",
		tostring(out.row == alvo), 4 - #faltam, #fora, nIcone, nCru))
