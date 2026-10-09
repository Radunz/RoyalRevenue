local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
local L = ns.L

-- ===== Sugestão de consumíveis (Mercado > Comprar > Consumíveis, abaixo da lista de usados) =====
-- O melhor de cada tipo para cada personagem: frasco do maior secundário, poção de combate, poção de vida,
-- mana (curador/classe de mana), comida, melhoria de arma, runa; itens de grupo (tambores, Emergency Soul Link,
-- caldeirões, banquetes, invisibilidade) com a caixa "incluir itens de grupo" ou se o personagem já usou.
-- Quantidade: horas e chefes mortos (1 poção de combate por chefe, 1 de vida a cada 2) em masmorra, raide e imersão nos últimos 14 dias → para os dias escolhidos.
local Consum = {}
ns.Consum = Consum

-- ids (as duas qualidades quando o item tem; nomes conferidos nos dados salvos do jogo em 08/10/2026)
local IT = {
	flask = { mastery = { 241323 }, haste = { 241325 }, crit = { 241327 }, vers = { 241321 } },
	potRecklessness = { 241289 }, potLight = { 241309 }, potLuster = { 271886, 271887 },
	health = { 271883, 271884 }, healthAlt = { 241305 },
	mana = { 241300, 241301 },
	foodPrimary = { 242747, 242275 },                  -- Hearty Royal Roast (continua após morrer) · Royal Roast
	foodSec = { crit = { 242287, 242278 }, haste = { 242286, 242277 }, vers = { 242284, 242280 }, any = { 255848, 242274 } },
	oil = { 243733, 243734 }, oilDawn = { 243735, 243736 }, whetstone = { 237370 }, weightstone = { 237367 },
	rune = { 259085 },
	drums = { 244639 }, soulLink = { 248486, 269586 }, invis = { 241303 },
	cauldronFlask = { 241319 }, cauldronPot = { 241285 }, feastPrimary = { 255845, 255846 },
}
Consum.IT = IT

local STAT_NAME = { crit = STAT_CRITICAL_STRIKE or "Crítico", haste = STAT_HASTE or "Aceleração", mastery = STAT_MASTERY or "Maestria", vers = STAT_VERSATILITY or "Versatilidade" }
-- classes com Heroísmo/Bloodlust (Shaman, Mage, Hunter pelo pet, Evoker) e com reviver em combate
-- (Druid, Death Knight, Warlock, Paladin): quem não tem, leva o item no lugar
local HAS_LUST = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
local HAS_BRES = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }
Consum.HAS_LUST, Consum.HAS_BRES = HAS_LUST, HAS_BRES
-- sem perfil lido (personagem não entrou desde a v1.24): classes que são sempre de Intelecto / sempre físicas
local CASTER_CLASS = { MAGE = true, WARLOCK = true, PRIEST = true, EVOKER = true }
local PHYS_CLASS = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true, DEMONHUNTER = true, HUNTER = true }
local MANA_CLASS = { PRIEST = true, MAGE = true, WARLOCK = true, DRUID = true, SHAMAN = true, PALADIN = true, EVOKER = true, MONK = true }

-- ===== perfil do personagem (lido ao entrar e ao trocar de spec) =====
local function DB()
	LucroCraftDB.charInfo = LucroCraftDB.charInfo or {}
	return LucroCraftDB.charInfo
end
local BLUNT = { [4] = true, [5] = true, [10] = true, [13] = true }   -- maça 1M/2M, cajado, punho
function Consum.ReadMe()
	if not (GetSpecialization and LucroCraftDB) then return end
	local spec = GetSpecialization()
	if not spec then return end
	local _, specName, _, _, role, primary = GetSpecializationInfo(spec)
	local function R(cr) return (cr and GetCombatRating and GetCombatRating(cr)) or 0 end
	local sec = { crit = R(CR_CRIT_MELEE or 9), haste = R(CR_HASTE_MELEE or 18), mastery = R(CR_MASTERY or 26), vers = R(CR_VERSATILITY_DAMAGE_DONE or 29) }
	local order = { "crit", "haste", "mastery", "vers" }
	table.sort(order, function(a, b) return sec[a] > sec[b] end)
	local weapon = "blade"
	local link = GetInventoryItemLink and GetInventoryItemLink("player", 16)
	if link then
		local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(link)
		if classID == 2 and BLUNT[subID] then weapon = "blunt" end
		if classID == 2 and (subID == 2 or subID == 3 or subID == 18) then weapon = "ranged" end
	end
	local _, class = UnitClass("player")
	-- atributo principal: o da spec; se a API não der, o maior entre Força/Agilidade/Intelecto
	if primary ~= 1 and primary ~= 2 and primary ~= 4 and UnitStat then
		local best, bv = nil, -1
		for _, st in ipairs({ 1, 2, 4 }) do
			local ok, v = pcall(UnitStat, "player", st)
			if ok and v and v > bv then best, bv = st, v end
		end
		primary = best
	end
	if CASTER_CLASS[class or ""] then primary = 4 end
	DB()[ns.CharKey()] = { role = role, primary = primary, spec = specName, sec = sec, top = order[1], second = order[2],
		weapon = weapon, class = class, t = time() }
