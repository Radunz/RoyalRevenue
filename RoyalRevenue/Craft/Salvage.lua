local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- Aba Destruir: tudo que transforma um item em outros.
--   salvage: receitas de recuperação do jogo (Prospecção, Trituração, Reciclagem, Moagem...)
--   craft:   receitas normais que só "quebram" um material (Estilhaçar do Encantamento)
--   spell:   Desencantar (magia, não é receita; o item é o que fica travado na bolsa durante o lançamento)
-- Parte 1: o que pode ser destruído e quanto custa (menor entre vendedor e menor anúncio da AH;
--          no Desencantar, o que o NPC paga pelo item, que é o que você deixa de ganhar).
-- Parte 2: o que sai, com a chance e a quantidade média que VOCÊ tirou (registrado a cada destruição),
--          o menor preço da AH e a média atual do mercado.
-- A API do jogo não diz o que cada destruição dá; o addon aprende com os seus resultados.
-- Sem registro ainda: dados de outros personagens, a saída fixa da receita ou a tabela "Destroy" do TSM.
local S = {}
ns.Salvage = S

local P = ns.Pricing
local MAX_ROWS = 60
local DISENCHANT = 13262
-- receitas normais que entram na aba (nome em inglês ou português)
-- (nome termina em "Shatter" — Dawn Shatter, Radiant Shatter — ou começa com "Estilha"; "Flask of the
-- Shattered Sun" e "Shatter Essence" não são destruição)
local CRAFT_PATTERNS = { "shatter$", "^estilha" }
-- "receitas de recuperação" que não dão item: só consomem o material e dão um bônus ao personagem
-- (Shatter Essence do Encantamento: estilhaça o mote e buffa o encantador). Ficam fora da aba.
local NOT_DESTROY = { [1235731] = true, [445466] = true }
local function NoItemRecipe(recipeID, name)
	if NOT_DESTROY[recipeID] then return true end
	local n = name and name:lower() or ""
	return n == "shatter essence" or n:find("^estilhaçar essência") ~= nil
end
S.NoItemRecipe = NoItemRecipe

local function Cfg(key)
	local db = LucroCraftDB and LucroCraftDB.config
	if db and db[key] ~= nil then return db[key] end
	return ns.DEFAULTS[key]
end

local function DB()
	LucroCraftDB.salvage = LucroCraftDB.salvage or {}
	local d = LucroCraftDB.salvage
	d.recipes = d.recipes or {}
	if not d.clean1 then
		d.clean1 = true
		for rid, r in pairs(d.recipes) do
			if r.kind == "craft" and not S.IsCraftDestroy({ name = r.name }) then d.recipes[rid] = nil end
		end
	end
	d.obs = d.obs or {}
	-- v1.18.4: destruições registradas sem nenhuma saída (o jogo não avisou, ex.: Shatter Essence) não contam
	if not d.clean2 then
		d.clean2 = true
		for _, byR in pairs(d.obs) do
			for _, byI in pairs(byR) do
				for _, o in pairs(byI) do
					if type(o) == "table" and o.out and next(o.out) == nil then o.casts, o.savedCasts = 0, 0 end
				end
			end
		end
	end
	d.sel = d.sel or {}
	return d
end
S._DB = DB

local function ProfName(skillLine)
	if skillLine and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
		local ok, pinfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLine)
		if ok and pinfo then return pinfo.parentProfessionName or pinfo.professionName end
	end
end

local function Base(recipeID, info, skillLine, kind)
	local d = DB()
	local r = d.recipes[recipeID] or {}
	d.recipes[recipeID] = r
	r.kind = kind
	r.name = info.name or r.name
	r.icon = info.icon or r.icon
	if not skillLine and C_TradeSkillUI.GetTradeSkillLineForRecipe then
		local ok, sl = pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, recipeID)
		skillLine = ok and sl or nil
	end
	r.skillLine = skillLine or r.skillLine
	r.prof = ProfName(r.skillLine) or r.prof
	r.chars = r.chars or {}
	if info.learned ~= false then r.chars[ns.CharKey()] = true end
	r.time = time()
	return r
end

-- transmutação (nome, categoria da janela de profissão ou marcação manual): entra na aba como "craft"
local function IsTransmuteInfo(info)
	if not (ns.IsTransmute and info) then return false end
	local t = { name = info.name, recipeID = info.recipeID }
	if info.categoryID and C_TradeSkillUI and C_TradeSkillUI.GetCategoryInfo then
		local ok, ci = pcall(C_TradeSkillUI.GetCategoryInfo, info.categoryID)
		if ok and ci then
			t.category = ci.name
			if ci.parentCategoryID then
				local okP, pi = pcall(C_TradeSkillUI.GetCategoryInfo, ci.parentCategoryID)
				if okP and pi then t.categoryParent = pi.name end
			end
		end
	end
	return ns.IsTransmute(t)
end
S.IsTransmuteInfo = IsTransmuteInfo

-- receita normal que entra na aba (Estilhaçar, transmutações)?
function S.IsCraftDestroy(info)
	local n = info and info.name and info.name:lower()
	if not n or info.isSalvageRecipe then return false end
	for _, pat in ipairs(CRAFT_PATTERNS) do if n:find(pat) then return true end end
	return IsTransmuteInfo(info)
end

