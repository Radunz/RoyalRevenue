-- v1.40.0: encantamento voltou a existir para o addon.
--
-- Encantamento nao produz item: produz um efeito. Para vender na casa de leiloes, aplica-se num
-- Pergaminho Encantado e AI sai um item, com itemID e nome proprios. O `GetOutputItemID` nao achava
-- saida nenhuma e o scan descartava a receita inteira (`if not itemID then skipped = skipped + 1`).
-- Medido no SavedVariables real: das 36 receitas de Encantamento do Radünz-Medivh, ZERO eram
-- encantamento. So varas, oleos, ilusoes e brinquedos -- justamente o que ja produz item.
--
-- O jogo nao expoe o itemID do pergaminho (o CraftSim guarda uma tabela a mao, e ela e privada:
-- `select(2, ...)`). Entao o addon aprende, do jeito que ja aprende bau e multicraft:
--   1. ao fabricar: o TRADE_SKILL_ITEM_CRAFTED_RESULT traz `data.itemID` junto de `data.isEnchant`,
--      e o handler de rendimento lia esse numero e jogava fora;
--   2. pelo nome na bolsa: o pergaminho se chama igual a receita.
dofile("harness13.lua")
local C = RR.Craft

local RECEITA = 1236500   -- receita de encantamento ficticia
local PERG_Q1, PERG_Q2, PERG_Q3 = 900101, 900102, 900103

print("=== o mapa aprendido: gravar e ler ===")
LucroCraftDB.enchantItem = nil
print(string.format("   antes de aprender: EnchantItem = %s", tostring(C.EnchantItem(RECEITA))))
local novo1 = C.LearnEnchantItem(RECEITA, PERG_Q2, 2)
local novo2 = C.LearnEnchantItem(RECEITA, PERG_Q2, 2)   -- repetido nao conta como novo
print(string.format("   aprendeu q2=%d: %s · repetir: %s", PERG_Q2, tostring(novo1), tostring(novo2)))
C.LearnEnchantItem(RECEITA, PERG_Q3, 3)
C.LearnEnchantItem(RECEITA, PERG_Q1, 1)
print(string.format("   EnchantItem(q1)=%s q2=%s q3=%s", tostring(C.EnchantItem(RECEITA, 1)),
	tostring(C.EnchantItem(RECEITA, 2)), tostring(C.EnchantItem(RECEITA, 3))))
print(string.format("   sem pedir qualidade -> %s (esperado a mais baixa, %d)",
	tostring(C.EnchantItem(RECEITA)), PERG_Q1))
local okMapa = novo1 == true and novo2 == false
	and C.EnchantItem(RECEITA, 1) == PERG_Q1 and C.EnchantItem(RECEITA, 2) == PERG_Q2
	and C.EnchantItem(RECEITA, 3) == PERG_Q3 and C.EnchantItem(RECEITA) == PERG_Q1
print(string.format("   -> %s", okMapa and "ok" or "FALHA"))

print("")
print("=== lixo nao entra no mapa ===")
local ruins = {
	{ C.LearnEnchantItem(nil, 123), "receita nil" },
	{ C.LearnEnchantItem(RECEITA, nil), "item nil" },
	{ C.LearnEnchantItem(RECEITA, 0), "item 0" },
}
local okRuins = true
for _, x in ipairs(ruins) do
	if x[1] ~= false then okRuins = false end
	print(string.format("   %-14s -> %s", x[2], tostring(x[1])))
end
print(string.format("   -> %s", okRuins and "ok (recusou os tres)" or "FALHA"))

print("")
print("=== aprende ao fabricar: o evento que o addon ja recebia e descartava ===")
local RECEITA2 = 1236501
local PERG2 = 900110
LucroCraftDB.enchantItem = nil
LucroCraftDB.yieldBy = nil
C_TradeSkillUI.GetRecipeInfo = function(id)
	return { name = "Enchant Weapon - Authority of Radiant Power", recipeID = id,
		isEnchantingRecipe = true }
end
C_TradeSkillUI.GetTradeSkillLineForRecipe = function() return 2909 end
FIRE("TRADE_SKILL_CRAFT_BEGIN", RECEITA2)
FIRE("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = PERG2, quantity = 1, multicraft = 0,
	isEnchant = true, craftingQuality = 3 })
