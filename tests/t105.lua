-- v1.34.5: os atributos de um acessório fabricado não batiam com os da aba Investimento.
-- LinkTier só entendia o formato antigo de qualidade (bônus 12499..12502). Nos links da Midnight a
-- qualidade vem no modificador 38 e não há bônus nenhum, então LinkTier devolvia nil para TODO
-- equipamento de profissão atual — e quem chama lê nil como "já está na qualidade máxima".
dofile("harness11.lua")
local Inv = RR.Craft.Invest
local LinkTier, Build = Inv._LinkTier, Inv._BuildCraftedLink

-- links de verdade, como o jogo os devolve (GetRecipeOutputItemData)
local MIDNIGHT = {   -- bônus 3524, modificador 38 = a própria qualidade
	[2] = "|cnIQ4:|Hitem:259205::::::::90:103::13:1:3524:2:40:6778:38:2:::::|h[Mixing Rod]|h|r",
	[3] = "|cnIQ3:|Hitem:240958::::::::90:262::13:1:3524:2:40:3134:38:3:::::|h[Magnifying Glass]|h|r",
	[4] = "|cnIQ2:|Hitem:245775::::::::90:103::13:1:3524:2:40:2869:38:4:::::|h[Scribe's Quill]|h|r",
	[5] = "|cnIQ4:|Hitem:259209::::::::90:103::13:1:3524:2:40:6780:38:5:::::|h[Sin'dorei Quill]|h|r",
}
local LEGADO = {     -- bônus 12499..12502 e modificador 38 = qualidade+3
	[2] = "|Hitem:200111::::::::70:250::11:2:12499:9633:2:28:2462:38:5:::::|h[antigo Q2]|h|r",
	[5] = "|Hitem:200111::::::::70:250::11:2:12502:9633:2:28:2462:38:8:::::|h[antigo Q5]|h|r",
}

print("=== LinkTier: formato da Midnight (modificador 38 = qualidade) ===")
local okM = true
for q, link in pairs(MIDNIGHT) do
	local got = LinkTier(link)
	if got ~= q then okM = false end
	print(string.format("  esperado Q%d -> %s %s", q, tostring(got), got == q and "ok" or "FALHA"))
end

print("")
print("=== LinkTier: formato antigo (bônus de qualidade) continua valendo ===")
local okL = true
for q, link in pairs(LEGADO) do
	local got = LinkTier(link)
	if got ~= q then okL = false end
	print(string.format("  esperado Q%d -> %s %s", q, tostring(got), got == q and "ok" or "FALHA"))
end

print("")
print("=== link sem marca de qualidade: nil (e não 'qualidade maxima') ===")
local semQ = LinkTier("|Hitem:6948::::::::70:250:::::::|h[Pedra]|h|r")
print("  " .. tostring(semQ) .. (semQ == nil and "  ok" or "  FALHA"))

print("")
print("=== BuildCraftedLink monta o link na qualidade pedida ===")
local okB = true
for _, base in ipairs({ MIDNIGHT[2], LEGADO[2] }) do
	for _, alvo in ipairs({ 3, 5 }) do
		local novo = Build(base, 259207, alvo)
		local volta = novo and LinkTier(novo)
		local id = novo and novo:match("item:(%d+)")
		if volta ~= alvo or id ~= "259207" then okB = false end
		print(string.format("  %s -> Q%d: itemID=%s LinkTier=%s %s",
			LinkTier(base) and ("Q" .. LinkTier(base)) or "?", alvo, tostring(id), tostring(volta),
			(volta == alvo and id == "259207") and "ok" or "FALHA"))
	end
end

print("")
print("=== efeito no Investimento: peça equipada abaixo da máxima vira candidata ===")
-- a decisão do EvalAgainst (Invest.lua:861): nil era lido como BEST_TIER e descartava a melhoria
for _, q in ipairs({ 2, 3, 5 }) do
	local t = LinkTier(MIDNIGHT[q])
	print(string.format("  equipado Q%d: LinkTier=%s -> %s", q, tostring(t),
		(t or 5) >= 5 and "descartado (nao oferece melhoria)" or "oferece refazer na Q5"))
end

print("")
print((okM and okL and okB and semQ == nil)
	and "OK: as duas convencoes de qualidade sao lidas e o link e remontado certo"
	or string.format("FALHA (midnight=%s legado=%s build=%s semQ=%s)",
		tostring(okM), tostring(okL), tostring(okB), tostring(semQ)))