-- ===== Receitas conhecidas =====
-- Chamado pelo scan (receitas aprendidas) e ao selecionar a receita na janela de profissão.
function S.Capture(recipeID, info, skillLine)
	if not recipeID or not C_TradeSkillUI or not LucroCraftDB then return end
	if not info then
		local ok, i = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
		info = ok and i or nil
	end
	if not info then return end
	if NoItemRecipe(recipeID, info.name) then
		if LucroCraftDB.salvage and LucroCraftDB.salvage.recipes then LucroCraftDB.salvage.recipes[recipeID] = nil end
		return
	end
	local okS, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
	sch = okS and sch or nil
	if info.isSalvageRecipe then
		local r = Base(recipeID, info, skillLine, "salvage")
		if sch then r.perCast = sch.quantityMax or sch.quantityMin or r.perCast end
		if C_TradeSkillUI.GetSalvagableItemIDs then
			local ok, ids = pcall(C_TradeSkillUI.GetSalvagableItemIDs, recipeID)
			if ok and type(ids) == "table" and #ids > 0 then r.inputs = ids end
		end
	elseif S.IsCraftDestroy(info) and sch then
		-- material = o reagente obrigatório principal: negociável (tem preço) e de maior quantidade
		-- (ex.: Bouquet of Herbs = 20 ervas, não o catalisador vinculado do 1º espaço)
		local slot, bestQ
		for _, s in ipairs(sch.reagentSlotSchematics or {}) do
			if s.required ~= false and s.reagents and #s.reagents > 0 then
				local priced = false
				for _, rg in ipairs(s.reagents) do if rg.itemID and ns.Pricing.Cost(rg.itemID) then priced = true end end
				local q = (s.quantityRequired or 1) + (priced and 100000 or 0)
				if not slot or q > bestQ then slot, bestQ = s, q end
			end
		end
		if not slot then return end
		local r = Base(recipeID, info, skillLine, "craft")
		r.perCast = slot.quantityRequired or 1
		r.inputs = {}
		for _, rg in ipairs(slot.reagents) do if rg.itemID then table.insert(r.inputs, rg.itemID) end end
		r.outItem = sch.outputItemID or r.outItem
		r.outQty = ((sch.quantityMin or 1) + (sch.quantityMax or sch.quantityMin or 1)) / 2
		-- os outros reagentes obrigatórios (ex.: o catalisador vinculado das transmutações) entram no custo de cada vez
		r.extras = {}
		for _, s2 in ipairs(sch.reagentSlotSchematics or {}) do
			if s2 ~= slot and s2.required and s2.reagentType == ((Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1) and s2.reagents and s2.reagents[1] and s2.reagents[1].itemID then
				local ids = {}
				for _, rg in ipairs(s2.reagents) do if rg.itemID then table.insert(ids, rg.itemID) end end
				table.insert(r.extras, { ids = ids, qty = s2.quantityRequired or 1 })
			end
		end
		r.transmute = IsTransmuteInfo(info) or nil
		-- cargas (transmutações): o limite por dia
		if C_TradeSkillUI.GetRecipeCooldown then
			local okR, cool, isDay, charges, maxCharges = pcall(C_TradeSkillUI.GetRecipeCooldown, recipeID)
			if okR and ((maxCharges or 0) > 0 or (cool or 0) > 0) then
				r.cdBy = r.cdBy or {}
				r.cdBy[ns.CharKey()] = { cool = cool or 0, day = isDay or nil, charges = charges or 0, max = maxCharges or 0, t = time() }
			else
				if r.cdBy then r.cdBy[ns.CharKey()] = nil end
			end
		end
	end
end

-- Desencantar: magia do encantador
local function SpellKnown(id)
	if IsPlayerSpell then
		local ok, v = pcall(IsPlayerSpell, id)
		if ok and v then return true end
	end
	if IsSpellKnown then
		local ok, v = pcall(IsSpellKnown, id)
		if ok and v then return true end
	end
	return false
end
function S.CaptureDisenchant()
	if not LucroCraftDB or not SpellKnown(DISENCHANT) then return end
	local name, icon
	if C_Spell and C_Spell.GetSpellName then
		name = C_Spell.GetSpellName(DISENCHANT)
		icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(DISENCHANT)
	end
	local d = DB()
	local r = d.recipes[DISENCHANT] or {}
	d.recipes[DISENCHANT] = r
	r.kind = "spell"
	r.name = name or r.name or L["Desencantar"]
	r.icon = icon or r.icon or 136244
	r.prof = r.prof or L["Encantamento"]
	r.perCast = 1
	r.chars = r.chars or {}
	r.chars[ns.CharKey()] = true
end

-- grupo de resultado de um equipamento no Desencantar: raridade + expansão (é o que decide o que sai)
local function DEGroup(link)
	if not link then return nil end
	local _, _, quality, _, _, _, _, _, _, _, sell, classID, _, _, expac = C_Item.GetItemInfo(link)
	if not quality then return nil end
	return string.format("q%d:x%d", quality, expac or 0), quality, classID, sell
end
S._DEGroup = DEGroup

-- equipamentos nas bolsas que dá para desencantar (verde, azul, roxo; armadura ou arma)
local function BagGear()
	local list, byKey = {}, {}
	if not C_Container or not C_Container.GetContainerNumSlots then return list end
	for bag = 0, 4 do
		local n = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, n do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and info.hyperlink then
				local grp, q, classID, sell = DEGroup(info.hyperlink)
				if grp and (classID == 2 or classID == 4) and q >= 2 and q <= 4 then
					local ilvl = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(info.hyperlink) or 0
					local key = info.itemID .. ":" .. ilvl
					local row = byKey[key]
					if row then
						row.have = row.have + 1
					else
						row = { itemID = info.itemID, link = info.hyperlink, ilvl = ilvl, group = grp, sell = sell, have = 1 }
						byKey[key] = row
						table.insert(list, row)
					end
				end
			end
		end
	end
	return list
end

-- item travado na bolsa (o que está sendo desencantado)
local function LockedItem()
	if not C_Container or not C_Container.GetContainerNumSlots then return nil end
	for bag = 0, 4 do
		for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.isLocked and info.hyperlink then return info.itemID, info.hyperlink end
		end
	end
end

-- ===== Registro dos resultados =====
local pend      -- destruição em andamento: { recipe, input, last, spell }
local current   -- receita da fabricação em andamento (TRADE_SKILL_CRAFT_BEGIN)

-- v1.8.2 conferia a bolsa antes de o material sair: bagUsed ficou 0. Apaga essa medição uma vez.
local function FixBag1()
	local d = LucroCraftDB and LucroCraftDB.salvage
	if not d or d.bagFix1 then return end
	d.bagFix1 = true
	for _, byR in pairs(d.obs or {}) do
		for _, byI in pairs(byR) do
			for _, o in pairs(byI) do o.bagCasts, o.bagUsed = nil, nil end
		end
	end
end

local function Obs(char, recipeID, input, create)
	local d = DB()
	local c = d.obs[char]
	if not c then if not create then return nil end; c = {}; d.obs[char] = c end
	local r = c[recipeID]
	if not r then if not create then return nil end; r = {}; c[recipeID] = r end
	local o = r[input]
	if not o and create then o = { casts = 0, out = {}, seen = {}, first = time() }; r[input] = o end
	return o
end

local refreshPending = false
local function SoonRefresh()
	if refreshPending then return end
	refreshPending = true
	C_Timer.After(0.5, function()
		refreshPending = false
		if ns.UI and ns.UI.RefreshTab and ns.UI.TAB then ns.UI.RefreshTab(ns.UI.TAB.SALVAGE) end
	end)
end

-- ===== Desenvoltura medida =====
-- Duas medições por destruição: (1) resourcesReturned do TRADE_SKILL_ITEM_CRAFTED_RESULT (o jogo diz o que
-- devolveu) e (2) a bolsa: material na bolsa antes do lote − agora = o que foi gasto de fato nas destruições.
-- o.bagCasts / o.bagUsed (bolsa) e o.saved / o.savedCasts (resourcesReturned).
local function BagCount(id)
	if not (C_Item and C_Item.GetItemCount) then return nil end
	local ok, n = pcall(C_Item.GetItemCount, id, false, false, true, false)
	return ok and type(n) == "number" and n or nil
end

-- todas as bolsas: itemID -> quantidade (para ver o que entrou quando o jogo não avisa o resultado)
local function BagAll() return (root.BagCounts()) end   -- tabela compartilhada: só leitura

-- saída pela bolsa: destruições sem TRADE_SKILL_ITEM_CRAFTED_RESULT (ex.: Shatter Essence) — o que entrou na bolsa
local function CommitOut(p)
	if not (p and p.snap and p.n) then return end
	local dn = p.n - (p.outN or 0)
	if dn <= 0 then return end
	local now = BagAll()
	if (p.evt or 0) == 0 then
		local o = Obs(ns.CharKey(), p.recipe, p.input, true)
		local any = false
		for id, q in pairs(now) do
			local g = q - (p.snap[id] or 0)
			if g > 0 and id ~= p.input then
				o.out[id] = (o.out[id] or 0) + g
				o.seen[id] = (o.seen[id] or 0) + math.min(g, dn)
				any = true
			end
		end
		if any then o.bagOut = true end
	end
	p.snap, p.outN, p.evt = now, p.n, 0
	SoonRefresh()
end

local function CommitBag(p)
	if not (p and p.base and p.n and p.n > (p.accN or 0)) then return end
	local now = BagCount(p.input)
	if not now then return end
	local used = p.base - now
	local dn, du = p.n - (p.accN or 0), used - (p.accUsed or 0)
	if du < 0 or du > dn * 50 then return end   -- entrou material de outro lugar: ignora
	local o = Obs(ns.CharKey(), p.recipe, p.input, true)
	o.bagCasts = (o.bagCasts or 0) + dn
	o.bagUsed = (o.bagUsed or 0) + du
	p.accN, p.accUsed = p.n, used
end

local function OnCraftSalvage(spellID, numCasts, itemTarget)
	local input
	if itemTarget and C_Item and C_Item.GetItemID then
		local ok, id = pcall(C_Item.GetItemID, itemTarget)
		if ok then input = id end
	end
	if not spellID or not input then pend = nil; return end
	if pend then pcall(CommitBag, pend) end
	pend = { recipe = spellID, input = input, last = GetTime(), base = BagCount(input), n = 0, snap = BagAll(), evt = 0 }
	pcall(S.Capture, spellID)
	DB().sel[spellID] = input
end

-- Estilhaçar: receita normal. O material vem da lista de reagentes (ou o que você tem na bolsa).
local function OnCraftRecipe(spellID, numCasts, reagents)
	local r = spellID and DB().recipes[spellID]
	if not r or r.kind ~= "craft" then return end
	local set = {}
	for _, id in ipairs(r.inputs or {}) do set[id] = true end
	local input
	for _, rg in ipairs(type(reagents) == "table" and reagents or {}) do
		local id = rg.itemID or (rg.reagent and rg.reagent.itemID)
		if id and set[id] then input = id; break end
	end
	if not input then
		for _, id in ipairs(r.inputs or {}) do
			local ok, n = pcall(C_Item.GetItemCount, id, true, false, true, true)
			if ok and n and n >= (r.perCast or 1) then input = id; break end
		end
	end
	input = input or (r.inputs and r.inputs[1])
	if not input then pend = nil; return end
	pend = { recipe = spellID, input = input, last = GetTime() }
	DB().sel[spellID] = input
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("TRADE_SKILL_CRAFT_BEGIN")
ev:RegisterEvent("UNIT_SPELLCAST_SENT")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
ev:RegisterEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT")
ev:RegisterEvent("LOOT_READY")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("TRADE_SKILL_SHOW")
ev:RegisterEvent("TRADE_SKILL_CLOSE")
ev:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
local function Hook(name, fn)
	if C_TradeSkillUI and C_TradeSkillUI[name] then
		hooksecurefunc(C_TradeSkillUI, name, function(...)
			local ok, err = pcall(fn, ...)
			if not ok and ns.Log then ns.Log("destruir: " .. tostring(err)) end
		end)
	end
end
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
	if root.AnySecret(a1, a2, a3, a4) then return end
	if event == "PLAYER_LOGIN" then
		pcall(FixBag1)
		Hook("CraftSalvage", OnCraftSalvage)
		Hook("CraftRecipe", OnCraftRecipe)
		-- receita de destruição selecionada na janela de profissão: foca a aba
		if EventRegistry and EventRegistry.RegisterCallback then
			EventRegistry:RegisterCallback("ProfessionsRecipeListMixin.Event.OnRecipeSelected", function(_, recipeInfo)
				local ok, err = pcall(S.OnRecipeSelected, recipeInfo)
				if not ok and ns.Log then ns.Log("destruir: " .. tostring(err)) end
			end, S)
		end
		pcall(S.CaptureDisenchant)
		return
	end
	if not LucroCraftDB then return end
	if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_CLOSE" or event == "TRADE_SKILL_LIST_UPDATE" then
		-- troca de profissão/expansão na janela do jogo: atualiza os botões
		local line = S.OpenSkillLine()
		if line ~= S._lastLine then S._lastLine = line; SoonRefresh() end
		return
	end
	if event == "SPELLS_CHANGED" then
		pcall(S.CaptureDisenchant)
	elseif event == "TRADE_SKILL_CRAFT_BEGIN" then
		current = a1
		if pend and a1 ~= pend.recipe then pend = nil end
	elseif event == "UNIT_SPELLCAST_SENT" then
		-- Desencantar: o item fica travado na bolsa enquanto a magia é lançada
		if a1 == "player" and a4 == DISENCHANT then
			local id, link = LockedItem()
			local grp = DEGroup(link)
			if grp then
				pend = { recipe = DISENCHANT, input = grp, item = id, last = GetTime(), spell = true }
				DB().sel[DISENCHANT] = grp
			end
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if a1 == "player" and pend and a3 == pend.recipe and GetTime() - pend.last < 30 then
			local o = Obs(ns.CharKey(), pend.recipe, pend.input, true)
			o.casts = o.casts + 1
			o.last = time()
			pend.last = GetTime()
			pend.looted = false
			if pend.n then
				pend.n = pend.n + 1
				-- confere a bolsa 3 s depois da última destruição (o material sai depois do evento)
				local p, mark = pend, pend.n
				C_Timer.After(3, function() if p.n == mark then pcall(CommitBag, p); pcall(CommitOut, p) end end)
			end
			o.savedCasts = (o.savedCasts or 0) + 1   -- toda destruição conta (com ou sem material devolvido)
			pend.resCounted = nil
			SoonRefresh()
		end
	elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
		if not pend or pend.spell or GetTime() - pend.last > 10 then return end
		if current and current ~= pend.recipe then return end
		local data = a1
		local ok, id, qty = pcall(function() return data.itemID, data.quantity end)
		if not ok or type(id) ~= "number" or id <= 0 then return end
		qty = (type(qty) == "number" and qty > 0) and qty or 1
		local o = Obs(ns.CharKey(), pend.recipe, pend.input, true)
		o.out[id] = (o.out[id] or 0) + qty
		o.seen[id] = (o.seen[id] or 0) + 1
		pend.evt = (pend.evt or 0) + 1   -- o jogo avisou: a leitura pela bolsa não conta este lote
		-- Desenvoltura: o jogo informa o material devolvido (uma vez por destruição)
		if not pend.resCounted then
			pend.resCounted = true
			local okR, ret = pcall(function() return data.resourcesReturned end)
			if okR and type(ret) == "table" then
				o.resSeen = true
				for _, rr in ipairs(ret) do
					local rid, rq = rr.itemID, rr.quantity
					if type(rq) == "number" and rq > 0 and (rid == pend.input or rid == nil) then o.saved = (o.saved or 0) + rq end
				end
			end
		end
		pend.last = GetTime()
		SoonRefresh()
	elseif event == "LOOT_READY" then
		-- saque do Desencantar (uma vez por lançamento)
		if not pend or not pend.spell or pend.looted ~= false or GetTime() - pend.last > 5 then return end
		pend.looted = true
		local o = Obs(ns.CharKey(), pend.recipe, pend.input, true)
		for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
			local link = GetLootSlotLink and GetLootSlotLink(i)
			local id = link and C_Item.GetItemInfoInstant(link)
			if id then
				local _, _, qty = GetLootSlotInfo(i)
				qty = (type(qty) == "number" and qty > 0) and qty or 1
				o.out[id] = (o.out[id] or 0) + qty
				o.seen[id] = (o.seen[id] or 0) + 1
			end
		end
		SoonRefresh()
	end
end)