local aprendeu = C.EnchantItem(RECEITA2, 3)
print(string.format("   fabricou o encantamento (q3) -> aprendeu item %s  %s", tostring(aprendeu),
	aprendeu == PERG2 and "ok" or "FALHA"))

-- e o rendimento NAO pode ter sido poluido: encantamento nao tem multicraft
local poluiu = false
for _, Y in pairs(LucroCraftDB.yieldBy or {}) do
	for _, recs in pairs((Y or {}).sigs or {}) do
		if recs[RECEITA2] then poluiu = true end
	end
end
print(string.format("   rendimento (yieldBy) ficou limpo: %s  %s", tostring(not poluiu),
	(not poluiu) and "ok" or "FALHA"))
local okEvento = aprendeu == PERG2 and not poluiu

print("")
print("=== craft normal continua contando rendimento (nao quebrei o que funcionava) ===")
local RECEITA3 = 1236502
C_TradeSkillUI.GetRecipeInfo = function(id) return { name = "Light's Potential", recipeID = id } end
FIRE("TRADE_SKILL_CRAFT_BEGIN", RECEITA3)
FIRE("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 241309, quantity = 13, multicraft = 8 })
local contou
for _, Y in pairs(LucroCraftDB.yieldBy or {}) do
	for _, recs in pairs((Y or {}).sigs or {}) do
		if recs[RECEITA3] then contou = recs[RECEITA3] end
	end
end
print(string.format("   n=%s items=%s mcN=%s mcItems=%s", tostring(contou and contou.n),
	tostring(contou and contou.items), tostring(contou and contou.mcN), tostring(contou and contou.mcItems)))
local okNormal = contou and contou.n == 1 and contou.items == 13 and contou.mcN == 1 and contou.mcItems == 8
print(string.format("   -> %s", okNormal and "ok" or "FALHA"))
-- e o craft normal nao pode virar pergaminho
print(string.format("   nao entrou no mapa de pergaminho: %s", tostring(C.EnchantItem(RECEITA3) == nil)))
okNormal = okNormal and C.EnchantItem(RECEITA3) == nil

print("")
print("=== a ligacao no scan (confere na fonte, que o scan precisa do jogo) ===")
local f = io.open((ADDON_DIR or "../") .. "Craft/Scanner.lua")
local src = f:read("*a"); f:close()
local checagens = {
	{ "o GetOutputItemID cai no pergaminho aprendido",
		"return ns%.EnchantItem%(recipeID%)\n" },
	{ "o scan tenta o nome na bolsa antes de descartar",
		"if not itemID and info%.isEnchantingRecipe and info%.name then" },
	{ "a tentativa pelo nome vem ANTES do skipped",
		"porNome%[info%.name%].-skipped = skipped %+ 1" },
	{ "aprende no resultado do craft",
		"if okD and enchant and id and id ~= 0 then" },
}
local okFonte = true
for _, c in ipairs(checagens) do
	local tem = src:find(c[2]) ~= nil
	if not tem then okFonte = false end
	print(string.format("   %-48s %s", c[1], tem and "ok" or "FALHA"))
end

print("")
print("=== o mapa sobrevive no SavedVariables (e por personagem nenhum: e da conta) ===")
print(string.format("   LucroCraftDB.enchantItem tem %s receitas",
	tostring((function() local n = 0; for _ in pairs(LucroCraftDB.enchantItem or {}) do n = n + 1 end; return n end)())))
local okSV = type(LucroCraftDB.enchantItem) == "table" and LucroCraftDB.enchantItem[RECEITA2] ~= nil
print(string.format("   -> %s", okSV and "ok" or "FALHA"))

print("")
local ok = okMapa and okRuins and okEvento and okNormal and okFonte and okSV
print(ok and "OK: o pergaminho de encantamento e aprendido e o scan deixa de descartar a receita"
	or string.format("FALHA (mapa=%s ruins=%s evento=%s normal=%s fonte=%s sv=%s)",
		tostring(okMapa), tostring(okRuins), tostring(okEvento), tostring(okNormal),
		tostring(okFonte), tostring(okSV)))

print("")
print("=== pendente pelo nome: nao precisa fabricar para resolver ===")
-- O scan anota o encantamento que ficou sem pergaminho, pelo NOME (o pergaminho se chama igual a
-- receita). Dai a bolsa ou o scan da casa de leiloes fecham, sem ele fabricar um de cada.
local RECEITA4 = 1236510
local NOME4 = "Enchant Ring - Cursed Haste"
local PERG4 = 900120
LucroCraftDB.enchantItem = nil
LucroCraftDB.enchantPend = nil
LucroCraftDB.enchantName = nil
C.NoteEnchantPending(RECEITA4, NOME4)
print(string.format("   anotado: enchantName[%d] = %s", RECEITA4,
	tostring(LucroCraftDB.enchantName and LucroCraftDB.enchantName[RECEITA4])))

-- nome que nao bate nao resolve nada
local nada = C.ResolveEnchantByName("Outro Item Qualquer", 999)
print(string.format("   nome diferente -> aprendeu? %s (esperado false)", tostring(nada)))

-- o nome certo fecha o pendente
local fechou = C.ResolveEnchantByName(NOME4, PERG4)
print(string.format("   nome igual ao da receita -> aprendeu? %s · EnchantItem=%s",
	tostring(fechou), tostring(C.EnchantItem(RECEITA4))))
-- o nome NAO e apagado: e por ele que o outro tier entra depois
print(string.format("   nome segue guardado (para achar o outro tier): %s",
	tostring(LucroCraftDB.enchantName[RECEITA4] == NOME4)))
local okPend = nada == false and fechou == true and C.EnchantItem(RECEITA4) == PERG4
	and LucroCraftDB.enchantName[RECEITA4] == NOME4

-- reanotar o mesmo nome e inofensivo (o mapa e por recipeID)
C.NoteEnchantPending(RECEITA4, NOME4)
local okNaoRepete = LucroCraftDB.enchantName[RECEITA4] == NOME4 and C.EnchantItem(RECEITA4) == PERG4
print(string.format("   reanotar nao perde o que foi aprendido: %s  %s", tostring(okNaoRepete),
	okNaoRepete and "ok" or "FALHA"))

print("")
print("=== a ligacao no scan da casa de leiloes (fonte) ===")
local f2 = io.open((ADDON_DIR or "../") .. "Craft/Own.lua")
local src2 = f2:read("*a"); f2:close()
local okOwn = src2:find("ns%.ResolveEnchantByName%(iname, itemID%)") ~= nil
	and src2:find("aprendeuPerg") ~= nil
print(string.format("   o scan da AH tenta fechar os pendentes: %s", okOwn and "ok" or "FALHA"))

print("")
print((okMapa and okRuins and okEvento and okNormal and okFonte and okSV and okPend
	and okNaoRepete and okOwn)
	and "OK (completo): pergaminho aprendido ao fabricar, pela bolsa e pelo scan da casa de leiloes"
	or string.format("FALHA no bloco pendente (pend=%s naoRepete=%s own=%s)",
		tostring(okPend), tostring(okNaoRepete), tostring(okOwn)))

print("")
print("=== o conserto do conserto: resolver pelo NOME, sem depender de ordem ===")
-- O que falhou na maquina do Rafael: ele rodou o scan da casa de leiloes ANTES de abrir a profissao
-- de Encantamento. Naquele momento enchantPend era nil, a guarda curto-circuitou, e o scan passou
-- por 50 mil anuncios sem resolver nada. Depois a profissao anotou 100+ pendentes -- tarde demais.
-- O GetItemInfo aceita NOME e devolve o link, para item que o cliente ja viu. Resolve sem ordem.
local NOME5 = "Enchant Weapon - Worldsoul Cradle"
local PERG5 = 900130
-- o harness devolve "|Hitem:<id>|h" para qualquer entrada; simula o cache de verdade
local getOrig = C_Item.GetItemInfo
local cache = { [NOME5] = PERG5 }
C_Item.GetItemInfo = function(x)
	local id = cache[x] or tonumber(x)
	if not id then return nil end
	return "Item" .. id, "|cffffffff|Hitem:" .. id .. "::::::::80:::::|h[Item" .. id .. "]|h|r"
end
print(string.format("   ItemIDByName(%q) = %s  %s", NOME5:sub(1, 30), tostring(C.ItemIDByName(NOME5)),
	C.ItemIDByName(NOME5) == PERG5 and "ok" or "FALHA"))
print(string.format("   nome que o cliente nao conhece -> %s (esperado nil)",
	tostring(C.ItemIDByName("Nome Que Nao Existe No Cache"))))
local okNome = C.ItemIDByName(NOME5) == PERG5 and C.ItemIDByName("Nome Que Nao Existe No Cache") == nil
print(string.format("   entrada invalida (nil, vazio, numero) -> %s %s %s",
	tostring(C.ItemIDByName(nil)), tostring(C.ItemIDByName("")), tostring(C.ItemIDByName(123) ~= nil)))
okNome = okNome and C.ItemIDByName(nil) == nil and C.ItemIDByName("") == nil

print("")
print("=== a varredura dos pendentes limpa o atraso sozinha ===")
-- o estado em que a conta dele ficou: pendentes salvos, nenhum resolvido
LucroCraftDB.enchantItem = nil
LucroCraftDB.enchantPend = { [1236079] = NOME5, [1236080] = "Enchant Weapon - Worldsoul Aegis" }
cache[NOME5] = PERG5   -- esse o cliente conhece; o outro nao
local resolvidos = C.ResolvePendingEnchants()
print(string.format("   resolvidos: %d de 2", resolvidos))
print(string.format("   1236079 -> %s (conhecido)", tostring(C.EnchantItem(1236079))))
print(string.format("   1236080 -> %s (ainda nao conhecido, segue pendente)", tostring(C.EnchantItem(1236080))))
print(string.format("   o que nao resolveu segue em enchantName: %s",
	tostring(LucroCraftDB.enchantName and LucroCraftDB.enchantName[1236080])))
local okVarre = resolvidos == 1 and C.EnchantItem(1236079) == PERG5
	and C.EnchantItem(1236080) == nil
	and LucroCraftDB.enchantName and LucroCraftDB.enchantName[1236080] == "Enchant Weapon - Worldsoul Aegis"
print(string.format("   -> %s", okVarre and "ok (resolve o que da, guarda o resto)" or "FALHA"))

-- quando todos resolvem, a lista some
cache["Enchant Weapon - Worldsoul Aegis"] = 900131
C.ResolvePendingEnchants()
local okLimpou = C.EnchantItem(1236080) == 900131 and LucroCraftDB.enchantPend == nil
print(string.format("   depois que o cliente conhece os dois: aprendido=%s · enchantPend zerado=%s  %s",
	tostring(C.EnchantItem(1236080)), tostring(LucroCraftDB.enchantPend == nil),
	okLimpou and "ok" or "FALHA"))
C_Item.GetItemInfo = getOrig

print("")
print("=== a ligacao no RepriceAll (fonte) ===")
local f3 = io.open((ADDON_DIR or "../") .. "Craft/Scanner.lua")
local src3 = f3:read("*a"); f3:close()
local okLiga = src3:find("pcall%(ns%.ResolvePendingEnchants%)") ~= nil
	and src3:find("local achado = ns%.ItemIDByName%(info%.name%)") ~= nil
print(string.format("   RepriceAll varre os pendentes · o scan tenta o nome primeiro: %s",
	okLiga and "ok" or "FALHA"))

print("")
print((okMapa and okRuins and okEvento and okNormal and okFonte and okSV and okPend
	and okNaoRepete and okOwn and okNome and okVarre and okLimpou and okLiga)
	and "OK (final): pergaminho resolvido por nome, bolsa, craft e scan da AH -- sem ordem obrigatoria"
	or string.format("FALHA (nome=%s varre=%s limpou=%s liga=%s)", tostring(okNome),
		tostring(okVarre), tostring(okLimpou), tostring(okLiga)))

print("")
print("=== a qualidade: so por fonte definitiva, nunca adivinhada ===")
-- Os 6 pergaminhos que resolveram na conta do Rafael entraram TODOS como q1, porque as tres
-- qualidades se chamam igual e o nome nao distingue. O q1 vale 0,14o a 5,00o, entao os seis
-- apareceram com prejuizo -- o dinheiro esta no q3.
-- Deduzir a qualidade pela ordem do itemID seria tentador: na tabela do CraftSim 96 de 103
-- encantamentos tem q1<q2<q3. Mas 7 estao fora de ordem, e trocar q1 por q3 num calculo de lucro
-- e pior que nao mostrar nada. Entao: so GetRecipeQualityItemIDs ou o evento de craft.
local f4 = io.open((ADDON_DIR or "../") .. "Craft/Scanner.lua")
local src4 = f4:read("*a"); f4:close()
local chk = {
	{ "tenta a API de ids por qualidade",
		"pcall%(C_TradeSkillUI%.GetRecipeQualityItemIDs, recipeID%)" },
	{ "aprende um id por tier quando ela responde",
		"for q, id in ipairs%(qids%) do ns%.LearnEnchantItem%(recipeID, id, q%) end" },
	{ "o caminho por nome so roda se a API falhou",
		"if not itemID then\n%s+local achado = ns%.ItemIDByName" },
	{ "nao deduz qualidade pela ordem do itemID",
		"Nao da para deduzir pela" },
}
local okQual = true
for _, c in ipairs(chk) do
	local tem = src4:find(c[2]) ~= nil
	if not tem then okQual = false end
	print(string.format("   %-44s %s", c[1], tem and "ok" or "FALHA"))
end
-- e o evento de craft segue sendo a fonte boa de qualidade
LucroCraftDB.enchantItem = nil
C_TradeSkillUI.GetRecipeInfo = function(id) return { name = "Enchant X", recipeID = id, isEnchantingRecipe = true } end
FIRE("TRADE_SKILL_CRAFT_BEGIN", 1236600)
FIRE("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 900201, quantity = 1, isEnchant = true, craftingQuality = 1 })
FIRE("TRADE_SKILL_CRAFT_BEGIN", 1236600)
FIRE("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 900203, quantity = 1, isEnchant = true, craftingQuality = 3 })
local okCraftQ = C.EnchantItem(1236600, 1) == 900201 and C.EnchantItem(1236600, 3) == 900203
print(string.format("   fabricando q1 e q3: q1=%s q3=%s  %s", tostring(C.EnchantItem(1236600, 1)),
	tostring(C.EnchantItem(1236600, 3)), okCraftQ and "ok" or "FALHA"))
okQual = okQual and okCraftQ

print("")
print(okQual and "OK (qualidade): definitiva pela API ou pelo craft; nunca deduzida pela ordem do id"
	or "FALHA no bloco de qualidade")

print("")
print("=== o tier vem do JOGO, nunca assumido ===")
-- O estado real do Rafael depois do scan da AH: 44 pergaminhos achados, 0 pendentes, Encantamento
-- do priest de 42 -> 66 receitas. Funcionou. Mas TODOS entraram como q1, porque as qualidades do
-- pergaminho sao itens diferentes com o MESMO nome. 27 das 30 receitas apareciam com prejuizo.
-- A fonte boa e a que o TSM usa: C_TradeSkillUI.GetItemCraftedQualityByItemInfo(itemID).
local TIERS = { [900301] = 1, [900302] = 2, [900401] = 2, [900402] = 1 }
C_TradeSkillUI.GetItemCraftedQualityByItemInfo = function(id) return TIERS[id] end
print(string.format("   CraftedTier(900301)=%s · (900302)=%s · desconhecido=%s",
	tostring(C.CraftedTier(900301)), tostring(C.CraftedTier(900302)),
	tostring(C.CraftedTier(999999))))
local okTier = C.CraftedTier(900301) == 1 and C.CraftedTier(900302) == 2 and C.CraftedTier(999999) == nil

-- aprender sem passar o tier: tem de perguntar, nao assumir q1
LucroCraftDB.enchantItem = nil
C.LearnEnchantItem(1236700, 900302)   -- sem tier; o jogo diz que e q2
local okPergunta = C.EnchantItem(1236700, 2) == 900302 and C.EnchantItem(1236700, 1) == nil
print(string.format("   aprendeu sem tier -> foi para q%s  %s",
	C.EnchantItem(1236700, 2) and "2" or "?", okPergunta and "ok (perguntou)" or "FALHA"))

print("")
print("=== RetierEnchants conserta o que ja estava gravado errado ===")
-- simula a conta dele: tudo gravado em q1
LucroCraftDB.enchantItem = {
	[1236701] = { [1] = 900401 },   -- o jogo diz que 900401 e q2
	[1236702] = { [1] = 900402 },   -- esse de fato e q1
	[1236703] = { [1] = 999999 },   -- o jogo nao sabe: fica onde esta
}
local movidos = C.RetierEnchants()
print(string.format("   movidos: %d", movidos))
print(string.format("   1236701: q1=%s q2=%s  (era q1, virou q2)", tostring(C.EnchantItem(1236701, 1)),
	tostring(C.EnchantItem(1236701, 2))))
print(string.format("   1236702: q1=%s  (ja estava certo)", tostring(C.EnchantItem(1236702, 1))))
print(string.format("   1236703: q1=%s  (sem resposta do jogo, nao mexe)", tostring(C.EnchantItem(1236703, 1))))
local okRetier = movidos == 1
	and C.EnchantItem(1236701, 2) == 900401 and C.EnchantItem(1236701, 1) == nil
	and C.EnchantItem(1236702, 1) == 900402
	and C.EnchantItem(1236703, 1) == 999999
print(string.format("   -> %s", okRetier and "ok" or "FALHA"))

print("")
print("=== o nome fica guardado: o segundo tier entra depois ===")
LucroCraftDB.enchantItem = nil
LucroCraftDB.enchantName = nil
LucroCraftDB.enchantPend = { [1236710] = "Enchant Weapon - Dois Tiers" }
C.ResolvePendingEnchants()   -- migra o pendente para nome permanente
print(string.format("   migrou o pendente: enchantName=%s · enchantPend=%s",
	tostring(LucroCraftDB.enchantName and LucroCraftDB.enchantName[1236710] ~= nil),
	tostring(LucroCraftDB.enchantPend)))
-- primeiro a AH mostra o q1
TIERS[900501], TIERS[900502] = 1, 2
C.ResolveEnchantByName("Enchant Weapon - Dois Tiers", 900501)
-- depois mostra o q2 -- e aqui que o desenho antigo falhava, porque apagava o nome no 1o acerto
local segundo = C.ResolveEnchantByName("Enchant Weapon - Dois Tiers", 900502)
print(string.format("   q1=%s q2=%s (o 2o acerto ainda funciona: %s)",
	tostring(C.EnchantItem(1236710, 1)), tostring(C.EnchantItem(1236710, 2)), tostring(segundo)))
local okDois = C.EnchantItem(1236710, 1) == 900501 and C.EnchantItem(1236710, 2) == 900502
	and segundo == true and LucroCraftDB.enchantPend == nil
print(string.format("   -> %s", okDois and "ok" or "FALHA"))

print("")
print("=== o scan monta a lista de qualidades com o que aprendeu ===")
local f5 = io.open((ADDON_DIR or "../") .. "Craft/Scanner.lua")
local src5 = f5:read("*a"); f5:close()
local okMonta = src5:find("if %(not qIDs or #qIDs == 0%) and info%.isEnchantingRecipe and ns%.EnchantItem then") ~= nil
	and src5:find("if #montada > 1 then qIDs = montada end") ~= nil
print(string.format("   monta qIDs do pergaminho · exige sequencia completa: %s",
	okMonta and "ok" or "FALHA"))
-- buraco no meio NAO pode virar lista (o #qIDs mentiria)
LucroCraftDB.enchantItem = { [1236720] = { [1] = 900601, [3] = 900603 } }
print(string.format("   com q1 e q3 (sem q2): EnchantItem(1)=%s EnchantItem(2)=%s -> a sequencia para em 1",
	tostring(C.EnchantItem(1236720, 1)), tostring(C.EnchantItem(1236720, 2))))
local okBuraco = C.EnchantItem(1236720, 2) == nil

print("")
print((okTier and okPergunta and okRetier and okDois and okMonta and okBuraco)
	and "OK (tier): qualidade do pergaminho vem do jogo, o gravado errado se conserta no login"
	or string.format("FALHA (tier=%s pergunta=%s retier=%s dois=%s monta=%s buraco=%s)",
		tostring(okTier), tostring(okPergunta), tostring(okRetier), tostring(okDois),
		tostring(okMonta), tostring(okBuraco)))

print("")
print("=== as receitas que ele NAO sabe fazer ===")
-- Relato: "carregou boa parte, porem nao carregou os recipes que eu nao sei fazer no priest".
-- No dado dele as 28 desconhecidas do Encantamento ESTAO carregadas (em entry.unknown), com itemID
-- e preco. O que as esconde e o filtro do terceiro grupo da lista: desconhecida so aparece com
-- `profit > 0`, por desenho. Com um tier so de pergaminho o lucro sai negativo e elas somem.
-- Ou seja: mesma causa raiz, nao um bug novo. O conserto e completar o tier.
local f6 = io.open((ADDON_DIR or "../") .. "Craft/UI.lua")
local src6 = f6:read("*a"); f6:close()
local okFiltro = src6:find('type%(p%) == "number" and p > 0') ~= nil
print(string.format("   o terceiro grupo filtra por lucro positivo: %s", okFiltro and "ok (confirmado)" or "FALHA"))

print("")
print("=== a 2a fonte definitiva de tier: saida com qualidade forcada ===")
local f7 = io.open((ADDON_DIR or "../") .. "Craft/Scanner.lua")
local src7 = f7:read("*a"); f7:close()
local chk2 = {
	{ "tenta GetRecipeOutputItemData por qualidade",
		"pcall%(C_TradeSkillUI%.GetRecipeOutputItemData, recipeID, {}, nil, q%)" },
	{ "so aceita quando os tiers dao itens diferentes", "if nd > 1 then" },
	{ "um id para todas as qualidades: deixa o jogo dizer o tier",
		"elseif nd == 1 and not itemID then" },
	{ "nao repete o trabalho se o tier 2 ja existe",
		"if not itemID or not ns%.EnchantItem%(recipeID, 2%) then" },
}
local okOut = true
for _, c in ipairs(chk2) do
	local tem = src7:find(c[2]) ~= nil
	if not tem then okOut = false end
	print(string.format("   %-50s %s", c[1], tem and "ok" or "FALHA"))
end

print("")
print("=== com um tier so, a Auditoria avisa em vez de afirmar prejuizo ===")
LucroCraftDB.enchantItem = { [1236800] = { [1] = 900701 } }
local rParcial = { recipeID = 1236800, maxQuality = 2, sale = 100000, itemID = 900701 }
local pv1 = C.Provenance(rParcial, "sale")
print(string.format("   so q1 conhecido -> nivel=%s", tostring(pv1 and pv1.nivel)))
print(string.format("      nota: %s", tostring(pv1 and pv1.nota)))
-- com os dois tiers, volta ao normal
LucroCraftDB.enchantItem = { [1236800] = { [1] = 900701, [2] = 900702 } }
local pv2 = C.Provenance(rParcial, "sale")
print(string.format("   q1 e q2 conhecidos -> nivel=%s nota=%s", tostring(pv2 and pv2.nivel),
	tostring(pv2 and pv2.nota)))
local okAviso = pv1 and pv1.nivel == "fraco" and pv1.nota
	and pv2 and pv2.nivel ~= "fraco"
print(string.format("   -> %s", okAviso and "ok" or "FALHA"))
-- receita que nao e encantamento nao pode ser afetada
local rNormal = { recipeID = 999888, maxQuality = 5, sale = 100000, itemID = 1 }
local pv3 = C.Provenance(rNormal, "sale")
local okIntacto = pv3 and pv3.nivel ~= "fraco"
print(string.format("   receita comum segue %s  %s", tostring(pv3 and pv3.nivel),
	okIntacto and "ok (nao afetada)" or "FALHA"))

print("")
print((okFiltro and okOut and okAviso and okIntacto)
	and "OK (desconhecidas): estao carregadas; o filtro de lucro as escondia, e o tier e a causa"
	or string.format("FALHA (filtro=%s out=%s aviso=%s intacto=%s)", tostring(okFiltro),
		tostring(okOut), tostring(okAviso), tostring(okIntacto)))
