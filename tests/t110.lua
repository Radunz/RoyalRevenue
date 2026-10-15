-- v1.36.0: conferência de geometria de UI em todas as abas.
-- A sobreposição do nome do item sobre a coluna Custo (v1.35.1) foi achada por acidente: o harness
-- não gravava SetPoint, então nenhum teste conseguia afirmar onde um widget estava. Agora grava, e
-- este teste varre todas as abas procurando o que é inequivocamente errado:
--   - widget desenhado fora da largura do canvas (texto sem largura conta pela extensao do texto).
dofile("harness11.lua")
local G = dofile("geom.lua")
local C = RR.Craft
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end

local NOMES = {}
for nome, id in pairs(C.UI.TAB) do NOMES[id] = nome end

print("=== abas do Craft ===")
local ids = {}
for _, id in pairs(C.UI.TAB) do table.insert(ids, id) end
table.sort(ids)
local problemas = 0
for _, id in ipairs(ids) do
	local okShow = pcall(C.UI.ShowTab, id)
	local cv = LucroCraftFrame and LucroCraftFrame.canvases and LucroCraftFrame.canvases[id]
	if okShow and cv and cv.pools then
		pcall(C.UI.RefreshTab, id)
		local total, fora = G.Check(cv)
		problemas = problemas + #fora
		print(string.format("  %-10s widgets=%-4d fora=%-2d %s",
			NOMES[id] or ("tab" .. id), total, #fora, #fora == 0 and "ok" or "PROBLEMA"))
		for i = 1, math.min(4, #fora) do print("     fora: " .. fora[i]) end
	else
		print(string.format("  %-10s (sem canvas proprio)", NOMES[id] or ("tab" .. id)))
	end
end

print("")
print("=== colunas da tabela de pedidos, em varias larguras ===")
local ruinsTotal = 0
for _, QW in ipairs({ 1200, 946, 750, 600, 520, 400 }) do
	local OC = C.Queue.OrderCols(QW)
	local cols = {
		{ nome = "Item", x = OC.item, w = OC.itemW },
		{ nome = "Custo", x = OC.cost, w = OC.w.cost },
		{ nome = "Reagentes", x = OC.reag, w = OC.w.reag },
		{ nome = "Conc", x = OC.conc, w = OC.w.conc },
		{ nome = "Recompensa", x = OC.reward, w = OC.w.reward },
		{ nome = "Lucro", x = OC.profit, w = OC.w.profit },
		{ nome = "Tempo", x = OC.time, w = OC.w.time },
		{ nome = "Pegar", x = OC.claim, w = OC.w.claim },
		{ nome = "x", x = OC.del, w = OC.delW },
	}
	local ruins = G.Colunas(cols)
	ruinsTotal = ruinsTotal + #ruins
	print(string.format("  QW=%4d  %s", QW, #ruins == 0 and "ok" or ("PROBLEMA: " .. ruins[1])))
end

print("")
print((problemas == 0 and ruinsTotal == 0)
	and "OK: nenhuma aba desenha fora do canvas e nenhuma coluna invade a seguinte"
	or string.format("FALHA (abas=%d colunas=%d)", problemas, ruinsTotal))