function S.OnRecipeSelected(recipeInfo)
	if not recipeInfo or not LucroCraftDB then return end
	if not recipeInfo.isSalvageRecipe and not S.IsCraftDestroy(recipeInfo) then return end
	local rid = recipeInfo.recipeID
	S.Capture(rid, recipeInfo)
	if not DB().recipes[rid] then return end
	DB().selRecipe = rid
	if not Cfg("salvageFocus") then return end
	if ns.UI and ns.UI.ShowTab then ns.UI.ShowTab(ns.UI.TAB.SALVAGE) end
end

-- ===== Cálculo =====
-- resultados de um item: os do personagem; sem nenhum, junta os dos outros personagens
function S.Stats(recipeID, input)
	local me = ns.CharKey()
	local o = Obs(me, recipeID, input)
	if o and o.casts > 0 then return o, false end
	local m = { casts = 0, out = {}, seen = {} }
	for char, byR in pairs(DB().obs) do
		local x = char ~= me and byR[recipeID] and byR[recipeID][input]
		if x and x.casts > 0 then
			m.casts = m.casts + x.casts
			m.bagCasts, m.bagUsed = (m.bagCasts or 0) + (x.bagCasts or 0), (m.bagUsed or 0) + (x.bagUsed or 0)
			m.saved, m.savedCasts = (m.saved or 0) + (x.saved or 0), (m.savedCasts or 0) + (x.savedCasts or 0)
			m.resSeen = m.resSeen or x.resSeen
			for id, q in pairs(x.out) do m.out[id] = (m.out[id] or 0) + q end
			for id, q in pairs(x.seen or {}) do m.seen[id] = (m.seen[id] or 0) + q end
		end
	end
	if m.casts > 0 then return m, true end
	return nil
