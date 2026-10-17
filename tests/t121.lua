-- v1.38.0: transmutação que vira baú — o valor da venda é uma PROJEÇÃO, e vale o tamanho da amostra.
-- "alguns geram items que são de simples venda na ah, outros geram item que são baús contendo
-- vários outros itens, tem que verificar o custo médio desses craft para verificar se vale a pena"
-- O valor do baú sai de `Containers.Value`: média do que saiu em N aberturas. Com 3 aberturas isso
-- é um chute, e aparecia com a mesma cara de um preço do TSM tirado de milhares de anúncios.
dofile("harness11.lua")
local C = RR.Craft

print("=== Pricing.Sale diz quando o preço é projeção, e de quantas aberturas ===")
local origGet, origValue, origTSM = C.Containers.Get, C.Containers.Value, C.Pricing.HasTSM
local ABERTURAS = 3
C.Containers.Get = function(id) return id == 555 and { opens = ABERTURAS, out = {}, seen = {} } or nil end
C.Containers.Value = function(id)
	if id ~= 555 then return nil end
	return 720542, { { itemID = 1, avg = 2, value = 720542 } }, ABERTURAS
end

local v, proj, opens = C.Pricing.Sale(555)
print(string.format("  baú (3 aberturas): venda=%s  projecao=%s  aberturas=%s",
	tostring(v), tostring(proj), tostring(opens)))
local v2, proj2 = C.Pricing.Sale(556)
print(string.format("  item comum:        venda=%s  projecao=%s", tostring(v2), tostring(proj2)))

print("")
print("=== a linha guarda a procedência (precisa do Reprice) ===")
local entry
for _, e in pairs(LucroCraftDB.chars[C.CharKey()] or {}) do
	if type(e) == "table" and e.rows then entry = e break end
end
local r = { recipeID = 999, name = "Transmutação de Teste", itemID = 555, qty = 1,
	quality = 1, maxQuality = 2, cost = 300000, parts = {},
	cd = { max = 2, charges = 1, cool = 0, t = time() } }
table.insert(entry.rows, r)
C.Scanner.Reprice(entry, C.CharKey())
print(string.format("  saleFromContainer=%s  saleOpens=%s  sale=%s",
	tostring(r.saleFromContainer), tostring(r.saleOpens), tostring(r.sale)))

print("")
print("=== o limiar de amostra fraca ===")
print("  ns.MIN_OPENS = " .. tostring(C.MIN_OPENS))
for _, n in ipairs({ 1, 3, 9, 10, 50 }) do
	print(string.format("  %2d aberturas -> %s", n, n < C.MIN_OPENS and "amostra fraca (avisa)" or "firme"))
end

print("")
print("=== amostra grande não é marcada como fraca ===")
ABERTURAS = 40
C.Scanner.Reprice(entry, C.CharKey())
local firme = r.saleOpens
print(string.format("  com 40 aberturas: saleOpens=%s  fraca=%s",
	tostring(firme), tostring((firme or 0) < C.MIN_OPENS)))

print("")
print("=== cargas continuam limitando (o que decide 'vale a pena') ===")
local cur, max, nextIn, porDia = C.Charges(r)
print(string.format("  %s de %s cargas · +1 em %s · %s por dia",
	tostring(cur), tostring(max), nextIn and string.format("%.1fh", nextIn / 3600) or "-", tostring(porDia)))

C.Containers.Get, C.Containers.Value, C.Pricing.HasTSM = origGet, origValue, origTSM

print("")
local ok = proj == true and opens == 3 and proj2 ~= true
	and r.saleFromContainer == true and firme == 40
	and C.MIN_OPENS == 10 and cur == 1 and max == 2
print(ok and "OK: projecao do bau sinalizada com o tamanho da amostra, e as cargas limitam"
	or string.format("FALHA (proj=%s opens=%s linha=%s firme=%s cargas=%s/%s)",
		tostring(proj), tostring(opens), tostring(r.saleFromContainer),
		tostring(firme), tostring(cur), tostring(max)))
