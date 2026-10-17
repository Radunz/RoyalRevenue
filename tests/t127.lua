-- v1.39.2: a marca de qualidade estava achatada e de um tamanho diferente em cada tela.
-- "consegue aumentar o tamanho do ícone da qualidade, deixar igual ou semelhante ao usado no jogo,
-- o feito pelo addon tem proporção do tamanho do ícone da qualidade diferente do jogo padrão, se
-- possível mantenha igual para todos os ícones usados no addon."
--
-- Causa: `CreateAtlasMarkup(atlas, size, size)` — quadrado. A marca do jogo NÃO é quadrada: o link
-- que o próprio jogo gera usa 17 de altura por 15 de largura.
dofile("harness11.lua")
local C = RR.Craft

-- o atlas do jogo, com a proporção real
local ATLAS = { width = 15, height = 17 }
C_Texture = C_Texture or {}
local origInfo = C_Texture.GetAtlasInfo
C_Texture.GetAtlasInfo = function(nome)
	if tostring(nome):find("Professions", 1, true) then return ATLAS end
	return origInfo and origInfo(nome) or nil
end
-- o harness nao tem CreateAtlasMarkup (sem ela o QIcon cai no texto "Q2" e nunca chega aqui).
-- Mesmo formato do jogo: |A:atlas:ALTURA:LARGURA:...|a, e a funcao recebe (atlas, largura, altura).
CreateAtlasMarkup = function(atlas, largura, altura)
	return string.format("|A:%s:%d:%d::|a", atlas, altura or 0, largura or 0)
end

local function medir(markup)
	-- |A:atlas:ALTURA:LARGURA:...|a  — o CreateAtlasMarkup escreve altura e depois largura
	local h, w = tostring(markup):match("|A:[^:]+:(%d+):(%d+)")
	return tonumber(h), tonumber(w)
end

print("=== a marca respeita a proporção do atlas (15x17), não é quadrada ===")
local okProp = true
for _, tam in ipairs({ 12, 16, 20, 26 }) do
	local m = C.QIcon(2, 2, tam)
	local h, w = medir(m)
	local esperadoW = h and math.floor(h * 15 / 17 + 0.5)
	local bate = h == tam and w == esperadoW
	if not bate then okProp = false end
	print(string.format("  pedido %2d -> altura %s largura %s (proporcional seria %s)  %s",
		tam, tostring(h), tostring(w), tostring(esperadoW), bate and "ok" or "FALHA"))
end

print("")
print("=== um tamanho padrão, em vez de 10/11/12/14 soltos ===")
print("  ns.QICON_SIZE = " .. tostring(C.QICON_SIZE))
local padrao = C.QIcon(2, 2)
local hp = medir(padrao)
print(string.format("  sem passar tamanho -> altura %s  %s", tostring(hp),
	hp == C.QICON_SIZE and "ok" or "FALHA"))

print("")
print("=== marca SOBRE ícone: TEXTURA, não texto ===")
-- Como FontString a marca nunca encostava no canto nem chegava ao tamanho do jogo: a linha de
-- texto tem altura própria e o glifo fica centrado nela. O jogo usa textura; o addon também.
print("  atlas escolhido para ★2 de 2: " .. tostring(C.QAtlas(2, 2)))
print("  atlas escolhido para ★3 de 5: " .. tostring(C.QAtlas(3, 5)))
print("  ns.QICON_FRAC = " .. tostring(C.QICON_FRAC))
local okFrac = true
for _, icone in ipairs({ 18, 22, 26, 32, 34, 36 }) do
	local h = math.max(10, math.floor(icone * C.QICON_FRAC + 0.5))
	local w = C.QAtlasW(C.QAtlas(2, 2), h)
	local esperadoW = math.floor(h * 15 / 17 + 0.5)
	if w ~= esperadoW then okFrac = false end
	print(string.format("  ícone %2d -> marca %dx%d (%.0f%% do ícone, proporcional %d)  %s",
		icone, w, h, h / icone * 100, esperadoW, w == esperadoW and "ok" or "FALHA"))
end

print("")
print("=== o Canvas:Icon desenha a textura e some com o texto ===")
local cv = RR.Craft.Visual.Create(LucroCraftFrame or CreateFrame("Frame"))
cv:Begin()
local b1 = cv:Icon(0, 0, 32, 134400, { qTier = 2, qMax = 2 })
local b2 = cv:Icon(0, 40, 32, 134400, {})
cv:End(100)
local marcou = b1.qtex and b1.qtex._shown
local limpo = (b1.q._text or "") == ""
local semMarca = b2.qtex and not b2.qtex._shown
print(string.format("  com qTier: textura visivel=%s, texto vazio=%s", tostring(marcou), tostring(limpo)))
print(string.format("  sem qTier: textura escondida=%s", tostring(semMarca)))

print("")
print("=== nenhum lugar do addon passa tamanho solto ===")
-- antes: 10, 11, 12 e 14 espalhados; a marca aparecia de um jeito em cada tela
local soltos = {}
for _, arq in ipairs({ "Pricing", "Scanner", "UI", "Plan", "Queue", "Buy", "Sell", "Salvage",
	"Invest", "InvestView", "Simulate", "RecipeShop", "Consum" }) do
	local f = io.open((ADDON_DIR or "../") .. "Craft/" .. arq .. ".lua")
	if f then
		local src = f:read("*a"); f:close()
		local n = 0
		for linha in src:gmatch("[^\n]+") do
			n = n + 1
			if not linha:match("^%s*%-%-") and linha:match("QIcon%([^)]*,%s*1[0-9]%)") then
				table.insert(soltos, string.format("%s.lua:%d  %s", arq, n, linha:gsub("^%s+", ""):sub(1, 52)))
			end
		end
	end
end
if #soltos == 0 then print("  nenhum  ok") else for _, l in ipairs(soltos) do print("  " .. l) end end

print("")
print("=== sem a API do atlas, não quebra: cai no texto ===")
-- comportamento documentado do QIcon: sem atlas, mostra "Q3" em vez de erro
C_Texture.GetAtlasInfo = function() error("sem atlas") end
local semApi = C.QIcon(3, 3, 19)
print(string.format("  devolveu %q  %s", tostring(semApi),
	semApi == "Q3" and "ok (texto, sem erro)" or "FALHA"))
C_Texture.GetAtlasInfo = origInfo

print("")
local ok = okProp and okFrac and #soltos == 0 and hp == C.QICON_SIZE and semApi == "Q3"
	and marcou and limpo and semMarca and C.QAtlas(2, 2) ~= nil
print(ok and "OK: marca na proporcao do jogo, um tamanho padrao e proporcao fixa sobre icone"
	or string.format("FALHA (prop=%s frac=%s soltos=%d)", tostring(okProp), tostring(okFrac), #soltos))
