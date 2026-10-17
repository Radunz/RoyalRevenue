-- v1.38.1: procedência num lugar só (ideia 2).
-- "De onde veio este número e quanto dá para confiar nele" era respondida em pedaços espalhados:
-- saleFromContainer, saleOpens, spdProjected, SpdIsEstimate, audit.prices. Quem lia a tela não
-- tinha como saber que uma venda de 720.542 saiu da média de 3 aberturas de um baú.
dofile("harness11.lua")
local C = RR.Craft
local G = dofile("geom.lua")

local function nivel(r, campo)
	local p = C.Provenance(r, campo)
	return p and (p.nivel .. " · " .. p.fonte .. (p.nota and ("  (" .. p.nota .. ")") or "")) or "nil"
end

print("=== venda ===")
print("  normal                : " .. nivel({ sale = 100 }, "sale"))
print("  baú, 3 aberturas      : " .. nivel({ sale = 100, saleFromContainer = true, saleOpens = 3 }, "sale"))
print("  baú, 40 aberturas     : " .. nivel({ sale = 100, saleFromContainer = true, saleOpens = 40 }, "sale"))
print("  sem venda             : " .. nivel({}, "sale"))

print("")
print("=== vendas por dia ===")
print("  normal                : " .. nivel({ spd = 100 }, "spd"))
print("  projetada do baú      : " .. nivel({ spd = 100, spdProjected = true }, "spd"))

print("")
print("=== custo ===")
print("  normal                : " .. nivel({ cost = 100 }, "cost"))
print("  reagente sem preço    : " .. nivel({ cost = 100, missing = true }, "cost"))
print("  reagente fabricado    : " .. nivel({ cost = 100, usesCrafted = true }, "cost"))

print("")
print("=== os níveis têm cor, para a tela não precisar decidir ===")
local niveis = {}
for k in pairs(C.NIVEL_COR) do niveis[#niveis + 1] = k end
table.sort(niveis)
print("  " .. table.concat(niveis, " · "))

print("")
print("=== a aba de Auditoria mostra o bloco ===")
local alvo
for _, e in pairs(LucroCraftDB.chars[C.CharKey()] or {}) do
	for _, r in ipairs(e.rows or {}) do
		if r.parts and #r.parts > 0 and not alvo then alvo = r end
	end
end
C.auditRaw = false
C.AuditTo(tostring(alvo.recipeID))
C.UI.ShowTab(C.UI.TAB.AUDIT)
C.UI.RefreshTab(C.UI.TAB.AUDIT)
local cv = LucroCraftFrame.canvases[C.UI.TAB.AUDIT]
local temBloco, linhas = false, 0
for i = 1, (cv.used.text or 0) do
	local t = (cv.pools.text[i]._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	if t:find("Procedência", 1, true) then temBloco = true end
	for k in pairs(C.NIVEL_COR) do
		if t == k or t:find("^" .. k) then linhas = linhas + 1 break end
	end
end
print("  bloco presente: " .. tostring(temBloco) .. " · linhas de nível: " .. linhas)
local total, fora = G.Check(cv)
print(string.format("  %d widgets, %d fora do canvas  %s", total, #fora, #fora == 0 and "ok" or "PROBLEMA"))

print("")
local fraco = C.Provenance({ sale = 1, saleFromContainer = true, saleOpens = 3 }, "sale")
local proj = C.Provenance({ sale = 1, saleFromContainer = true, saleOpens = 40 }, "sale")
local ok = fraco.nivel == "fraco" and proj.nivel == "projetado"
	and C.Provenance({ spd = 1, spdProjected = true }, "spd").nivel == "projetado"
	and C.Provenance({ cost = 1, missing = true }, "cost").nivel == "fraco"
	and C.Provenance(nil, "sale") == nil
	and temBloco and #fora == 0
print(ok and "OK: uma funcao responde a procedencia, e a Auditoria mostra tudo num bloco"
	or string.format("FALHA (fraco=%s proj=%s bloco=%s fora=%d)",
		fraco and fraco.nivel, proj and proj.nivel, tostring(temBloco), #fora))
