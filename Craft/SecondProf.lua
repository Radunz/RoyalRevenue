local ADDON, root = ...
root.Craft = root.Craft or {}
local ns = root.Craft
ns.root = root
local L = ns.L

-- ===== Investimento > Segunda profissão =====
-- Para o personagem logado com menos de 2 profissões principais: lista as que ele ainda não tem,
-- da mais lucrativa para a menos, com os dados da conta (o melhor personagem que já tem cada profissão)
-- e o bônus racial do personagem.
--  Fabricação: lucro por semana com a concentração (Invest.WeeklyValue) + o que a perícia racial acrescenta.
--  Coleta: valor por hora coletando (registro de coletas de todos os personagens) + Fineza racial.
local SP = {}
ns.SecondProf = SP

local P = ns.Pricing
local V = ns.Visual

local PRIMARY = { 171, 164, 333, 202, 773, 755, 165, 197, 182, 186, 393 }
local GATHER = { [182] = true, [186] = true, [393] = true }
-- profissões que se completam (uma fornece material para a outra)
local PAIRS = {
	[182] = { 171, 773 }, [171] = { 182 }, [773] = { 182 },
	[186] = { 164, 755, 202 }, [164] = { 186 }, [755] = { 186 }, [202] = { 186 },
	[393] = { 165 }, [165] = { 393 },
	[333] = { 197 }, [197] = { 333 },
}

-- Bônus raciais de profissão (atuais desde o patch 10.0.2; Fineza do Terrano desde 11.0.2).
-- chave = raceFile do UnitRace. skill = perícia; deft = % de Destreza (coleta mais rápida); fin = Fineza (+material).
local RACIAL = {
	Draenei = { [755] = { skill = 5 } },
	Gnome = { [202] = { skill = 5 } },
	BloodElf = { [333] = { skill = 5 } },
	Goblin = { [171] = { skill = 5 } },
	Nightborne = { [773] = { skill = 5 } },
	LightforgedDraenei = { [164] = { skill = 5, forge = true } },
	DarkIronDwarf = { [164] = { skill = 5, speed = 10 } },
	Tauren = { [182] = { skill = 5, deft = 25 } },
	HighmountainTauren = { [186] = { skill = 5, deft = 25 } },
	Worgen = { [393] = { skill = 5, deft = 25 } },
	KulTiran = { all = { skill = 2 } },
	EarthenDwarf = { [182] = { fin = 25 }, [186] = { fin = 25 }, [393] = { fin = 25 } },
	Mechagnome = { craft = { tools = true } },
}

if not ns.isPT then
	local T = {
		["Segunda profissão"] = "Second profession",
		["Fabricação · lucro por semana com a concentração"] = "Crafting · profit per week with concentration",
		["Coleta · valor por hora coletando"] = "Gathering · value per hour gathering",
		["por semana"] = "per week",
		["por hora"] = "per hour",
		["Racial: +%d de perícia"] = "Racial: +%d skill",
		["Racial: +%d de perícia (com a Forja da Luz)"] = "Racial: +%d skill (with Forge of Light)",
		["Racial: +%d%% de Destreza"] = "Racial: +%d%% Deftness",
		["Racial: +%d de Fineza"] = "Racial: +%d Finesse",
		["Racial: +%d%% de velocidade"] = "Racial: +%d%% speed",
		["Racial: ferramentas de profissão próprias"] = "Racial: own profession tools",
		["combina com %s"] = "pairs with %s",
		["medido em %s"] = "measured on %s",
		["sem dados: abra esta profissão em algum personagem"] = "no data: open this profession on any character",
		["sem coletas registradas"] = "no gathers recorded",
		["Você já tem duas profissões."] = "You already have two professions.",
		["Profissões atuais: %s"] = "Current professions: %s",
		["nenhuma"] = "none",
		["Ganho da racial"] = "Racial gain",
		["Lucro por semana"] = "Profit per week",
		["Valor por hora"] = "Value per hour",
		["Coletas por hora"] = "Gathers per hour",
		["Melhores receitas"] = "Best recipes",
		["Dados de"] = "Data from",
		["Perícia no scan"] = "Skill in the scan",
		["O lucro foi medido num personagem que já tem a profissão (pontos de conhecimento e equipamento dele). Começando do zero, o seu fica abaixo disso até pegar conhecimento."] = "Profit was measured on a character who already has the profession (their knowledge points and gear). Starting from zero yours will be lower until you gain knowledge.",
		["Coleta não usa concentração: o valor depende das horas que você coletar."] = "Gathering doesn't use concentration: value depends on how many hours you gather.",
		["melhor: %s"] = "best: %s",
		["Ranking pelo lucro com a racial. Fabricação e coleta não se comparam direto (semana × hora)."] = "Ranked by profit including the racial. Crafting and gathering aren't directly comparable (week × hour).",
		["coleta mais rápida"] = "faster gathering",
		["fabricação mais rápida"] = "faster crafting",
		["sem custo de mesa"] = "no table needed",
	}
	for k, v in pairs(T) do L[k] = v end