end
local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }) do pcall(f.RegisterEvent, f, ev) end
f:SetScript("OnEvent", function(_, ev, unit)
	if root.AnySecret(unit) then return end
	if ev == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then return end
	C_Timer.After(2, function() pcall(Consum.ReadMe) end)
end)

-- ===== horas e entradas em combate (masmorra, raide, imersão) nos últimos 14 dias =====
local COMBAT = { dungeon = true, raid = true, delve = true }
local function Activity(char)
	local c = LucroLivroDB and LucroLivroDB.chars and LucroLivroDB.chars[char]
	if not c then return 0, 0, 0 end
	local from = date("%Y-%m-%d", time() - 14 * 86400)
	local secs, runs, firstD = 0, 0, nil
	for d, day in pairs(c.days or {}) do
		if d >= from then
			local any = false
			for k in pairs(COMBAT) do
				local t = day.time and day.time[k] or 0
				local a = day.act and day.act[k]
				if t > 0 or (a and (a.n or 0) > 0) then any = true end
				secs = secs + t
				runs = runs + (a and a.n or 0)
			end
			if any and (not firstD or d < firstD) then firstD = d end
		end
	end
	local days = 14
	if firstD then
		local y, m, dd = firstD:match("(%d+)-(%d+)-(%d+)")
		local t0 = time({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 0 })
		days = math.max(3, math.min(14, (time() - t0) / 86400))
	end
	return secs / 3600, runs, days
end
Consum.Activity = Activity

-- qualidade das sugestões (botão na barra "Sugestão"): 1 ou 2, quando o item tem as duas
function Consum.Quality() return math.max(1, math.min(2, tonumber(LucroCraftDB.config.consQuality) or 1)) end
function Consum.SetQuality(n)
	LucroCraftDB.config = LucroCraftDB.config or {}
	LucroCraftDB.config.consQuality = math.max(1, math.min(2, math.floor(tonumber(n) or 1)))
	if ns.Buy and ns.Buy.Refresh then ns.Buy.Refresh() end
end

