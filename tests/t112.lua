-- v1.36.1: descarte de preço fora de escala (ideia 3).
-- Medido no SavedVariables real: o Auctionator traz valor absurdo em 8 de 5.555 itens — o 241307
-- a 17.000,84g contra 5,02g do TSM (3.386x). Com o TSM na frente isso nunca apareceu, mas com o
-- Auctionator como fonte vira lucro fantasioso no plano e na curva, sem nenhum sinal.
dofile("harness11.lua")
local C = RR.Craft
local P = C.Pricing
local Sane = P._Sane

print("=== a regra, isolada (razao limite = " .. tostring(P.SANE_RATIO) .. "x) ===")
local casos = {
	{ nome = "igual a referencia",      v = 50000,     ref = 50000 },
	{ nome = "2x acima",                v = 100000,    ref = 50000 },
	{ nome = "19x acima (passa)",       v = 950000,    ref = 50000 },
	{ nome = "21x acima (descarta)",    v = 1050000,   ref = 50000 },
	{ nome = "o caso real: 3386x",      v = 170008400, ref = 50212 },
	{ nome = "21x ABAIXO (descarta)",   v = 2380,      ref = 50000 },
	{ nome = "sem referencia (passa)",  v = 170008400, ref = nil },
	{ nome = "referencia zero (passa)", v = 170008400, ref = 0 },
}
local ok = true
local esperado = { true, true, true, false, false, false, true, true }
for i, c in ipairs(casos) do
	local r = Sane(1000 + i, c.v, c.ref)
	local passou = r ~= nil
	if passou ~= esperado[i] then ok = false end
	print(string.format("  %-26s valor=%12s ref=%8s -> %s  %s",
		c.nome, tostring(c.v), tostring(c.ref), passou and "usa" or "descarta",
		passou == esperado[i] and "ok" or "FALHA"))
end

print("")
print("=== so avisa uma vez por item (nao polui o log) ===")
local n = 0
local origLog = C.Log
C.Log = function() n = n + 1 end
for _ = 1, 5 do Sane(999, 170008400, 50212) end
C.Log = origLog
print(string.format("  5 descartes do mesmo item -> %d avisos  %s", n, n == 1 and "ok" or "FALHA"))

print("")
print("=== valor valido nao e tocado ===")
local v = Sane(998, 123456, 100000)
print(string.format("  entrou 123456, saiu %s  %s", tostring(v), v == 123456 and "ok" or "FALHA"))

print("")
print((ok and n == 1 and v == 123456)
	and "OK: preco fora de escala e descartado, o resto passa intacto"
	or "FALHA")
