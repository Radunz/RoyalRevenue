-- v1.40.2: consumivel no banco nao serve na masmorra.
--
-- Relato: "na aba market > consumiveis, diz que tenho comida, porem no banco e em outros personagem
-- nao me adianta, tenho que ter elas na bag para poder usar na dg".
--
-- Causa: Consum.Groups usava Plan.Count.own -> OwnCountRaw ->
--   C_Item.GetItemCount(id, true, false, true, false)   <- includeBank e includeReagentBank LIGADOS
-- Para CRAFTAR isso esta certo (o Stock.Usable soma bolsa + banco + banco do bando de proposito).
-- Para consumivel nao: o que esta no banco nao entra na masmorra com voce.
--
-- E o conserto nao e mandar comprar: seria gastar ouro no que ele ja tem. Sao TRES estados --
-- na bolsa (pronto), no banco (pegue), nem um (compre).
dofile("harness13.lua")
local C = RR.Craft

-- bolsa x banco x bando controlados pelo teste
local BOLSA, BANCO, BANDO = {}, {}, {}
C_Item.GetItemCount = function(id, incBank, incUses, incReagent, incAccount)
	local n = BOLSA[id] or 0
	if incBank then n = n + (BANCO[id] or 0) end
	if incAccount then n = n + (BANDO[id] or 0) end
	return n
end

print("=== Stock.InBags separa os tres ===")
BOLSA[100] , BANCO[100], BANDO[100] = 5, 12, 7
local b, k, w = C.Stock.InBags(100)
print(string.format("   bolsa=5 banco=12 bando=7 -> InBags devolve %d, %d, %d  %s", b, k, w,
	(b == 5 and k == 12 and w == 7) and "ok" or "FALHA"))
local okSplit = b == 5 and k == 12 and w == 7
-- e o Stock.Usable segue somando tudo, que e o certo para CRAFTAR
local total = C.Stock.Usable(100)
print(string.format("   Stock.Usable (para craftar) segue somando: %d  %s", total,
	total == 24 and "ok (nao mexi nisso)" or "FALHA"))
local okUsable = total == 24

print("")
print("=== o caso do relato: comida so no banco ===")
local COMIDA = 222333
BOLSA[COMIDA], BANCO[COMIDA], BANDO[COMIDA] = 0, 20, 0
-- monta uma sugestao de consumivel com a API interna do Consum
C.Consum.For = function() return { { ids = { COMIDA }, need = 20, note = "comida", why = "teste" } }, 2, 3 end
UnitName = function() return "Nazdru" end
UnitFullName = function() return "Nazdru", "Goldrinn" end
for _, n in ipairs({ "Craft", "Livro" }) do local x = RR[n]; if x and x._ResetCharKey then x._ResetCharKey() end end
local me = C.CharKey()
local gs = C.Consum.Groups(me, false, {})
local m = gs[1] and gs[1].order and gs[1].order[1]
print(string.format("   precisa 20, bolsa 0, banco 20"))
print(string.format("   own(na bolsa)=%s · bank=%s · fetch(pegar)=%s · buy(comprar)=%s",
	tostring(m and m.own), tostring(m and m.bank), tostring(m and m.fetch), tostring(m and m.buy)))
local okBanco = m and m.own == 0 and m.bank == 20 and m.fetch == 20 and m.buy == 0
print(string.format("   -> %s", okBanco and "ok (nao diz que tem na bolsa, e nao manda comprar)" or "FALHA"))

print("")
print("=== os tres estados ===")
local casos = {
	{ bolsa = 20, banco = 0, need = 20, own = 20, fetch = 0, buy = 0, txt = "tudo na bolsa: pronto" },
	{ bolsa = 0, banco = 20, need = 20, own = 0, fetch = 20, buy = 0, txt = "tudo no banco: pegar" },
	{ bolsa = 0, banco = 0, need = 20, own = 0, fetch = 0, buy = 20, txt = "nao tem: comprar" },
	{ bolsa = 5, banco = 5, need = 20, own = 5, fetch = 5, buy = 10, txt = "misturado" },
	{ bolsa = 30, banco = 10, need = 20, own = 30, fetch = 0, buy = 0, txt = "sobra na bolsa" },
}
local okEstados = true
for _, c in ipairs(casos) do
	BOLSA[COMIDA], BANCO[COMIDA], BANDO[COMIDA] = c.bolsa, c.banco, 0
	C.Consum.For = function() return { { ids = { COMIDA }, need = c.need } }, 2, 3 end
	C.Plan.ResetCounts()
	local g = C.Consum.Groups(me, false, {})
	local x = g[1] and g[1].order and g[1].order[1]
	local bate = x and x.own == c.own and x.fetch == c.fetch and x.buy == c.buy
	if not bate then okEstados = false end
	print(string.format("   %-24s bolsa %2d banco %2d -> bolsa=%s pegar=%s comprar=%s  %s",
		c.txt, c.bolsa, c.banco, tostring(x and x.own), tostring(x and x.fetch),
		tostring(x and x.buy), bate and "ok" or "FALHA"))
