-- v1.38.2: as correções desta série, conferidas sobre o dado ATUAL (ideia 5).
-- A fixture sv11 é de 07/10 e não tem os campos criados depois — por isso o Bouquet dela ainda
-- conta 65,9% da profissão no t118. Os testes passavam sobre uma realidade que já não existe.
-- A sv13 é o SavedVariables de hoje, com os campos gravados por scan de verdade.
dofile("harness13.lua")
local C = RR.Craft

print("=== a fixture nova tem os campos que a sv11 não tem ===")
local nVer, nProj, nSaleCont, nCargas, total = 0, 0, 0, 0, 0
for _, profs in pairs(LucroCraftDB.chars or {}) do
	for _, e in pairs(profs) do
		if type(e) == "table" and e.rows then
			if e.ver then nVer = nVer + 1 end
			for _, r in ipairs(e.rows) do
				total = total + 1
				if r.spdProjected then nProj = nProj + 1 end
				if r.saleFromContainer then nSaleCont = nSaleCont + 1 end
				if r.cd and (r.cd.max or 0) > 0 then nCargas = nCargas + 1 end
			end
		end
	end
end
print(string.format("  receitas: %d · com spdProjected: %d · com saleFromContainer: %d · com cargas: %d",
	total, nProj, nSaleCont, nCargas))
print("  profissões com entry.ver gravado: " .. nVer)

print("")
print("=== nenhuma receita domina uma profissão COM denominador suficiente ===")
-- Era isto que o Bouquet quebrava: 79% numa profissão com dezenas de receitas.
-- Mas com poucas receitas escaneadas uma dominar é aritmética, não defeito: a Culinária do
-- Riwariel tem 3 receitas com venda, e a maior leva 92% honestamente. O teste só acusa quando o
-- denominador é grande o bastante para a participação significar alguma coisa.
local MIN_RECEITAS = 10
local pior, piorNome, piorProf, piorN = 0, nil, nil, 0
local pequenas = 0
for _, profs in pairs(LucroCraftDB.chars or {}) do
	for pid, e in pairs(profs) do
		if type(e) == "table" and e.rows then
			C.Scanner.ApplyABC(e.rows)
			local n = 0
			for _, r in ipairs(e.rows) do if (r.spdShare or 0) > 0 then n = n + 1 end end
			if n < MIN_RECEITAS then
				pequenas = pequenas + 1
			else
				for _, r in ipairs(e.rows) do
					if (r.spdShare or 0) > pior then
						pior, piorNome, piorProf, piorN = r.spdShare, r.name, pid, n
					end
				end
			end
		end
	end
end
print(string.format("  profissões com menos de %d receitas (fora da conta): %d", MIN_RECEITAS, pequenas))
print(string.format("  maior participação onde o denominador vale: %.1f%%  (%s, prof %s, %d receitas)",
	pior * 100, tostring(piorNome):sub(1, 28), tostring(piorProf), piorN))
-- Dominar NÃO é defeito por si: o tecido é 68% da Alfaiataria porque é a commodity que todo mundo
-- compra, e vende 6.093/dia de verdade. O defeito é dominar sendo projeção de baú ou item que nem
-- vai para a casa de leilões — foi o caso do Bouquet. É só isso que o teste acusa.
local suspeita = nil
for _, profs in pairs(LucroCraftDB.chars or {}) do
	for _, e in pairs(profs) do
		if type(e) == "table" and e.rows then
			for _, r in ipairs(e.rows) do
				if (r.spdShare or 0) > 0.30 and (r.spdProjected or r.notAuctionable or r.saleFromContainer) then
					suspeita = string.format("%s (%.0f%%, projetado=%s semAH=%s)", tostring(r.name),
						r.spdShare * 100, tostring(r.spdProjected), tostring(r.notAuctionable))
				end
			end
		end
	end
end
print("  dominando SEM ser venda real: " .. (suspeita or "nenhuma  ok"))

print("")
print("=== as duas contas de participação continuam batendo ===")
-- CountsInShare e a mesma regra para a linha de receita e para a linha de tela
local divergem = 0
for _, profs in pairs(LucroCraftDB.chars or {}) do
	for _, e in pairs(profs) do
		if type(e) == "table" and e.rows then
			for _, r in ipairs(e.rows) do
				local conta = C.CountsInShare(r, false)
				local tem = (r.spdShare or 0) > 0
				if conta ~= tem then divergem = divergem + 1 end
			end
		end
	end
end
print("  linhas em que a regra e o resultado discordam: " .. divergem)

print("")
print("=== procedência sobre dado real ===")
local porNivel = {}
for _, profs in pairs(LucroCraftDB.chars or {}) do
	for _, e in pairs(profs) do
		if type(e) == "table" and e.rows then
			for _, r in ipairs(e.rows) do
				local p = C.Provenance(r, "sale")
				if p then porNivel[p.nivel] = (porNivel[p.nivel] or 0) + 1 end
			end
		end
	end
end
local ks = {}
for k in pairs(porNivel) do ks[#ks + 1] = k end
table.sort(ks)
for _, k in ipairs(ks) do print(string.format("  venda %-10s %d receitas", k, porNivel[k])) end

print("")
print("=== as abas abrem sobre o dado de hoje ===")
UnitName = function() return "Radunz" end; UnitFullName = function() return "Radunz", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
local G = dofile("geom.lua")
local problemas, abas = 0, 0
for _, id in pairs(C.UI.TAB) do
	local ok = pcall(C.UI.ShowTab, id)
	local cv = LucroCraftFrame and LucroCraftFrame.canvases and LucroCraftFrame.canvases[id]
	if ok and cv and cv.pools then
		pcall(C.UI.RefreshTab, id)
		abas = abas + 1
		local _, fora = G.Check(cv)
		problemas = problemas + #fora
	end
end
print(string.format("  %d abas desenhadas · %d widgets fora do canvas", abas, problemas))

print("")
local ok = total > 100 and divergem == 0 and suspeita == nil and problemas == 0
print(ok and "OK: as correcoes valem sobre o dado atual, e as abas desenham limpas"
	or string.format("FALHA (receitas=%d divergem=%d suspeita=%s fora=%d)",
		total, divergem, tostring(suspeita), problemas))