end

local function ProfName(id)
	if ns.Sell and ns.Sell.ProfName then return ns.Sell.ProfName(id) end
	return tostring(id)
end
local function ProfIcon(id)
	if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture then
		local ok, t = pcall(C_TradeSkillUI.GetTradeSkillTexture, id)
		if ok and t then return t end
	end
	return 134400
end

-- profissões principais do personagem logado (skillLine base)
function SP.MyProfessions()
	local out = {}
	if not GetProfessions then return out end
	local p1, p2 = GetProfessions()
	for _, idx in ipairs({ p1, p2 }) do
		if idx then
			local name, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
			if skillLine then table.insert(out, { id = skillLine, name = name }) end
		end
	end
	return out
end

function SP.Racial(prof, raceFile)
	local r = RACIAL[raceFile or ""]
	if not r then return nil end
	local b = r[prof] or r.all or (not GATHER[prof] and r.craft) or nil
	return b
end

local function RacialText(b)
	if not b then return nil end
	local parts = {}
	if b.skill then table.insert(parts, string.format(b.forge and L["Racial: +%d de perícia (com a Forja da Luz)"] or L["Racial: +%d de perícia"], b.skill)) end
	if b.deft then table.insert(parts, string.format(L["Racial: +%d%% de Destreza"], b.deft)) end
	if b.fin then table.insert(parts, string.format(L["Racial: +%d de Fineza"], b.fin)) end
	if b.speed then table.insert(parts, string.format(L["Racial: +%d%% de velocidade"], b.speed)) end
	if b.tools then table.insert(parts, L["Racial: ferramentas de profissão próprias"]) end
	return table.concat(parts, " · ")
end

-- melhor entrada da conta para uma profissão (a de maior lucro semanal)
local function BestEntry(prof)
	local best, bestV, bestInfo, bestChar
	for char, entries in pairs(LucroCraftDB.chars or {}) do
		for _, e in pairs(entries) do
			if e.parentID == prof and e.rows and #e.rows > 0 then
				local ok, v, info = pcall(ns.Invest.WeeklyValue, e)
				if ok and v and (not bestV or v > bestV) then best, bestV, bestInfo, bestChar = e, v, info, char end
			end
		end
	end
	return best, bestV, bestInfo, bestChar
end

