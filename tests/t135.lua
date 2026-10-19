-- v1.40.0: o travamento que o Lokir relatou no CurseForge (19/10).
--
--   17x integer overflow attempting to store nan
--   Blizzard_SharedXML/FormattingUtil.lua:92  GetMoneyString
--   RoyalRevenue/Craft/Pricing.lua:481
--   RoyalRevenue/Craft/UI.lua:1079
--   locals: money = Infinite · goldString = "nan|TInterface\MoneyFrame\UI-GoldIcon..."
--
-- Causa: `if r.concCost and r.concSale then ... r.perConc = r.concProfit / r.concEff`.
-- Com concCost = 0 a guarda PASSAVA, porque **0 e verdadeiro em Lua** -- regra 2 do CLAUDE.md, e a
-- terceira vez nesta base (o ajuste de saldo do Livro e o count do invoice foram as outras duas).
-- O EffectiveConc devolvia o proprio 0, e concProfit/0 = infinito. O infinito chegava no
-- GetMoneyString do jogo e derrubava a interface.
--
-- concCost = 0 e a receita cuja qualidade de cima sai SEM gastar concentracao -- o caso que o
-- proprio Rafael levantou nesta sessao (pedido pedindo Q4 que a pericia ja alcanca).
dofile("harness13.lua")
local C = RR.Craft
local P = C.Pricing

print("=== a formatacao nao passa infinito/nan para o jogo ===")
local inf, nan = math.huge, 0 / 0
local casos = {
	{ inf, "+infinito" }, { -inf, "-infinito" }, { nan, "nan" },
	{ nil, "nil" }, { "texto", "texto" },
}
local okFmt = true
for _, c in ipairs(casos) do
	local okM, m = pcall(P.FormatMoney, c[1])
	local okG, g = pcall(P.FormatGold, c[1])
	local limpo = okM and okG and not tostring(m):find("nan") and not tostring(g):find("nan")
		and not tostring(m):find("inf") and not tostring(g):find("inf")
	if not limpo then okFmt = false end
	print(string.format("   %-10s FormatMoney=%-10s FormatGold=%-22s %s", c[2], tostring(m),
		tostring(g), limpo and "ok" or "FALHA"))
end
-- e numero normal segue formatando
local normal = P.FormatMoney(123456)
print(string.format("   numero normal -> %s  %s", tostring(normal),
	(normal and not tostring(normal):find("nan")) and "ok" or "FALHA"))
okFmt = okFmt and normal ~= nil and not tostring(normal):find("—")

print("")
print("=== EffectiveConc com 0 nao devolve 0 (era o denominador) ===")
local E = C.Scanner.EffectiveConc
local st = { ing = 0, mc = 0, res = 0 }
print(string.format("   EffectiveConc(0)=%s · (nil)=%s · (-5)=%s · (300)=%s",
	tostring(E(0, st)), tostring(E(nil, st)), tostring(E(-5, st)), tostring(E(300, st))))
local okEff = E(0, st) == nil and E(nil, st) == nil and E(-5, st) == nil and E(300, st) == 300
print(string.format("   -> %s", okEff and "ok" or "FALHA"))

print("")
print("=== a receita com concCost = 0 nao gera mais infinito ===")
-- monta o cenario do relato numa receita de verdade da fixture
local alvo, entrada
for char, profs in pairs(LucroCraftDB.chars or {}) do
	for pk, e in pairs(profs) do
		if not alvo and type(e) == "table" and e.rows then
			for _, r in ipairs(e.rows) do
				if r.concCost and r.concSale and r.itemID then alvo, entrada = r, e; break end
			end
		end
	end
end
print(string.format("   receita: %s (concCost original %s)", tostring(alvo and alvo.name),
	tostring(alvo and alvo.concCost)))
alvo.concCost = 0
local okRe = pcall(C.Scanner.Reprice, entrada, nil)
print(string.format("   Reprice rodou: %s", tostring(okRe)))
print(string.format("   concCost=%s concEff=%s perConc=%s concProfit=%s concFree=%s",
	tostring(alvo.concCost), tostring(alvo.concEff), tostring(alvo.perConc),
	alvo.concProfit and "sim" or "nil", tostring(alvo.concFree)))