end

-- custo de 1 unidade: o menor entre vendedor e o menor anúncio da AH
function S.UnitCost(itemID, noBound)
	local vendor = P.VendorBuy(itemID)
	local ah = P.MarketNow(itemID)
	if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
	if ah then return ah, "ah" end
	local c = P.Cost(itemID)
	if c then return c, "cost" end
	-- vinculado que você mesmo faz (recuperação): custo de fazer
	if S.BoundCost and not noBound then
		local b = S.BoundCost(itemID)
		if b then return b, "bound" end
	end
	return nil
end

local function OutRow(id, avg, chance)
	local price = P.Sale(id)
	return { itemID = id, avg = avg, chance = chance, minb = (P.MarketNow(id)), mean = P.Average(id), price = price,
		value = price and avg * price or nil }
end

-- o que sai de um item (por destruição). how: "mine" | "alts" | "recipe"
function S.Outputs(recipeID, input)
	local o, other = S.Stats(recipeID, input)
	local list, total = {}, 0
	if o then
		for id, q in pairs(o.out) do
			local row = OutRow(id, q / o.casts, math.min(1, (o.seen[id] or 0) / o.casts))
			total = total + (row.value or 0)
			table.insert(list, row)
		end
		return list, total, o.casts, other and "alts" or "mine"
	end
	-- receita normal: a saída é fixa
	local r = DB().recipes[recipeID]
	if r and r.kind == "craft" and r.outItem then
		local q = r.outQty or 1
		-- sem registros: quantidade esperada do scan da profissão (já com o multicraft do personagem)
		local me = ns.CharKey()
		for _, e in pairs((LucroCraftDB.chars or {})[me] or {}) do
			for _, row in ipairs(e.rows or {}) do
				if row.recipeID == recipeID and row.expQty and row.expQty > 0 then q = row.expQty end
			end
		end
		local row = OutRow(r.outItem, q, 1)
		return { row }, row.value or 0, 0, "recipe"
	end
	return nil
end

-- material gasto de fato por destruição (Desenvoltura medida). Devolve: gasto, % economizado, como mediu
local RES_MIN = 5
function S.UsePerCast(recipeID, input, per)
	local o = S.Stats(recipeID, input)
	if o and o.resSeen and (o.savedCasts or 0) >= RES_MIN then
		local use = math.max(0, per - (o.saved or 0) / o.savedCasts)
		return use, 1 - use / per, "game", o.savedCasts
	end
	if o and (o.bagCasts or 0) >= RES_MIN and (o.bagUsed or 0) > 0 then
		local use = math.max(0, math.min(per, o.bagUsed / o.bagCasts))
		return use, 1 - use / per, "bag", o.bagCasts
	end
	return per, nil, nil, 0
end

-- ===== custo de um reagente VINCULADO que você mesmo faz destruindo/recuperando outro item =====
-- Ex.: o catalisador das transmutações da Alquimia sai da recuperação de ervas. Vinculado não tem preço na AH,
-- então o custo é: (preço da entrada mais barata × gasto por destruição) ÷ quantos saem por destruição (medido).
-- Devolve: custo por unidade, { recipeID, input, name, perOut } ou nil. Cache de 30 s.
local bcCache, bcT = {}, 0
function S.BoundCost(itemID)
	if not itemID or not LucroCraftDB then return nil end
	local now = GetTime and GetTime() or 0
	if now - bcT > 30 then wipe(bcCache); bcT = now end
	local c = bcCache[itemID]
	if c ~= nil then return c and c.unit or nil, c or nil end
	local d = DB()
	local best
	for rid, r in pairs(d.recipes) do
		if r.kind ~= "spell" and r.inputs then
			-- saída média do item por destruição: por entrada (todas as contas) e da receita inteira
			local totCasts, totOut, byIn = 0, 0, {}
			for _, byR in pairs(d.obs) do
				for input, o in pairs(byR[rid] or {}) do
					local n = o.out and o.out[itemID]
					if (o.casts or 0) > 0 then
						totCasts = totCasts + o.casts
						totOut = totOut + (n or 0)
						local b = byIn[input] or { c = 0, n = 0 }
						b.c, b.n = b.c + o.casts, b.n + (n or 0)
						byIn[input] = b
					end
				end
			end
			if totOut > 0 then
				local avg = totOut / totCasts
				for _, input in ipairs(r.inputs) do
					local b = byIn[input]
					local per = (b and b.c >= 3) and (b.n / b.c) or avg
					if per > 0 then
						local unit = S.UnitCost(input, true)
						if unit then
							local use = S.UsePerCast(rid, input, r.perCast or 1)
							local cost = unit * use / per
							if not best or cost < best.unit then
								best = { unit = cost, recipeID = rid, input = input, name = r.name, perOut = per, use = use }
							end
						end
					end
				end
			end
		end
	end
	bcCache[itemID] = best or false
	return best and best.unit or nil, best
end

-- custo dos outros reagentes de cada vez (craft): AH/vendedor ou, se vinculado, o custo de fazer (BoundCost)
function S.ExtraCost(r)
	if not r.extras or #r.extras == 0 then return nil end
	local total, list = 0, {}
	for _, x in ipairs(r.extras) do
		local best, how, id0
		for _, id in ipairs(x.ids or {}) do
			local u, h = S.UnitCost(id)
			if u and (not best or u < best) then best, how, id0 = u, h, id end
		end
		id0 = id0 or (x.ids and x.ids[1])
		local c = best and best * x.qty or 0
		total = total + c
		table.insert(list, { itemID = id0, qty = x.qty, unit = best, cost = c, how = how })
	end
	return total, list
end

-- cargas agora (estimado desde a captura), máximo, segundos até a próxima
function S.Charges(r, char)
	local c = r and r.cdBy and r.cdBy[char or ns.CharKey()]
	if not c or not ns.Charges then return nil end
	return ns.Charges({ cd = c })
end

-- todas as linhas da parte 1
function S.Inputs(recipeID)
	local r = DB().recipes[recipeID]
	if not r then return {} end
	local per = r.perCast or 1
	local cut = Cfg("ahCut") or 0.05
	local rows = {}
	local function Finish(row)
		local _, gross, casts, how = S.Outputs(recipeID, row.key)
		row.how, row.casts, row.gross = how, casts or 0, gross
		if not gross and r.kind ~= "spell" then
			local dv = P.Destroy(row.itemID)
			if dv then row.gross, row.how = dv * per, "tsm" end
		end
		row.net = row.gross and row.gross * (1 - cut) or nil
		row.profit = (row.net and row.cost) and (row.net - row.cost) or nil
		table.insert(rows, row)
	end
	if r.kind == "spell" then
		-- Desencantar: custo = o que o NPC paga pelo item (o que você deixa de ganhar)
		for _, g in ipairs(BagGear()) do
			Finish({ itemID = g.itemID, key = g.group, link = g.link, ilvl = g.ilvl, per = 1,
				unit = g.sell or 0, src = "npc", cost = g.sell or 0, have = g.have })
		end
	else
		local extra, extraList = S.ExtraCost(r)
		for _, id in ipairs(r.inputs or {}) do
			local unit, src = S.UnitCost(id)
			local okC, n = pcall(C_Item.GetItemCount, id, true, false, true, true)
			local use, res, resHow = S.UsePerCast(recipeID, id, per)
			Finish({ itemID = id, key = id, per = per, use = use, res = res, resHow = resHow, unit = unit, src = src,
				cost = unit and (unit * use + (extra or 0)) or nil, extra = extra, extraList = extraList, have = okC and n or 0 })
		end
		-- transmutação: as entradas são qualidades do mesmo material → fica só a combinação mais barata
		if r.transmute and #rows > 1 then
			local best
			for _, rw in ipairs(rows) do if rw.cost and (not best or rw.cost < best.cost) then best = rw end end
			if best then
				best.cheapest = true
				rows = { best }
			end
		end
	end
	return rows