function SP.Build()
	local mine = SP.MyProfessions()
	local have = {}
	for _, p in ipairs(mine) do have[p.id] = true end
	local _, raceFile = UnitRace("player")
	local res = { mine = mine, race = raceFile, craft = {}, gather = {} }
	for _, prof in ipairs(PRIMARY) do
		if not have[prof] then
			local it = { prof = prof, name = ProfName(prof), icon = ProfIcon(prof) }
			it.racial = SP.Racial(prof, raceFile)
			it.racialText = RacialText(it.racial)
			for _, other in ipairs(PAIRS[prof] or {}) do
				if have[other] then it.pair = ProfName(other) end
			end
			if GATHER[prof] then
				local key = ns.Gather and ns.Gather.BY_PARENT[prof]
				local an = key and ns.Gather.Analyze(key) or { n = 0 }
				it.an = an
				if an.value100 and an.rate then
					it.value = an.value100 / 100 * an.rate
					it.rate = an.rate
					-- Fineza racial: valor de +1 ponto em 100 coletas × pontos × coletas/h
					if it.racial and it.racial.fin and an.fin and an.fin.per then
						it.racialGain = an.fin.per * it.racial.fin / 100 * an.rate
					end
					-- Destreza racial: coleta mais rápida (parte do tempo é deslocamento: conta metade)
					if it.racial and it.racial.deft then
						it.racialGain = (it.racialGain or 0) + it.value * (it.racial.deft / 100) * 0.5
					end
				end
				table.insert(res.gather, it)
			else
				local e, v, info, char = BestEntry(prof)
				if e then
					it.value, it.info, it.char, it.entry = v, info, char, e
					if it.racial and it.racial.skill then
						local ok, v2 = pcall(ns.Invest.WeeklyValue, e, { skill = it.racial.skill })
						if ok and v2 then it.racialGain = math.max(0, v2 - v) end
					end
					if it.racial and it.racial.speed then it.speed = it.racial.speed end
				end
				table.insert(res.craft, it)
			end
			it.total = (it.value or 0) + (it.racialGain or 0)
		end
	end
	local function sorter(a, b)
		if (a.value ~= nil) ~= (b.value ~= nil) then return a.value ~= nil end
		if a.total ~= b.total then return a.total > b.total end
		return a.name < b.name
	end
	table.sort(res.craft, sorter)
	table.sort(res.gather, sorter)
	return res
end

