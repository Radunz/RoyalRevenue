-- v1.30.0: cada aba de Receitas tem a SUA curva ABC.
--   Concentração     -> ouro por ponto de concentração (r.concAbc)
--   Sem concentração -> margem, lucro ÷ custo (r.abc / r.mixAbc)
-- Antes a aba "Sem concentração" jogava tudo que dava lucro em A (abcFree), sem B nem C.
dofile("harness11.lua")
local C = RR.Craft
local e = LucroCraftDB.chars["Radunz-Goldrinn"][2906]   -- Alquimia Midnight
C.Scanner.ApplyABC(e.rows)

local cc, nc = { A = 0, B = 0, C = 0 }, { A = 0, B = 0, C = 0 }
for _, r in ipairs(e.rows) do
	if r.concAbc then cc[r.concAbc] = cc[r.concAbc] + 1 end
	if r.abc then nc[r.abc] = nc[r.abc] + 1 end
end
print(string.format("aba Concentração (ouro/ponto): A=%d B=%d C=%d", cc.A, cc.B, cc.C))
print(string.format("aba Sem concentração (margem): A=%d B=%d C=%d", nc.A, nc.B, nc.C))

print("")
print("=== curva da margem, na ordem ===")
local l = {}
for _, r in ipairs(e.rows) do if r.abc and r.abcShare then table.insert(l, r) end end
table.sort(l, function(x, y) return x.abcShare > y.abcShare end)
local cum = 0
for _, r in ipairs(l) do
	print(string.format("  %s %-28s margem %5.1f%%  share %5.1f%%  acum %5.1f%%", r.abc, tostring(r.name):sub(1, 28),
		(r.margin or 0) * 100, r.abcShare * 100, cum * 100))
	cum = cum + r.abcShare
end

print("")
print("=== a mesma receita pode ter classe diferente em cada aba ===")
for _, r in ipairs(e.rows) do
	if r.abc and r.concAbc then
		print(string.format("  %-28s sem conc=%s (margem %.1f%%)  ·  com conc=%s (%.1f ouro/ponto)",
			tostring(r.name):sub(1, 28), r.abc, (r.margin or 0) * 100, r.concAbc, (r.perConc or 0) / 10000))
	end
end

print("")
print("=== curva só com o que dá lucro e vende (ordem por margem, não por volume) ===")
local semLucro, semGiro = 0, 0
local minSpd = tonumber(C.Cfg("minSoldPerDay")) or 1
for _, r in ipairs(e.rows) do
	if not r.abc and not r.concAbc then
		if (r.profit or 0) <= 0 and not (r.perConc and r.perConc > 0) then semLucro = semLucro + 1
		elseif (r.spd or 0) < minSpd then semGiro = semGiro + 1 end
	end
end
print(string.format("  fora das duas curvas: %d sem lucro · %d sem giro", semLucro, semGiro))
