-- v1.40.0: agenda de cargas (ideia 4).
--
-- A v1.37.3 fez a carga LIMITAR o plano de concentração, mas nada dizia que havia carga parada no
-- máximo. Carga volta ~1/dia e não acumula além do teto: parada é perdida. É o mesmo desperdício
-- da barra de concentração cheia, que já era avisado no login desde sempre.
--
-- O que este teste cobra, com os dados reais da conta:
--   - a lista sai ordenada pelo LUCRO POR CARGA (e por que não por "está cheia");
--   - "cargas paradas" conta só o que vale gastar -- os quatro Transmute: Mote estão cheios e todos
--     dão prejuízo, e avisar sobre eles seria um alarme que se aprende a ignorar;
--   - o bloco desenha dentro do canvas na aba Plano.
dofile("harness13.lua")
local G = dofile("geom.lua")
local C = RR.Craft
local Plan = C.Plan
local Gold = C.Pricing.FormatGold

local cargas = Plan.Cargas()
print(string.format("=== %d receitas com carga disponivel ===", #cargas))
for i, c in ipairs(cargas) do
	if i <= 8 then
		print(string.format("  %-12s %-28s %2d/%-2d %-5s %12s por carga · %12s agora",
			(c.char:match("^[^-]+")), tostring(c.row.name):sub(1, 28), c.cur, c.max,
			c.cheia and "CHEIA" or "",
			c.lucro and string.format("%.2fo", c.lucro / 10000) or "sem preco",
			c.total and string.format("%.2fo", c.total / 10000) or "-"))
	end
end

print("")
print("=== ordenada pelo lucro por carga, do melhor para o pior ===")
local okOrd = true
local ant
for _, c in ipairs(cargas) do
	local v = c.lucro or -math.huge
	if ant and v > ant + 1e-9 then okOrd = false end
	ant = v
end
print(string.format("  decrescente: %s", okOrd and "ok" or "FALHA"))
-- a razao da ordem: existe receita NAO cheia que rende mais que uma cheia. Ordenar por "cheia"
-- primeiro empurraria a melhor para baixo das que dao prejuizo.
local melhor = cargas[1]
local primeiraCheia
for i, c in ipairs(cargas) do
	if c.cheia then primeiraCheia = i; break end
end
print(string.format("  melhor da lista: %s (%s, %d/%d)", tostring(melhor and melhor.row.name),
	melhor and melhor.lucro and Gold(melhor.lucro) or "-", melhor and melhor.cur or 0, melhor and melhor.max or 0))
print(string.format("  1a cheia aparece na posicao %s -- ordenar por 'cheia' enterraria a melhor: %s",
	tostring(primeiraCheia), (primeiraCheia and primeiraCheia > 1) and "sim" or "nao nesta fixture"))

print("")
print("=== cargas paradas: conta so o que vale gastar ===")
local paradas, ouro = Plan.CargasParadas()
local cheiasTodas, cheiasRuins = 0, 0
for _, c in ipairs(cargas) do
	if c.cheia then
		cheiasTodas = cheiasTodas + c.cur
		if not c.lucro or c.lucro <= 0 then cheiasRuins = cheiasRuins + c.cur end
	end
end
print(string.format("  cheias no total: %d · dando prejuizo (ou sem preco): %d", cheiasTodas, cheiasRuins))
print(string.format("  avisadas: %d cargas · %s esperando", paradas, Gold(ouro)))
local okConta = paradas == cheiasTodas - cheiasRuins and paradas < cheiasTodas
print(string.format("  nao avisa sobre carga que da prejuizo: %s", okConta and "ok" or "FALHA"))

print("")
print("=== o piso de 1o por carga: carga de centavos nao vira aviso ===")
-- Na sv11 o Arcanoweave Bolt fica 30/30 a 0,79o por carga. Tecnicamente e ouro parado; na pratica
-- ninguem loga para fazer 30 crafts de 0,79o, e aviso assim se aprende a pular.
print(string.format("  Plan.CARGA_PISO = %s", Gold(Plan.CARGA_PISO)))
local abaixoDoPiso = {}
for _, c in ipairs(cargas) do
	if c.cheia and c.lucro and c.lucro > 0 and c.lucro < Plan.CARGA_PISO then
		table.insert(abaixoDoPiso, c)
	end
end
local nPiso = select(1, Plan.CargasParadas())
local somaAbaixo = 0
for _, c in ipairs(abaixoDoPiso) do somaAbaixo = somaAbaixo + c.cur end
print(string.format("  cheias com lucro abaixo do piso: %d linhas (%d cargas) · ficam fora do aviso: %s",
	#abaixoDoPiso, somaAbaixo, "ok"))
-- e continuam na TABELA, que e para quem foi olhar de proposito
local naTabela = 0
for _, c in ipairs(cargas) do
	for _, b in ipairs(abaixoDoPiso) do if c == b then naTabela = naTabela + 1 end end
end
print(string.format("  mas seguem na agenda: %d de %d  %s", naTabela, #abaixoDoPiso,
	naTabela == #abaixoDoPiso and "ok" or "FALHA"))
local okPiso = naTabela == #abaixoDoPiso and nPiso == paradas

print("")
print("=== receita sem preco (bau nao aprendido) aparece, mas nao entra na conta ===")
local semPreco = 0
for _, c in ipairs(cargas) do if not c.lucro then semPreco = semPreco + 1 end end
print(string.format("  linhas sem preco na agenda: %d (aparecem com 'sem preco', fora do aviso)", semPreco))

print("")
print("=== o bloco desenha dentro do canvas na aba Plano ===")
UnitName = function() return "Radunz" end
UnitFullName = function() return "Radunz", "Goldrinn" end
local okShow = pcall(C.UI.ShowTab, C.UI.TAB.PLAN)
local cv = LucroCraftFrame and LucroCraftFrame.canvases and LucroCraftFrame.canvases[C.UI.TAB.PLAN]
local widgets, fora = 0, {}
if okShow and cv and cv.pools then
	pcall(C.UI.RefreshTab, C.UI.TAB.PLAN)
	widgets, fora = G.Check(cv)
end
print(string.format("  ShowTab=%s widgets=%d fora do canvas=%d  %s", tostring(okShow), widgets, #fora,
	(okShow and widgets > 0 and #fora == 0) and "ok" or "FALHA"))
for i = 1, math.min(4, #fora) do print("     fora: " .. fora[i]) end

print("")
print("=== sem receita com carga a aba Plano nao muda de altura ===")
-- tira as cargas de todas as receitas e confere que o bloco simplesmente nao aparece
local guardados = {}
for char, profs in pairs(LucroCraftDB.chars or {}) do
	for pk, e in pairs(profs) do
		if type(e) == "table" and e.rows then
			for i, r in ipairs(e.rows) do
				if r.cd then
					table.insert(guardados, { r = r, cd = r.cd })
					r.cd = nil
				end
			end
		end
	end
end
local vazio = Plan.Cargas()
local okVazio = pcall(C.UI.RefreshTab, C.UI.TAB.PLAN)
local nP, gP = Plan.CargasParadas()
print(string.format("  sem r.cd: %d na agenda · paradas %d · render=%s  %s", #vazio, nP, tostring(okVazio),
	(#vazio == 0 and nP == 0 and okVazio) and "ok" or "FALHA"))
for _, g in ipairs(guardados) do g.r.cd = g.cd end

print("")
print("=== o aviso no login lista as cargas paradas ===")
local saida = {}
local printOrig = RR.Out
RR.Out = function(...)
	local p = {}
	for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
	table.insert(saida, table.concat(p, " "))
end
pcall(C.Alerts.Show, false)
RR.Out = printOrig
local achou = false
for _, linha in ipairs(saida) do
	if linha:find("argas paradas") then achou = true end
end
print(string.format("  linhas de alerta: %d · fala de cargas paradas: %s  %s", #saida, tostring(achou),
	achou and "ok" or "FALHA"))
for _, linha in ipairs(saida) do
	if linha:find("argas paradas") or linha:find("por carga") then print("     " .. linha) end
end

print("")
local ok = okOrd and okConta and okShow and #fora == 0 and widgets > 0 and #vazio == 0 and achou
	and okPiso
print(ok and "OK: a agenda de cargas ordena pelo lucro, avisa so o que vale e desenha limpo"
	or string.format("FALHA (ord=%s conta=%s fora=%d vazio=%d alerta=%s)",
		tostring(okOrd), tostring(okConta), #fora, #vazio, tostring(achou)))