end

print("")
print("=== banco do bando tambem e 'pegar', nao 'tem' ===")
BOLSA[COMIDA], BANCO[COMIDA], BANDO[COMIDA] = 0, 0, 15
C.Consum.For = function() return { { ids = { COMIDA }, need = 20 } }, 2, 3 end
C.Plan.ResetCounts()
local gb = C.Consum.Groups(me, false, {})
local xb = gb[1] and gb[1].order and gb[1].order[1]
print(string.format("   bando 15, precisa 20 -> bolsa=%s pegar=%s comprar=%s",
	tostring(xb and xb.own), tostring(xb and xb.fetch), tostring(xb and xb.buy)))
local okBando = xb and xb.own == 0 and xb.fetch == 15 and xb.buy == 5
print(string.format("   -> %s", okBando and "ok" or "FALHA"))

print("")
print("=== outro personagem: nao da para afirmar que esta na bolsa ===")
-- o retrato guardado soma bolsa e banco sem separar
LucroCraftDB.inv = LucroCraftDB.inv or {}
LucroCraftDB.inv["Outro-Goldrinn"] = { t = time(), items = { [COMIDA] = 40 } }
LucroLivroDB.chars = LucroLivroDB.chars or {}
LucroLivroDB.chars["Outro-Goldrinn"] = LucroLivroDB.chars["Outro-Goldrinn"] or { class = "HUNTER" }
C.Plan.ResetCounts()
local go = C.Consum.Groups("Outro-Goldrinn", false, {})
local xo = go[1] and go[1].order and go[1].order[1]
print(string.format("   alt com 40 no retrato -> bolsa=%s bank=%s naoSabeBolsa=%s",
	tostring(xo and xo.own), tostring(xo and xo.bank), tostring(xo and xo.naoSabeBolsa)))
local okAlt = xo and xo.own == 0 and xo.bank == 40 and xo.naoSabeBolsa == true
print(string.format("   -> %s", okAlt and "ok (nao finge que esta na bolsa)" or "FALHA"))

print("")
print("=== a lista desenha os tres estados, e nao quebra ===")
LucroCraftDB.config = LucroCraftDB.config or {}
LucroCraftDB.config.buyList = "cons"
BOLSA[COMIDA], BANCO[COMIDA], BANDO[COMIDA] = 5, 10, 0
C.Consum.For = function() return { { ids = { COMIDA }, need = 20 } }, 2, 3 end
C.Plan.ResetCounts()
local G = dofile("geom.lua")
local okShow = pcall(C.UI.ShowTab, C.UI.TAB.BUY)
local cv = LucroCraftFrame and LucroCraftFrame.canvases and LucroCraftFrame.canvases[C.UI.TAB.BUY]
local widgets, fora = 0, {}
if okShow and cv and cv.pools then
	pcall(C.UI.RefreshTab, C.UI.TAB.BUY)
	widgets, fora = G.Check(cv)
end
print(string.format("   ShowTab=%s widgets=%d fora do canvas=%d  %s", tostring(okShow), widgets,
	#fora, (okShow and widgets > 0 and #fora == 0) and "ok" or "FALHA"))
-- a frase "na bolsa" tem de aparecer em algum texto
local achou = false
G.Each(cv, function(wd, tipo)
	if tipo == "text" and tostring(wd._text or ""):find("na bolsa", 1, true) then achou = true end
end)
print(string.format("   a linha fala 'na bolsa': %s", tostring(achou)))

print("")
local ok = okSplit and okUsable and okBanco and okEstados and okBando and okAlt
	and okShow and #fora == 0 and widgets > 0
print(ok and "OK: consumivel conta a BOLSA; banco virou 'pegue', nao 'tem' nem 'compre'"
	or string.format("FALHA (split=%s usable=%s banco=%s estados=%s bando=%s alt=%s fora=%d)",
		tostring(okSplit), tostring(okUsable), tostring(okBanco), tostring(okEstados),
		tostring(okBando), tostring(okAlt), #fora))
