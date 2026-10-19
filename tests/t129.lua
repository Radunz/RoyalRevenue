-- v1.40.0: aba Acerto (previsto x realizado), ideia 1.
--
-- O addon prevê lucro o tempo todo e nada conferia se deu certo. O motor da comparação existia no
-- Sales.lua desde que a aba Vendas foi para o Livro, e ninguém chamava o GetRows(). Agora tem tela.
--
-- O teste injeta vendas com erro CONHECIDO (o item vendeu a 80%, 150%, 40%... do previsto) e cobra
-- da tela os números de volta. Sem isso a aba seria só "parece certo no print".
dofile("harness13.lua")
local TSM = dofile("tsmstub.lua")
local G = dofile("geom.lua")
local C = RR.Craft
local A = C.Acerto

TSM.Install()

-- ===== vendas sintéticas no formato do TSM Accounting =====
-- itemString,stackSize,quantity,price,otherPlayer,player,time,source
local FATOR = { 1.00, 0.80, 1.50, 0.40, 1.05, 0.95, 2.20 }
local QTDE = { 40, 120, 3, 250, 8, 400, 1 }

local alvos = {}
for _, profs in pairs(LucroCraftDB.chars or {}) do
	for _, e in pairs(profs) do
		if type(e) == "table" and e.rows then
			for _, r in ipairs(e.rows) do
				if r.itemID and r.sale and r.sale > 0 and #alvos < #FATOR then
					local repetido = false
					for _, a in ipairs(alvos) do if a.itemID == r.itemID then repetido = true end end
					if not repetido then
						table.insert(alvos, { itemID = r.itemID, sale = r.sale, name = r.name,
							fator = FATOR[#alvos + 1], qty = QTDE[#alvos + 1] })
					end
				end
			end
		end
	end
end

local agora = time()
local linhas = {}
for _, a in ipairs(alvos) do
	-- preço por unidade: o CSV do TSM guarda o preço unitário
	a.preco = math.floor(a.sale * a.fator)
	table.insert(linhas, string.format("i:%d,1,%d,%d,Comprador,Radunz,%d,Auction",
		a.itemID, a.qty, a.preco, agora - 86400))
end
-- uma venda de item que NÃO é fabricável: tem de ficar fora da tabela e dentro do total geral
table.insert(linhas, string.format("i:1,1,5,100,Comprador,Radunz,%d,Auction", agora - 86400))
-- uma venda por vendedor (source Vendor): o Sales.Load só conta Auction
table.insert(linhas, string.format("i:%d,1,99,1,Comprador,Radunz,%d,Vendor", alvos[1].itemID, agora - 86400))

TradeSkillMasterDB = { ["r@Goldrinn@internalData@csvSales"] = table.concat(linhas, "\n") }

print(string.format("=== %d itens com venda injetada · HasTSM=%s ===", #alvos, tostring(C.Pricing.HasTSM())))

local rows, sum = A.Dados(true)
local porID = {}
for _, x in ipairs(rows) do porID[x.itemID] = x end

print("")
print("=== o erro que a tela calcula bate com o injetado ===")
local cut = C.Cfg("ahCut") or 0
local okErro, okImp = true, true
for _, a in ipairs(alvos) do
	local x = porID[a.itemID]
	if not x then
		okErro = false
		print(string.format("  %-26s FALHA (nao apareceu na tabela)", tostring(a.name):sub(1, 26)))
	else
		-- o avg sai de gold/qty, e o gold foi preco*qty: volta ao preco unitario
		local espDiff = a.preco / a.sale - 1
		local espImp = a.qty * (a.preco - a.sale) * (1 - cut)
		local bateD = math.abs((x.diff or 0) - espDiff) < 1e-6
		local bateI = math.abs((x.impacto or 0) - espImp) < 1
		if not bateD then okErro = false end
		if not bateI then okImp = false end
		print(string.format("  %-26s x%.2f  erro %+7.1f%% (esp %+7.1f%%) %s · impacto %12s (esp %12s) %s",
			tostring(a.name):sub(1, 26), a.fator, (x.diff or 0) * 100, espDiff * 100,
			bateD and "ok" or "FALHA",
			string.format("%.0f", (x.impacto or 0) / 10000), string.format("%.0f", espImp / 10000),
			bateI and "ok" or "FALHA"))
	end
end

print("")
print("=== a venda de item nao fabricavel fica fora da tabela ===")
print(string.format("  linhas na tabela: %d (itens injetados: %d)  %s", #rows, #alvos,
	#rows == #alvos and "ok" or "FALHA"))
print(string.format("  total geral conta tudo: %d vendidos (tabela soma %d)  %s",
	sum.allQty or 0, sum.qty or 0, (sum.allQty or 0) > (sum.qty or 0) and "ok" or "FALHA"))

print("")
print("=== o erro ponderado e o da carteira, nao a media dos erros ===")
local prev, obt, soltos = 0, 0, 0
for _, a in ipairs(alvos) do
	prev = prev + a.qty * a.sale
	obt = obt + a.qty * a.preco
	soltos = soltos + (a.preco / a.sale - 1)
end
local espPond = obt / prev - 1
local mediaSolta = soltos / #alvos
print(string.format("  ponderado %+.2f%% (esperado %+.2f%%)  %s", (sum.erroPond or 0) * 100, espPond * 100,
	math.abs((sum.erroPond or 0) - espPond) < 1e-6 and "ok" or "FALHA"))
print(string.format("  media solta dos erros seria %+.2f%% -- diferente, e por isso a tela usa o ponderado",
	mediaSolta * 100))
print(string.format("  acima do previsto: %d · abaixo: %d · sem previsao: %d", sum.acima or 0, sum.abaixo or 0, sum.semPrev or 0))

print("")
print("=== ordenacao: erro e impacto pelo modulo ===")
C.Acerto.SetSort("impacto")
if not A.Sort().desc then C.Acerto.SetSort("impacto") end
local grupos = A.Grupos(rows)
local okOrd = true
for _, g in ipairs(grupos) do
	local ant
	for _, x in ipairs(g.linhas) do
		local v = math.abs(x.impacto or 0)
		if ant and v > ant + 1e-9 then okOrd = false end
		ant = v
	end
	print(string.format("  %-16s %d linhas · impacto %s · lucro %s",
		g.char, #g.linhas, C.Pricing.FormatGold(g.impacto), C.Pricing.FormatGold(g.profit)))
end
print(string.format("  decrescente pelo modulo do impacto: %s", okOrd and "ok" or "FALHA"))

print("")
print("=== a tela desenha dentro do canvas ===")
UnitName = function() return "Radunz" end
UnitFullName = function() return "Radunz", "Goldrinn" end
local okShow = pcall(C.UI.ShowTab, C.UI.TAB.ACERTO)
local cv = LucroCraftFrame and LucroCraftFrame.canvases and LucroCraftFrame.canvases[C.UI.TAB.ACERTO]
local fora = {}
local widgets = 0
if okShow and cv and cv.pools then
	pcall(C.UI.RefreshTab, C.UI.TAB.ACERTO)
	widgets, fora = G.Check(cv)
end
print(string.format("  ShowTab=%s widgets=%d fora do canvas=%d  %s", tostring(okShow), widgets, #fora,
	(okShow and widgets > 0 and #fora == 0) and "ok" or "FALHA"))
for i = 1, math.min(4, #fora) do print("     fora: " .. fora[i]) end

print("")
print("=== colunas nao invadem a seguinte, da largura minima para cima ===")
-- A aba declara MIN_W e o UI.TabMinWidth devolve isso, entao a janela nunca chega mais estreita
-- que o que a tabela precisa. Varrer abaixo disso acusaria um defeito que o usuario nao alcanca.
local ORDEM = { "qty", "perDay", "sale", "avg", "diff", "impacto", "profit", "share", "rate" }
local okCols = true
print(string.format("  MIN_W declarado pela aba: %d", A.MIN_W))
for _, W in ipairs({ 1600, 1400, 1010, 960, A.MIN_W }) do
	local c = A.Cols(W)
	local ruim = nil
	-- o nome nao pode encostar na primeira coluna numerica
	if c.nome + c.nomeW > c.qty then ruim = "nome invade qty" end
	for i = 1, #ORDEM - 1 do
		local k, prox = ORDEM[i], ORDEM[i + 1]
		if c[k] + c.w[k] > c[prox] + 1e-9 then ruim = k .. " invade " .. prox end
	end
	if c[ORDEM[#ORDEM]] + c.w[ORDEM[#ORDEM]] > W - 8 + 1e-9 then ruim = "ultima passa da borda" end
	if ruim then okCols = false end
	print(string.format("  W=%-5d nome %d..%d · qty em %d · rate em %d  %s", W, c.nome, c.nome + c.nomeW,
		c.qty, c.rate, ruim or "ok"))
end
-- mesmo numa janela impossivel nenhuma largura sai negativa (o canvas engasga com isso)
local okEstreito = true
for _, W in ipairs({ 820, 600, 300 }) do
	local c = A.Cols(W)
	if c.nomeW <= 0 then okEstreito = false end
end
print(string.format("  abaixo do minimo nenhuma largura fica negativa: %s", okEstreito and "ok" or "FALHA"))

print("")
print("=== o grupo fecha e abre ===")
local char1 = grupos[1] and grupos[1].char
A.Toggle(char1)
local fechado = LucroCraftDB.config.acertoFechado[char1] and true or false
pcall(C.UI.RefreshTab, C.UI.TAB.ACERTO)
local _, foraF = G.Check(cv)
A.Toggle(char1)
local reaberto = LucroCraftDB.config.acertoFechado[char1] == nil
print(string.format("  fechou=%s · reabriu=%s · fora do canvas fechado=%d  %s",
	tostring(fechado), tostring(reaberto), #foraF,
	(fechado and reaberto and #foraF == 0) and "ok" or "FALHA"))

print("")
print("=== sem venda nenhuma a tela nao quebra ===")
TradeSkillMasterDB = { ["r@Goldrinn@internalData@csvSales"] = "" }
A.Invalidate()
local rowsVazio, sumVazio = A.Dados(true)
local okVazio = pcall(C.UI.RefreshTab, C.UI.TAB.ACERTO)
print(string.format("  linhas=%d erroPond=%s render=%s  %s", #rowsVazio, tostring(sumVazio.erroPond),
	tostring(okVazio), (#rowsVazio == 0 and sumVazio.erroPond == nil and okVazio) and "ok" or "FALHA"))

TSM.Remove()

print("")
local ok = okErro and okImp and #rows == #alvos and okOrd and okCols and okVazio and okEstreito
	and #fora == 0 and widgets > 0 and math.abs((sum.erroPond or 0) - espPond) < 1e-6
print(ok and "OK: a aba Acerto devolve o erro injetado e desenha dentro do canvas"
	or string.format("FALHA (erro=%s imp=%s nRows=%d ord=%s cols=%s fora=%d)",
		tostring(okErro), tostring(okImp), #rows, tostring(okOrd), tostring(okCols), #fora))
