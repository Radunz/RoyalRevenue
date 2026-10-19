-- v1.40.0: a aba Reinos saiu e o nucleo util dela virou um sinal de procedencia.
--
-- Por que a aba saiu (medido nos dados reais do Rafael): o filtro "preco do reino fora da regiao"
-- marcava 156 de 558 itens, e 73% deles vendiam MENOS DE 1/dia -- na populacao geral sao 24%. Dos
-- 156 marcados ele vendeu ZERO. O maior da lista, Junker's Multitool, tinha razao de 389x e girava
-- 0,04/dia. A razao e circular: preco divergente e CAUSADO por falta de liquidez (um anuncio
-- solitario caro em item morto), entao a aba selecionava o sintoma de "nao tem mercado".
--
-- O que motivou a aba era real: a receita de encantamento da imersao contou 200k de lucro que nao
-- dava para realizar. Isso agora aparece onde serve -- na Auditoria, em "Procedencia dos numeros",
-- para a receita que ele esta olhando. O addon ja LIMITAVA o preco (BoundBySale, v1.38.3), mas
-- limitava calado.
dofile("harness13.lua")
local TSM = dofile("tsmstub.lua")
local G = dofile("geom.lua")
local C = RR.Craft
TSM.Install()

local function Ouro(c) return string.format("%.2fo", (c or 0) / 10000) end

print("=== a aba Reinos nao existe mais ===")
print(string.format("   ns.Realms = %s · TAB.REALMS = %s  %s", tostring(C.Realms),
	tostring(C.UI.TAB.REALMS), (C.Realms == nil and C.UI.TAB.REALMS == nil) and "ok" or "FALHA"))
local okFora = C.Realms == nil and C.UI.TAB.REALMS == nil

print("")
print("=== Pricing.RealmGap: a razao entre o seu reino e a regiao ===")
local casos = {
	{ 900020, { DBMinBuyout = 1678654208, DBMarket = 1678654208, DBRegionMarketAvg = 420000000,
		DBRegionSaleAvg = 420000000 }, 4.00, "o caso da imersao" },
	{ 900021, { DBMinBuyout = 100000, DBMarket = 100000, DBRegionMarketAvg = 98000,
		DBRegionSaleAvg = 98000 }, 1.02, "preco normal" },
	{ 900022, { DBMinBuyout = 50000, DBMarket = 50000, DBRegionMarketAvg = 200000,
		DBRegionSaleAvg = 200000 }, 0.25, "barato aqui" },
	{ 900023, { DBMarket = 100000 }, nil, "sem dado da regiao" },
}
local okGap = true
for _, c in ipairs(casos) do
	TSM.Set(c[1], c[2])
	local r = C.Pricing.RealmGap(c[1])
	local bate = (c[3] == nil and r == nil) or (r and math.abs(r - c[3]) < 0.01)
	if not bate then okGap = false end
	print(string.format("   %-22s razao %-8s (esperado %-6s) %s", c[4],
		r and string.format("%.2fx", r) or "nil", tostring(c[3]), bate and "ok" or "FALHA"))
end

print("")
print("=== a procedencia da venda marca 'fraco' quando o reino esta fora ===")
-- pega uma receita salva e troca o preco do item dela
local alvo
for _, profs in pairs(LucroCraftDB.chars or {}) do
	for _, e in pairs(profs) do
		if not alvo and type(e) == "table" and e.rows then
			for _, r in ipairs(e.rows) do
				if r.itemID and r.sale and r.sale > 0 then alvo = r; break end
			end
		end
	end
end
print(string.format("   receita: %s (itemID %s)", tostring(alvo and alvo.name), tostring(alvo and alvo.itemID)))

-- preco saudavel
TSM.Set(alvo.itemID, { DBMinBuyout = 100000, DBMarket = 100000, DBRegionMarketAvg = 95000,
	DBRegionSaleAvg = 95000 })
local pv = C.Provenance(alvo, "sale")
print(string.format("   reino 10o / regiao 9,50o (1,05x) -> nivel=%s nota=%s",
	tostring(pv and pv.nivel), tostring(pv and pv.nota)))
local okFirme = pv and pv.nivel == "firme" and pv.nota == nil

-- o caso da imersao, nos numeros reais
TSM.Set(alvo.itemID, { DBMinBuyout = 1678654208, DBMarket = 1678654208,
	DBRegionMarketAvg = 420000000, DBRegionSaleAvg = 420000000 })
pv = C.Provenance(alvo, "sale")
print(string.format("   reino %s / regiao %s (4x) -> nivel=%s", Ouro(1678654208), Ouro(420000000),
	tostring(pv and pv.nivel)))
print(string.format("      nota: %s", tostring(pv and pv.nota)))
local okFraco = pv and pv.nivel == "fraco" and pv.nota and pv.nota:find("4%.0")

-- o limiar e configuravel
LucroCraftDB.config.realmGapRatio = 10
pv = C.Provenance(alvo, "sale")
local okLimiar = pv and pv.nivel == "firme"
print(string.format("   com realmGapRatio=10, a mesma razao de 4x -> nivel=%s  %s",
	tostring(pv and pv.nivel), okLimiar and "ok (abaixo do limiar, nao avisa)" or "FALHA"))
LucroCraftDB.config.realmGapRatio = nil

print("")
print("=== sem TSM nao ha com o que comparar: segue firme, sem erro ===")
TSM.Remove()
local okSemTSM = pcall(function() return C.Pricing.RealmGap(alvo.itemID) end)
local gapSem = C.Pricing.RealmGap(alvo.itemID)
pv = C.Provenance(alvo, "sale")
print(string.format("   RealmGap=%s · nivel=%s · rodou=%s  %s", tostring(gapSem),
	tostring(pv and pv.nivel), tostring(okSemTSM),
	(gapSem == nil and okSemTSM) and "ok" or "FALHA"))
local okNil = gapSem == nil and okSemTSM

print("")
print("=== a Auditoria desenha com o aviso, dentro do canvas ===")
TSM.Install()
TSM.Set(alvo.itemID, { DBMinBuyout = 1678654208, DBMarket = 1678654208,
	DBRegionMarketAvg = 420000000, DBRegionSaleAvg = 420000000 })
UnitName = function() return "Radunz" end
UnitFullName = function() return "Radunz", "Goldrinn" end
C.auditOut = { row = alvo }
local okShow = pcall(C.UI.ShowTab, C.UI.TAB.AUDIT)
local cv = LucroCraftFrame and LucroCraftFrame.canvases and LucroCraftFrame.canvases[C.UI.TAB.AUDIT]
local widgets, fora = 0, {}
if okShow and cv and cv.pools then
	pcall(C.UI.RefreshTab, C.UI.TAB.AUDIT)
	widgets, fora = G.Check(cv)
end
print(string.format("   ShowTab=%s widgets=%d fora do canvas=%d  %s", tostring(okShow), widgets,
	#fora, (okShow and widgets > 0 and #fora == 0) and "ok" or "FALHA"))
for i = 1, math.min(3, #fora) do print("      fora: " .. fora[i]) end
TSM.Remove()

print("")
local ok = okFora and okGap and okFirme and okFraco and okLimiar and okNil
	and okShow and #fora == 0 and widgets > 0
print(ok and "OK: a aba saiu e o preco de reino fora da regiao virou procedencia fraca na Auditoria"
	or string.format("FALHA (fora=%s gap=%s firme=%s fraco=%s limiar=%s nil=%s canvas=%d)",
		tostring(okFora), tostring(okGap), tostring(okFirme), tostring(okFraco),
		tostring(okLimiar), tostring(okNil), #fora))