end

-- linha da receita no scan da profissão do personagem (qualidade, concentração, quantidade esperada)
function S.ScanRow(recipeID, skillLine)
	local me = ns.CharKey()
	local es = (LucroCraftDB.chars or {})[me] or {}
	local function find(e) for _, row in ipairs(e.rows or {}) do if row.recipeID == recipeID then return row end end end
	if skillLine and es[skillLine] then local x = find(es[skillLine]); if x then return x end end
	for _, e in pairs(es) do local x = find(e); if x then return x end end
end

-- projeção com concentração: sai a qualidade de cima (concItemID). Valor = baú/itens de cima;
-- sem aberturas da qualidade de cima, projeta com o mesmo conteúdo na qualidade superior de cada item.
function S.ConcProjection(r, recipeID, costPerCast)
	local row = S.ScanRow(recipeID, r.skillLine)
	if not (row and row.concItemID and row.concCost and row.concItemID ~= row.itemID) then return nil end
	local cut = Cfg("ahCut") or 0.05
	local q = row.expQty or row.qty or 1
	local baseItem = row.itemID
	local CTm = ns.Containers
	local vBase = P.Sale(baseItem)
	local vTop, how = P.Sale(row.concItemID), "price"
	if CTm and CTm.Get(row.concItemID) then how = "opens"
	elseif CTm and CTm.Get(baseItem) then vTop, how = CTm.ProjectHigher(baseItem), "projected" end
	if not vTop then return { row = row, noValue = true } end
	local netBase = vBase and vBase * q * (1 - cut) or nil
	local netTop = vTop * q * (1 - cut)
	local res = { row = row, how = how, vBase = vBase, vTop = vTop, q = q, netTop = netTop, netBase = netBase, conc = row.concCost }
	if costPerCast then
		res.profitTop = netTop - costPerCast
		res.profitBase = netBase and (netBase - costPerCast) or nil
		if res.profitBase then res.extra = res.profitTop - res.profitBase; res.perPoint = res.extra / row.concCost end
	end
	return res
end

-- receitas para mostrar: as do personagem (ou todas, se ele não tem nenhuma)
-- profissões que o personagem tem agora: nomes e linhas de perícia base (333 = Encantamento)
local function MyProfessions()
	local names, lines = {}, {}
	if GetProfessions and GetProfessionInfo then
		-- principais + secundárias (arqueologia, pesca, culinária): Culinária tem recuperação (Practically Pork etc.)
		local a, b, c, d, e = GetProfessions()
		for _, i in pairs({ a, b, c, d, e }) do
			local ok, name, _, _, _, _, _, line = pcall(GetProfessionInfo, i)
			if ok and name then names[name] = true end
			if ok and line then lines[line] = true end
		end
	end
	return names, lines, next(names) ~= nil
end
S._MyProfessions = MyProfessions
ns.MyProfessions = MyProfessions

-- receitas do personagem logado, só das profissões que ele tem
-- profissão aberta na janela do jogo, já com a expansão escolhida no filtro (ex.: 2906 = Midnight Alchemy).
-- Janela fechada: a última que foi aberta.
function S.OpenSkillLine()
	local open = ProfessionsFrame and ProfessionsFrame.IsShown and ProfessionsFrame:IsShown()
	if open and C_TradeSkillUI.GetChildProfessionInfo then
		local ok, info = pcall(C_TradeSkillUI.GetChildProfessionInfo)
		if ok and info and info.professionID and info.professionID > 0 then return info.professionID, info.parentProfessionID end
	end
	local last = LucroCraftDB.last and LucroCraftDB.last.professionID
	if last and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
		local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, last)
		return last, ok and info and info.parentProfessionID or nil
	end
	return last
end

function S.Recipes()
	local d, me, list = DB(), ns.CharKey(), {}
	local names, lines, known = MyProfessions()
	local openLine, openParent = S.OpenSkillLine()
	for rid, r in pairs(d.recipes) do
		local ok = r.chars and r.chars[me] and not NoItemRecipe(rid, r.name)
		if ok and known then
			if r.kind == "spell" then ok = lines[333] or names[r.prof or ""]
			elseif r.kind == "craft" and not (r.transmute or S.IsCraftDestroy({ name = r.name, recipeID = rid })) then ok = false
			else ok = names[r.prof or ""] end
		end
		if ok then table.insert(list, rid) end
	end
	-- só os botões da profissão/expansão aberta (Desencantar vai junto com qualquer expansão do Encantamento)
	if openLine then
		local f = {}
		for _, rid in ipairs(list) do
			local r = d.recipes[rid]
			if r.skillLine == openLine or (r.kind == "spell" and openParent == 333) then table.insert(f, rid) end
		end
		list = f
	end
	table.sort(list, function(a, b)
		local ra, rb = d.recipes[a], d.recipes[b]
		if (ra.prof or "") ~= (rb.prof or "") then return (ra.prof or "") < (rb.prof or "") end
		return (ra.name or "") < (rb.name or "")
	end)
	return list
end

-- ===== Desenho =====
local nameWait = false
local function ItemName(id)
	local n = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if n then return n end
	if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	if not nameWait then
		nameWait = true
		C_Timer.After(1, function() nameWait = false; SoonRefresh() end)
	end
	return "item " .. id
end
local function ItemColor(id)
	local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
	if q and C_Item.GetItemQualityColor then
		local _, _, _, hex = C_Item.GetItemQualityColor(q)
		if hex then return "|c" .. hex end
	end
	return "|cffffffff"
end
local function Name(id, ilvl)
	local q = ns.Scanner and ns.Scanner.ReagentQuality and ns.Scanner.ReagentQuality(id)
	return ItemColor(id) .. ItemName(id) .. "|r" .. (q and (" " .. ns.QIcon(q, 2, 12)) or "")
		.. ((ilvl and ilvl > 0) and (" |cff9d9d9d" .. ilvl .. "|r") or "")
end

local function Section(cv, y, W, title, sub)
	cv:Box(0, y, W, 18, 1, 0.82, 0, 0.10)
	cv:Text(6, y + 3, "|cffffd100" .. title .. "|r" .. (sub and ("  |cff9d9d9d" .. sub .. "|r") or ""), GameFontNormalSmall)
	return y + 24
end

local SRC = { vendor = L["vendedor"], ah = L["AH"], cost = L["custo"], npc = L["NPC paga"], bound = L["fazer"] }
local HOW = { mine = L["seus registros"], alts = L["outros personagens"], tsm = L["estimativa TSM"], recipe = L["saída da receita"] }
local GREY = "|cff9d9d9d"

-- coluna de item: ícone + nome
local function ItemCol(getID, getLink, getIlvl)
	return function(cv, x, y, w, row)
		local id = getID(row)
		local link = getLink and getLink(row)
		cv:Icon(x, y, 20, ns.Visual.ItemIcon(id), { link = link, tip = function(tt)
			if link then tt:SetHyperlink(link) else tt:SetItemByID(id) end
		end })
		cv:Text(x + 26, y + 4, Name(id, getIlvl and getIlvl(row)), GameFontHighlightSmall, w - 26)
	end
end