-- entre as qualidades do item: a escolhida em Consum.Quality(); item com só 1 ID não tem escolha
local function Pick(ids)
	if #ids <= 1 then return ids[1] end
	return ids[math.min(#ids, Consum.Quality())]
end
Consum.Pick = Pick

local function UsedIds(char)
	local out = {}
	local c = LucroLivroDB and LucroLivroDB.chars and LucroLivroDB.chars[char]
	for _, e in ipairs(c and c.journal or {}) do
		if e.a == "4.5.01" and e.i then out[e.i] = true end
	end
	return out
end

-- lista de sugestões de um personagem: { { cat, ids, need, note } }
function Consum.For(char, group)
	local info = DB()[char] or {}
	local c = LucroLivroDB and LucroLivroDB.chars and LucroLivroDB.chars[char]
	local class = info.class or (c and c.class)
	local role = info.role or "DAMAGER"
	local top, second = info.top, info.second
	local hours, runs, days = Activity(char)
	local cover = ns.Buy.ConsDays()
	local perDay = function(x) return x / days * cover end
	local hrs = perDay(hours)
	local nruns = perDay(runs)
	local out = {}
	local function add(cat, ids, need, note, why)
		table.insert(out, { cat = cat, ids = ids, need = math.max(1, math.ceil(need)), note = note, why = why })
	end
	-- frasco do maior secundário
	if top then
		add("flask", IT.flask[top], hrs, string.format(L["Frasco · %s"], STAT_NAME[top]),
			string.format(L["%s é o seu maior atributo secundário (%s)."], STAT_NAME[top], info.spec or ""))
	else
		add("flask", IT.flask.mastery, hrs, L["Frasco"], L["Entre neste personagem para o addon ler o maior atributo secundário (até lá: Maestria)."])
	end
	-- poção de combate
	local recklessness = info.sec and top and second and info.sec[top] > 0 and (info.sec[top] - info.sec[second]) / info.sec[top] >= 0.15
	if recklessness then
		add("pot", IT.potRecklessness, nruns, L["Poção de combate"], L["Potion of Recklessness: o maior secundário está bem acima do segundo."])
	else
		add("pot", IT.potLight, nruns, L["Poção de combate"], L["Light's Potential (atributo principal): os secundários estão parelhos."])
	end
	-- vida
	add("health", IT.health, nruns / 2, L["Poção de vida"], L["A mais forte; a Silvermoon Health Potion é a opção barata."])
	local isInt = CASTER_CLASS[class or ""] or info.primary == 4
	local isPhys = not isInt and (PHYS_CLASS[class or ""] or (info.primary == 1 or info.primary == 2))
	-- mana
	if role == "HEALER" or (MANA_CLASS[class or ""] and isInt) then
		add("mana", IT.mana, nruns, L["Poção de mana"], L["Para curador e classes de mana."])
	end
	-- comida
	add("food", IT.foodPrimary, hrs, L["Comida"], L["Hearty Royal Roast: atributo principal e continua depois de morrer."])
	-- arma (atributo principal pela spec lida; sem leitura, pela classe; híbrido sem leitura fica sem sugestão)
	if not isInt and not isPhys then
		-- híbrido (Druida, Xamã, Paladino, Monge) que ainda não foi lido: não chuta
	elseif role == "TANK" or role == "HEALER" then
		add("weapon", IT.oilDawn, hrs, L["Arma · Oil of Dawn"], L["Escudo de absorção: bom para tanque e curador."])
	elseif isInt or class == "HUNTER" or info.weapon == "ranged" then
		add("weapon", IT.oil, hrs, L["Arma · Thalassian Phoenix Oil"], L["Crítico + Aceleração."])
	elseif info.weapon == "blunt" then
		add("weapon", IT.weightstone, hrs, L["Arma · Refulgent Weightstone"], L["Poder de ataque para arma de impacto."])
	else
		add("weapon", IT.whetstone, hrs, L["Arma · Refulgent Whetstone"], L["Poder de ataque para arma de lâmina."])
	end
	-- runa
	add("rune", IT.rune, hrs, L["Runa de aumento"], L["Void-Touched Augment Rune: cara, para conteúdo difícil."])
	-- itens de grupo: com a caixa, ou se o personagem já usou
	local used = UsedIds(char)
	local function usedAny(ids) for _, id in ipairs(ids) do if used[id] then return true end end end
	local cls = class or ""
	local noLust, noBres = cls ~= "" and not HAS_LUST[cls], cls ~= "" and not HAS_BRES[cls]
	if noLust then
		add("drums", IT.drums, math.max(1, nruns / 3), L["Tambores (Void-Touched Drums)"], L["Sua classe não tem Heroísmo/Bloodlust: os tambores dão +15% de Aceleração ao grupo."])
	end
	if noBres then
		add("res", IT.soulLink, math.max(1, nruns / 3), L["Reviver em combate (Emergency Soul Link)"], L["Sua classe não tem reviver em combate: leve o Emergency Soul Link."])
	end
	for _, gi in ipairs({

		{ "invis", IT.invis, L["Invisibilidade (Void-Shrouded Tincture)"], L["Pular trechos em M+."] },
		{ "cauldron", IT.cauldronFlask, L["Caldeirão de frascos"], L["Para o grupo/raide."] },
		{ "feast", IT.feastPrimary, L["Banquete"], L["Para o grupo/raide."] },
	}) do
		if #gi[2] > 0 and (group or usedAny(gi[2])) then add(gi[1], gi[2], math.max(1, nruns / 3), gi[3], gi[4]) end
	end
	return out, hours, runs
end

-- grupos para a lista de compras (formato do Buy)
function Consum.Groups(me, allChars, usedGroups)
	local C = ns.Plan.Count
	local group = LucroCraftDB.config.consGroup
	local chars = {}
	if allChars then
		for char in pairs(LucroLivroDB and LucroLivroDB.chars or {}) do table.insert(chars, char) end
		table.sort(chars, function(a, b) if (a == me) ~= (b == me) then return a == me end return a < b end)
	else
		chars = { me }
	end
	-- o que já está na lista de usados não repete
	local inUsed = {}
	for _, g in ipairs(usedGroups or {}) do
		inUsed[g.char] = inUsed[g.char] or {}
		for _, m in ipairs(g.order) do inUsed[g.char][m.buyId] = true end
	end
	local out = {}
	for _, char in ipairs(chars) do
		local list, hours, runs = Consum.For(char, group)
		local c = LucroLivroDB and LucroLivroDB.chars and LucroLivroDB.chars[char]
		local g = { char = char, class = c and c.class, sugg = true, hours = hours, runs = runs, profs = {}, mats = {}, order = {}, cost = 0, gain = 0, crafts = 0 }
		for _, s in ipairs(list) do
			local id = Pick(s.ids)
			local skip = false
			for _, x in ipairs(s.ids) do if inUsed[char] and inUsed[char][x] then skip = true end end
			if id and not skip then
				-- tem/precisa somado entre as qualidades (uma vale pela outra); comprar é uma OU outra, não as duas
				local own = 0
				for _, x in ipairs(s.ids) do own = own + C.own(char, x) end
				local wb = 0
				for _, x in ipairs(s.ids) do wb = wb + C.warband(x) end
				local m = { key = id, ids = { id }, buyId = id, need = s.need, uses = {}, own = own, wb = math.min(wb, math.max(0, s.need - own)),
					alts = 0, queue = true, note = s.note, why = s.why, hasQuality = #s.ids > 1 }
				m.buy = math.max(0, s.need - own - m.wb)
				table.insert(g.order, m)
			end
		end
		if #g.order > 0 then table.insert(out, g) end
	end
	return out
end
