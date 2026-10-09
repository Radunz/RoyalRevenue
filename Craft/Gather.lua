local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- ===== Coleta (Herbalismo, Mineração, Esfolamento) =====
-- Não há fórmula publicada para Finesse/Perception na Midnight. Então:
--   1) cada coleta é registrada (itens, quantidades e os atributos do personagem naquele momento);
--   2) valor de 100 coletas = média real × preço de venda;
--   3) valor de cada ponto = regressão do rendimento contra o atributo (os buffs geram a variação);
--      sem dados/variação suficientes usa uma aproximação e avisa qual está em uso.
local Gather = {}
ns.Gather = Gather

local P = ns.Pricing

-- profissão pela subclasse do material (classe 7 = mercadorias de profissão)
local SUBCLASS = { [9] = "herb", [7] = "mining", [6] = "skinning" }
local PARENT = { herb = 182, mining = 186, skinning = 393 }
local BY_PARENT = { [182] = "herb", [186] = "mining", [393] = "skinning" }
Gather.BY_PARENT = BY_PARENT

local KEEP = 600              -- coletas guardadas por profissão
local MIN_N = 30              -- coletas para usar a medição
local MIN_SD = 5              -- desvio mínimo do atributo (pontos) para medir o efeito dele
local COMMON = 0.4            -- item presente em >= 40% das coletas = material base (o resto é "raro")
-- aproximação (até ter medição): cada ponto de Finesse = +1/FIN_FACTOR do material base;
-- Perception = chance de raro proporcional ao valor (sem chance base).
local FIN_FACTOR = 1000

local function DB()
	LucroCraftDB.gather = LucroCraftDB.gather or {}
	return LucroCraftDB.gather
end

-- ===== atributos de coleta do personagem agora =====
local STATS = { "finesse", "perception", "deftness" }
local EN = { finesse = "finesse", perception = "perception", deftness = "deftness" }

local function LineStat(text)
	local low = text:lower()
	for _, k in ipairs(STATS) do
		local loc = (ns.STAT[k] or ""):lower()
		if (loc ~= "" and low:find(loc, 1, true)) or low:find(EN[k], 1, true) then
			local num = text:match("(%d[%d%.,]*)")
			if num then return k, tonumber((num:gsub("[,%.]", ""))) end
		end
	end
end

local function AddTip(st, tip)
	if not tip or not tip.lines then return end
	for _, line in ipairs(tip.lines) do
		if line.leftText then
			local k, n = LineStat(line.leftText)
			if k and n then st[k] = st[k] + n end
		end
	end
end

-- espaços de equipamento da profissão de coleta (20-22 ou 23-25, pela ordem das profissões)
local function Slots(prof)
	if not GetProfessions then return nil end
	local p1, p2 = GetProfessions()
	for idx, base in pairs({ [p1 or -1] = 20, [p2 or -2] = 23 }) do
		if idx and idx > 0 then
			local _, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
			if skillLine == PARENT[prof] then return { base, base + 1, base + 2 }, idx end
		end
	end
	return nil
end

-- espaço da ferramenta da profissão (pedra de afiar vai nela)
function Gather.ToolSlot(prof)
	local slots = Slots(prof)
	return slots and slots[1] or nil
end

local function Skill(prof, idx)
	-- linha da expansão atual escaneada (a aba da profissão de coleta já foi aberta)
	local mine = (LucroCraftDB.chars or {})[ns.CharKey()] or {}
	for id, e in pairs(mine) do
		if e.parentID == PARENT[prof] and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
			local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
			if ok and info and info.skillLevel then return (info.skillLevel or 0) + (info.skillModifier or 0) end
		end
	end
	if idx then
		local _, _, rank, _, _, _, _, mod = GetProfessionInfo(idx)
		return (rank or 0) + (mod or 0)
	end
	return 0
end

