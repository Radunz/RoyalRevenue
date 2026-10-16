-- v1.37.2: a aba Auditoria acompanha a receita selecionada na janela da profissão.
-- Antes só o Alt+clique enchia a aba, então auditar três receitas era trocar de aba três vezes.
-- Agora: clique simples na lista (que já seleciona a receita no jogo) e seleção feita na própria
-- janela da profissão levam a auditoria junto, com um botão para congelar numa receita.
dofile("harness11.lua")
local C = RR.Craft
local UI = C.UI
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
LucroCraftDB.config = LucroCraftDB.config or {}

-- duas receitas de verdade da fixture
local a, b
for _, e in pairs(LucroCraftDB.chars[C.CharKey()] or {}) do
	for _, r in ipairs(e.rows or {}) do
		if r.parts and #r.parts > 0 then
			if not a then a = r elseif not b and r.recipeID ~= a.recipeID then b = r end
		end
	end
end
print(string.format("  receitas: %s (%d) e %s (%d)", a.name, a.recipeID, b.name, b.recipeID))

print("")
print("=== a janela da profissao expoe a receita selecionada ===")
local selecionada
ProfessionsFrame = {
	IsShown = function() return true end,
	CraftingPage = { SchematicForm = {
		-- caminho mais novo: currentRecipeInfo
		currentRecipeInfo = setmetatable({}, { __index = function(_, k)
			if k == "recipeID" then return selecionada end
		end }),
	} },
}
selecionada = a.recipeID
print("  UI.SelectedRecipeID() = " .. tostring(UI.SelectedRecipeID()))

print("")
print("=== caminhos alternativos (se a Blizzard mudar de lugar) ===")
local formOnly = { GetRecipeInfo = function() return { recipeID = 4242 } end }
ProfessionsFrame.CraftingPage.SchematicForm = formOnly
print("  por GetRecipeInfo() -> " .. tostring(UI.SelectedRecipeID()))
ProfessionsFrame.CraftingPage.SchematicForm = { recipeSchematic = { recipeID = 777 } }
print("  por recipeSchematic -> " .. tostring(UI.SelectedRecipeID()))
ProfessionsFrame.CraftingPage.SchematicForm = {}
print("  sem nenhum caminho  -> " .. tostring(UI.SelectedRecipeID()) .. " (nil, sem erro)")
ProfessionsFrame.IsShown = function() return false end
print("  janela fechada      -> " .. tostring(UI.SelectedRecipeID()))

print("")
print("=== seguir ligado: a auditoria troca sozinha ===")
ProfessionsFrame.IsShown = function() return true end
ProfessionsFrame.CraftingPage.SchematicForm = { currentRecipeInfo = { recipeID = a.recipeID } }
LucroCraftDB.config.auditFollow = true
UI.ShowTab(UI.TAB.AUDIT)
UI.AuditFollow(a.recipeID)
local nome1 = C.auditOut and C.auditOut.row and C.auditOut.row.name
UI.AuditFollow(b.recipeID)
local nome2 = C.auditOut and C.auditOut.row and C.auditOut.row.name
print(string.format("  seguiu %s depois %s", tostring(nome1), tostring(nome2)))

print("")
print("=== a mesma receita duas vezes nao re-audita (o laco roda a cada 0,5 s) ===")
local repetiu = UI.AuditFollow(b.recipeID)
print("  AuditFollow na mesma -> " .. tostring(repetiu) .. (repetiu == false and "  ok" or "  FALHA"))

print("")
print("=== seguir desligado: congela na que esta ===")
LucroCraftDB.config.auditFollow = false
local mudou = UI.AuditFollow(a.recipeID)
local nome3 = C.auditOut and C.auditOut.row and C.auditOut.row.name
print(string.format("  tentou trocar para %s -> mudou=%s, continua em %s", a.name, tostring(mudou), tostring(nome3)))

print("")
print("=== mas o Alt+clique continua forcando (forcar=true) ===")
local forcou = UI.AuditFollow(a.recipeID, true)
local nome4 = C.auditOut and C.auditOut.row and C.auditOut.row.name
print(string.format("  forcado -> mudou=%s, agora em %s", tostring(forcou), tostring(nome4)))
LucroCraftDB.config.auditFollow = true

print("")
print("=== o laco so fica ligado na aba de Auditoria ===")
local vivos = 0
C_Timer.NewTicker = function() vivos = vivos + 1; return { Cancel = function() vivos = vivos - 1 end } end
UI.AuditWatch(true)
local ligado = vivos
UI.AuditWatch(false)
local desligado = vivos
print(string.format("  ligado=%d  desligado=%d  %s", ligado, desligado,
	(ligado == 1 and desligado == 0) and "ok" or "FALHA"))

print("")
local ok = nome1 == a.name and nome2 == b.name and repetiu == false
	and mudou == false and nome3 == b.name
	and forcou == true and nome4 == a.name
	and ligado == 1 and desligado == 0
print(ok and "OK: a auditoria segue a selecao, congela quando desligado e o laco so vive na aba"
	or string.format("FALHA (%s/%s repetiu=%s mudou=%s congelou=%s forcou=%s laco=%d/%d)",
		tostring(nome1), tostring(nome2), tostring(repetiu), tostring(mudou),
		tostring(nome3), tostring(forcou), ligado, desligado))