-- ===== desenho =====
local function Row(cv, y, W, it, unit, idx)
	local G = P.FormatGold
	root.Zebra(cv, idx, 0, y, W, 44)
	local tip = function(tt)
		tt:SetText(it.name)
		if it.value then
			tt:AddDoubleLine(GATHER[it.prof] and L["Valor por hora"] or L["Lucro por semana"], P.FormatMoney(it.value), 1, 0.82, 0, 1, 1, 1)
			if it.racialGain and it.racialGain > 0 then tt:AddDoubleLine(L["Ganho da racial"], "+" .. P.FormatMoney(it.racialGain), 1, 0.82, 0, 0.3, 1, 0.3) end
			if it.rate then tt:AddDoubleLine(L["Coletas por hora"], root.Num(it.rate, 0), 1, 0.82, 0, 1, 1, 1) end
			if it.char then tt:AddDoubleLine(L["Dados de"], (it.char:match("^([^-]+)")) or it.char, 1, 0.82, 0, 1, 1, 1) end
		end
		if it.racialText then tt:AddLine(it.racialText, 0.4, 0.8, 1, true) end
		if it.info and it.info.used and #it.info.used > 0 then
			tt:AddLine(" ")
			tt:AddLine(L["Melhores receitas"], 1, 0.82, 0)
			for k, u in ipairs(it.info.used) do
				if k > 5 then break end
				tt:AddDoubleLine(string.format("%sx %s", root.Num(u.crafts, 1), u.row.name or "?"), P.FormatMoney(u.gold), 1, 1, 1, 0.3, 1, 0.3)
			end
		end
		tt:AddLine(" ")
		tt:AddLine(GATHER[it.prof] and L["Coleta não usa concentração: o valor depende das horas que você coletar."]
			or L["O lucro foi medido num personagem que já tem a profissão (pontos de conhecimento e equipamento dele). Começando do zero, o seu fica abaixo disso até pegar conhecimento."], 0.6, 0.6, 0.6, true)
	end
	cv:Icon(8, y + 6, 32, it.icon, { border = it.racial and { 0.83, 0.69, 0.22 } or { 0.6, 0.6, 0.6 }, desaturate = not it.value, tip = tip })
	cv:Text(48, y + 6, (it.value and "|cffffffff" or "|cff9d9d9d") .. it.name .. "|r", GameFontHighlight, 200)
	local sub
	if it.value then
		local parts = {}
		if it.char then table.insert(parts, string.format(L["medido em %s"], (it.char:match("^([^-]+)")) or it.char)) end
		if it.info and it.info.row then table.insert(parts, string.format(L["melhor: %s"], it.info.row.name or "?")) end
		if it.rate then table.insert(parts, root.Num(it.rate, 0) .. " " .. L["Coletas por hora"]:lower()) end
		sub = "|cff9d9d9d" .. table.concat(parts, " · ") .. "|r"
	else
		sub = "|cff9d9d9d" .. (GATHER[it.prof] and L["sem coletas registradas"] or L["sem dados: abra esta profissão em algum personagem"]) .. "|r"
	end
	cv:Text(48, y + 24, sub, GameFontDisableSmall, 360)
	-- racial e combinação
	local tx = 420
	if it.racialText then
		cv:Box(tx, y + 6, 230, 16, 0.83, 0.69, 0.22, 0.25)
		cv:Text(tx + 4, y + 8, "|cffd4af37" .. it.racialText .. "|r", GameFontHighlightSmall, 226)
		if it.racialGain and it.racialGain > 0 then
			cv:Text(tx + 4, y + 26, "|cff55ff55+" .. G(it.racialGain) .. "|r |cff9d9d9d" .. unit .. "|r", GameFontHighlightSmall, 226)
		end
	end
	if it.pair then
		cv:Box(tx + 236, y + 6, 150, 16, 0.17, 0.36, 0.66, 0.35)
		cv:Text(tx + 240, y + 8, "|cff66ccff" .. string.format(L["combina com %s"], it.pair) .. "|r", GameFontHighlightSmall, 146)
	end
	-- valor
	cv:Text(W - 170, y + 6, it.value and G(it.total, true) or "|cff9d9d9d—|r", GameFontNormalLarge, 160, "RIGHT")
	cv:Text(W - 170, y + 26, "|cff9d9d9d" .. unit .. "|r", GameFontDisableSmall, 160, "RIGHT")
	cv:Hit(48, y + 2, 360, 40, nil, tip)
	return y + 44
end

-- grupo "Segunda profissão" (só aparece com menos de 2 profissões principais)
function SP.Draw(cv, y, W)
	local mine = SP.MyProfessions()
	if #mine >= 2 then return y end
	local res = SP.Build()
	local best = res.craft[1] and res.craft[1].value and res.craft[1] or nil
	local names = {}
	for _, p in ipairs(mine) do table.insert(names, p.name) end
	local summary = best and string.format(L["melhor: %s"], best.name .. " " .. P.FormatGold(best.total, true)) or ""
	local col
	y, col = ns.Invest._Group(cv, y + 8, W, "secondprof", L["Segunda profissão"], summary)
	if col then return y end
	cv:Text(8, y, "|cff9d9d9d" .. string.format(L["Profissões atuais: %s"], #names > 0 and table.concat(names, ", ") or L["nenhuma"]) .. " · " ..
		L["Ranking pelo lucro com a racial. Fabricação e coleta não se comparam direto (semana × hora)."] .. "|r", GameFontDisableSmall, W - 16)
	y = y + 18
	cv:Text(8, y, L["Fabricação · lucro por semana com a concentração"], GameFontNormal)
	y = y + 18
	for k, it in ipairs(res.craft) do y = Row(cv, y, W, it, L["por semana"], k) end
	y = y + 8
	cv:Text(8, y, L["Coleta · valor por hora coletando"], GameFontNormal)
	y = y + 18
	for k, it in ipairs(res.gather) do y = Row(cv, y, W, it, L["por hora"], k) end
	return y + 8
end