function Gather.Snapshot(prof)
	local st = { finesse = 0, perception = 0, deftness = 0 }
	local slots, idx = Slots(prof)
	for _, slot in ipairs(slots or {}) do
		if GetInventoryItemLink("player", slot) then
			local ok, tip = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
			if ok then AddTip(st, tip) end
		end
	end
	-- buffs ativos (chás, frascos...): números do tooltip do buff.
	-- Na Midnight as auras podem vir "secretas" (ex.: em combate) e a leitura dá erro: nesse caso usa a
	-- última leitura boa (até 10 min) em vez de perder a coleta ou gravar o atributo sem o buff.
	local aura = { finesse = 0, perception = 0, deftness = 0 }
	local okA = pcall(function()
		if InCombatLockdown and InCombatLockdown() then error("combate") end
		for i = 1, 60 do
			local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
			if not a then break end
			local ok, tip = pcall(C_TooltipInfo.GetUnitBuffByAuraInstanceID, "player", a.auraInstanceID)
			if ok then AddTip(aura, tip) end
		end
	end)
	if okA then
		Gather.lastAura = { s = aura, t = GetTime() }
	elseif Gather.lastAura and GetTime() - Gather.lastAura.t < 600 then
		aura = Gather.lastAura.s
		st.cached = true
	else
		st.noAura = true   -- sem leitura dos buffs: coleta fica fora das medições de atributo
	end
	for k, v in pairs(aura) do st[k] = st[k] + v end
	st.skill = Skill(prof, idx)
	return st
end

-- ===== tipo do nó (nome) e modificadores =====
-- O nome do alvo vem do UNIT_SPELLCAST_SENT do feitiço de coleta ("Lightfused Tranquility Bloom", "Rich Umbral Tin
-- Deposit"...). Sem nome (coletas antigas), o modificador sai pelo mote que veio no saque.
Gather.MOTES = { [236949] = "light", [236951] = "wild", [236950] = "primal", [236952] = "void" }
Gather.MODS = {
	{ key = "light",  mote = 236949, words = { "lightfused", "luzid", "lumin" } },
	{ key = "wild",   mote = 236951, words = { "wild", "selvag", "silvestr" } },
	{ key = "primal", mote = 236950, words = { "primal", "primord" } },
	{ key = "void",   mote = 236952, words = { "voidbound", "void", "caótic", "vazio", "vácuo" } },
}
Gather.KINDS = {
	{ key = "rich", words = { "rich", "ric" } },
	{ key = "lush", words = { "lush", "viços", "exuberant" } },
	{ key = "seam", words = { "seam", "veio", "filão" } },
}
local function Has(name, words)
	for _, w in ipairs(words) do if name:find(w, 1, true) then return true end end
end
function Gather.Classify(g)
	local name = g.n and g.n:lower() or ""
	local mod, kind
	for _, m in ipairs(Gather.MODS) do if name ~= "" and Has(name, m.words) then mod = m.key break end end
	if not mod then
		for id in pairs(g.i or {}) do if Gather.MOTES[id] then mod = Gather.MOTES[id] break end end
		if not mod then for id in pairs(g.x or {}) do if Gather.MOTES[id] then mod = Gather.MOTES[id] break end end end
	end
	for _, k in ipairs(Gather.KINDS) do if name ~= "" and Has(name, k.words) then kind = k.key break end end
	return mod, kind
end

local sentName, sentAt = nil, 0           -- alvo do último feitiço (nome do nó)
local ovAt, ovCD = 0, nil                  -- último Overload e o recarregamento dele
local open                                  -- coleta recém-registrada que ainda recebe extras (orbes, bichos)

-- ===== registro das coletas =====
local lastSource, lastAt = nil, 0

local function CurrentExp(id)
	local exp = select(15, C_Item.GetItemInfo(id))
	local cur = (GetServerExpansionLevel and GetServerExpansionLevel()) or (GetExpansionLevel and GetExpansionLevel())
	return exp == nil or cur == nil or exp == cur
end

local function OnLoot()
	local n = GetNumLootItems and GetNumLootItems() or 0
	if n == 0 then return end
	local items, prof, source = {}, nil, nil
	for slot = 1, n do
		local link = GetLootSlotLink(slot)
		local id = link and C_Item.GetItemInfoInstant(link)
		if id then
			local _, _, qty = GetLootSlotInfo(slot)
			items[id] = (items[id] or 0) + (qty or 1)
			local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
			if classID == 7 and SUBCLASS[subClassID] and not prof and CurrentExp(id) then
				prof = SUBCLASS[subClassID]
				source = GetLootSourceInfo and GetLootSourceInfo(slot) or nil
			end
		end
	end
	if not prof or not source then return end
	-- erva e minério vêm de objeto; couro de criatura (esfolada)
	local kind = source:match("^(%a+)")
	if (prof == "skinning") ~= (kind == "Creature") then return end
	if prof ~= "skinning" and kind ~= "GameObject" then return end
	if not Slots(prof) then return end   -- o personagem não tem essa profissão
	if source == lastSource and GetTime() - lastAt < 30 then return end   -- mesma janela de saque
	lastSource, lastAt = source, GetTime()
	local db = DB()
	db[prof] = db[prof] or {}
	local list = db[prof]
	local rec = { t = time(), c = ns.CharKey(), i = items, s = Gather.Snapshot(prof) }
	if sentName and GetTime() - sentAt < 15 then rec.n = sentName end
	local oid = source:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if oid then rec.o = tonumber(oid) end
	-- Overload logo antes (ou logo depois, ver OnSpell) desta coleta
	if GetTime() - ovAt < 20 then rec.ov = true; rec.ovcd = ovCD end
	table.insert(list, rec)
	while #list > KEEP do table.remove(list, 1) end
	-- o que vier pelo chat nos próximos segundos e não for deste saque = extra do nó (orbes, bichos do Wild...)
	local pend = {}
	for id, q in pairs(items) do pend[id] = q end
	open = { rec = rec, pend = pend, at = GetTime(), until_ = GetTime() + (rec.ov and 120 or 45) }
	Gather.cache = nil
end

-- mensagens de saque do próprio personagem ("Você recebe saque: %s" / "...x%d" / "Você recebe item: %s")
local lootPats
local function LootPats()
	if lootPats then return lootPats end
	lootPats = {}
	for _, gname in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
		"LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF" }) do
		local f = _G[gname]
		if type(f) == "string" then
			local pat = "^" .. f:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)") .. "$"
			table.insert(lootPats, pat)
		end
	end
	return lootPats