function S.Render(cv)
	local G = P.FormatGold
	local W = cv:Width()
	local d = DB()
	cv:Begin()
	pcall(S.CaptureDisenchant)
	local recipes = S.Recipes()
	if #recipes == 0 and S.OpenSkillLine() then
		local line = S.OpenSkillLine()
		local name = "?"
		if C_TradeSkillUI.GetProfessionInfoBySkillLineID then
			local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, line)
			if ok and info then name = info.professionName or name end
		end
		cv:Text(8, 8, string.format(L["Nenhuma receita de destruição ou transmutação conhecida em |cffffd100%s|r. Troque a profissão ou a expansão na janela de profissão."], name),
			GameFontHighlight, W - 16)
		cv:End(60)
		return
	end
	if #recipes == 0 then
		cv:Text(8, 8, L["Nenhuma receita de destruição das profissões deste personagem ainda. Abra a profissão (Joalheria, Engenharia, Escrivania, Encantamento, Alquimia) para o addon conhecer as receitas: Prospecção, Trituração, Reciclagem, Moagem, Estilhaçar..."],
			GameFontHighlight, W - 16)
		cv:End(60)
		return
	end
	local rid = d.selRecipe
	local inList = false
	for _, x in ipairs(recipes) do if x == rid then inList = true end end
	if not inList then
		rid = recipes[1]
		local last = LucroCraftDB.last and LucroCraftDB.last.professionID
		for _, x in ipairs(recipes) do if d.recipes[x].skillLine == last then rid = x; break end end
	end
	local r = d.recipes[rid]
	local spell = r.kind == "spell"

	-- receitas (botões)
	local y, x = 6, 8
	for _, id in ipairs(recipes) do
		local rr = d.recipes[id]
		local label = (id == rid and "|cffd4af37" or "") .. (rr.name or ("#" .. id)) .. (id == rid and "|r" or "")
		local w = math.max(110, math.min(220, 24 + #(rr.name or "") * 7))
		if x + w > W - 8 then x = 8; y = y + 26 end
		cv:Button(x, y, w, 22, label, function() d.selRecipe = id; S.Refresh() end,
			function(tt) tt:SetText(rr.name or "?"); tt:AddLine(rr.prof or "", 0.7, 0.7, 0.7) end)
		x = x + w + 6
	end
	y = y + 32
	cv:Icon(8, y, 28, r.icon)
	cv:Text(42, y + 2, "|cffffd100" .. (r.name or "?") .. "|r  " .. GREY .. (r.prof or "") .. "|r", GameFontNormal)
	local sub
	local trans = r.kind == "craft" and r.transmute
	if trans then
		sub = string.format(L["|cff9d9d9dtransmutação: todos os materiais da receita · retorno líquido = valor de venda − %d%% da AH|r"],
			math.floor((Cfg("ahCut") or 0.05) * 100 + 0.5))
	elseif spell then
		sub = L["|cff9d9d9d1 item por vez · o que sai depende da raridade e da expansão do item · custo = o que o NPC pagaria por ele|r"]
	else
		sub = string.format(L["|cff9d9d9d%d por destruição · retorno líquido = valor de venda − %d%% da AH|r"],
			r.perCast or 1, math.floor((Cfg("ahCut") or 0.05) * 100 + 0.5))
	end
	if r.transmute then
		local cur, max, nextIn = S.Charges(r)
		sub = sub .. "  ·  " .. (cur and string.format(L["|cffffd100cargas %d/%d|r%s"], cur, max,
			nextIn and string.format(L[" (+1 em %s)"], (nextIn >= 3600 and string.format("%dh%02d", math.floor(nextIn / 3600), math.floor(nextIn % 3600 / 60)) or string.format("%d min", math.ceil(nextIn / 60)))) or "")
			or L["|cff9d9d9dcargas: abra a profissão para ler|r"])
		local me = ns.CharKey()
		local e = (LucroCraftDB.chars or {})[me] and LucroCraftDB.chars[me][r.skillLine]
		local nc = e and ns.Invest and ns.Invest.NextCharge and ns.Invest.NextCharge(e)
		if nc then sub = sub .. "  ·  " .. string.format(L["próximo: %s em %s (%d pts)"], ns.Invest._ChargeLabel and ns.Invest._ChargeLabel(nc) or "?", nc.node, nc.points) end
	end
	cv:Text(42, y + 16, sub, GameFontDisableSmall, W - 50)
	y = y + 38

	-- ===== Parte 1: o que pode ser destruído =====
	local rows = S.Inputs(rid)
	if trans then
		y = Section(cv, y, W, L["Materiais por craft"], L["cada espaço na qualidade mais barata · custo = menor entre vendedor e menor anúncio da AH"])
	else
		y = Section(cv, y, W, L["O que pode ser destruído"], spell and L["equipamentos nas suas bolsas · clique para ver o que sai"]
			or L["custo = menor entre vendedor e menor anúncio da AH · clique para ver o que sai"])
	end
	local sel = d.sel[rid]
	local selOK = false
	for _, row in ipairs(rows) do if row.key == sel then selOK = true end end
	-- linhas úteis: com preço, registro ou estoque
	local useful, hidden = {}, 0
	for _, row in ipairs(rows) do
		if row.unit or row.gross or (row.have or 0) > 0 or row.key == sel then table.insert(useful, row)
		else hidden = hidden + 1 end
	end
	local function money(v, color) return v and G(v, color) or GREY .. "—|r" end
	local y1, shown, cut
	-- lista do meio com rolagem própria; o topo (receitas) e a parte de baixo (o que sai) ficam visíveis
	local sub = cv._salvIn
	local listTop = y
	if trans then
		y1, shown, cut = y, useful, 0
		if sub then sub:Hide() end
	else
	if not sub then sub = ns.Visual.CreateSub(cv); cv._salvIn = sub end
	local listH = cv._salvListH or 300
	sub:Place(0, y, W, listH)
	sub:Show()
	sub:Begin()
	y1, shown, cut = ns.Visual.Table(sub, 0, sub:Width(), {
		id = "salvageIn", rows = useful, max = MAX_ROWS, refresh = function() S.Refresh() end,
		defaultSort = { key = "profit", desc = true },
		columns = {
			{ key = "name", label = L["Item"], width = 250, align = "LEFT", sort = function(rw) return ItemName(rw.itemID) end,
				draw = ItemCol(function(rw) return rw.itemID end, function(rw) return rw.link end, function(rw) return rw.ilvl end) },
			{ key = "per", label = L["Qtd"], width = 36, align = "RIGHT", sort = function(rw) return rw.per end,
				text = function(rw)
					if rw.res and rw.res > 0.0005 then return root.Num(rw.use, 2) end
					return tostring(rw.per)
				end },
			{ key = "res", label = ns.STAT.resourcefulness, width = 84, align = "RIGHT", sort = function(rw) return rw.res or -1 end,
				text = function(rw)
					if rw.res == nil then return GREY .. "—|r" end
					return "|cff55ff55" .. root.Num(rw.res * 100, 1) .. "%|r"
				end },
			{ key = "unit", label = spell and L["NPC paga"] or L["Custo un."], width = 120, align = "RIGHT", sort = function(rw) return rw.unit end,
				text = function(rw) return rw.unit and (G(rw.unit) .. " " .. GREY .. (SRC[rw.src] or "") .. "|r") or GREY .. "?|r" end },
			{ key = "cost", label = L["Custo/vez"], width = 86, align = "RIGHT", sort = function(rw) return rw.cost end,
				text = function(rw) return rw.cost and G(rw.cost) or GREY .. "?|r" end },
			{ key = "ret", label = L["Retorno/vez"], width = 96, align = "RIGHT", sort = function(rw) return rw.net end,
				desc = L["valor de venda do que sai, menos o corte da AH (~ = estimativa)"],
				text = function(rw)
					local s = money(rw.net)
					if rw.how == "tsm" or rw.how == "alts" then s = GREY .. "~|r" .. s end
					return s
				end },
			{ key = "profit", label = L["Lucro/vez"], width = 86, align = "RIGHT", sort = function(rw) return rw.profit end,
				text = function(rw) return money(rw.profit, true) end },
			{ key = "have", label = L["Tem"], width = 44, align = "RIGHT", sort = function(rw) return rw.have or 0 end,
				text = function(rw) return (rw.have or 0) > 0 and tostring(rw.have) or GREY .. "0|r" end },
			{ key = "regs", label = L["Registros"], width = 70, align = "RIGHT", sort = function(rw) return rw.casts end,
				desc = L["quantas destruições o addon registrou para este item"],
				text = function(rw)
					if rw.casts > 0 then return tostring(rw.casts) end
					return GREY .. (rw.how == "tsm" and L["TSM"] or rw.how == "recipe" and L["receita"] or "0") .. "|r"
				end },
		},
		selected = function(rw) return rw.key == (selOK and sel or nil) end,
		onClick = function(rw) d.sel[rid] = rw.key; S.Refresh() end,
		tip = function(rw)
			return function(tt)
				tt:SetText(ItemName(rw.itemID))
				tt:AddDoubleLine(spell and L["NPC paga"] or L["Custo por destruição"], rw.cost and P.FormatMoney(rw.cost) or "?", 1, 1, 1, 1, 1, 1)
				for _, x in ipairs(rw.extraList or {}) do
					tt:AddDoubleLine("  + " .. x.qty .. "x " .. ItemName(x.itemID), x.unit and P.FormatMoney(x.cost) or "?", 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
				end
				tt:AddDoubleLine(L["Retorno líquido"], rw.net and P.FormatMoney(rw.net) or "?", 1, 1, 1, 0.3, 1, 0.3)
				tt:AddDoubleLine(L["Fonte do retorno"], HOW[rw.how] or L["sem dados"], 1, 1, 1, 0.7, 0.7, 0.7)
				if rw.casts > 0 then tt:AddDoubleLine(L["Destruições registradas"], tostring(rw.casts), 1, 1, 1, 1, 1, 1) end
				tt:AddLine(L["Clique para ver o que sai."], 0.6, 0.6, 0.6)
			end
		end,
	})
	sub:End(y1)
	local vis = math.min(y1, listH)
	sub:Place(0, y, W, vis)
	y1 = y + vis + 4
	end
	y = y1
	if not selOK then sel = shown[1] and shown[1].key end
	-- materiais de cada vez (todos os espaços, na qualidade mais barata)
	if r.kind == "craft" and (trans or (r.extras and #r.extras > 0)) and shown[1] then
		local base = shown[1]
		for _, rw in ipairs(rows) do if rw.key == sel then base = rw end end
		if not trans then
			cv:Text(8, y + 2, "|cffffd100" .. L["Materiais por vez (qualidade mais barata):"] .. "|r", GameFontNormalSmall)
			y = y + 18
		end
		local mats = { { itemID = base.itemID, qty = base.use or base.per, unit = base.unit, how = base.src } }
		for _, x in ipairs(base.extraList or {}) do table.insert(mats, { itemID = x.itemID, qty = x.qty, unit = x.unit, how = x.how }) end
		local total = 0
		for k, m in ipairs(mats) do
			ns.root.Zebra(cv, k, 0, y - 2, W, 20)
			cv:Icon(16, y, 16, ns.Visual.ItemIcon(m.itemID), { tip = function(tt) tt:SetItemByID(m.itemID) end })
			cv:Text(38, y + 2, root.Num(m.qty, m.qty == math.floor(m.qty) and 0 or 2) .. "x " .. Name(m.itemID), GameFontHighlightSmall, 300)
			cv:Text(350, y + 2, m.unit and (G(m.unit) .. " " .. GREY .. (SRC[m.how] or "") .. "|r") or GREY .. "?|r", GameFontHighlightSmall, 120, "RIGHT")
			cv:Text(480, y + 2, m.unit and G(m.unit * m.qty) or GREY .. "?|r", GameFontHighlightSmall, 90, "RIGHT")
			total = total + (m.unit or 0) * m.qty
			y = y + 20
		end
		cv:Text(350, y + 2, L["Total"], GameFontNormalSmall, 120, "RIGHT")
		cv:Text(480, y + 2, G(total), GameFontNormalSmall, 90, "RIGHT")
		y = y + 22
		if trans then
			-- quantas dá para fazer com o que tem (bolsa + banco)
			local can
			for _, m in ipairs(mats) do
				local okC, n = pcall(C_Item.GetItemCount, m.itemID, true, false, true, true)
				local k = math.floor(((okC and n) or 0) / math.max(m.qty, 1))
				if not can or k < can then can = k end
			end
			cv:Text(8, y, string.format(L["Com o que você tem dá para fazer |cffffffff%d|r."], can or 0), GameFontHighlightSmall, W - 16)
			y = y + 18
		end
	end
	if #useful == 0 then
		cv:Text(8, y, spell and L["|cff9d9d9dNenhum equipamento verde, azul ou roxo nas bolsas.|r"]
			or L["|cff9d9d9dSem itens com preço para esta receita. Selecione a receita na janela de profissão para atualizar a lista.|r"],
			GameFontHighlightSmall, W - 16)
		y = y + 18
	end
	if hidden + (cut or 0) > 0 then
		cv:Text(8, y, string.format(L["|cff9d9d9d+%d itens sem preço nem registro|r"], hidden + (cut or 0)), GameFontDisableSmall)
		y = y + 16
	end
	y = y + 10
	local bottomStart = y

	-- ===== Parte 2: o que pode sair =====
	if sel then
		local row
		for _, rw in ipairs(rows) do if rw.key == sel then row = rw end end
		local title = row and ItemName(row.itemID) or tostring(sel)
		if spell and row then
			title = title .. GREY .. string.format(L[" (e tudo da mesma raridade e expansão)"]) .. "|r"
		end
		if trans then title = r.name or title end
		y = Section(cv, y, W, string.format(L["O que pode sair de %s"], title),
			trans and L["quantidade = média dos seus crafts (ou a esperada pelo scan) · valor = quantidade × preço de venda"]
			or L["chance e quantidade = média das suas destruições · valor/vez = quantidade média × preço de venda"])
		local list, total, casts, how = S.Outputs(rid, sel)
		if list and #list > 0 then
			local maxV = 1
			for _, o in ipairs(list) do if (o.value or 0) > maxV then maxV = o.value end end
			y = ns.Visual.Table(cv, y, W, {
				id = "salvageOut", rows = list, refresh = function() S.Refresh() end,
				defaultSort = { key = "value", desc = true },
				columns = {
					{ key = "name", label = L["Item"], width = 270, align = "LEFT", sort = function(o) return ItemName(o.itemID) end,
						draw = ItemCol(function(o) return o.itemID end) },
					{ key = "chance", label = L["Chance"], width = 60, align = "RIGHT", sort = function(o) return o.chance end,
						text = function(o) return string.format("%.0f%%", o.chance * 100) end },
					{ key = "avg", label = L["Média/vez"], width = 70, align = "RIGHT", sort = function(o) return o.avg end,
						text = function(o) return root.Num(o.avg, 2) end },
					{ key = "minb", label = L["Menor AH"], width = 96, align = "RIGHT", sort = function(o) return o.minb end,
						text = function(o) return money(o.minb) end },
					{ key = "mean", label = L["Média atual"], width = 96, align = "RIGHT", sort = function(o) return o.mean end,
						text = function(o) return money(o.mean) end },
					{ key = "value", label = L["Valor/vez"], width = 230, align = "LEFT", sort = function(o) return o.value end,
						draw = function(cv2, x2, y2, w2, o)
							cv2:Text(x2, y2 + 4, o.value and G(o.value) or GREY .. "?|r", GameFontHighlightSmall, 80, "RIGHT")
							local bw = math.floor((w2 - 90) * (o.value or 0) / maxV)
							if bw > 0 then cv2:Box(x2 + 90, y2 + 6, bw, 10, 0.83, 0.69, 0.22, 0.7) end
						end },
				},
			})
			local cutPct = Cfg("ahCut") or 0.05
			local net = total * (1 - cutPct)
			local cost = row and row.cost
			local line = string.format(trans and L["Retorno por craft: |cffffffff%s|r · líquido |cff55ff55%s|r"] or L["Retorno por destruição: |cffffffff%s|r · líquido |cff55ff55%s|r"], G(total), G(net))
			if cost then line = line .. string.format(L[" · custo %s · lucro %s"], G(cost), G(net - cost, true)) end
			cv:Text(8, y + 2, line, GameFontNormalSmall, W - 16)
			y = y + 18
			local base
			if how == "recipe" then base = trans and L["|cff9d9d9dSaída esperada da receita (ainda sem crafts registrados).|r"] or L["|cff9d9d9dSaída fixa da receita (ainda sem destruições registradas).|r"]
			elseif how == "alts" then base = string.format(L["|cff9d9d9dBase: %d destruições de outros personagens (a especialização de cada um muda o resultado).|r"], casts)
			else base = string.format(L["|cff9d9d9dBase: %d destruições suas.|r"], casts) end
			cv:Text(8, y, base, GameFontDisableSmall, W - 16)
			y = y + 16
			-- saída é um baú: mostra o que sai ao abrir (aprendido pelas aberturas)
			for _, o in ipairs(list) do
				local CTm = ns.Containers
				if CTm and (CTm.Get(o.itemID) or (r.transmute and not o.price)) then
					y = y + 6
					local val, items, opens = CTm.Value(o.itemID)
					if not opens then
						cv:Text(8, y, string.format(L["|cffffd100%s|r é um baú: abra alguns para o addon aprender o que sai (o valor vem do conteúdo)."], ItemName(o.itemID)),
							GameFontHighlightSmall, W - 16)
						y = y + 18
					else
						cv:Text(8, y, string.format(L["Ao abrir |cffffd100%s|r (%d aberturas): vale %s em média"], ItemName(o.itemID), opens, val and G(val) or "?"),
							GameFontNormalSmall, W - 16)
						y = y + 18
						for k, it in ipairs(items or {}) do
							if k > 10 then break end
							ns.root.Zebra(cv, k, 0, y - 2, W, 22)
							cv:Icon(16, y, 18, ns.Visual.ItemIcon(it.itemID), { tip = function(tt) tt:SetItemByID(it.itemID) end })
							cv:Text(40, y + 3, Name(it.itemID), GameFontHighlightSmall, 300)
							cv:Text(350, y + 3, string.format("%.0f%%", it.chance * 100), GameFontHighlightSmall, 50, "RIGHT")
							cv:Text(410, y + 3, root.Num(it.avg, 2), GameFontHighlightSmall, 60, "RIGHT")
							cv:Text(480, y + 3, it.price and G(it.price) or GREY .. "?|r", GameFontHighlightSmall, 90, "RIGHT")
							cv:Text(580, y + 3, it.value and G(it.value) or GREY .. "?|r", GameFontHighlightSmall, 90, "RIGHT")
							y = y + 22
						end
					end
				end
			end
			-- projeção com concentração (qualidade de cima)
			y = y + 6
			local pj = r.kind == "craft" and S.ConcProjection(r, rid, cost)
			if pj then
				y = y + 6
				cv:Box(0, y - 2, W, 18, 0.17, 0.36, 0.66, 0.25)
				cv:Text(8, y + 1, string.format(L["|cffffd100Com concentração|r (%s pontos): sai %s"], root.Num(pj.conc, 0), Name(pj.row.concItemID)), GameFontNormalSmall, W - 16)
				y = y + 20
				if pj.noValue then
					cv:Text(16, y, L["|cff9d9d9dSem valor da qualidade de cima ainda: abra alguns baús dessa qualidade.|r"], GameFontHighlightSmall, W - 24)
					y = y + 18
				else
					local function Pf(v) return v and G(v, true) or GREY .. "?|r" end
					cv:Text(16, y, string.format(L["Sem concentração: valor %s · lucro %s"], pj.vBase and G(pj.vBase * pj.q) or "?", Pf(pj.profitBase)), GameFontHighlightSmall, W - 24)
					y = y + 16
					cv:Text(16, y, string.format(L["Com concentração: valor %s · lucro %s"], G(pj.vTop * pj.q), Pf(pj.profitTop)), GameFontHighlightSmall, W - 24)
					y = y + 16
					if pj.extra then
						cv:Text(16, y, string.format(L["Ganho da concentração: %s por craft · |cffffd100%s por ponto|r"], G(pj.extra, true), G(pj.perPoint, true)), GameFontHighlightSmall, W - 24)
						y = y + 16
					end
					local note = pj.how == "projected" and L["|cff9d9d9dProjeção: mesmo conteúdo do baú comum, com cada item na qualidade de cima. Abra baús dessa qualidade para trocar pela média real.|r"]
						or pj.how == "opens" and L["|cff9d9d9dValor pela média dos baús dessa qualidade que você abriu.|r"]
						or L["|cff9d9d9dValor pelo preço de venda da qualidade de cima.|r"]
					cv:Text(16, y, note, GameFontDisableSmall, W - 24)
					y = y + 16
				end
			end
		else
			-- sem registro deste item: saídas já vistas na receita (outros itens) + estimativa do TSM
			local seen = {}
			for _, byR in pairs(d.obs) do
				for _, o in pairs(byR[rid] or {}) do for id in pairs(o.out or {}) do seen[id] = true end end
			end
			cv:Text(8, y, L["|cff9d9d9dAinda sem registro deste item: destrua alguns e o addon aprende o que sai (chance e quantidade).|r"],
				GameFontHighlightSmall, W - 16)
			y = y + 18
			local dv = row and P.Destroy(row.itemID)
			if dv then
				cv:Text(8, y, string.format(L["Estimativa do TSM: %s por destruição (%s por unidade)."], G(dv * (r.perCast or 1)), G(dv)),
					GameFontHighlightSmall, W - 16)
				y = y + 18
			end
			local ids = {}
			for id in pairs(seen) do table.insert(ids, id) end
			table.sort(ids)
			if #ids > 0 then
				cv:Text(8, y, L["Já saiu desta receita com outros itens:"], GameFontNormalSmall)
				y = y + 16
				for _, id in ipairs(ids) do
					cv:Icon(8, y, 20, ns.Visual.ItemIcon(id), { tip = function(tt) tt:SetItemByID(id) end })
					cv:Text(34, y + 4, Name(id), GameFontHighlightSmall, 300)
					local minb = P.MarketNow(id)
					local mean = P.Average(id)
					cv:Text(340, y + 4, string.format(L["menor AH %s · média %s"], minb and G(minb) or "—", mean and G(mean) or "—"),
						GameFontHighlightSmall, 300)
					y = y + 24
				end
			end
		end
	end
	cv:End(y + 10)
	-- altura da lista do meio: o que sobra da janela depois do topo e da parte de baixo (2ª passada se mudou)
	if not trans and not cv._salvRe then
		local viewH = cv.frame:GetHeight()
		local want = math.max(120, math.floor(viewH - listTop - (y - bottomStart) - 24))
		if math.abs(want - (cv._salvListH or 300)) > 4 then
			cv._salvListH = want
			cv._salvRe = true
			pcall(S.Render, cv)
			cv._salvRe = nil
		end
	end
end

function S.Refresh()
	if ns.UI and ns.UI.RefreshTab and ns.UI.TAB then ns.UI.RefreshTab(ns.UI.TAB.SALVAGE) end
end
