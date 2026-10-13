-- v1.34.4: a conciliação do Uriuri acusava -371.797,88 de diferença. O culpado era um "ajuste de
-- conciliação" de 371.797,88 lançado em 09/10 — num dia em que o caixa variou -3.445,95. O ajuste saía
-- do tamanho do saldo inteiro porque CheckAdjustment aceitava last == 0 (0 é verdadeiro em Lua) e
-- calculava diff = ouro - 0. Aqui: o ajuste indevido é removido e o legítimo sobrevive.
dofile("harness11.lua")
local Led = RR.Livro.Ledger
local function G(c) return string.format("%+.2f", (c or 0) / 10000) end

local SPUR, LEGIT = 5000000, 5000000               -- 500 ouro em cada caso
LucroLivroDB.chars["Fake1-Teste"] = {
	class = "MAGE", journal = {
		{ t = 1791571290, a = Led.ADJ_CODE, h = "sessão não salva", v = SPUR, c = 1 },
		{ t = 1791571291, a = "4.4.07", h = "depósito", v = 100000, c = 1 },
	},
	days = { ["2026-10-09"] = { act = {}, inc = {}, out = { ahdep = 100000 }, xin = 0, xout = 0,
		adj = SPUR, cashOpen = 1000000, cashClose = 900000, time = {}, v2 = true } },
}
LucroLivroDB.chars["Fake2-Teste"] = {
	class = "MAGE", journal = {
		{ t = 1791571290, a = Led.ADJ_CODE, h = "sessão não salva", v = LEGIT, c = 1 },
	},
	days = { ["2026-10-09"] = { act = {}, inc = {}, out = {}, xin = 0, xout = 0,
		adj = LEGIT, cashOpen = 1000000, cashClose = 6000000, time = {}, v2 = true } },
}

local function conc(char)                          -- a mesma conta da aba (Livro/UI.lua:548)
	local data = Led.Collect(nil)
	for _, t in ipairs(data.chars) do
		if t.char == char and t.any and t.cashOpen and t.cashClose then
			local tm = Led.Merge({ chars = { t } })
			local td = Led.DRE(tm)
			local mv = td.actGold + td.comm + td.itemsale - td.cashOut + tm.xin - tm.xout + tm.adj
			return t.cashClose - (t.cashOpen + mv)
		end
	end
end

local function estado(tag)
	for _, ch in ipairs({ "Fake1-Teste", "Fake2-Teste" }) do
		local c = LucroLivroDB.chars[ch]
		local n = 0
		for _, e in ipairs(c.journal) do if e.a == Led.ADJ_CODE then n = n + 1 end end
		print(string.format("  %-8s %-13s dia.adj=%9s  lancamentos=%d  diferenca=%9s",
			tag, ch, G(c.days["2026-10-09"].adj), n, G(conc(ch))))
	end
end

print("=== antes: o indevido desconcilia, o legitimo ja fecha ===")
estado("antes")

print("")
print("=== FixAdj0 ===")
Led.rev = (Led.rev or 0) + 1
LucroLivroDB.fixAdj0 = nil
Led.FixAdj0()
Led.rev = (Led.rev or 0) + 1
estado("depois")

print("")
print("=== roda uma vez so (flag no SavedVariables) ===")
LucroLivroDB.chars["Fake2-Teste"].days["2026-10-09"].adj = LEGIT
Led.FixAdj0()
print("  Fake2 dia.adj depois da 2a chamada: " .. G(LucroLivroDB.chars["Fake2-Teste"].days["2026-10-09"].adj))

local d1, d2 = conc("Fake1-Teste"), conc("Fake2-Teste")
local n2 = 0
for _, e in ipairs(LucroLivroDB.chars["Fake2-Teste"].journal) do if e.a == Led.ADJ_CODE then n2 = n2 + 1 end end
print("")
print((math.abs(d1) < 10000 and math.abs(d2) < 10000 and n2 == 1)
	and "OK: ajuste indevido removido, legitimo intacto, as duas contas conciliadas"
	or string.format("FALHA (fake1=%s fake2=%s lancLegitimo=%d)", G(d1), G(d2), n2))