local semInf = alvo.perConc == nil
	and alvo.concEff ~= math.huge and alvo.perConc ~= math.huge
print(string.format("   perConc ficou nil (nao infinito) e marcou concFree: %s",
	(semInf and alvo.concFree) and "ok" or "FALHA"))
-- e o lucro da qualidade de cima NAO se perde: e craft normal numa qualidade melhor
print(string.format("   concProfit preservado (a receita nao desaparece): %s",
	alvo.concProfit and "ok" or "FALHA"))
local okZero = semInf and alvo.concFree == true and alvo.concProfit ~= nil

print("")
print("=== o caminho que de fato estourou: SEM stats (ou sem engenhosidade) ===")
-- Com stats ligados o EffectiveConc caia em math.max(conc - ing*refund, 1), e o piso de 1 salvava.
-- O estouro exige o outro ramo -- `not Cfg("useStats") or not st or st.ing <= 0` --, que devolvia o
-- proprio conc. Com conc = 0, concProfit/0 = infinito. E o ramo de quem joga com stats desligado.
local cfgAntes = LucroCraftDB.config.useStats
LucroCraftDB.config.useStats = false
print(string.format("   EffectiveConc(0) sem stats = %s (era 0, o denominador)", tostring(E(0, st))))
alvo.concCost = 0
local okRe3 = pcall(C.Scanner.Reprice, entrada, nil)
print(string.format("   Reprice=%s · concEff=%s · perConc=%s", tostring(okRe3),
	tostring(alvo.concEff), tostring(alvo.perConc)))
local semInf2 = alvo.perConc == nil or (alvo.perConc == alvo.perConc and alvo.perConc ~= math.huge
	and alvo.perConc ~= -math.huge)
print(string.format("   nada de infinito: %s  %s", tostring(semInf2), semInf2 and "ok" or "FALHA"))
-- e a formatacao do que sair daqui tambem tem de sobreviver
local okTela = pcall(P.FormatMoney, alvo.perConc)
print(string.format("   FormatMoney do resultado: %s  %s", tostring(P.FormatMoney(alvo.perConc)),
	okTela and "ok" or "FALHA"))
local okSemStats = semInf2 and okTela and E(0, st) == nil
LucroCraftDB.config.useStats = cfgAntes

print("")
print("=== e com concentracao de verdade continua calculando ===")
alvo.concCost = 300
local okRe2 = pcall(C.Scanner.Reprice, entrada, nil)
print(string.format("   concCost=300 -> concEff=%s perConc=%s concFree=%s",
	tostring(alvo.concEff), alvo.perConc and string.format("%.2f", alvo.perConc) or "nil",
	tostring(alvo.concFree)))
local okNormal2 = okRe2 and alvo.perConc ~= nil and alvo.concFree == nil
	and alvo.perConc == alvo.perConc and alvo.perConc ~= math.huge
print(string.format("   -> %s", okNormal2 and "ok" or "FALHA"))

print("")
print("=== varredura: nenhuma receita da fixture produz infinito ou nan ===")
local ruins = 0
for char, profs in pairs(LucroCraftDB.chars or {}) do
	for pk, e in pairs(profs) do
		if type(e) == "table" and e.rows then
			for _, r in ipairs(e.rows) do
				for _, k in ipairs({ "perConc", "profit", "concProfit", "margin", "cost", "sale" }) do
					local v = r[k]
					if type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then
						ruins = ruins + 1
						if ruins <= 5 then
							print(string.format("   RUIM %s.%s = %s", tostring(r.name):sub(1, 30), k, tostring(v)))
						end
					end
				end
			end
		end
	end
end
print(string.format("   campos com infinito/nan: %d  %s", ruins, ruins == 0 and "ok" or "FALHA"))

print("")
local ok = okFmt and okEff and okZero and okNormal2 and okSemStats and ruins == 0
print(ok and "OK: concCost 0 nao vira mais infinito, e a formatacao barra o que o jogo nao aceita"
	or string.format("FALHA (fmt=%s eff=%s zero=%s normal=%s ruins=%d)", tostring(okFmt),
		tostring(okEff), tostring(okZero), tostring(okNormal2), ruins))
