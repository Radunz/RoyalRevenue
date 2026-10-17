-- v1.38.0: aviso de número velho + limpeza de código morto.
-- Os números de uma receita só mudam quando a profissão é reaberta (ComputeProfit e ApplyABC
-- rodam no scan). Em quatro ocasiões seguidas foi preciso explicar isso à mão depois de uma
-- correção. Agora a entrada guarda a versão que a calculou e a barra da profissão avisa.
dofile("harness11.lua")
local C = RR.Craft

print("=== root.Version() ===")
print("  versão lida do .toc: " .. tostring(RR.Version and RR.Version()))

print("")
print("=== root.VerCmp: ordena como versão, não como texto ===")
local casos = {
	{ "1.37.6", "1.37.6", 0 },
	{ "1.37.2", "1.37.6", -1 },
	{ "1.37.6", "1.37.2", 1 },
	{ "1.9.0",  "1.10.0", -1 },   -- o caso que texto puro erra
	{ "1.37",   "1.37.0", 0 },
	{ "2.0.0",  "1.99.99", 1 },
	{ nil,      "1.0.0", -1 },
}
local okCmp = true
for _, c in ipairs(casos) do
	local r = RR.VerCmp(c[1], c[2])
	if r ~= c[3] then okCmp = false end
	print(string.format("  %-9s vs %-9s -> %2d  (esperado %2d)  %s",
		tostring(c[1]), tostring(c[2]), r, c[3], r == c[3] and "ok" or "FALHA"))
end

print("")
print("=== a barra da profissão avisa quando o número é de outra versão ===")
-- marca TODAS as profissões do personagem: a barra mostra a atual, que não é necessariamente
-- a primeira da tabela (foi o que fez a primeira versão deste teste medir a entrada errada)
local entradas = {}
for _, e in pairs(LucroCraftDB.chars[C.CharKey()] or {}) do
	if type(e) == "table" and e.rows then table.insert(entradas, e) end
end
local function marcar(v) for _, e in ipairs(entradas) do e.ver = v end end
local function barra()
	C.UI.ShowTab(C.UI.TAB.LIST)
	C.UI.Refresh()
	local t = LucroCraftFrame.profLabel and LucroCraftFrame.profLabel._text or ""
	return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
marcar(RR.Version())
local atual = barra()
marcar("1.30.0")
local velho = barra()
marcar(nil)
local semVer = barra()

print("  scan desta versão:  " .. (atual:find("reabra", 1, true) and "AVISA (errado)" or "sem aviso  ok"))
print("  scan da v1.30.0:    " .. (velho:find("reabra", 1, true) and "avisa  ok" or "SEM AVISO (errado)"))
print("  scan sem versão:    " .. (semVer:find("reabra", 1, true) and "avisa  ok" or "SEM AVISO (errado)"))
print("  texto do aviso: " .. (velho:match("!.*reabra.*") or "-"))

print("")
print("=== nenhuma função exposta sem uso ficou para trás ===")
local mortas = {}
for _, nome in ipairs({ "NumAuctions", "InvalidateCraftMap", "TrendShade", "ClearPriceCache", "TopTabTemplate" }) do
	if (C.Pricing and C.Pricing[nome]) or (C.Scanner and C.Scanner[nome])
		or (C.Visual and C.Visual[nome]) or RR[nome] then
		table.insert(mortas, nome)
	end
end
if RR.Livro and RR.Livro.UI and RR.Livro.UI.ClearCache then table.insert(mortas, "Livro.UI.ClearCache") end
print("  ainda presentes: " .. (#mortas == 0 and "nenhuma  ok" or table.concat(mortas, ", ")))

print("")
local ok = okCmp and not atual:find("reabra", 1, true)
	and velho:find("reabra", 1, true) and semVer:find("reabra", 1, true)
	and #mortas == 0
print(ok and "OK: versao comparada certo, aviso so quando o dado e de outra versao, sem codigo morto"
	or string.format("FALHA (cmp=%s atual=%s velho=%s mortas=%d)",
		tostring(okCmp), tostring(atual:find("reabra", 1, true) ~= nil),
		tostring(velho:find("reabra", 1, true) ~= nil), #mortas))