end

local function OnChatLoot(msg)
	if not open or GetTime() > open.until_ then open = nil return end
	if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
	for _, pat in ipairs(LootPats()) do
		local link, q = msg:match(pat)
		if link then
			local id = tonumber(link:match("item:(%d+)"))
			q = tonumber(q) or 1
			if not id then return end
			local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
			if classID ~= 7 and not Gather.MOTES[id] then return end
			local p = open.pend[id] or 0
			local mine = math.min(p, q)
			open.pend[id] = p - mine
			local extra = q - mine
			if extra > 0 then
				local rec = open.rec
				rec.x = rec.x or {}
				rec.x[id] = (rec.x[id] or 0) + extra
				Gather.cache = nil
			end
			return
		end
	end
end

-- Overload (erva/minério): marca a coleta (a de agora ou a próxima) e guarda o recarregamento
local function OnSpell(spellID)
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return end
	local low = name:lower()
	if not (low:find("overload", 1, true) or low:find("sobrecarg", 1, true)) then return end
	ovAt = GetTime()
	C_Timer.After(0.5, function()
		local ok, cd = pcall(C_Spell.GetSpellCooldown, spellID)
		if ok and cd and type(cd.duration) == "number" and cd.duration > 2 then ovCD = cd.duration end
		if open and GetTime() - (open.at or 0) < 20 and not open.rec.ov then
			open.rec.ov, open.rec.ovcd = true, ovCD
			open.until_ = GetTime() + 120
		end
	end)
	if open and open.rec and time() - open.rec.t < 20 then
		open.rec.ov = true
		open.until_ = GetTime() + 120
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("LOOT_READY")
ev:RegisterEvent("CHAT_MSG_LOOT")
ev:RegisterEvent("UNIT_SPELLCAST_SENT")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
	if root.AnySecret(a1, a2, a3, a4) then return end
	local ok, err
	if event == "LOOT_READY" then ok, err = pcall(OnLoot)
	elseif event == "CHAT_MSG_LOOT" then ok, err = pcall(OnChatLoot, a1)
	elseif event == "UNIT_SPELLCAST_SENT" then
		if a1 == "player" and type(a2) == "string" and a2 ~= "" then sentName, sentAt = a2, GetTime() end
		return
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if a1 == "player" then ok, err = pcall(OnSpell, a3) end
	end
	if ok == false and ns.Log then ns.Log("coleta: " .. tostring(err)) end
end)

-- ===== análise =====
local function Price(id)
	local s = P.Sale(id)
	return s and s * (1 - (ns.Cfg("ahCut") or 0.05)) or 0
end

local function Mean(t)
	local s = 0
	for _, v in ipairs(t) do s = s + v end
	return #t > 0 and s / #t or 0
end

-- inclinação de y contra x (mínimos quadrados) e desvio de x
local function Slope(xs, ys)
	local mx, my = Mean(xs), Mean(ys)
	local sxx, sxy = 0, 0
	for i = 1, #xs do
		sxx = sxx + (xs[i] - mx) ^ 2
		sxy = sxy + (xs[i] - mx) * (ys[i] - my)
	end
	local sd = #xs > 1 and math.sqrt(sxx / (#xs - 1)) or 0
	if sxx <= 0 then return nil, sd end
	local b = sxy / sxx
	-- erro padrão da inclinação: só vale como "medido" se o efeito for maior que o ruído
	local se
	if #xs > 2 then
		local ss = 0
		for i = 1, #xs do ss = ss + (ys[i] - (my + b * (xs[i] - mx))) ^ 2 end
		se = math.sqrt(ss / (#xs - 2) / sxx)
	end
	return b, sd, se
end

-- quantas coletas fogem do valor mais comum do atributo (com/sem buff): precisa de contraste dos dois lados
local MIN_OTHER = 10
local function Contrast(xs)
	local c, best = {}, 0
	for _, x in ipairs(xs) do c[x] = (c[x] or 0) + 1; if c[x] > best then best = c[x] end end
	return #xs - best
end

-- gathers por hora pelas sessões registradas (intervalos acima de 5 min contam como pausa)
local function Rate(list)
	local active, count = 0, 0
	for k = 2, #list do
		local dt = list[k].t - list[k - 1].t
		if dt > 0 and dt <= 300 then active = active + dt; count = count + 1 end
	end
	if active < 600 then return nil end
	return count / active * 3600
end

function Gather.Analyze(prof)
	local list = DB()[prof] or {}
	local n = #list
	local out = { prof = prof, n = n }
	if n == 0 then return out end
	-- frequência de cada item
	local present, total = {}, {}
	for _, g in ipairs(list) do
		for id, q in pairs(g.i) do
			present[id] = (present[id] or 0) + 1
			total[id] = (total[id] or 0) + q
		end
	end
	-- material base = mesma subclasse da profissão (qualquer minério/erva/couro, qualquer qualidade):
	-- é o que Finesse aumenta. O resto (partículas, raros) é o que Perception traz.
	local base = {}
	for id, c in pairs(present) do
		local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
		if classID then
			base[id] = (classID == 7 and SUBCLASS[subClassID] == prof)
		else
			base[id] = (c / n) >= COMMON
		end
	end
	local fin, per, skill, vb, vr, vt = {}, {}, {}, {}, {}, {}
	local fx, fb, px, pr = {}, {}, {}, {}
	local sumBQ, sumBV = 0, 0
	for _, g in ipairs(list) do
		local b, r, bq = 0, 0, 0
		for id, q in pairs(g.i) do
			local v = q * Price(id)
			if base[id] then b = b + v; bq = bq + q else r = r + v end
		end
		sumBQ, sumBV = sumBQ + bq, sumBV + b
		table.insert(fin, g.s.finesse or 0); table.insert(per, g.s.perception or 0); table.insert(skill, g.s.skill or 0)
		table.insert(vb, b); table.insert(vr, r); table.insert(vt, b + r)
		if not g.s.noAura then
			table.insert(fx, g.s.finesse or 0); table.insert(fb, bq)
			table.insert(px, g.s.perception or 0); table.insert(pr, r)
		end
	end
	out.value100 = Mean(vt) * 100
	out.base100, out.rare100 = Mean(vb) * 100, Mean(vr) * 100
	out.stats = { finesse = Mean(fin), perception = Mean(per), skill = Mean(skill) }
	-- itens mais valiosos (para os ícones)
	out.items = {}
	for id, q in pairs(total) do
		table.insert(out.items, { itemID = id, per100 = q / n * 100, value100 = q / n * 100 * Price(id), base = base[id] })
	end
	table.sort(out.items, function(a, b) return a.value100 > b.value100 end)

	-- Finesse: +1 ponto = quanto muda o valor do material base em 100 coletas
	-- inclinação na QUANTIDADE de material base × valor médio de uma unidade (tira a sorte de ★2 da conta)
	local unitBase = sumBQ > 0 and sumBV / sumBQ or 0
	local s, sd, se = Slope(fx, fb)
	local enough = #fx >= MIN_N and s and sd >= MIN_SD and Contrast(fx) >= MIN_OTHER
	if enough and se and math.abs(s) >= 2 * se then
		out.fin = { per = s * unitBase * 100, measured = true, sd = sd, err = se * unitBase * 100 }
	else
		local f = out.stats.finesse
		local b0 = Mean(vb) / (1 + f / FIN_FACTOR)
		out.fin = { per = b0 / FIN_FACTOR * 100, measured = false, sd = sd,
			inconclusive = enough and true or nil, mper = s and s * unitBase * 100 or nil, err = se and se * unitBase * 100 or nil }
	end
	-- Perception: +1 ponto = quanto muda o valor dos raros em 100 coletas
	s, sd, se = Slope(px, pr)
	enough = #px >= MIN_N and s and sd >= MIN_SD and Contrast(px) >= MIN_OTHER
	if enough and se and math.abs(s) >= 2 * se then
		out.per = { per = s * 100, measured = true, sd = sd, err = se * 100 }
	else
		local p = out.stats.perception
		out.per = { per = (p > 0) and (Mean(vr) / p * 100) or 0, measured = false, sd = sd, noRare = Mean(vr) <= 0,
			inconclusive = enough and true or nil, mper = s and s * 100 or nil, err = se and se * 100 or nil }
	end
	-- Perícia: só medida (muda a qualidade do material; sem aproximação confiável)
	s, sd, se = Slope(skill, vt)
	if n >= MIN_N and s and sd >= 2 and se and math.abs(s) >= 2 * se then out.skill = { per = s * 100, measured = true } end
	out.rate = Rate(list)

	-- ===== valor por nó e modificadores =====
	-- valor do nó = tudo que saiu dele (saque + extras: orbes, bichos do Wild, Overload)
	local groups = {}
	local function add(key, v)
		local gr = groups[key] or { n = 0, sum = 0, sumsq = 0 }
		gr.n, gr.sum, gr.sumsq = gr.n + 1, gr.sum + v, gr.sumsq + v * v
		groups[key] = gr
	end
	local allV, allN, named = 0, 0, 0
	local ovCDs = {}
	for _, g in ipairs(list) do
		local v = 0
		for id, q in pairs(g.i) do v = v + q * Price(id) end
		for id, q in pairs(g.x or {}) do v = v + q * Price(id) end
		allV, allN = allV + v, allN + 1
		if g.n then named = named + 1 end
		local mod, kind = Gather.Classify(g)
		if g.ov then
			add("ov:" .. (mod or "none"), v)
			if g.ovcd then table.insert(ovCDs, g.ovcd) end
		else
			add("mod:" .. (mod or "none"), v)
			if kind then add("kind:" .. kind, v) end
			if not mod and not kind then add("plain", v) end
		end
	end
	out.nodeValue = allN > 0 and allV / allN or 0
	out.named = named
	out.groups = groups
	local plain = groups.plain or groups["mod:none"]
	out.plainValue = plain and plain.n > 0 and plain.sum / plain.n or out.nodeValue
	local function stat(gr)
		if not gr or gr.n == 0 then return nil end
		local m = gr.sum / gr.n
		local var = gr.n > 1 and math.max(0, (gr.sumsq - gr.n * m * m) / (gr.n - 1)) or 0
		return m, math.sqrt(var / gr.n)
	end
	out.mods = {}
	local nonOv = 0
	for k, gr in pairs(groups) do if k:find("^mod:") then nonOv = nonOv + gr.n end end
	for _, def in ipairs(Gather.MODS) do
		local gr = groups["mod:" .. def.key]
		local m, se = stat(gr)
		if m then
			table.insert(out.mods, { key = def.key, mote = def.mote, n = gr.n, share = gr.n / math.max(nonOv, 1), avg = m, se = se, delta = m - out.plainValue })
		end
	end
	out.kinds = {}
	for _, def in ipairs(Gather.KINDS) do
		local gr = groups["kind:" .. def.key]
		local m, se = stat(gr)
		if m then table.insert(out.kinds, { key = def.key, n = gr.n, share = gr.n / math.max(nonOv, 1), avg = m, se = se, delta = m - out.plainValue }) end
	end
	-- Overload: nó com Overload − o mesmo modificador sem Overload
	out.overload = {}
	for _, def in ipairs(Gather.MODS) do
		local gr = groups["ov:" .. def.key]
		local m = stat(gr)
		if m then
			local base = stat(groups["mod:" .. def.key]) or out.plainValue
			table.insert(out.overload, { key = def.key, mote = def.mote, n = gr.n, avg = m, gain = m - base })
		end
	end
	table.sort(ovCDs)
	out.ovCD = ovCDs[1]
	return out
end

-- nós por hora: o ajuste do jogador (config) ou o medido nas sessões
function Gather.NodesPerHour(prof, an)
	local cfg = LucroCraftDB.config.gatherRate
	local v = cfg and cfg[prof]
	if v and v > 0 then return v, "manual" end
	if an and an.rate then return an.rate, "medido" end
	return 60, "padrão"
end
function Gather.SetNodesPerHour(prof, v)
	LucroCraftDB.config.gatherRate = LucroCraftDB.config.gatherRate or {}
	LucroCraftDB.config.gatherRate[prof] = v
end
